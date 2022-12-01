public without sharing virtual class RollupDeferredFullRecalcProcessor extends RollupFullRecalcProcessor {
  public RollupDeferredFullRecalcProcessor(
    List<Rollup__mdt> matchingMeta,
    SObjectType calcItemType,
    String queryString,
    Set<String> recordIds,
    InvocationPoint invokePoint,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(queryString, invokePoint, matchingMeta, calcItemType, recordIds, postProcessor);
  }

  public override String runCalc() {
    this.process(this.getRollups());
    return this.getCurrentJobId();
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return this.getRollups();
  }

  protected override String getTypeName() {
    return RollupDeferredFullRecalcProcessor.class.getName();
  }

  private List<RollupAsyncProcessor> getRollups() {
    this.isProcessed = true;
    return this.getDelegatedFullRecalcRollup(this.rollupMetas, this.getCalcItemsByQuery(), this);
  }
}
