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
    super(RollupQueryBuilder.Current.getAllRowSafeQuery(calcItemType, queryString), invokePoint, rollupMetas, calcItemType, recordIds, postProcessor);
  }

  protected override void performWork() {
    this.process(this.getDelegatedFullRecalcRollups(this.calcItems));
  }

  protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    props = super.customizeToStringEntries(props);
    this.addToMap(props, 'Stateful Previously Reset Parents', this.statefulPreviouslyResetParents);
    return props;
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

  protected override Set<String> getPreviouslyResetParents() {
    return this.statefulPreviouslyResetParents;
  }
}
