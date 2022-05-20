@SuppressWarnings('PMD.UnusedLocalVariable')
public abstract without sharing class RollupFullRecalcProcessor extends RollupAsyncProcessor.QueueableProcessor {
  public String queryString;

  protected final List<Rollup__mdt> rollupInfo;
  protected final Set<String> recordIds;
  protected final Set<String> objIds = new Set<String>(); // necessary; there's a bind variable in the query string

  private final Set<String> previouslyResetParents = new Set<String>();
  private final RollupFullRecalcProcessor postProcessor;

  private static final Map<String, List<SObject>> QUERY_TO_CALC_ITEMS {
    get {
      if (QUERY_TO_CALC_ITEMS == null) {
        QUERY_TO_CALC_ITEMS = new Map<String, List<SObject>>();
      }
      return QUERY_TO_CALC_ITEMS;
    }
    set;
  }

  public RollupFullRecalcProcessor(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupInfo,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(invokePoint);
    this.isFullRecalc = true;
    this.isNoOp = true; // consumers should either opt out of this or have it be set properly downstream
    this.calcItemType = calcItemType;
    this.queryString = queryString;
    this.rollupInfo = rollupInfo;
    this.recordIds = recordIds;
    this.postProcessor = postProcessor;
    this.overrideRollupControl();
  }

  public SObjectType getCalcItemType() {
    return this.calcItemType;
  }

  public override Rollup addLimit(Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    for (Rollup__mdt rollupMeta : this.rollupInfo) {
      this.addLimitToMetadata(rollupMeta, limitAmount, calcItemRollupField);
    }
    return this;
  }

  public override Rollup addOrderBys(List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    for (Integer index = 0; index < this.rollupInfo.size(); index++) {
      Rollup__mdt rollupMeta = this.addOrderBys(this.rollupInfo[index], orderBys, calcItemRollupField);
      this.rollupInfo.set(index, rollupMeta);
    }
    return this;
  }

  protected List<SObject> getCalcItemsByQuery() {
    if (QUERY_TO_CALC_ITEMS.containsKey(this.queryString)) {
      RollupLogger.Instance.log('returning pre-queried records from cache', LoggingLevel.FINE);
      return QUERY_TO_CALC_ITEMS.get(this.queryString);
    }
    List<SObject> calcItems = Database.query(this.queryString);
    QUERY_TO_CALC_ITEMS.put(this.queryString, calcItems);
    return calcItems;
  }

  protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    props = super.customizeToStringEntries(props);
    this.addToMap(props, 'Rollup Metadata', this.rollupInfo);
    this.addToMap(props, 'Query String', this.queryString);
    return props;
  }

  protected override String getHashedContents() {
    return String.valueOf(this.rollupInfo);
  }

  protected virtual override String startAsyncWork() {
    return this.enqueue();
  }

  public void finish() {
    if (this.postProcessor != null) {
      RollupLogger.Instance.log('Starting post-full recalc processor', this.postProcessor, LoggingLevel.DEBUG);
      // chain jobs together so that if recalc job is being tracked within the Recalc Rollups app,
      // job continuity is established between the full recalc and then any downstream job that runs
      // (as the postProcessor)
      this.setCurrentJobId(this.postProcessor.runCalc());
    }
  }

  public Boolean parentRollupFieldHasBeenReset(Rollup__mdt meta, SObject parent) {
    return this.previouslyResetParents.contains(this.getKey(meta.RollupFieldOnLookupObject__c, parent));
  }

  public Boolean parentRollupFieldHasBeenReset(RollupAsyncProcessor processor, SObject parent) {
    return this.previouslyResetParents.contains(this.getKey(String.valueOf(processor.opFieldOnLookupObject), parent));
  }

  public void storeParentResetField(RollupAsyncProcessor processor, SObject parent) {
    this.previouslyResetParents.add(this.getKey(String.valueOf(processor.opFieldOnLookupObject), parent));
    this.postProcessor?.recordIds.add(parent.Id);
    this.postProcessor?.storeParentResetField(processor, parent);
  }

  private String getKey(String fieldKey, SObject parent) {
    return fieldKey + parent.Id;
  }

  private void overrideRollupControl() {
    for (Rollup__mdt meta : this.rollupInfo) {
      if (meta.RollupControl__c != null) {
        RollupControl__mdt specificControl = this.getSpecificControl(meta.RollupControl__c);
        this.overrideParentRollupControlValues(specificControl);
      }
    }
  }
}
