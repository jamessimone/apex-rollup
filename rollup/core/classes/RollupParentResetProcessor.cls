public without sharing class RollupParentResetProcessor extends RollupFullBatchRecalculator {
  @TestVisible
  private static Integer maxQueryRows = Limits.getLimitQueryRows() / 2;
  private static Boolean isValidRun = false;

  private Integer countOfItems;

  private without sharing class QueueableResetProcessor implements System.Queueable {
    private final RollupParentResetProcessor processor;
    private final Integer batchChunkSize;
    private QueueableResetProcessor(RollupParentResetProcessor processor, Integer batchChunkSize) {
      this.processor = processor;
      this.batchChunkSize = batchChunkSize;
    }

    public void execute(QueueableContext qc) {
      this.processor.countOfItems = this.processor.getNumberOfItems();
      if (this.processor.countOfItems > maxQueryRows) {
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
    getRefinedQueryString(this.queryString, this.rollupInfo);
    this.objIds.addAll(this.recordIds);
    String processId = this.getNoProcessId();
    if (isValidRun == false) {
      return processId;
    }
    if (this.countOfItems == null) {
      this.countOfItems = this.getNumberOfItems();
    }
    Boolean isOverLimit = this.countOfItems > maxQueryRows;
    if (isOverLimit && System.isBatch() == false) {
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
    RollupLogger.Instance.log('resetting parent fields for: ' + parentItems.size() + ' items', LoggingLevel.DEBUG);
    Map<String, Schema.SObjectField> parentFields = parentItems.get(0).getSObjectType().getDescribe().fields.getMap();
    for (SObject parentItem : parentItems) {
      for (Rollup__mdt rollupMeta : this.rollupInfo) {
        if (this.parentRollupFieldHasBeenReset(rollupMeta, parentItem) == false && parentFields.containsKey(rollupMeta.RollupFieldOnLookupObject__c)) {
          parentItem.put(rollupMeta.RollupFieldOnLookupObject__c, null);
        }
      }
    }
    this.getDML().doUpdate(parentItems);
  }

  protected override String getTypeName() {
    return RollupParentResetProcessor.class.getName();
  }

  protected override String startAsyncWork() {
    return System.enqueueJob(new QueueableResetProcessor(this, this.rollupControl.BatchChunkSize__c.intValue()));
  }

  private Integer getNumberOfItems() {
    return Database.countQuery(this.queryString.replaceFirst('SELECT.+\n', 'SELECT Count()\n'));
  }

  private void runSync() {
    List<SObject> parentItems = Database.query(this.queryString);
    this.execute(null, parentItems);
    this.logFinish();
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
          additionalFilters += meta.RollupFieldOnLookupObject__c + (' != null' + orClause);
        }
      }
    }

    return isValidRun ? localQueryString + '\nAND (' + additionalFilters.removeEnd(orClause) + ')' : localQueryString;
  }
}
