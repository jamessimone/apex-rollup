public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor implements Database.Stateful {
  private final Map<String, CalcItemBag> statefulLookupToCalcItems = new Map<String, CalcItemBag>();

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
    this.isProcessed = true;
    // note - if the optional where clause was appended to the passed in query string,
    // this.recordIds is also used as a bind variable
    return Database.getQueryLocator(RollupQueryBuilder.Current.getAllRowSafeQuery(this.calcItemType, this.queryString));
  }

  public virtual override void execute(Database.BatchableContext bc, List<SObject> calcItems) {
    RollupLogger.Instance.log('starting full batch recalc run:', this, LoggingLevel.DEBUG);
    /**
     * this batch class is a glorified "for loop" for the calc items, dispatching
     * them to the overall Rollup framework while breaking us out of the query limits
     * it has to be it's own class - Database.Batchable does not support inner classes
     * being batched, even if the inner class is just extending the functionality of its
     * parent class
     */
    this.getDelegatedFullRecalcRollup(this.rollupMetas, calcItems, this)?.runCalc();
    RollupLogger.Instance.save();
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    if (this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous) {
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

  protected override Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor roll, Set<String> uniqueLookupObjectFields) {
    if (this.statefulLookupToCalcItems.isEmpty() == false) {
      return this.statefulLookupToCalcItems;
    }
    return super.getCalcItemsByLookupField(roll, uniqueLookupObjectFields);
  }

  protected override void retrieveAdditionalCalcItems(Map<String, CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    Map<String, CalcItemBag> lookupKeysThatNeedFilling = new Map<String, CalcItemBag>();
    for (String lookupKey : lookupToCalcItems.keySet()) {
      CalcItemBag bag = lookupToCalcItems.get(lookupKey);
      CalcItemBag potentiallyStatefulBag = this.statefulLookupToCalcItems.get(lookupKey);
      if (potentiallyStatefulBag != null && potentiallyStatefulBag.hasQueriedForAdditionalItems) {
        lookupToCalcItems.put(lookupKey, this.statefulLookupToCalcItems.get(lookupKey));
      } else {
        lookupKeysThatNeedFilling.put(lookupKey, bag);
      }
    }

    super.retrieveAdditionalCalcItems(lookupKeysThatNeedFilling, rollup);

    for (String lookupKey : lookupKeysThatNeedFilling.keySet()) {
      CalcItemBag bag = lookupKeysThatNeedFilling.get(lookupKey);
      this.statefulLookupToCalcItems.put(lookupKey, bag);
      lookupToCalcItems.put(lookupKey, bag);
      this.recordIds.add(lookupKey);
    }
  }
}
