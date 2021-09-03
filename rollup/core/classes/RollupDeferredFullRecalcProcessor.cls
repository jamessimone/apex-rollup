public class RollupDeferredFullRecalcProcessor extends RollupAsyncProcessor.FullRecalcProcessor {
  public RollupDeferredFullRecalcProcessor(
    List<Rollup__mdt> matchingMeta,
    SObjectType calcItemType,
    String queryString,
    Set<Id> recordIds,
    InvocationPoint invokePoint
  ) {
    super(queryString, invokePoint, matchingMeta, calcItemType, recordIds);
  }

  public override String runCalc() {
    return this.getProcessor().runCalc();
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return this.getProcessor().rollups;
  }

  protected override String getTypeName() {
    return RollupDeferredFullRecalcProcessor.class.getName();
  }

  private RollupAsyncProcessor getProcessor() {
    this.isProcessed = true;
    List<SObject> localCalcItems = Database.query(this.queryString);
    return this.getDelegatedFullRecalcRollup(this.rollupInfo, localCalcItems, this);
  }
}
