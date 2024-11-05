public without sharing class RollupParentResetProcessor extends RollupFullBatchRecalculator {
  @TestVisible
  private static Integer maxQueryRows = Limits.getLimitQueryRows() / 2;
  private static Boolean isValidRun = false;
  private static Boolean isRecursiveRun = false;

  private Integer countOfItems {
    get {
      this.countOfItems = this.countOfItems ?? this.preStart().getCount();
      return this.countOfItems;
    }
    set;
  }

  private without sharing class QueueableResetProcessor extends RollupAsyncProcessor.QueueableProcessor {
    private final RollupParentResetProcessor processor;
    private QueueableResetProcessor(RollupParentResetProcessor processor) {
      super(processor.invokePoint);
      this.processor = processor;
      this.finalizer = processor.finalizer;
    }

    public override String getTypeName() {
      return QueueableResetProcessor.class.getName();
    }

    protected override void performWork() {
      for (RollupAsyncProcessor roll : this.processor.rollups) {
        if (roll instanceof RollupFullRecalcProcessor) {
          this.finalizer.addCaboose((RollupFullRecalcProcessor) roll);
        }
      }
      if (this.processor.countOfItems > maxQueryRows) {
        Database.executeBatch(this.processor, this.processor.rollupControl.BatchChunkSize__c.intValue());
      } else {
        this.processor.runSync();
      }
    }
  }

  public RollupParentResetProcessor(
    List<Rollup__mdt> matchingMeta,
    SObjectType calcItemType,
    String queryString,
    Set<String> recordIds,
    InvocationPoint invokePoint
  ) {
    super(getRefinedQueryString(queryString, matchingMeta, invokePoint), invokePoint, matchingMeta, calcItemType, recordIds, null);
    this.overridesRunCalc = true;
    this.isNoOp = false;
    this.shouldSortToFront = true;
  }

  public override String runCalc() {
    this.isProcessed = true;
    // reset isValidRun flag properly
    getRefinedQueryString(this.queryString, this.rollupMetas, this.invokePoint);
    this.objIds.addAll(this.recordIds);
    String processId = this.getNoProcessId();
    if (isValidRun == false || this.rollupControl.ShouldSkipResettingParentFields__c == true || this.countOfItems <= 0) {
      this.logger.log('Parent reset processor no-op', System.LoggingLevel.INFO);
      return processId;
    }
    Boolean isOverLimit = this.countOfItems > maxQueryRows;
    Integer previouslyQueuedJobs = Limits.getQueueableJobs();
    if (isOverLimit && System.isQueueable() && previouslyQueuedJobs == 1 && this.finalizer != null) {
      this.finalizer.addCaboose(new QueueableResetProcessor(this));
    } else if (isOverLimit && Limits.getLimitQueueableJobs() > previouslyQueuedJobs) {
      // avoids System.LimitException: Too many queueable jobs added to the queue: { output of Limits.getQueueableJobs() }
      // down the rabbit hole we go again
      processId = this.startAsyncWork();
    } else if (this.countOfItems > 0) {
      isRecursiveRun = true;
      for (RollupAsyncProcessor proc : this.rollups) {
        proc.runCalc();
      }
      isRecursiveRun = false;
      this.runSync();
    }

    return processId;
  }

  protected override void innerBatchExecute(List<SObject> parentItems) {
    if (parentItems.isEmpty()) {
      return;
    }
    Map<String, Schema.SObjectField> parentFields = parentItems.get(0).getSObjectType().getDescribe().fields.getMap();
    for (Rollup__mdt rollupMeta : this.rollupMetas) {
      Schema.SObjectField parentFieldToken = parentFields.get(rollupMeta.RollupFieldOnLookupObject__c);
      if (
        rollupMeta.LookupObject__c != this.calcItemType.toString() ||
        this.parentRollupFieldHasBeenReset(rollupMeta.LookupObject__c, rollupMeta.RollupFieldOnLookupObject__c) ||
        parentFieldToken == null
      ) {
        continue;
      }
      Object defaultVal = this.getDefaultValue(rollupMeta);
      this.logger.log(
        'resetting parent fields to: ' + defaultVal + ' for field: ' + parentFieldToken + ' for ' + parentItems.size() + ' items',
        System.LoggingLevel.DEBUG
      );
      for (SObject parentItem : parentItems) {
        this.getDML().updateField(parentFieldToken, parentItem, defaultVal);
      }
    }
    if (isRecursiveRun == false) {
      this.getDML().updateRecords();
    }
  }

  protected override String getTypeName() {
    return RollupParentResetProcessor.class.getName();
  }

  protected override String startAsyncWork() {
    return this.rollupControl.ShouldSkipResettingParentFields__c ? this.getNoProcessId() : System.enqueueJob(new QueueableResetProcessor(this));
  }

  protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    props = super.customizeToStringEntries(props);
    props.remove('Rollup Control');
    props.remove('Rollup Metadata');
    return props;
  }

  private void runSync() {
    List<SObject> parentItems = this.preStart().get();
    this.execute(null, parentItems);
    this.finish(null);
  }

  private static String getRefinedQueryString(String localQueryString, List<Rollup__mdt> matchingMeta, InvocationPoint invokePoint) {
    isValidRun = false;
    String additionalFilters = '';
    String orClause = ' OR ';
    if (matchingMeta.isEmpty() == false) {
      Map<String, SObjectField> fieldTokens = RollupFieldInitializer.Current.getDescribeFromName(matchingMeta[0].LookupObject__c).fields.getMap();
      for (Rollup__mdt meta : matchingMeta) {
        if (RollupFieldInitializer.Current.getSObjectFieldByName(fieldTokens, meta.RollupFieldOnLookupObject__c)?.getDescribe().isFilterable() != true) {
          continue;
        }
        isValidRun = isValidRun || true;
        Object searchObject = getDefaultValue(meta, invokePoint);
        String searchValue = String.valueOf(searchObject);
        if (searchObject instanceof String) {
          searchValue = '\'' + searchValue + '\'';
        }

        additionalFilters += meta.RollupFieldOnLookupObject__c + (' != ' + searchValue + orClause);
      }
    }

    return isValidRun ? localQueryString + '\nAND (' + additionalFilters.removeEnd(orClause) + ')' : localQueryString;
  }

  private static Object getDefaultValue(Rollup__mdt meta, InvocationPoint invokePoint) {
    return new RollupAsyncProcessor.NoOpProcessor(invokePoint).getDefaultValue(meta);
  }
}
