public class RollupFullBatchRecalculator extends RollupAsyncProcessor implements Database.Stateful {
  private final String queryString;
  private final List<Rollup__mdt> rollupInfo;
  private final Set<Id> recordIds;
  private final Map<String, Rollup.CalcItemBag> statefulLookupToCalcItems;

  public RollupFullBatchRecalculator(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupInfo,
    SObjectType calcItemType,
    Set<Id> recordIds
  ) {
    super(invokePoint);
    this.isNoOp = false;
    this.calcItemType = calcItemType;
    this.queryString = queryString;
    this.rollupInfo = rollupInfo;
    this.recordIds = recordIds;
    this.statefulLookupToCalcItems = new Map<String, Rollup.CalcItemBag>();
  }

  public override Database.QueryLocator start(Database.BatchableContext bc) {
    Set<Id> objIds = new Set<Id>(); // necessary; there's a bind variable in the query string
    // note - if the optional where clause was appended to the passed in query string, this.recordIds is also
    // used as a bind variable
    return Database.getQueryLocator(this.queryString);
  }

  public override void execute(Database.BatchableContext bc, List<SObject> calcItems) {
    /**
     * this batch class is a glorified "for loop" for the calc items, dispatching
     * them to the overall Rollup framework while breaking us out of the query limits
     * it has to be it's own class - Database.Batchable does not support inner classes
     * being batched, even if the inner class is just extending the functionality of its
     * parent class
     */
    this.processDelegatedFullRecalcRollup(this.rollupInfo, calcItems, new Map<Id, SObject>(calcItems));
    RollupLogger.Instance.save();
  }

  public override void finish(Database.BatchableContext bc) {
    RollupLogger.Instance.log('RollupFullBatchRecalculator finished', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
  }

  protected override void retrieveAdditionalCalcItems(Map<String, Rollup.CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    Map<String, Rollup.CalcItemBag> local = new Map<String, Rollup.CalcItemBag>();
    for (String lookupKey : lookupToCalcItems.keySet()) {
      Rollup.CalcItemBag bag = lookupToCalcItems.get(lookupKey);
      if (bag.hasQueriedForAdditionalItems == false && this.statefulLookupToCalcItems.containsKey(lookupKey)) {
        bag = this.statefulLookupToCalcItems.get(lookupKey);
      } else {
        local.put(lookupKey, bag);
      }
    }

    super.retrieveAdditionalCalcItems(local, rollup);

    for (String lookupKey : local.keySet()) {
      this.statefulLookupToCalcItems.put(lookupKey, local.get(lookupKey));
    }
  }
}
