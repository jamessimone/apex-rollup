public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor implements Database.Stateful, Database.RaisesPlatformEvents {
  protected final Set<String> statefulPreviouslyResetParents = new Set<String>();

  public RollupFullBatchRecalculator(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupMetas,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(queryString, invokePoint, rollupMetas, calcItemType, recordIds, postProcessor);
  }

  public override Database.QueryLocator start(Database.BatchableContext bc) {
    // note - if the optional where clause was appended to the passed in query string,
    // this.recordIds is also used as a bind variable
    return Database.getQueryLocator(RollupQueryBuilder.Current.getAllRowSafeQuery(this.calcItemType, this.queryString));
  }

  public virtual override void execute(Database.BatchableContext bc, List<SObject> calcItems) {
    this.logger.log(
      'starting full batch chunk for: ' +
      this.rollupMetas.size() +
      ' rollups with state',
      this.statefulPreviouslyResetParents,
      LoggingLevel.INFO
    );
    /**
     * this batch class is a glorified "for loop" for the calc items, dispatching
     * them to the overall Rollup framework while breaking us out of the query limits
     * it has to be it's own class - Database.Batchable does not support inner classes
     * being batched, even if the inner class is just extending the functionality of its
     * parent class
     */
    this.process(this.getDelegatedFullRecalcRollups(calcItems));
    this.logger.log('batch chunk end', LoggingLevel.INFO);
    this.logger.save();
  }

  protected override Boolean isBatch() {
    return true;
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    if (this.isProcessed == false && this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous) {
      this.startAsyncWork();
    }
    return new List<RollupAsyncProcessor>();
  }

  protected virtual override String getTypeName() {
    return RollupFullBatchRecalculator.class.getName();
  }

  protected virtual override String startAsyncWork() {
    return this.startBatchProcessor();
  }

  protected override Set<String> getPreviouslyResetParents() {
    return this.statefulPreviouslyResetParents;
  }
}
