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
    RollupAsyncProcessor processor = (RollupAsyncProcessor) this.getAsyncRollup(
      this.rollupInfo,
      this.calcItemType,
      localCalcItems,
      new Map<Id, SObject>(),
      null,
      this.invokePoint
    );
    processor.isFullRecalc = true;
    for (Rollup innerRoll : processor.rollups) {
      innerRoll.isFullRecalc = true;
      innerRoll.calcItems = localCalcItems;
    }
    return processor;
  }
}
