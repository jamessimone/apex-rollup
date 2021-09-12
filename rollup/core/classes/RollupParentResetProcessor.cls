public inherited sharing class RollupParentResetProcessor extends RollupAsyncProcessor.FullRecalcProcessor {
  public RollupParentResetProcessor(
    List<Rollup__mdt> matchingMeta,
    SObjectType calcItemType,
    String queryString,
    Set<Id> recordIds,
    InvocationPoint invokePoint
  ) {
    super(getRefinedQueryString(queryString, matchingMeta), invokePoint, matchingMeta, calcItemType, recordIds);
    this.overridesRunCalc = true;
  }

  public override String runCalc() {
    this.isProcessed = true;
    List<SObject> parentItems = Database.query(this.queryString);
    for (SObject parentItem : parentItems) {
      for (Rollup__mdt rollupMeta : this.rollupInfo) {
        parentItem.put(rollupMeta.RollupFieldOnLookupObject__c, null);
      }
    }
    this.getDML().doUpdate(parentItems);
    return 'No process Id';
  }

  protected override String getTypeName() {
    return RollupParentResetProcessor.class.getName();
  }

  private static String getRefinedQueryString(String localQueryString, List<Rollup__mdt> matchingMeta) {
    if (matchingMeta.isEmpty() == false) {
      localQueryString += '\nAND (';
    }
    for (Rollup__mdt meta : matchingMeta) {
      localQueryString += meta.RollupFieldOnLookupObject__c + ' != null OR ';
    }
    return localQueryString.removeEnd(' OR ') + ')';
  }
}