public without sharing virtual class RollupDeferredFullRecalcProcessor extends RollupFullRecalcProcessor {
  private static final Map<String, List<SObject>> QUERY_TO_CALC_ITEMS = new Map<String, List<SObject>>();

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

  protected List<SObject> getCalcItems() {
    if (QUERY_TO_CALC_ITEMS.containsKey(this.queryString)) {
      this.logger.log('returning pre-queried records from cache', System.LoggingLevel.FINE);
      return QUERY_TO_CALC_ITEMS.get(this.queryString);
    }
    List<SObject> localCalcItems = this.preStart().get();
    if (this.isNoOpOverridden && this.calcItems?.isEmpty() == false) {
      localCalcItems.addAll(this.calcItems);
    }
    QUERY_TO_CALC_ITEMS.put(this.queryString, localCalcItems);
    return localCalcItems;
  }
}
