public without sharing class RollupParentResetProcessor extends RollupFullBatchRecalculator {
  @TestVisible
  private static Integer maxQueryRows = Limits.getLimitQueryRows() / 2;
  private static Boolean isValidRun = false;

  private Integer countOfItems;

  private without sharing class QueueableResetProcessor extends RollupAsyncProcessor.QueueableProcessor {
    private final RollupParentResetProcessor processor;
    private final Integer batchChunkSize;
    private QueueableResetProcessor(RollupParentResetProcessor processor, Integer batchChunkSize) {
      super(processor.invokePoint);
      this.processor = processor;
      this.batchChunkSize = batchChunkSize;
    }

    protected override void performWork() {
      if (this.processor.getNumberOfItems() > maxQueryRows) {
        Database.executeBatch(this.processor, this.batchChunkSize);
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
    super(getRefinedQueryString(queryString, matchingMeta), invokePoint, matchingMeta, calcItemType, recordIds, null);
    this.overridesRunCalc = true;
    this.isNoOp = false;
    this.shouldSortToFront = true;
  }

  public override String runCalc() {
    this.isProcessed = true;
    // reset isValidRun flag properly
    getRefinedQueryString(this.queryString, this.rollupMetas);
    this.objIds.addAll(this.recordIds);
    String processId = this.getNoProcessId();
    if (isValidRun == false || this.rollupControl.ShouldSkipResettingParentFields__c == true) {
      this.logger.log('Parent reset processor no-op', LoggingLevel.INFO);
      return processId;
    }
    Boolean isOverLimit = this.getNumberOfItems() > maxQueryRows;
    if (isOverLimit && this.isBatch() == false) {
      // avoids: System.AsyncException: Database.executeBatch cannot be called from a batch start, batch execute, or future method
      processId = super.startAsyncWork();
    } else if (isOverLimit && Limits.getLimitQueueableJobs() > Limits.getQueueableJobs()) {
      // avoids System.LimitException: Too many queueable jobs added to the queue: { output of Limits.getQueueableJobs() }
      // down the rabbit hole we go again
      processId = this.startAsyncWork();
    } else {
      this.runSync();
    }

    return processId;
  }

  public override void execute(Database.BatchableContext bc, List<SObject> parentItems) {
    if (parentItems.isEmpty()) {
      return;
    }
    this.logger.log('resetting parent fields for: ' + parentItems.size() + ' items', LoggingLevel.INFO);
    Map<String, Schema.SObjectField> parentFields = parentItems.get(0).getSObjectType().getDescribe().fields.getMap();
    for (SObject parentItem : parentItems) {
      for (Rollup__mdt rollupMeta : this.rollupMetas) {
        if (this.parentRollupFieldHasBeenReset(rollupMeta, parentItem) == false && parentFields.containsKey(rollupMeta.RollupFieldOnLookupObject__c)) {
          Object resetVal = getDefaultValue(rollupMeta);
          parentItem.put(rollupMeta.RollupFieldOnLookupObject__c, resetVal);
        }
      }
    }
    this.getDML().doUpdate(parentItems);
  }

  protected override String getTypeName() {
    return RollupParentResetProcessor.class.getName();
  }

  protected override String startAsyncWork() {
    return this.rollupControl.ShouldSkipResettingParentFields__c
      ? this.getNoProcessId()
      : System.enqueueJob(new QueueableResetProcessor(this, this.rollupControl.BatchChunkSize__c.intValue()));
  }

  private Integer getNumberOfItems() {
    if (this.countOfItems == null) {
      this.countOfItems = new RollupRepository(this.accessLevel).getCount(this.queryString, this.bindVars);
    }
    return this.countOfItems;
  }

  private void runSync() {
    List<SObject> parentItems = new RollupRepository(this.accessLevel).get(this.queryString, this.bindVars);
    this.execute(null, parentItems);
    this.finish(null);
  }

  private static String getRefinedQueryString(String localQueryString, List<Rollup__mdt> matchingMeta) {
    isValidRun = false;
    String additionalFilters = '';
    String orClause = ' OR ';
    if (matchingMeta.isEmpty() == false) {
      Map<String, SObjectField> fieldTokens = RollupFieldInitializer.Current.getDescribeFromName(matchingMeta[0].LookupObject__c).fields.getMap();
      for (Rollup__mdt meta : matchingMeta) {
        SObjectField token = RollupFieldInitializer.Current.getSObjectFieldByName(fieldTokens, meta.RollupFieldOnLookupObject__c);
        if (token?.getDescribe().isFilterable() == true) {
          isValidRun = isValidRun || true;
          Object searchObject = getDefaultValue(meta);
          String searchValue = String.valueOf(searchObject);
          if (searchObject instanceof String) {
            searchValue = '\'' + searchValue + '\'';
          }

          additionalFilters += meta.RollupFieldOnLookupObject__c + (' != ' + searchValue + orClause);
        }
      }
    }

    return isValidRun ? localQueryString + '\nAND (' + additionalFilters.removeEnd(orClause) + ')' : localQueryString;
  }

  private static Object getDefaultValue(Rollup__mdt meta) {
    Object resetVal = null;
    if (meta.FullRecalculationDefaultNumberValue__c != null) {
      resetVal = meta.FullRecalculationDefaultNumberValue__c;
    } else if (meta.FullRecalculationDefaultStringValue__c != null) {
      resetVal = meta.FullRecalculationDefaultStringValue__c;
    }
    return resetVal;
  }
}
