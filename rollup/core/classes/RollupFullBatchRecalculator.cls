public class RollupFullBatchRecalculator extends Rollup {
  private final String queryString;
  private final List<Rollup__mdt> rollupInfo;
  private final Set<Id> recordIds;

  public RollupFullBatchRecalculator(
    String queryString,
    RollupInvocationPoint invokePoint,
    List<Rollup__mdt> rollupInfo,
    SObjectType calcItemType,
    Set<Id> recordIds
  ) {
    super(invokePoint);
    this.calcItemType = calcItemType;
    this.queryString = queryString;
    this.rollupInfo = rollupInfo;
    this.recordIds = recordIds;
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
    Rollup roll = this.getDelegatedRollup(this.rollupInfo, calcItems, new Map<Id, SObject>(calcItems));
    roll.isFullRecalc = true;
    roll.runCalc();
  }

  public override void finish(Database.BatchableContext bc) {
    this.log('RollupFullBatchRecalculator finished');
  }
}
