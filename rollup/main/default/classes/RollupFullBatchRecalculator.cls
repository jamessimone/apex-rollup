public class RollupFullBatchRecalculator extends Rollup {
  private final String queryString;
  private final Rollup__mdt rollupInfo;
  private final SObjectType calcItemType;

  public RollupFullBatchRecalculator(String queryString, RollupInvocationPoint invokePoint, Rollup__mdt rollupInfo, SObjectType calcItemType) {
    super(invokePoint);
    this.queryString = queryString;
    this.rollupInfo = rollupInfo;
  }

  public override Database.QueryLocator start(Database.BatchableContext bc) {
    Set<Id> objIds = new Set<Id>(); // necessary; there's a bind variable in the query string
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
    this.getDelegatedRollup(
        this.rollupInfo,
        this.calcItemType,
        calcItems,
        new Map<Id, SObject>(calcItems),
        null, // the evaluator, which we don't need here
        this.invokePoint
      )
      .runCalc();
  }

  public override void finish(Database.BatchableContext bc) {
    System.debug('Recalculation batched');
  }
}
