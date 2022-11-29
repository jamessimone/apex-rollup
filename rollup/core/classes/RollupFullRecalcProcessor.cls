@SuppressWarnings('PMD.UnusedLocalVariable')
public abstract without sharing class RollupFullRecalcProcessor extends RollupAsyncProcessor.QueueableProcessor {
  protected final List<Rollup__mdt> rollupMetas;
  protected final Set<String> recordIds;
  protected final Set<String> objIds = new Set<String>(); // necessary; there's a bind variable in the query string

  private final RollupFullRecalcProcessor postProcessor;
  private final Map<Id, SObject> parentRecordsToClear = new Map<Id, SObject>();

  protected String queryString;
  private Boolean hasProcessedParentRecords = false;

  private static final Map<String, List<SObject>> QUERY_TO_CALC_ITEMS {
    get {
      if (QUERY_TO_CALC_ITEMS == null) {
        QUERY_TO_CALC_ITEMS = new Map<String, List<SObject>>();
      }
      return QUERY_TO_CALC_ITEMS;
    }
    set;
  }

  protected RollupFullRecalcProcessor(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupMetas,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(invokePoint);
    this.isFullRecalc = true;
    this.calcItemType = calcItemType;
    this.queryString = queryString;
    this.rollupMetas = rollupMetas;
    this.recordIds = recordIds;
    this.postProcessor = postProcessor;
    this.overrideRollupControl();
    this.previouslyResetParents = new Set<String>();
  }

  public virtual Boolean isBatch() {
    return false;
  }

  public void setQuery(String replacementQuery) {
    this.queryString = replacementQuery;
  }

  public SObjectType getCalcItemType() {
    return this.calcItemType;
  }

  public override Rollup addLimit(Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    for (Rollup__mdt rollupMeta : this.rollupMetas) {
      this.addLimitToMetadata(rollupMeta, limitAmount, calcItemRollupField);
    }
    return this;
  }

  public override Rollup addOrderBys(List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    for (Integer index = 0; index < this.rollupMetas.size(); index++) {
      Rollup__mdt rollupMeta = this.addOrderBys(this.rollupMetas[index], orderBys, calcItemRollupField);
      this.rollupMetas.set(index, rollupMeta);
    }
    return this;
  }

  public void finish() {
    if (this.postProcessor != null) {
      RollupLogger.Instance.log('Starting post-full recalc processor', this.postProcessor, LoggingLevel.DEBUG);
      // chain jobs together so that if recalc job is being tracked within the Recalc Rollups app,
      // job continuity is established between the full recalc and then any downstream job that runs
      // (as the postProcessor)
      this.setCurrentJobId(this.postProcessor.runCalc());
    }
    if (this.hasProcessedParentRecords == false) {
      List<SObject> parentRecords = new List<SObject>();
      this.processParentFieldsToReset(parentRecords);
      this.getDML().doUpdate(parentRecords);
    }
  }

  public override void storeParentResetField(RollupAsyncProcessor processor, SObject parent) {
    this.addToPreviouslyResetParents(processor, parent);
    this.postProcessor?.recordIds.add(parent.Id);
    this.postProcessor?.addToPreviouslyResetParents(processor, parent);
  }

  public void storeParentFieldsToClear(List<SObject> parentRecordsToClear) {
    this.parentRecordsToClear.putAll(parentRecordsToClear);
  }

  public void processParentFieldsToReset(List<SObject> relatedParentRecords) {
    if (this.hasProcessedParentRecords || this.rollupControl.ShouldSkipResettingParentFields__c == true) {
      return;
    }
    this.hasProcessedParentRecords = true;
    Map<Id, SObject> relatedParentRecordsMap = new Map<Id, SObject>(relatedParentRecords);
    for (SObject parentRecordToReset : this.parentRecordsToClear.values()) {
      SObject relatedParentRecord = relatedParentRecordsMap.containsKey(parentRecordToReset.Id)
        ? relatedParentRecordsMap.get(parentRecordToReset.Id)
        : RollupCurrencyInfo.createNewRecord(parentRecordToReset);

      for (Rollup__mdt meta : this.rollupMetas) {
        if (relatedParentRecord.getSObjectType().getDescribe().getName() == meta.LookupObject__c) {
          relatedParentRecord.put(meta.RollupFieldOnLookupObject__c, null);
        }
      }

      relatedParentRecordsMap.put(relatedParentRecord.Id, relatedParentRecord);
    }
    relatedParentRecords.clear();
    relatedParentRecords.addAll(relatedParentRecordsMap.values());
    this.parentRecordsToClear.clear();
  }

  protected List<SObject> getCalcItemsByQuery() {
    if (QUERY_TO_CALC_ITEMS.containsKey(this.queryString)) {
      RollupLogger.Instance.log('returning pre-queried records from cache', LoggingLevel.FINE);
      return QUERY_TO_CALC_ITEMS.get(this.queryString);
    }
    List<SObject> localCalcItems = Database.query(this.queryString);
    QUERY_TO_CALC_ITEMS.put(this.queryString, localCalcItems);
    return localCalcItems;
  }

  protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    props = super.customizeToStringEntries(props);
    this.addToMap(props, 'Rollup Metadata', this.rollupMetas);
    this.addToMap(props, 'Query String', this.queryString);
    return props;
  }

  protected override String getHashedContents() {
    return String.valueOf(this.rollupMetas);
  }

  protected override Boolean getCanRollupWithoutCustomSetting() {
    Boolean canRollupWithoutCustomSetting = false;
    for (Rollup__mdt rollupMeta : this.rollupMetas) {
      canRollupWithoutCustomSetting = rollupMeta.ShouldRunWithoutCustomSettingEnabled__c == true;
      // all included rollups need to have the override enabled; if even one does NOT, we can stop
      if (canRollupWithoutCustomSetting == false) {
        break;
      }
    }
    return canRollupWithoutCustomSetting;
  }

  private void overrideRollupControl() {
    for (Rollup__mdt meta : this.rollupMetas) {
      if (meta.RollupControl__c != null) {
        RollupControl__mdt specificControl = this.getSpecificControl(meta.RollupControl__c);
        this.overrideParentRollupControlValues(specificControl);
      }
    }
  }
}
