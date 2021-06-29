public class RollupFullBatchRecalculator extends RollupAsyncProcessor implements Database.Stateful {
  private final String queryString;
  private final List<Rollup__mdt> rollupInfo;
  private final Set<Id> recordIds;
  private final Map<String, CachedCalcItems> lookupKeyToCachedChildren = new Map<String, CachedCalcItems>();

  private String currentBatchId;

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
  }

  public override Database.QueryLocator start(Database.BatchableContext bc) {
    Set<Id> objIds = new Set<Id>(); // necessary; there's a bind variable in the query string
    // note - if the optional where clause was appended to the passed in query string, this.recordIds is also
    // used as a bind variable
    return Database.getQueryLocator(this.queryString);
  }

  public override void execute(Database.BatchableContext bc, List<SObject> calcItems) {
    this.currentBatchId = bc.getChildJobId();
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

  protected override void retrieveAdditionalCalcItems(List<SObject> localCalcItems, String lookupKey, String lookupFieldOnCalcItem, Rollup__mdt meta) {
    if (String.isNotBlank(meta.GrandparentRelationshipFieldPath__c) || meta.RollupToUltimateParent__c ) {
      // grandparent / hierarchy rollups unsupported
      return;
    } else if (this.lookupKeyToCachedChildren.containsKey(lookupKey) == false && localCalcItems.isEmpty() == false) {
      RollupLogger.Instance.log('querying to ensure we have all calc items for parent: ' + lookupKey, LoggingLevel.DEBUG);
      Set<Id> objIds = new Map<Id, SObject>(localCalcItems).keySet();
      // the fields used in all calc item where clauses and for all the included rollups are already
      // in existence in the larger query string that's spawned this batch process
      // reconstituting any necessary fields from there allows us to cache the calc items by lookupKey, instead of
      // by something more tenuous (like the stringified value of the Rollup__mdt record passed)
      List<String> populatedFieldNames = this.queryString.split('\\n')[0].substringAfter('SELECT ').split(',');

      String whereClause =  lookupFieldOnCalcItem + ' = \'' + lookupKey + '\'';
      String query = RollupQueryBuilder.Current.getQuery(localCalcItems[0].getSObjectType(), populatedFieldNames, 'Id', '!=', whereClause);
      List<SObject> additionalCalcItems = Database.query(query);
      RollupLogger.Instance.log('number of additionally retrieved records: ' + additionalCalcItems.size(), LoggingLevel.DEBUG);

      CachedCalcItems cache = new CachedCalcItems();
      cache.additionalCalcItems = additionalCalcItems;
      cache.retrievedInBatchId = this.currentBatchId;
      this.lookupKeyToCachedChildren.put(lookupKey, cache);
    }

    if (this.lookupKeyToCachedChildren.containsKey(lookupKey)) {
      localCalcItems.addAll(this.lookupKeyToCachedChildren.get(lookupKey).additionalCalcItems);
    }
  }

  protected override Boolean shouldBypassUpdatingLookupItems(String lookupKey) {
    Boolean shouldBypass = false;
    if (this.lookupKeyToCachedChildren.containsKey(lookupKey)) {
      shouldBypass = this.lookupKeyToCachedChildren.get(lookupKey).retrievedInBatchId != this.currentBatchId;
    }
    return shouldBypass;
  }

  private class CachedCalcItems {
    public List<SObject> additionalCalcItems;
    public String retrievedInBatchId;
  }
}
