public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor implements Database.Stateful, Database.RaisesPlatformEvents {
  private final RollupState state = new RollupState();

  public RollupFullBatchRecalculator(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupMetas,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(RollupQueryBuilder.Current.getAllRowSafeQuery(calcItemType, queryString), invokePoint, rollupMetas, calcItemType, recordIds, postProcessor);
  }

  public override RollupState getState() {
    return this.state;
  }

  protected override void performWork() {
    this.process(this.getDelegatedFullRecalcRollups(this.calcItems));
  }

  protected override Boolean isBatch() {
    return true;
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    if (this.isProcessed == false && this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous && System.isBatch() == false) {
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
}
