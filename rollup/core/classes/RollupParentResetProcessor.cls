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
    Set<Id> recordIds,
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

  public override void execute(Database.BatchableContext bc, List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return;
    }
    RollupLogger.Instance.log('resetting parent fields for: ' + calcItems.size() + ' items', LoggingLevel.DEBUG);
    for (SObject parentItem : calcItems) {
      for (Rollup__mdt rollupMeta : this.rollupInfo) {
        parentItem.put(rollupMeta.RollupFieldOnLookupObject__c, null);
      }
    }
    this.getDML().doUpdate(calcItems);
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
  }

  private static String getRefinedQueryString(String localQueryString, List<Rollup__mdt> matchingMeta) {
    isValidRun = false;
    if (matchingMeta.isEmpty() == false) {
      localQueryString += '\nAND (';
    } else {
      return localQueryString;
    }

    Map<String, SObjectField> fieldTokens = RollupFieldInitializer.Current.getSObjectFromName(matchingMeta[0].LookupObject__c)
      .getSObjectType()
      .getDescribe()
      .fields.getMap();
    for (Rollup__mdt meta : matchingMeta) {
      SObjectField token = RollupFieldInitializer.Current.getSObjectFieldByName(fieldTokens, meta.RollupFieldOnLookupObject__c);
      if (token.getDescribe().isFilterable()) {
        isValidRun = isValidRun || true;
        localQueryString += meta.RollupFieldOnLookupObject__c + ' != null OR ';
      }
    }
    return localQueryString.removeEnd(' OR ') + ')';
  }
}
