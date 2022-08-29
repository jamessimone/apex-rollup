public without sharing class RollupDeferredFullRecalcProcessor extends RollupFullRecalcProcessor {
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
    return this.getProcessor()?.runCalc();
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return this.getProcessor().rollups;
  }

  protected override String getTypeName() {
    return RollupDeferredFullRecalcProcessor.class.getName();
  }

  private RollupAsyncProcessor getProcessor() {
    this.isProcessed = true;
    return this.getDelegatedFullRecalcRollup(this.rollupMetas, this.getCalcItemsByQuery(), this);
  }
}
