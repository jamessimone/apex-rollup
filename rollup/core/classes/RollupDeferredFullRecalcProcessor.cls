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

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return this.getDelegatedFullRecalcRollups(this.getCalcItems());
  }

  protected override String getTypeName() {
    return RollupDeferredFullRecalcProcessor.class.getName();
  }
}
