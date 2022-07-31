global without sharing virtual class Rollup {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @TestVisible
  private static Boolean shouldRun = false;
  @TestVisible
  private static TriggerOperation apexContext;
  @TestVisible
  private static List<SObject> records;
  @TestVisible
  private static Map<Id, SObject> oldRecordsMap;
  @TestVisible
  private static List<Rollup__mdt> rollupMetadata;
  @TestVisible
  private static RollupControl__mdt defaultControl;
  @TestVisible
  private static RollupControl__mdt specificControl;
  @TestVisible
  private static Boolean onlyUseMockMetadata = false;
  @TestVisible
  private static final String CONTROL_ORG_DEFAULTS = 'Org_Defaults';

  private static List<Rollup__mdt> cachedMetadata;
  private static RollupControl__mdt cachedOrgDefault;
  private static Boolean isCDC = false;
  private static Boolean isDeferralAllowed = true;
  private static Boolean isFullRecalcApp = false;
  private static String currentJobId;

  protected final RollupControl__mdt rollupControl;
  protected final InvocationPoint invokePoint;
  protected final Boolean isConductor;

  // non-final instance variables
  protected List<SObject> calcItems;
  protected Rollup__mdt metadata;
  protected Boolean isFullRecalc = false;
  protected Boolean isNoOp;
  protected Boolean isCDCUpdate = false;
  protected Integer queryCount;
  protected RollupCalcItemReplacer calcItemReplacer;

  // Lazy-load section. Lots of additional lines, but with the benefit that we keep the heap size down for instances of Rollup
  // that never reference these variables
  private static final Map<SObjectType, Set<TriggerOperation>> CACHED_APEX_OPERATIONS {
    get {
      if (CACHED_APEX_OPERATIONS == null) {
        CACHED_APEX_OPERATIONS = new Map<SObjectType, Set<TriggerOperation>>();
      }
      return CACHED_APEX_OPERATIONS;
    }
    set;
  }

  private static final List<RollupFullRecalcProcessor> CACHED_FULL_RECALCS {
    get {
      if (CACHED_FULL_RECALCS == null) {
        CACHED_FULL_RECALCS = new List<RollupFullRecalcProcessor>();
      }
      return CACHED_FULL_RECALCS;
    }
    set;
  }

  private static final List<Rollup> CACHED_ROLLUPS {
    get {
      if (CACHED_ROLLUPS == null) {
        CACHED_ROLLUPS = new List<Rollup>();
      }
      return CACHED_ROLLUPS;
    }
    set;
  }

  private static final RollupCalcItemReplacer CALC_ITEM_REPLACER {
    get {
      if (CALC_ITEM_REPLACER == null) {
        CALC_ITEM_REPLACER = new RollupCalcItemReplacer(getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl));
      }
      return CALC_ITEM_REPLACER;
    }
    set;
  }

  protected Map<Id, SObject> oldCalcItems {
    get {
      if (oldCalcItems == null) {
        oldCalcItems = new Map<Id, SObject>();
      }
      return oldCalcItems;
    }
    set;
  }

  protected final Set<Id> matchingCalcItemIds {
    get {
      if (matchingCalcItemIds == null) {
        matchingCalcItemIds = new Set<Id>();
      }
      return matchingCalcItemIds;
    }
    set;
  }

  @TestVisible
  protected final List<RollupAsyncProcessor> rollups {
    get {
      if (rollups == null) {
        rollups = new List<RollupAsyncProcessor>();
      }
      return rollups;
    }
    set;
  }

  /**
   * receiving an interface/subclass from a property get/set (from the book "The Art Of Unit Testing") is an old technique;
   * useful in limited contexts to get around the classic approach to dependency injection
   * (such as in this case, when constructor-based DI isn't possible).
   * It's more palatable in Apex than in many other languages, as a matter of fact -
   * this is because the @TestVisible annotation enforces for us the override only being possible while testing
   */
  @TestVisible
  private static RollupSObjectUpdater DML {
    get {
      if (DML == null) {
        DML = new RollupSObjectUpdater();
      }
      return DML;
    }
    set;
  }

  public enum Op {
    AVERAGE,
    CONCAT_DISTINCT,
    CONCAT,
    COUNT_DISTINCT,
    COUNT,
    DELETE_AVERAGE,
    DELETE_CONCAT_DISTINCT,
    DELETE_CONCAT,
    DELETE_COUNT_DISTINCT,
    DELETE_COUNT,
    DELETE_FIRST,
    DELETE_LAST,
    DELETE_MAX,
    DELETE_MIN,
    DELETE_MOST,
    DELETE_SUM,
    FIRST,
    LAST,
    MAX,
    MIN,
    MOST,
    SUM,
    UPDATE_AVERAGE,
    UPDATE_CONCAT_DISTINCT,
    UPDATE_CONCAT,
    UPDATE_COUNT_DISTINCT,
    UPDATE_COUNT,
    UPDATE_FIRST,
    UPDATE_LAST,
    UPDATE_MAX,
    UPDATE_MIN,
    UPDATE_MOST,
    UPDATE_SUM
  }

  public class FilterResults {
    public FilterResults() {
      this.matchingItemIds = new Set<Id>();
    }
    public Set<Id> matchingItemIds { get; private set; }
    public Evaluator eval { get; set; }
  }

  private class RollupMetadata {
    public final Set<String> recordIds = new Set<String>();
    public final Set<String> queryFields = new Set<String>();
    public final List<Rollup__mdt> metadata = new List<Rollup__mdt>();
    public final List<SObject> parentRecordsToReset = new List<SObject>();
    public final Set<String> possibleWhereClauses = new Set<String>();
    public String whereClause = '';
    public Integer recordCount = RollupQueryBuilder.SENTINEL_COUNT_VALUE;

    public String concatenateWhereClauses() {
      if (this.recordIds.isEmpty() && this.possibleWhereClauses.isEmpty()) {
        return null;
      }
      String orDelimiter = ' OR ';
      String concatenatedWhereClause = '(';
      for (String possibleClause : this.possibleWhereClauses) {
        if (String.isBlank(possibleClause)) {
          // if even one of the where clauses is null, all calc items need to be retrieved
          // and the filtering has to be done in-memory
          return null;
        }
        concatenatedWhereClause += '(' + possibleClause + ')' + orDelimiter;
      }

      return concatenatedWhereClause.removeEnd(orDelimiter) + ')';
    }
  }

  private class FullRecalculationMetadata {
    private final Rollup__mdt meta;
    private final QueryWrapper wrapper;
    private final SObjectType calcItemType;
    public FullRecalculationMetadata(Rollup__mdt meta, QueryWrapper wrapper, SObjectType calcItemType) {
      this.meta = meta;
      this.wrapper = wrapper;
      this.calcItemType = calcItemType;
    }
  }

  public class CalcItemBag {
    private final Map<Id, SObject> idToCalcItem = new Map<Id, SObject>();
    private Boolean hasBeenCleared = false;
    public Boolean hasQueriedForAdditionalItems = false;
    public CalcItemBag(List<SObject> calcItems) {
      for (SObject calcItem : calcItems) {
        this.add(calcItem);
      }
    }

    public List<SObject> getAll() {
      return this.idToCalcItem.values();
    }

    public void clear() {
      if (this.hasBeenCleared == false) {
        this.idToCalcItem.clear();
        this.hasBeenCleared = true;
      }
    }

    public void add(SObject calcItem) {
      this.idToCalcItem.put(calcItem.Id, calcItem);
    }
  }

  global interface Evaluator {
    Boolean matches(Object calcItem);
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  global enum InvocationPoint {
    FROM_APEX,
    FROM_INVOCABLE,
    FROM_SCHEDULED,
    FROM_FULL_RECALC_LWC,
    FROM_SINGULAR_PARENT_RECALC_LWC,
    FROM_STATIC_LOGGER,
    FROM_FULL_RECALC_FLOW
  }

  protected Rollup() {
  }

  protected Rollup(InvocationPoint invokePoint) {
    this.invokePoint = invokePoint;
    this.rollupControl = getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl);
    if (invokePoint != InvocationPoint.FROM_STATIC_LOGGER) {
      this.calcItemReplacer = CALC_ITEM_REPLACER;
      this.isConductor = true;
      // a batch only becomes valid if other Rollups are added to it
      this.isNoOp = true;
    }
  }

  protected Rollup(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    this(invokePoint);
    this.calcItems = calcItems;
    this.oldCalcItems = oldCalcItems;
  }

  public override String toString() {
    Map<String, String> props = new Map<String, String>{
      'Type' => this.getTypeName(),
      'Invocation Point' => this.invokePoint?.name(),
      'Is Full Recalc' => String.valueOf(this.isFullRecalc),
      'Is No Op' => String.valueOf(this.isNoOp),
      'Is Conductor' => String.valueOf(this.isConductor),
      'Inner rollups' => String.valueOf(this.rollups.size())
    };

    this.customizeToStringEntries(props);

    String baseString = '';
    for (String key : props.keySet()) {
      baseString += key + ': ' + props.get(key) + '\n';
    }
    return baseString.removeEnd('\n');
  }

  public virtual String runCalc() {
    RollupLogger.Instance.log('no-op!', LoggingLevel.ERROR);
    return 'Not implemented';
  }

  public virtual Rollup addLimit(Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    for (Rollup roll : this.rollups) {
      this.addLimitToMetadata(roll.metadata, limitAmount, calcItemRollupField);
    }
    return this;
  }

  public virtual Rollup addOrderBys(List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    for (Rollup roll : this.rollups) {
      roll.metadata = this.addOrderBys(roll.metadata, orderBys, calcItemRollupField);
    }
    return this;
  }

  protected Rollup__mdt addOrderBys(Rollup__mdt localMeta, List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    if (localMeta.RollupFieldOnCalcItem__c == calcItemRollupField.getDescribe().getName()) {
      localMeta = appendOrderByMetadata(localMeta, orderBys);
    }
    return localMeta;
  }

  protected void addLimitToMetadata(Rollup__mdt localMeta, Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    if (localMeta.RollupFieldOnCalcItem__c == calcItemRollupField.getDescribe().getName()) {
      localMeta.LimitAmount__c = limitAmount;
      localMeta.IsFullRecordSet__c = true;
    }
  }

  protected RollupControl__mdt getSpecificControl(Id rollupControlId) {
    return getSingleControlOrDefault(RollupControl__mdt.Id, rollupControlId, specificControl);
  }

  protected List<Rollup> getCachedRollups() {
    return CACHED_ROLLUPS;
  }

  protected Map<SObjectType, Set<TriggerOperation>> getCachedApexOperations() {
    return CACHED_APEX_OPERATIONS;
  }

  protected Boolean getIsDeferralAllowed() {
    return isDeferralAllowed;
  }

  protected void setIsDeferralAllowed(Boolean value) {
    isDeferralAllowed = value;
  }

  protected void setCurrentJobId(String jobId) {
    currentJobId = jobId;
  }

  protected RollupAsyncProcessor getAsyncRollup(
    List<Rollup__mdt> rollupOperations,
    SObjectType sObjectType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    InvocationPoint rollupInvokePoint
  ) {
    return getRollup(rollupOperations, sObjectType, calcItems, oldCalcItems, eval, rollupInvokePoint);
  }

  protected RollupSObjectUpdater getDML() {
    DML.addRollupControl(this.rollupControl);
    return DML;
  }

  protected virtual String getHashedContents() {
    return null;
  }

  protected virtual String getTypeName() {
    return Rollup.class.getName();
  }

  protected virtual Map<String, String> customizeToStringEntries(Map<String, String> props) {
    this.addToMap(props, 'Rollup Metadata', this.metadata);
    this.addToMap(props, 'Rollup Control', this.rollupControl);
    this.addToMap(props, 'Calc Items', this.calcItems?.size() > 10 ? ((Object) this.calcItems.size() + ' items') : (Object) this.calcItems);
    if (this.oldCalcItems?.isEmpty() == false) {
      this.addToMap(props, 'Old Calc Items', this.oldCalcItems?.size() > 10 ? ((Object) this.oldCalcItems.size() + ' items') : (Object) this.oldCalcItems);
    }
    this.addToMap(props, 'Query Count', this.queryCount);
    return props;
  }

  protected void addToMap(Map<String, String> props, String key, Object ref) {
    if (ref != null) {
      props.put(key, JSON.serializePretty(ref));
    }
  }

  /**
   * global facing RollupAsyncProcessor calculation section
   * - Trigger operations
   * - Batch (multiple RollupAsyncProcessor operations chained into one job)
   * - Invocable
   * - Schedulable
   * - LWC-based full recalculation calls
   */

  @AuraEnabled(cacheable=true)
  global static Map<String, List<Rollup__mdt>> getRollupMetadataByCalcItem() {
    Map<String, List<Rollup__mdt>> calcItemToMetadata = new Map<String, List<Rollup__mdt>>();
    List<Rollup__mdt> localMetadata = getMetadataFromCache(Rollup__mdt.SObjectType);
    for (Rollup__mdt localMeta : localMetadata) {
      if (calcItemToMetadata.containsKey(localMeta.CalcItem__c)) {
        calcItemToMetadata.get(localMeta.CalcItem__c).add(localMeta);
      } else {
        calcItemToMetadata.put(localMeta.CalcItem__c, new List<Rollup__mdt>{ localMeta });
      }
    }
    return calcItemToMetadata;
  }

  /**
   * Rollup__mdt has a child CMDT relationship: Rollup__mdt.RollupOrderBys__r
   * Unfortunately, data passed between the frontend and backend strips out child relationship values
   * (even when they were set and initialized via the backend itself!). In order to avoid a breaking change
   * on this method, it instead delegates to the new one.
   */
  @AuraEnabled
  global static String performBulkFullRecalc(List<Rollup__mdt> metadata, String invokePointName) {
    return performSerializedBulkFullRecalc(JSON.serialize(metadata), invokePointName);
  }

  @AuraEnabled
  global static String performSerializedBulkFullRecalc(String serializedMetadata, String invokePointName) {
    InvocationPoint localInvokePoint = InvocationPoint.valueOf(invokePointName);
    switch on localInvokePoint {
      when FROM_FULL_RECALC_LWC, FROM_SINGULAR_PARENT_RECALC_LWC, FROM_FULL_RECALC_FLOW {
        isFullRecalcApp = true;
      }
    }
    List<Rollup__mdt> matchingMetadata = (List<Rollup__mdt>) JSON.deserialize(serializedMetadata, List<Rollup__mdt>.class);
    RollupLogger.Instance.log('bulk full recalc called with data:', matchingMetadata, LoggingLevel.DEBUG);

    String potentialWhereClause = '';
    String delimiter = ' ||| ';
    String lookupFieldName;
    Integer delimiterIndex = -1;
    String possibleParentId;

    Map<SObjectType, RollupMetadata> childToMetaWrapper = new Map<SObjectType, RollupMetadata>();
    for (Rollup__mdt matchingMeta : matchingMetadata) {
      FlowInput validationRuleWrapper = new FlowInput();
      validationRuleWrapper.rollupOperation = matchingMeta.RollupOperation__c.toUpperCase();
      validationRuleWrapper.concatDelimiter = matchingMeta.ConcatDelimiter__c;
      validationRuleWrapper.fullRecalculationDefaultStringValue = matchingMeta.FullRecalculationDefaultStringValue__c;
      validationRuleWrapper.fullRecalculationDefaultNumberValue = matchingMeta.FullRecalculationDefaultNumberValue__c;
      enforceValidationRules(validationRuleWrapper);

      if (localInvokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC && String.isBlank(potentialWhereClause)) {
        delimiterIndex = matchingMeta.CalcItemWhereClause__c.indexOf(delimiter);
        potentialWhereClause = matchingMeta.CalcItemWhereClause__c.substring(delimiterIndex + delimiter.length(), matchingMeta.CalcItemWhereClause__c.length());
        possibleParentId = potentialWhereClause.substringAfter(' = ').remove('\'');
        lookupFieldName = matchingMeta.LookupFieldOnCalcItem__c;
      } else if (String.isNotBlank(potentialWhereClause)) {
        potentialWhereClause = potentialWhereClause.replace(lookupFieldName, matchingMeta.LookupFieldOnCalcItem__c);
        lookupFieldName = matchingMeta.LookupFieldOnCalcItem__c;
      }
      if (delimiterIndex != -1) {
        matchingMeta.CalcItemWhereClause__c = matchingMeta.CalcItemWhereClause__c?.substringBeforeLast(delimiter);
        if (String.isNotBlank(matchingMeta.CalcItemWhereClause__c)) {
          matchingMeta.CalcItemWhereClause__c += ' AND ' + potentialWhereClause;
        } else {
          matchingMeta.CalcItemWhereClause__c = potentialWhereClause;
        }
      }

      populateFullRecalcMetasByType(childToMetaWrapper, matchingMeta, possibleParentId);
    }

    List<Rollup> processors = transformWrappedMetadataToFullRecalcRollups(childToMetaWrapper, localInvokePoint);
    isFullRecalcApp = false;
    return batch(processors, localInvokePoint);
  }

  @AuraEnabled
  global static String getBatchRollupStatus(String jobId) {
    if (currentJobId != null) {
      jobId = currentJobId;
    }
    return [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1]?.Status;
  }

  /**
   * Sending metadata from the frontend LWCs omits
   * the RollupOrderBys__r children unless it's sent serialized (using the same
   * child object format used in the "appendOrderByMetadata").
   */
  @AuraEnabled
  global static String performSerializedFullRecalculation(String metadata) {
    return performSerializedBulkFullRecalc('[' + metadata + ']', InvocationPoint.FROM_FULL_RECALC_LWC.name());
  }

  @AuraEnabled
  global static String performFullRecalculation(Rollup__mdt meta) {
    return performSerializedFullRecalculation(JSON.serialize(meta));
  }

  global class FlowInput {
    @InvocableVariable(label='Calc Item Calc Field' description='The API Name of the field on each of the records passed in to rollup.' required=true)
    global String rollupFieldOnCalcItem;
    @InvocableVariable(
      label='Calc Item Lookup Field'
      description='The API Name of the field on the record to rollup that matches a field on the object where the rollup will be stored'
      required=true
    )
    global String lookupFieldOnCalcItem;

    @InvocableVariable(label='Rollup Object API Name' description='The API Name of the SObject where the rollup value will be stored.' required=true)
    global String rollupSObjectName;

    @InvocableVariable(
      label='Rollup Object Calc Field'
      description='The API Name of the field on the target object where the rollup value will be stored'
      required=true
    )
    global String rollupFieldOnOpObject;
    @InvocableVariable(
      label='Rollup Object Lookup Field'
      description='The API Name of the field on the SObject matching the value found in "lookupFieldOnCalcItem" where the rollup will be stored'
      required=true
    )
    global String lookupFieldOnOpObject;

    @InvocableVariable(label='Rollup Operation' description='SUM, COUNT, COUNT_DISTINCT, MAX, MIN, AVG, CONCAT, CONCAT_DISTINCT, FIRST, LAST' required=true)
    global String rollupOperation;
    @InvocableVariable(label='Rollup Operation Context' description='INSERT, UPDATE, UPSERT, or DELETE' required=true)
    global String rollupContext;

    // optional fields shared with RollupFlowBulkProcessor.FlowInput
    @InvocableVariable(label='Defer processing')
    global Boolean deferProcessing = false;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
    // rest of optional fields
    @InvocableVariable(
      label='Calc Item Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;
    @InvocableVariable(
      label='Concat Delimiter Split Should Apply On Calc Item'
      description='the text values on the Calc Item\'s field being rolled up can also be split if this field is enabled and set to {!$GlobalConstant.True}'
    )
    global Boolean splitConcatDelimiterOnCalcItem;

    @InvocableVariable(
      label='Full Recalculation Default Number Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for number-based rollups'
    )
    global Decimal fullRecalculationDefaultNumberValue;
    @InvocableVariable(
      label='Full Recalculation Default String Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for String-based rollups'
    )
    global String fullRecalculationDefaultStringValue;

    @InvocableVariable(label='Grandparent Relationship Field Path' description='Used for grand(or greater)parent rollups')
    global String grandparentRelationshipFieldPath;
    @InvocableVariable(label='One To Many Grandparent Fields (Comma separated list)')
    global String oneToManyGrandparentFields;
    @InvocableVariable(
      label='Is Full Record Set'
      description='If provided, does not try to abort rollup calculation early if no records match, and instead resets the rollup field value'
    )
    global Boolean isFullRecordSet;
    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(label='Order By (First/Last)')
    global String orderByFirstLast;
    @InvocableVariable(label='Limit Amount')
    global Decimal limitAmount;

    // these are listed with the optional properties because otherwise Flow builders always have to check for null after using a Get Records
    // element with filter conditions; the Flow engine otherwise isn't satisfied because Get Records returns null instead of an empty list
    // and null isn't a valid collection variable reference for a required field
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)')
    global List<SObject> recordsToRollup = new List<SObject>();
    @InvocableVariable(label='Prior records to rollup' description='The old version of the records for update/upsert')
    global List<SObject> oldRecordsToRollup = new List<SObject>();

    @InvocableVariable(
      label='Should rollup to ultimate hierarchy parent'
      description='Used in conjunction with Ultimate Parent Field to drive hierarchical parent rollups'
    )
    global Boolean rollupToUltimateParent = false;
    @InvocableVariable(label='Should run sync?' description='Runs rollup calculations synchronously when set to true')
    global Boolean shouldRunSync = false;
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;
    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;

    // internal variables!
    public Id rollupControlId;
  }

  global class FlowOutput {
    @InvocableVariable(label='Is Success' description='Was rollup enqueued successfully?')
    global Boolean isSuccess;
    @InvocableVariable(label='Status Message' description='"SUCCESS" when isSuccess is true, otherwise the encountered error message')
    global String message;
    global FlowOutput() {
      this.isSuccess = true;
      this.Message = 'SUCCESS';
    }
  }

  private class FlowInputWrapper {
    private final FlowInput flowInput;
    private final String rollupContext;
    private final SObjectType sObjectType;
    private final Set<Rollup__mdt> rollupMetadata;

    private FlowInputWrapper(FlowInput flowInput, String rollupContext, SObjectType sObjectType, Rollup__mdt meta) {
      this.flowInput = flowInput;
      this.rollupContext = rollupContext;
      this.sObjectType = sObjectType;
      this.rollupMetadata = new Set<Rollup__mdt>{ meta };
    }
  }

  @InvocableMethod(
    category='Rollups'
    label='Perform rollup on records'
    description='Returns a single FlowOutput record with "SUCCESS" as the message if async rollup operation is enqueued successfully, and the encountered error otherwise'
  )
  global static List<FlowOutput> performRollup(List<FlowInput> flowInputs) {
    List<FlowOutput> flowOutputs = new List<FlowOutput>();
    InvocationPoint fromInvocable = InvocationPoint.FROM_INVOCABLE;

    // Flow bulkifies things, but poorly. It's possible to get multiple FlowInputs with the same metadata, but different calc items (for example)
    // let's head that off at the pass by bulkifying here
    Map<Rollup__mdt, FlowInputWrapper> metaToInputWrapper = new Map<Rollup__mdt, FlowInputWrapper>();
    for (FlowInput flowInput : flowInputs) {
      flowInput.rollupOperation = flowInput.rollupOperation.toUpperCase();
      RollupLogger.Instance.log('processing invocable data:', flowInput, LoggingLevel.DEBUG);

      FlowOutput flowOutput = new FlowOutput();
      if (flowInput.recordsToRollup?.isEmpty() != false) {
        flowOutput.message = 'No records to rollup, returning early';
      } else {
        // flow collections are not strongly typed, so we grab from the first record
        SObjectType sObjectType = flowInput.recordsToRollup[0].getSObjectType();
        // this will throw back up to the Flow engine if the inputs don't pass validation
        enforceValidationRules(flowInput);
        enforceFlowSpecificRules(flowInput, sObjectType);
        winnowOldFlowRecords(flowInput);

        String rollupContext = getFlowRollupContext(flowInput, flowInput.recordsToRollup[0], sObjectType, flowInput.oldRecordsToRollup);

        Rollup__mdt meta = transformFlowInputToRollupMetadata(flowInput, rollupContext, sObjectType);
        if (shouldSkipRollupForFlow(meta, rollupContext)) {
          continue;
        }
        if (metaToInputWrapper.containsKey(meta)) {
          FlowInputWrapper wrapper = metaToInputWrapper.get(meta);
          if (wrapper.rollupMetadata.contains(meta)) {
            wrapper.flowInput.recordsToRollup.addAll(flowInput.recordsToRollup);
            wrapper.flowInput.oldRecordsToRollup.addAll(flowInput.oldRecordsToRollup);
          } else {
            wrapper.rollupMetadata.add(meta);
          }
        } else {
          metaToInputWrapper.put(meta, new FlowInputWrapper(flowInput, rollupContext, sObjectType, meta));
        }
      }

      flowOutputs.add(flowOutput);
    }

    Map<SObjectType, List<Rollup>> localRollups = new Map<SObjectType, List<Rollup>>();
    Map<Integer, List<SObject>> hashCodeToCalcItems = new Map<Integer, List<SObject>>();
    Map<SObjectType, RollupMetadata> typeToWrappedMeta = new Map<SObjectType, RollupMetadata>();
    for (Rollup__mdt key : metaToInputWrapper.keySet()) {
      FlowInputWrapper wrapper = metaToInputWrapper.get(key);
      if (wrapper == null) {
        continue;
      }
      // here we clone the list because it can get winnowed in "processCustomMetadata"
      List<Rollup__mdt> metas = new List<Rollup__mdt>(wrapper.rollupMetadata);
      wrapper.flowInput.recordsToRollup = replaceFlowInputCalcItemsIfNecessary(hashCodeToCalcItems, wrapper.flowInput.recordsToRollup, metas);
      wrapper.flowInput.oldRecordsToRollup = replaceFlowInputCalcItemsIfNecessary(hashCodeToCalcItems, wrapper.flowInput.oldRecordsToRollup, metas);
      Map<Id, SObject> oldFlowRecords = new Map<Id, SObject>(wrapper.flowInput.oldRecordsToRollup);
      processCustomMetadata(
        localRollups,
        metas,
        wrapper.flowInput.recordsToRollup,
        oldFlowRecords,
        new Set<String>(),
        wrapper.rollupContext,
        fromInvocable,
        typeToWrappedMeta
      );

      if (metas.isEmpty() == false) {
        Rollup rollupConductor = getRollup(metas, wrapper.sObjectType, wrapper.flowInput.recordsToRollup, oldFlowRecords, null, fromInvocable);
        String logMessage = 'adding invocable rollup to list:';
        if (wrapper.flowInput.deferProcessing) {
          logMessage = 'deferring processing for rollup:';
          CACHED_ROLLUPS.add(rollupConductor);
        } else {
          populateRollupByType(localRollups, wrapper.sObjectType, rollupConductor);
        }
        if (wrapper.flowInput.shouldRunSync) {
          for (Rollup roll : rollupConductor.rollups) {
            roll.rollupControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;
          }
        }
        RollupLogger.Instance.log(logMessage, rollupConductor, LoggingLevel.DEBUG);
      }
    }

    try {
      if (localRollups.isEmpty() == false) {
        batch(getFlattenedProcessors(localRollups), fromInvocable);
      }
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred during invocable action:', ex, LoggingLevel.ERROR);
      for (FlowOutput flowOutput : flowOutputs) {
        flowOutput.IsSuccess = false;
        flowOutput.Message = ex.getMessage() + '\n' + ex.getStackTraceString();
      }
    }
    flatten(CACHED_ROLLUPS);
    RollupLogger.Instance.save();

    return flowOutputs;
  }

  global static Id schedule(String jobName, String cronExp, String query, String rollupObjectName, Evaluator eval) {
    List<SObject> localCalcItems;
    try {
      localCalcItems = Database.query(query);
    } catch (QueryException ex) {
      throw new QueryException('There\'s a problem with your query: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
    }
    SObjectType calcItemType = localCalcItems.getSObjectType();
    Rollup roll = getRollup(
      getRollupMetadataBySObject(calcItemType),
      calcItemType,
      localCalcItems,
      new Map<Id, SObject>(),
      eval,
      InvocationPoint.FROM_SCHEDULED
    );
    RollupSchedulable scheduledRollup = new RollupSchedulable(roll);
    return System.schedule(jobName, cronExp, scheduledRollup);
  }

  global static void batch(Rollup rollup, Rollup secondRollup) {
    batch(new List<Rollup>{ rollup, secondRollup });
  }

  global static void batch(Rollup rollup, Rollup secondRollup, Rollup thirdRollup) {
    batch(new List<Rollup>{ rollup, secondRollup, thirdRollup });
  }

  global static String batch(List<Rollup> rollups) {
    return batch(rollups, InvocationPoint.FROM_APEX);
  }

  global static Rollup averageFromApex(
    SObjectField averageFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField averageFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return averageFromApex(
      averageFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      averageFieldOnOperationObject,
      lookupSobjectType,
      null,
      null
    );
  }

  global static Rollup averageFromApex(
    SObjectField averageFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField averageFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue
  ) {
    return averageFromApex(
      averageFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      averageFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup averageFromApex(
    SObjectField averageFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      averageFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      sumFieldOnOpOject,
      lookupSobjectType,
      Op.AVERAGE,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup countDistinctFromApex(
    SObjectField countDistinctFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countDistinctFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return countDistinctFromApex(
      countDistinctFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countDistinctFieldOnOperationObject,
      lookupSobjectType,
      null,
      null
    );
  }

  global static Rollup countDistinctFromApex(
    SObjectField countDistinctFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countDistinctFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue
  ) {
    return countDistinctFromApex(
      countDistinctFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countDistinctFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup countDistinctFromApex(
    SObjectField countDistinctFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countDistinctFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      countDistinctFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countDistinctFieldOnOperationObject,
      lookupSobjectType,
      Op.COUNT_DISTINCT,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup concatDistinctFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return concatDistinctFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      null,
      null
    );
  }

  global static Rollup concatDistinctFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue
  ) {
    return concatDistinctFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup concatDistinctFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue,
    Evaluator eval
  ) {
    return concatDistinctFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      eval,
      null
    );
  }

  global static Rollup concatDistinctFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue,
    Evaluator eval,
    List<RollupOrderBy__mdt> orderBys
  ) {
    return operateFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT_DISTINCT,
      defaultRecalculationValue,
      orderBys,
      eval
    );
  }

  global static Rollup concatFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return concatFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      null,
      null
    );
  }

  global static Rollup concatFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue
  ) {
    return concatFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup concatFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue,
    Evaluator eval
  ) {
    return concatFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSObjectType,
      defaultRecalculationValue,
      eval,
      null
    );
  }

  global static Rollup concatFromApex(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    String defaultRecalculationValue,
    Evaluator eval,
    List<RollupOrderBy__mdt> orderBys
  ) {
    return operateFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT,
      defaultRecalculationValue,
      orderBys,
      eval
    );
  }

  global static Rollup countFromApex(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return countFromApex(countFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, countFieldOnOperationObject, lookupSobjectType, null, null);
  }

  global static Rollup countFromApex(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue
  ) {
    return countFromApex(
      countFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup countFromApex(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      countFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      sumFieldOnOpOject,
      lookupSobjectType,
      Op.COUNT,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup firstFromApex(
    SObjectField firstFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField firstFieldOnOpObject,
    SObjectType lookupSobjectType,
    String orderByFirstLast
  ) {
    return firstFromApex(
      firstFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      firstFieldOnOpObject,
      lookupSobjectType,
      null,
      orderByFirstLast,
      null
    );
  }

  global static Rollup firstFromApex(
    SObjectField firstFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField firstFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    String orderByFirstLast
  ) {
    return firstFromApex(
      firstFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      firstFieldOnOpObject,
      lookupSobjectType,
      defaultRecalculationValue,
      orderByFirstLast,
      null
    );
  }

  global static Rollup firstFromApex(
    SObjectField firstFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField firstFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    String orderByFirstLast,
    Evaluator eval
  ) {
    return firstFromApex(
      firstFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      firstFieldOnOpObject,
      lookupSobjectType,
      defaultRecalculationValue,
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = orderByFirstLast) },
      eval
    );
  }

  global static Rollup firstFromApex(
    SObjectField firstFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField firstFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    List<RollupOrderBy__mdt> orderByMetas,
    Evaluator eval
  ) {
    return operateFromApex(
      firstFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      firstFieldOnOpObject,
      lookupSobjectType,
      Op.FIRST,
      defaultRecalculationValue,
      orderByMetas,
      eval
    );
  }

  global static Rollup lastFromApex(
    SObjectField lastFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField lastFieldOnOpObject,
    SObjectType lookupSobjectType,
    String orderByFirstLast
  ) {
    return lastFromApex(
      lastFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      lastFieldOnOpObject,
      lookupSobjectType,
      null,
      orderByFirstLast,
      null
    );
  }

  global static Rollup lastFromApex(
    SObjectField lastFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField lastFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    String orderByFirstLast
  ) {
    return lastFromApex(
      lastFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      lastFieldOnOpObject,
      lookupSobjectType,
      defaultRecalculationValue,
      orderByFirstLast,
      null
    );
  }

  global static Rollup lastFromApex(
    SObjectField lastFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField lastFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    String orderByFirstLast,
    Evaluator eval
  ) {
    return lastFromApex(
      lastFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      lastFieldOnOpObject,
      lookupSobjectType,
      defaultRecalculationValue,
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = orderByFirstLast) },
      eval
    );
  }

  global static Rollup lastFromApex(
    SObjectField lastFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField lastFieldOnOpObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    List<RollupOrderBy__mdt> orderByMetas,
    Evaluator eval
  ) {
    return operateFromApex(
      lastFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      lastFieldOnOpObject,
      lookupSobjectType,
      Op.LAST,
      defaultRecalculationValue,
      orderByMetas,
      eval
    );
  }

  global static Rollup maxFromApex(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return maxFromApex(maxFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, maxFieldOnOperationObject, lookupSobjectType, null, null);
  }

  global static Rollup maxFromApex(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue
  ) {
    return maxFromApex(
      maxFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      maxFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup maxFromApex(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      maxFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      maxFieldOnOperationObject,
      lookupSobjectType,
      Op.MAX,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup minFromApex(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return minFromApex(minFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, minFieldOnOperationObject, lookupSobjectType, null, null);
  }

  global static Rollup minFromApex(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue
  ) {
    return minFromApex(
      minFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      minFieldOnOperationObject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup minFromApex(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOpOject,
    SObjectType lookupSobjectType,
    Object defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      minFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      minFieldOnOpOject,
      lookupSobjectType,
      Op.MIN,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup sumFromApex(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType
  ) {
    return sumFromApex(sumFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, null, null);
  }

  global static Rollup sumFromApex(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue
  ) {
    return sumFromApex(
      sumFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      sumFieldOnOpOject,
      lookupSobjectType,
      defaultRecalculationValue,
      null
    );
  }

  global static Rollup sumFromApex(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Decimal defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      sumFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      sumFieldOnOpOject,
      lookupSobjectType,
      Op.SUM,
      defaultRecalculationValue,
      eval
    );
  }

  global static Rollup mostFromApex(
    SObjectField mostFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField mostFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return mostFromApex(mostFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, mostFieldOnOperationObject, lookupSobjectType, null);
  }

  global static Rollup mostFromApex(
    SObjectField mostFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField mostFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromApex(
      mostFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      mostFieldOnOperationObject,
      lookupSobjectType,
      Op.MOST,
      null,
      eval
    );
  }

  global static void runFromCDCTrigger() {
    isCDC = true;
    // CDC always uses Trigger.new
    List<SObject> cdcRecords = records != null ? records : Trigger.new;
    if (cdcRecords.isEmpty()) {
      return;
    }
    SObject firstRecord = cdcRecords[0];
    EventBus.ChangeEventHeader header = (EventBus.ChangeEventHeader) firstRecord.get('ChangeEventHeader');
    SObjectType sObjectType = RollupFieldInitializer.Current.getSObjectFromName(header.getEntityName()).getSObjectType();

    List<Rollup__mdt> matchingMetadata = getRollupMetadataBySObject(sObjectType);
    if (matchingMetadata.isEmpty()) {
      return;
    }

    Set<String> uniqueFieldNames = new Set<String>();
    for (Rollup__mdt rollupInfo : matchingMetadata) {
      RollupEvaluator.WhereFieldEvaluator eval = String.isBlank(rollupInfo.CalcItemWhereClause__c)
        ? null
        : RollupEvaluator.getWhereEval(rollupInfo.CalcItemWhereClause__c, sObjectType);
      uniqueFieldNames.addAll(getQueryFieldsFromMetadata(rollupInfo, eval));
    }

    // it would have been nice if this was an enum!
    switch on header.changeType {
      when 'CREATE', 'GAP_CREATE' {
        apexContext = TriggerOperation.AFTER_INSERT;
      }
      when 'UPDATE', 'GAP_UPDATE' {
        apexContext = TriggerOperation.AFTER_UPDATE;
      }
      when 'DELETE' {
        apexContext = TriggerOperation.BEFORE_DELETE;
      }
    }

    // non-obvious coupling between objIds and the "queryString" below
    List<Id> objIds = new List<Id>();
    for (SObject cdcRecord : cdcRecords) {
      header = (EventBus.ChangeEventHeader) cdcRecord.get('ChangeEventHeader');
      uniqueFieldNames.addAll(header.changedfields);
      objIds.add(header.getRecordIds()[0]);
    }

    String queryString = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(uniqueFieldNames), 'Id', '=');
    // getting the items back from the database before putting them into the map is an important step
    // we COULD just initialize the map with the query, but then the map's .values() list doesn't return
    // anything for .getSObjectType() - which we need, further downstream
    List<SObject> cdcCalcItems = Database.query(queryString);
    Map<Id, SObject> cdcCalcItemsMap = new Map<Id, SObject>(cdcCalcItems);

    Rollup rollupToReturn = runFromApex(matchingMetadata, null, cdcCalcItems, cdcCalcItemsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isCDCUpdate = apexContext == TriggerOperation.AFTER_UPDATE;
    // we're already async, so let's not waste any more time
    rollupToReturn.rollupControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;
    rollupToReturn?.runCalc();
  }

  global static void runFromTrigger() {
    List<SObject> triggerRecords = getTriggerRecords();
    List<Rollup__mdt> matchingMetadata = getRollupMetadataBySObject(triggerRecords.getSObjectType());
    if (matchingMetadata.isEmpty() == false) {
      runFromApex(matchingMetadata, null, triggerRecords, getOldTriggerRecordsMap())?.runCalc();
    }
  }

  /**
   * @param `List<SObject>` calcItems - the records whose values you'd like to roll up
   * @param `TriggerOperation` rollupContext - acceptable values are:
   * - TriggerOperation.AFTER_INSERT
   * - TriggerOperation.AFTER_UDATE
   * - TriggerOperation.BEFORE_DELETE
   * - TriggerOperation.AFTER_UNDELETE
   *
   * Note that while it's an anti-pattern to call this from directly within a Trigger,
   * because `runFromTrigger()` coupled with CMDT is the better option,
   * you should pass: `Trigger.operationType` for the second argument if you do.
   */
  global static void runFromApex(List<SObject> calcItems, TriggerOperation rollupContext) {
    shouldRun = true;
    records = calcItems;
    apexContext = rollupContext;

    runFromTrigger();

    records = null;
    shouldRun = false;
    apexContext = null;
  }

  global static Rollup runFromApex(List<Rollup__mdt> rollupMetadata, Evaluator eval, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    Rollup rollupConductor = RollupAsyncProcessor.getConductor(InvocationPoint.FROM_APEX, calcItems, oldCalcItems);
    if (shouldRunFromTrigger() == false) {
      return rollupConductor;
    }

    String rollupContext;
    Boolean shouldReturn = false;
    Set<String> mergedParentIds = new Set<String>();

    switch on apexContext {
      when AFTER_UPDATE {
        rollupContext = 'UPDATE_';
      }
      when BEFORE_DELETE {
        rollupContext = 'DELETE_';
      }
      when AFTER_INSERT {
        /** for AFTER_INSERT, the base operation name will always be used */
        rollupContext = '';
      }
      when AFTER_DELETE {
        shouldReturn = reparentAndGetMergedRecordIds(calcItems, rollupMetadata, mergedParentIds, rollupConductor.rollupControl, shouldReturn);
      }
      when else {
        shouldReturn = true;
      }
    }

    if (shouldReturn) {
      return rollupConductor;
    }

    Map<SObjectType, List<Rollup>> localRollups = new Map<SObjectType, List<Rollup>>();
    Map<SObjectType, RollupMetadata> typeToWrappedMeta = new Map<SObjectType, RollupMetadata>();
    processCustomMetadata(localRollups, rollupMetadata, calcItems, oldCalcItems, mergedParentIds, rollupContext, InvocationPoint.FROM_APEX, typeToWrappedMeta);

    SObjectType calcItemSObjectType = calcItems.getSObjectType();
    populateCachedApexOperations(calcItemSObjectType, apexContext);

    if (rollupMetadata.isEmpty() == false) {
      populateRollupByType(
        localRollups,
        calcItemSObjectType,
        getRollup(rollupMetadata, calcItemSObjectType, calcItems, oldCalcItems, eval, InvocationPoint.FROM_APEX)
      );
    }

    flattenBatches(rollupConductor, getFlattenedProcessors(localRollups));
    return rollupConductor;
  }

  /**
   * @return `Rollup__mdt` the metadata with the `List<RollupOrderBy__mdt>` RollupOrderBys__r relationship set
   * <br>
   * Credit for this method (with some tweaking) goes to: https://github.com/tsalb
   */
  global static Rollup__mdt appendOrderByMetadata(Rollup__mdt meta, List<RollupOrderBy__mdt> children) {
    meta.OrderByFirstLast__c = null;
    String serializedMeta = JSON.serialize(meta).removeEnd('}');

    JSONGenerator gen = JSON.createGenerator(false);
    gen.writeStartObject();
    gen.writeNumberField('totalSize', children.size());
    gen.writeBooleanField('done', true);
    gen.writeObjectField('records', children);
    gen.writeEndObject();
    // using Rollup__mdt.SObjectType.getDescribe().getChildRelationships() and doing that whole dance
    // makes me ... sad ... so we'll just live with this little sin for now
    String childrenJson = '"RollupOrderBys__r" : ' + gen.getAsString();
    serializedMeta = serializedMeta += ',' + childrenJson + '}';

    return (Rollup__mdt) JSON.deserialize(serializedMeta, Rollup__mdt.class);
  }

  /** end global-facing section, begin public/private static helpers */

  public static void processStoredFlowRollups() {
    List<Rollup> rollupsToProcess = new List<Rollup>(CACHED_ROLLUPS);
    CACHED_ROLLUPS.clear();
    batch(rollupsToProcess, InvocationPoint.FROM_INVOCABLE);
  }

  public static List<SObject> getMetadataFromCache(SObjectType metadataType) {
    List<SObject> matchingMetadata;
    // We need to clean up the Entity Definition / Field Definition
    // particles for custom objects and custom fields
    if (metadataType == Rollup__mdt.SObjectType) {
      if (cachedMetadata == null && onlyUseMockMetadata == false) {
        cachedMetadata = [
          SELECT
            MasterLabel,
            DeveloperName,
            // we have to do transforms on these fields because custom objects/custom fields
            // have references that otherwise won't work with the rest of the code
            LookupObject__c,
            LookupObject__r.QualifiedApiName,
            CalcItem__c,
            CalcItem__r.QualifiedApiName,
            RollupFieldOnCalcItem__c,
            RollupFieldOnCalcItem__r.QualifiedApiName,
            LookupFieldOnCalcItem__c,
            LookupFieldOnCalcItem__r.QualifiedApiName,
            LookupFieldOnLookupObject__c,
            LookupFieldOnLookupObject__r.QualifiedApiName,
            RollupFieldOnLookupObject__c,
            RollupFieldOnLookupObject__r.QualifiedApiName,
            UltimateParentLookup__c,
            UltimateParentLookup__r.QualifiedApiName,
            // rest of the fields
            CalcItemWhereClause__c,
            ChangedFieldsOnCalcItem__c,
            ConcatDelimiter__c,
            FullRecalculationDefaultNumberValue__c,
            FullRecalculationDefaultStringValue__c,
            GrandparentRelationshipFieldPath__c,
            IsFullRecordSet__c,
            IsRollupStartedFromParent__c,
            LimitAmount__c,
            OneToManyGrandparentFields__c,
            OrderByFirstLast__c,
            RollupControl__c,
            RollupOperation__c,
            RollupToUltimateParent__c,
            SplitConcatDelimiterOnCalcItem__c,
            (SELECT Id, FieldName__c, NullSortOrder__c, Ranking__c, SortOrder__c FROM RollupOrderBys__r ORDER BY Ranking__c, DeveloperName)
          FROM Rollup__mdt
          WHERE RollupControl__r.ShouldAbortRun__c = FALSE
        ];
        // do the transforms
        for (Rollup__mdt meta : cachedMetadata) {
          meta.LookupObject__c = meta.LookupObject__r.QualifiedApiName;
          meta.CalcItem__c = meta.CalcItem__r.QualifiedApiName;
          meta.RollupFieldOnCalcItem__c = meta.RollupFieldOnCalcItem__r.QualifiedApiName;
          meta.LookupFieldOnCalcItem__c = meta.LookupFieldOnCalcItem__r.QualifiedApiName;
          meta.LookupFieldOnLookupObject__c = meta.LookupFieldOnLookupObject__r.QualifiedApiName;
          meta.RollupFieldOnLookupObject__c = meta.RollupFieldOnLookupObject__r.QualifiedApiName;
          meta.UltimateParentLookup__c = meta.UltimateParentLookup__r.QualifiedApiName;
        }
      } else if (onlyUseMockMetadata) {
        cachedMetadata = new List<Rollup__mdt>();
      }
      if (rollupMetadata != null) {
        cachedMetadata.addAll(rollupMetadata);
        rollupMetadata = null;
      }
      matchingMetadata = cachedMetadata.clone();
    } else if (metadataType == RollupControl__mdt.SObjectType) {
      // CMDT is read-only when returned from the cache
      // use "deepClone" to get access to mutable versions of the CMDT records.
      matchingMetadata = RollupControl__mdt.getAll().deepClone().values();
    }
    return matchingMetadata;
  }

  public static Boolean hasExceededCurrentRollupLimits(RollupControl__mdt control) {
    Boolean hasExceededQueryNumberLimit = control?.MaxNumberOfQueries__c < Limits.getQueries();
    Boolean hasExceededQueryRowLimit = control?.MaxLookupRowsBeforeBatching__c < Limits.getQueryRows();
    Boolean hasExceededHeapSizeLimit = (Limits.getLimitHeapSize() / 2) < Limits.getHeapSize();
    Boolean hasExceededDMLRowLimit = control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();
    Integer intervalTillTimeout = ((System.isBatch() || System.isQueueable()) && Test.isRunningTest() == false) ? 14000 : 3000;
    Boolean hasExceededCPUTimeLimit = (Limits.getCpuTime() + intervalTillTimeout) >= Limits.getLimitCpuTime();
    Boolean hasExceededLimits =
      hasExceededQueryNumberLimit ||
      hasExceededQueryRowLimit ||
      hasExceededHeapSizeLimit ||
      hasExceededDMLRowLimit ||
      hasExceededCPUTimeLimit;
    return hasExceededLimits && isDeferralAllowed;
  }

  public static String getBaseOperationName(String fullOpName) {
    Set<String> operationsWithUnderscores = new Set<String>{ Op.COUNT_DISTINCT.name(), Op.CONCAT_DISTINCT.name() };
    return operationsWithUnderscores.contains(fullOpName) == false && fullOpName.contains('_') ? fullOpName.substringAfter('_') : fullOpName;
  }

  private static Rollup__mdt transformFlowInputToRollupMetadata(FlowInput flowInput, String rollupContext, SObjectType sObjectType) {
    return new Rollup__mdt(
      CalcItem__c = flowInput.isRollupStartedFromParent || String.isNotBlank(flowInput.calcItemTypeWhenRollupStartedFromParent)
        ? flowInput.calcItemTypeWhenRollupStartedFromParent
        : String.valueOf(sObjectType),
      CalcItemWhereClause__c = flowInput.calcItemWhereClause,
      ChangedFieldsOnCalcItem__c = flowInput.calcItemChangedFields,
      ConcatDelimiter__c = flowInput.concatDelimiter,
      FullRecalculationDefaultNumberValue__c = flowInput.fullRecalculationDefaultNumberValue,
      FullRecalculationDefaultStringValue__c = flowInput.fullRecalculationDefaultStringValue,
      GrandparentRelationshipFieldPath__c = flowInput.grandparentRelationshipFieldPath,
      IsFullRecordSet__c = flowInput.isFullRecordSet,
      IsRollupStartedFromParent__c = flowInput.isRollupStartedFromParent,
      LookupFieldOnCalcItem__c = flowInput.lookupFieldOnCalcItem,
      LookupFieldOnLookupObject__c = flowInput.lookupFieldOnOpObject,
      LookupObject__c = flowInput.rollupSObjectName,
      OneToManyGrandparentFields__c = flowInput.oneToManyGrandparentFields,
      OrderByFirstLast__c = flowInput.orderByFirstLast,
      RollupControl__r = getSingleControlOrDefault(RollupControl__mdt.Id, flowInput.rollupControlId, defaultControl),
      RollupFieldOnCalcItem__c = flowInput.rollupFieldOnCalcItem,
      RollupFieldOnLookupObject__c = flowInput.rollupFieldOnOpObject,
      RollupOperation__c = rollupContext + flowInput.rollupOperation,
      RollupToUltimateParent__c = flowInput.rollupToUltimateParent,
      SplitConcatDelimiterOnCalcItem__c = flowInput.splitConcatDelimiterOnCalcItem,
      UltimateParentLookup__c = flowInput.ultimateParentLookup
    );
  }

  private static Boolean shouldSkipRollupForFlow(Rollup__mdt meta, String flowContext) {
    if (String.isBlank(meta.RollupControl__r?.OnlyRunInFlowContexts__c)) {
      return false;
    }
    Set<String> allowedContexts = new Set<String>();
    for (String specificAllowedContext : meta.RollupControl__r.OnlyRunInFlowContexts__c.split(',')) {
      allowedContexts.add(specificAllowedContext.trim());
    }
    return allowedContexts.isEmpty() ? false : allowedContexts.contains(flowContext) == false;
  }

  private static Rollup operateFromApex(
    SObjectField operationFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField operationFieldOnOperationObject,
    SObjectType lookupSObjectType,
    Op rollupOperation,
    Object defaultRecalculationValue,
    Evaluator eval
  ) {
    return operateFromApex(
      operationFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      operationFieldOnOperationObject,
      lookupSObjectType,
      rollupOperation,
      defaultRecalculationValue,
      null,
      eval
    );
  }

  private static Rollup operateFromApex(
    SObjectField operationFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField operationFieldOnOperationObject,
    SObjectType lookupSObjectType,
    Op rollupOperation,
    Object defaultRecalculationValue,
    List<RollupOrderBy__mdt> orderByMetas,
    Evaluator eval
  ) {
    Rollup__mdt meta = new Rollup__mdt(
      RollupFieldOnCalcItem__c = operationFieldOnCalcItem.getDescribe().getName(),
      LookupObject__c = lookupSObjectType.getDescribe().getName(),
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.getDescribe().getName(),
      LookupFieldOnLookupObject__c = lookupFieldOnOperationObject.getDescribe().getName(),
      RollupFieldOnLookupObject__c = operationFieldOnOperationObject.getDescribe().getName(),
      RollupOperation__c = rollupOperation.name()
    );
    if (defaultRecalculationValue instanceof Decimal) {
      meta.FullRecalculationDefaultNumberValue__c = (Decimal) defaultRecalculationValue;
    } else if (defaultRecalculationValue instanceof String) {
      meta.FullRecalculationDefaultStringValue__c = (String) defaultRecalculationValue;
    }
    if (orderByMetas?.isEmpty() == false) {
      meta = appendOrderByMetadata(meta, orderByMetas);
    }
    return runFromApex(new List<Rollup__mdt>{ meta }, eval, getTriggerRecords(), getOldTriggerRecordsMap());
  }

  private static void flatten(List<Rollup> stackedRollups) {
    Map<String, Rollup> rollupOperationToRollup = new Map<String, Rollup>();
    for (Rollup stackedRollup : stackedRollups) {
      // If the hashed content doesn't match, we can't collapse the two rollup operations
      String rollupKey = stackedRollup.getHashedContents();
      if (rollupOperationToRollup.containsKey(rollupKey)) {
        Rollup matchingRollup = rollupOperationToRollup.get(rollupKey);
        Map<Id, SObject> stackedMatchingItems = new Map<Id, SObject>(stackedRollup.calcItems);
        stackedMatchingItems.putAll(matchingRollup.calcItems);
        stackedRollup.calcItems = stackedMatchingItems.values();
        stackedRollup.oldCalcItems.putAll(matchingRollup.oldCalcItems);

        for (Integer index = 0; index < matchingRollup.rollups.size(); index++) {
          Rollup innerRollup = matchingRollup.rollups[index];
          Rollup matchingInnerRollup = stackedRollup.rollups[index];
          matchingInnerRollup.matchingCalcItemIds.addAll(innerRollup.matchingCalcItemIds);
          matchingInnerRollup.matchingCalcItemIds.addAll(innerRollup.oldCalcItems.keySet());
        }
      }
      rollupOperationToRollup.put(rollupKey, stackedRollup);
    }

    stackedRollups.clear();
    stackedRollups.addAll(rollupOperationToRollup.values());
  }

  private static void processCustomMetadata(
    Map<SObjectType, List<Rollup>> rollups,
    List<Rollup__mdt> metas,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Set<String> mergedParentIds,
    String rollupContext,
    InvocationPoint invokePoint,
    Map<SObjectType, RollupMetadata> typeToWrappedMeta
  ) {
    List<FullRecalculationMetadata> fullRecalcMetas = new List<FullRecalculationMetadata>();
    Map<String, DeleteReparentOperation> deleteKeyToReparentOp = new Map<String, DeleteReparentOperation>();
    for (Integer index = metas.size() - 1; index >= 0; index--) {
      Rollup__mdt meta = metas[index];
      Boolean nonMatchingGrandparent =
        String.isNotBlank(meta.GrandparentRelationshipFieldPath__c) && meta.CalcItem__c != String.valueOf(calcItems.getSObjectType());
      SObjectType calcItemSObjectType = meta.IsRollupStartedFromParent__c == false &&
        apexContext != TriggerOperation.AFTER_DELETE &&
        nonMatchingGrandparent == false &&
        calcItems.isEmpty() == false
        ? calcItems[0].getSObjectType()
        : RollupFieldInitializer.Current.getSObjectFromName(meta.CalcItem__c).getSObjectType();
      Boolean isIntermediateRollupForGrandparent =
        nonMatchingGrandparent &&
        calcItems.isEmpty() == false &&
        meta.IsRollupStartedFromParent__c == false &&
        meta.LookupObject__c != String.valueOf(calcItemSObjectType);

      if (String.isBlank(meta.CalcItem__c)) {
        meta.CalcItem__c = String.valueOf(calcItemSObjectType);
      }

      Boolean isRefresh = meta.RollupOperation__c.contains('REFRESH');
      QueryWrapper queryWrapper;
      if (apexContext == TriggerOperation.AFTER_DELETE && mergedParentIds.isEmpty() == false) {
        queryWrapper = new QueryWrapper('', meta.LookupFieldOnCalcItem__c);
        for (String mergedParentId : mergedParentIds) {
          queryWrapper.addRecordId(mergedParentId);
        }
        if (String.isNotBlank(meta.CalcItemWhereClause__c)) {
          queryWrapper.setQuery(meta.CalcItemWhereClause__c + ' AND ' + queryWrapper.getQuery());
        }
      } else if (isRefresh) {
        // the order of operations is important here - REFRESH *also* needs to check for
        // meta.IsRollupStartedFromParent__c, so that check can't come first
        queryWrapper = getFullRecalcQueryWrapper(meta, calcItems, oldCalcItems);
      } else if (meta.IsRollupStartedFromParent__c) {
        queryWrapper = getParentQueryWrapper(calcItems, oldCalcItems, meta);
      } else if (isIntermediateRollupForGrandparent) {
        queryWrapper = getIntermediateGrandparentQueryWrapper(meta, calcItems, oldCalcItems);
      }

      if (queryWrapper != null) {
        metas.remove(index);
        fullRecalcMetas.add(new FullRecalculationMetadata(meta, queryWrapper, calcItemSObjectType));
        prepareReparentDeletionOps(meta, calcItems, oldCalcItems, deleteKeyToReparentOp);
      } else if (isRefresh) {
        // remove non-matches
        metas.remove(index);
      } else {
        // if the same items get run through different rollup operations in the same transaction (rare, but not impossible ...)
        // we need to reset the CMDT to the correct base operation prior to appending the new context
        meta.RollupOperation__c =
          rollupContext +
          (meta.RollupOperation__c.contains('UPDATE_') || meta.RollupOperation__c.contains('DELETE_')
            ? meta.RollupOperation__c.substringAfter('_')
            : meta.RollupOperation__c);
      }
    }

    // collapse delete/full recalc operations
    for (String deleteKey : deleteKeyToReparentOp.keySet()) {
      DeleteReparentOperation deleteReparentOp = deleteKeyToReparentOp.get(deleteKey);
      SObjectType deleteSObjectType = deleteReparentOp.reparentedRecords.getSObjectType();
      Rollup deleteProcessor = getRollup(
        deleteReparentOp.rollupMetas,
        deleteSObjectType,
        deleteReparentOp.reparentedRecords,
        new Map<Id, SObject>(),
        null,
        invokePoint
      );
      populateRollupByType(rollups, deleteSObjectType, deleteProcessor);
    }
    fillFullRecalcRollups(fullRecalcMetas, invokePoint, typeToWrappedMeta, rollups);
  }

  private static QueryWrapper getFullRecalcQueryWrapper(Rollup__mdt meta, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    QueryWrapper wrapper;
    meta.RollupOperation__c = meta.RollupOperation__c.replace('REFRESH_', '');
    if (String.isNotBlank(meta.CalcItemWhereClause__c)) {
      SObjectType calcItemType = calcItems[0].getSObjectType();
      RollupEvaluator.WhereFieldEvaluator eval = RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, calcItemType);
      Boolean matches = false;
      FilterResults filter = filter(calcItems, oldCalcItems, eval, meta, calcItemType, CALC_ITEM_REPLACER);
      for (SObject calcItem : calcItems) {
        matches = matches || filter.matchingItemIds.contains(calcItem.Id);
        if (matches) {
          break;
        }
      }
      if (matches == false) {
        return wrapper;
      }
    }
    if (meta.IsRollupStartedFromParent__c == false) {
      wrapper = new QueryWrapper('', meta.LookupFieldOnCalcItem__c);
      for (SObject calcItem : calcItems) {
        fillWrapper(wrapper, meta.LookupFieldOnCalcItem__c, calcItem, oldCalcItems);
      }
    } else {
      wrapper = getParentQueryWrapper(calcItems, oldCalcItems, meta);
    }

    return wrapper;
  }

  private static void populateFullRecalcMetasByType(Map<SObjectType, RollupMetadata> childToMetaWrapper, Rollup__mdt matchingMeta, String possibleParentId) {
    SObjectType childType = RollupFieldInitializer.Current.getSObjectFromName(matchingMeta.CalcItem__c).getSObjectType();
    RollupEvaluator.WhereFieldEvaluator eval = String.isBlank(matchingMeta.CalcItemWhereClause__c)
      ? null
      : RollupEvaluator.getWhereEval(matchingMeta.CalcItemWhereClause__c, childType);
    Set<String> whereFields = getQueryFieldsFromMetadata(matchingMeta, eval);
    RollupMetadata metaWrapper;
    if (childToMetaWrapper.containsKey(childType)) {
      metaWrapper = childToMetaWrapper.get(childType);
    } else {
      metaWrapper = new RollupMetadata();
      childToMetaWrapper.put(childType, metaWrapper);
    }
    if (possibleParentId != null) {
      metaWrapper.recordIds.add(possibleParentId);
    }
    metaWrapper.possibleWhereClauses.add(matchingMeta.CalcItemWhereClause__c);
    metaWrapper.queryFields.addAll(wherefields);
    metaWrapper.metadata.add(matchingMeta);

    Integer amountOfCalcItems = 0;
    if (amountOfCalcItems != RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
      String countQuery = RollupQueryBuilder.Current.getQuery(
        childType,
        new List<String>{ 'Count()' },
        matchingMeta.LookupFieldOnLookupObject__c,
        '!=',
        matchingMeta.CalcItemWhereClause__c
      );
      Set<String> emptyCollection = new Set<String>();
      Integer currentCount = getCountFromDb(countQuery, emptyCollection, emptyCollection);
      if (currentCount == RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
        amountOfCalcItems = currentCount;
      } else {
        metaWrapper.recordCount = currentCount;
        amountOfCalcItems += currentCount;
      }
    }
  }

  private class DeleteReparentOperation {
    public List<SObject> reparentedRecords;
    public final List<Rollup__mdt> rollupMetas = new List<Rollup__mdt>();
  }

  private static void prepareReparentDeletionOps(
    Rollup__mdt meta,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Map<String, DeleteReparentOperation> deleteKeyToOps
  ) {
    if (oldCalcItems?.isEmpty() != false || calcItems?.isEmpty() != false || meta.IsRollupStartedFromParent__c) {
      return;
    }
    List<SObject> typedCalcItems = calcItems.clone();
    typedCalcItems.clear();
    String potentialDeleteOpName = 'DELETE_' + getBaseOperationName(meta.RollupOperation__c);
    Rollup__mdt clonedMeta = meta.clone();
    clonedMeta.RollupOperation__c = potentialDeleteOpName;
    String deleteKey = potentialDeleteOpName + meta.LookupFieldOnCalcItem__c + meta.LookupObject__c;

    if (deleteKeyToOps.containsKey(deleteKey)) {
      deleteKeyToOps.get(deleteKey).rollupMetas.add(clonedMeta);
    } else if (calcItems[0].getSObjectType().getDescribe().fields.getMap().containsKey(meta.LookupFieldOnCalcItem__c)) {
      for (SObject calcItem : calcItems) {
        if (oldCalcItems.containsKey(calcItem.Id)) {
          SObject oldCalcItem = oldCalcItems.get(calcItem.Id);
          if (calcItem.get(meta.LookupFieldOnCalcItem__c) != oldCalcItem.get(meta.LookupFieldOnCalcItem__c)) {
            typedCalcItems.add(oldCalcItem);
          }
        }
      }
      if (typedCalcItems.isEmpty() == false) {
        DeleteReparentOperation deleteReparentOp = new DeleteReparentOperation();
        deleteReparentOp.reparentedRecords = typedCalcItems;
        deleteReparentOp.rollupMetas.add(clonedMeta);
        deleteKeyToOps.put(deleteKey, deleteReparentOp);
      }
    }
  }

  private static Set<String> getQueryFieldsFromMetadata(Rollup__mdt meta, RollupEvaluator.WhereFieldEvaluator eval) {
    Set<String> queryFields = new Set<String>{ 'Id', meta.RollupFieldOnCalcItem__c, meta.LookupFieldOnCalcItem__c };
    if (eval != null) {
      queryFields.addAll(eval.getQueryFields());
    }
    for (RollupOrderBy__mdt orderByInfo : meta.RollupOrderBys__r) {
      queryFields.add(orderByInfo.FieldName__c);
    }
    return queryFields;
  }

  private static String getFullRecalcQueryString(List<Rollup__mdt> metas) {
    List<String> orderByFields = new List<String>();
    for (Rollup__mdt meta : metas) {
      orderByFields.add(meta.LookupFieldOnCalcItem__c);
    }
    return '\nORDER BY ' + String.join(orderByFields, ',');
  }

  private static void fillFullRecalcRollups(
    List<FullRecalculationMetadata> fullRecalcMetas,
    InvocationPoint invokePoint,
    Map<SObjectType, RollupMetadata> typeToWrappedMeta,
    Map<SObjectType, List<Rollup>> rollups
  ) {
    for (Integer index = 0; index < fullRecalcMetas.size(); index++) {
      FullRecalculationMetadata fullRecalcMeta = fullRecalcMetas[index];
      RollupMetadata wrappedMeta;
      if (typeToWrappedMeta.containsKey(fullRecalcMeta.calcItemType) == false) {
        wrappedMeta = new RollupMetadata();
        wrappedMeta.recordCount = 0;
      } else {
        wrappedMeta = typeToWrappedMeta.get(fullRecalcMeta.calcItemType);
        if (rollups.containsKey(fullRecalcMeta.calcItemType)) {
          rollups.get(fullRecalcMeta.calcItemType).clear();
        }
      }
      transformFullRecalcMetadataToRollupMetadata(fullRecalcMetas, wrappedMeta, index);
      if (wrappedMeta.recordCount != RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
        String countQuery = RollupQueryBuilder.Current.getQuery(
          fullRecalcMeta.calcItemType,
          new List<String>{ 'Count()' },
          fullRecalcMeta.meta.LookupFieldOnLookupObject__c,
          '!=',
          wrappedMeta.whereClause
        );
        Integer localCount = getCountFromDb(countQuery, new Set<String>(), wrappedMeta.recordIds);
        wrappedMeta.recordCount = localCount == RollupQueryBuilder.SENTINEL_COUNT_VALUE ? localCount : wrappedMeta.recordCount + localCount;
      }
      typeToWrappedMeta.put(fullRecalcMeta.calcItemType, wrappedMeta);
    }

    List<RollupFullRecalcProcessor> fullRecalcs = transformWrappedMetadataToFullRecalcRollups(typeToWrappedMeta, invokePoint);
    for (RollupFullRecalcProcessor fullRecalc : fullRecalcs) {
      populateRollupByType(rollups, fullRecalc.getCalcItemType(), fullRecalc);
    }
  }

  private static List<RollupFullRecalcProcessor> transformWrappedMetadataToFullRecalcRollups(
    Map<SObjectType, RollupMetadata> typeToWrappedMeta,
    InvocationPoint localInvokePoint
  ) {
    List<RollupFullRecalcProcessor> fullRecalcRollups = new List<RollupFullRecalcProcessor>();
    for (RollupFullRecalcProcessor preCachedRollup : CACHED_FULL_RECALCS) {
      if (typeToWrappedMeta.containsKey(preCachedRollup.getCalcItemType())) {
        RollupMetadata wrappedMeta = typeToWrappedMeta.get(preCachedRollup.getCalcItemType());
        // if other query fields were added to the query string, we need to fix up the cached full recalcs(s') query strings
        String queryString = RollupQueryBuilder.Current.getQuery(
          preCachedRollup.getCalcItemType(),
          new List<String>(wrappedMeta.queryFields),
          'Id',
          '!=',
          wrappedMeta.whereClause
        );
        preCachedRollup.setQuery(queryString);
      }
    }
    Integer maxQueryLength = 100000;
    for (SObjectType calcType : typeToWrappedMeta.keySet()) {
      RollupMetadata wrappedMeta = typeToWrappedMeta.get(calcType);
      wrappedMeta.whereClause = wrappedMeta.concatenateWhereClauses();
      if (wrappedMeta.whereClause?.length() >= maxQueryLength) {
        wrappedMeta.whereClause = '';
        wrappedMeta.recordCount = RollupQueryBuilder.SENTINEL_COUNT_VALUE;
      }
      String queryString = RollupQueryBuilder.Current.getQuery(calcType, new List<String>(wrappedMeta.queryFields), 'Id', '!=', wrappedMeta.whereClause);
      RollupFullRecalcProcessor fullRecalc = buildFullRecalcRollup(wrappedMeta, queryString, calcType, localInvokePoint);
      setControlToSyncForSingularParentRecalcs(fullRecalc.rollupControl, localInvokePoint);
      if (fullRecalc.isNoOp) {
        fullRecalc.isNoOp = wrappedMeta.recordCount == 0;
      }
      fullRecalc.queryCount = wrappedMeta.recordCount;
      RollupLogger.Instance.log('full recalc prepared:', fullRecalc, LoggingLevel.DEBUG);
      fullRecalcRollups.add(fullRecalc);
      CACHED_FULL_RECALCS.add(fullRecalc);
    }
    return fullRecalcRollups;
  }

  private static void transformFullRecalcMetadataToRollupMetadata(List<FullRecalculationMetadata> fullRecalcMetas, RollupMetadata wrappedMeta, Integer index) {
    FullRecalculationMetadata fullRecalcMeta = fullRecalcMetas[index];
    wrappedMeta.metadata.add(fullRecalcMeta.meta);
    wrappedMeta.recordIds.addAll(fullRecalcMeta.wrapper.recordIds);
    wrappedMeta.possibleWhereClauses.add(fullRecalcMeta.wrapper.getQuery());

    if (String.isNotBlank(fullRecalcMeta.meta.CalcItemWhereClause__c)) {
      wrappedMeta.queryFields.addAll(RollupEvaluator.getWhereEval(fullRecalcMeta.meta.CalcItemWhereClause__c, fullRecalcMeta.calcItemType).getQueryFields());
    }
    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(fullRecalcMeta.wrapper.toString(), fullRecalcMeta.calcItemType);
    wrappedMeta.queryFields.addAll(getQueryFieldsFromMetadata(fullRecalcMeta.meta, whereEval));
    wrappedMeta.parentRecordsToReset.addAll(fullRecalcMeta.wrapper.parentRecordsToReset);
  }

  private static RollupFullRecalcProcessor buildFullRecalcRollup(
    RollupMetadata wrappedMeta,
    String queryString,
    SObjectType calcItemType,
    InvocationPoint invokePoint
  ) {
    for (Rollup__mdt meta : wrappedMeta.metadata) {
      meta.IsFullRecordSet__c = true;
      meta.RollupOperation__c = getBaseOperationName(meta.RollupOperation__c);
    }
    SObjectType parentType = RollupFieldInitializer.Current.getSObjectFromName(wrappedMeta.metadata[0].LookupObject__c).getSObjectType();
    String equality = invokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC ? '=' : '!=';
    String parentQuery = RollupQueryBuilder.Current.getQuery(parentType, new List<String>{ 'Id' }, 'Id', equality);
    RollupFullRecalcProcessor parentResetProcessor = new RollupParentResetProcessor(
      wrappedMeta.metadata,
      parentType,
      parentQuery,
      wrappedMeta.recordIds,
      invokePoint
    );
    Boolean shouldQueue =
      wrappedMeta.recordCount != RollupQueryBuilder.SENTINEL_COUNT_VALUE &&
      wrappedMeta.recordCount < parentResetProcessor.rollupControl.MaxLookupRowsBeforeBatching__c;
    if (wrappedMeta.recordCount == 0 && wrappedMeta.metadata.isEmpty() == false && isFullRecalcApp) {
      return parentResetProcessor;
    } else if (invokePoint != InvocationPoint.FROM_FULL_RECALC_LWC && invokePoint != InvocationPoint.FROM_FULL_RECALC_FLOW) {
      parentResetProcessor = null;
    }

    RollupFullRecalcProcessor fullRecalc;
    if (shouldQueue) {
      fullRecalc = new RollupDeferredFullRecalcProcessor(
        wrappedMeta.metadata,
        calcItemType,
        queryString,
        wrappedMeta.recordIds,
        invokePoint,
        parentResetProcessor
      );
    } else {
      fullRecalc = new RollupFullBatchRecalculator(
        (queryString + getFullRecalcQueryString(wrappedMeta.metadata)),
        invokePoint,
        wrappedMeta.metadata,
        calcItemType,
        wrappedMeta.recordIds,
        parentResetProcessor
      );
    }

    if (wrappedMeta.parentRecordsToReset.isEmpty() == false) {
      fullRecalc.storeParentFieldsToClear(wrappedMeta.parentRecordsToReset);
      fullRecalc.isNoOp = false;
    }
    return fullRecalc;
  }

  private static List<SObject> replaceFlowInputCalcItemsIfNecessary(
    Map<Integer, List<SObject>> hashCodeToCalcItems,
    List<SObject> calcItems,
    List<Rollup__mdt> metas
  ) {
    Integer priorHashCode = calcItems.hashCode();
    if (hashCodeToCalcItems.containsKey(priorHashCode)) {
      return hashCodeToCalcItems.get(priorHashCode);
    }
    calcItems = CALC_ITEM_REPLACER.replace(calcItems, metas);
    hashCodeToCalcItems.put(priorHashCode, calcItems);
    return calcItems;
  }

  private static String batch(List<Rollup> rollups, InvocationPoint invokePoint) {
    Rollup conductor;
    if (rollups.isEmpty()) {
      conductor = new Rollup(invokePoint);
    } else {
      conductor = RollupAsyncProcessor.getConductor(invokePoint, rollups[0].calcItems, rollups[0].oldCalcItems);
      flattenBatches(conductor, rollups);
    }
    return conductor.runCalc();
  }

  private static void populateRollupByType(Map<Schema.SObjectType, List<Rollup>> rollups, Schema.SObjectType calcType, Rollup processor) {
    List<Rollup> processors = rollups.containsKey(calcType) ? rollups.get(calcType) : new List<Rollup>();
    processors.add(processor);
    rollups.put(calcType, processors);
  }

  private static List<Rollup> getFlattenedProcessors(Map<Schema.SObjectType, List<Rollup>> typeToProcessors) {
    List<Rollup> flattenedRollups = new List<Rollup>();
    for (Schema.SObjectType calcType : typeToProcessors.keySet()) {
      flattenedRollups.addAll(typeToProcessors.get(calcType));
    }
    return flattenedRollups;
  }

  private static void flattenBatches(Rollup outerRollup, List<Rollup> rollups) {
    for (Rollup rollup : rollups) {
      if (rollup.rollups.isEmpty() == false) {
        for (Rollup innerRoll : rollup.rollups) {
          if (rollup.calcItems?.isEmpty() == false) {
            innerRoll.calcItems = rollup.calcItems;
          }
          if (rollup.oldCalcItems?.isEmpty() == false) {
            innerRoll.oldCalcItems = rollup.oldCalcItems;
          }
          innerRoll.isFullRecalc = rollup.isFullRecalc;
        }
        // recurse through lists until there aren't any more nested rollups
        flattenBatches(outerRollup, rollup.rollups);
      } else if (rollup instanceof RollupAsyncProcessor) {
        loadRollups((RollupAsyncProcessor) rollup, outerRollup);
      }
    }
  }

  private static void enforceValidationRules(FlowInput flowInput) {
    String errorMessage;
    if (
      (flowInput.rollupToUltimateParent && String.isBlank(flowInput.ultimateParentLookup)) ||
      (String.isNotBlank(flowInput.ultimateParentLookup) && flowInput.rollupToUltimateParent == false)
    ) {
      errorMessage = 'Rollup To Ultimate Parent and Ultimate Parent Lookup must both be set for hierarchical rollups';
    } else if (String.isNotBlank(flowInput.fullRecalculationDefaultStringValue) && flowInput.fullRecalculationDefaultNumberValue != null) {
      errorMessage = 'Only one override - the default string value or number value - can be supplied for each rollup';
    } else if (flowInput.rollupOperation.contains(Op.CONCAT.name()) == false) {
      errorMessage = '';
      if (String.isNotBlank(flowInput.concatDelimiter)) {
        errorMessage = 'Concat delimiter should only be supplied for CONCAT-based rollups.';
      }
      if (flowInput.splitConcatDelimiterOnCalcItem == true) {
        errorMessage += (String.isNotBlank(errorMessage) ? ' ' : '') + 'Concat options should only be set for CONCAT_DISTINCT operations';
      }
    }

    if (String.isNotBlank(errorMessage)) {
      Exception ex = new IllegalArgumentException(errorMessage);
      logAndThrowFlowException(ex, 'an error occurred while validating flow inputs');
    }
  }

  private static void enforceFlowSpecificRules(FlowInput flowInput, SObjectType sObjectType) {
    try {
      if ((flowInput.rollupContext == 'UPDATE' || flowInput.rollupContext == 'UPSERT') && flowInput.oldRecordsToRollup?.isEmpty() == true) {
        throw new IllegalArgumentException('Prior records to rollup collection required for rollup context: ' + flowInput.rollupContext);
      } else if (String.isBlank(flowInput.grandparentRelationshipFieldPath)) {
        SObject firstRecord = flowInput.recordsToRollup[0];
        SObject lookupItem = RollupFieldInitializer.Current.getSObjectFromName(
          flowInput.isRollupStartedFromParent ? flowInput.calcItemTypeWhenRollupStartedFromParent : flowInput.rollupSObjectName
        );

        // validate the fields exist on the rollup record
        (flowInput.isRollupStartedFromParent ? lookupItem : firstRecord).get(flowInput.rollupFieldOnCalcItem);
        (flowInput.isRollupStartedFromParent ? lookupItem : firstRecord).get(flowInput.lookupFieldOnCalcItem);

        // validate that the fields exist on the lookup item
        (flowInput.isRollupStartedFromParent ? firstRecord : lookupItem).get(flowInput.rollupFieldOnOpObject);
        (flowInput.isRollupStartedFromParent ? firstRecord : lookupItem).get(flowInput.lookupFieldOnOpObject);
      }
    } catch (Exception ex) {
      logAndThrowFlowException(ex, 'an error occurred while validating flow-specific rules');
    }
  }

  private static void logAndThrowFlowException(Exception ex, String logString) {
    RollupLogger.Instance.log(logString, ex, LoggingLevel.ERROR);
    RollupLogger.Instance.save();
    throw ex;
  }

  private static QueryWrapper getIntermediateGrandparentQueryWrapper(Rollup__mdt meta, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    if (isCDC) {
      return new QueryWrapper();
    }

    SObjectType sObjectType = calcItems[0].getSObjectType();
    SObjectField fieldToken = getPartOfGrandparentChain(meta, sObjectType);
    String relationshipName = fieldToken.getDescribe().getRelationshipName();
    Integer relationshipIndex = meta.GrandparentRelationshipFieldPath__c.indexOf(relationshipName) + relationshipName.length();
    String priorFieldPath = meta.GrandparentRelationshipFieldPath__c.substring(0, relationshipIndex) + '.Id';
    if (meta.OneToManyGrandparentFields__c != null && meta.OneToManyGrandparentFields__c.contains(fieldToken.getDescribe().getName())) {
      List<String> fieldPathTuples = meta.OneToManyGrandparentFields__c.split(',');
      for (String fieldPathTuple : fieldPathTuples) {
        if (fieldToken.getDescribe().getName().equalsIgnoreCase(fieldPathTuple.substringAfter('.'))) {
          priorFieldPath = 'Id';
          break;
        }
      }
    }

    QueryWrapper wrapper = new QueryWrapper('', priorFieldPath);
    for (SObject calcItem : calcItems) {
      SObject oldCalcItem = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem;
      String currentLookup = (String) calcItem.get(fieldToken);
      String oldLookup = (String) oldCalcItem.get(fieldToken);
      if (currentLookup != oldLookup) {
        wrapper.addRecordId(currentLookup);
        wrapper.addRecordId(oldLookup);
      }
    }
    return wrapper;
  }

  private class QueryWrapper {
    private Boolean hasQuery = false;
    private String query;
    private final List<SObject> parentRecordsToReset = new List<SObject>();
    private final Set<String> recordIds = new Set<String>();
    private final Set<String> stringifiedRecordIds = new Set<String>();

    private QueryWrapper() {
    }

    private QueryWrapper(String lookupObject, String lookupField) {
      String base = String.isBlank(lookupObject) ? '' : lookupObject.replace('__c', '__r') + '.';
      this.query = base + lookupField + ' = :recordIds';
    }

    public void addRecordId(String recordId) {
      if (String.isNotBlank(recordId)) {
        this.hasQuery = true;
        this.recordIds.add(recordId);
        this.stringifiedRecordIds.add('\'' + recordId + '\'');
      }
    }

    public String getQuery() {
      return this.hasQuery ? this.query : '';
    }

    public void setQuery(String query) {
      if (String.isNotBlank(query)) {
        this.hasQuery = true;
        this.query = query;
      }
    }

    public override String toString() {
      return this.hasQuery ? this.query.replace('= :recordIds', 'IN (' + String.join(new List<String>(this.stringifiedRecordIds), ',') + ')') : '';
    }
  }

  private static QueryWrapper getParentQueryWrapper(List<SObject> calcItems, Map<Id, SObject> oldCalcItems, Rollup__mdt meta) {
    String fieldName = meta.LookupFieldOnLookupObject__c;
    String lookupObjectName = meta.LookupObject__c;
    if (String.isNotBlank(meta.GrandparentRelationshipFieldPath__c)) {
      lookupObjectName = '';
      fieldName = meta.GrandparentRelationshipFieldPath__c.substringBeforeLast('.') + '.Id';
    } else if (meta.LookupFieldOnCalcItem__c.endsWith('Id') || meta.LookupFieldOnCalcItem__c.endsWith('__c')) {
      lookupObjectName = '';
      fieldName = meta.LookupFieldOnCalcItem__c;
    }

    QueryWrapper wrapper = new QueryWrapper(lookupObjectName, fieldName);
    wrapper.parentRecordsToReset.addAll(calcItems);
    for (SObject calcItem : calcItems) {
      fillWrapper(wrapper, meta.LookupFieldOnLookupObject__c, calcItem, oldCalcItems);
    }
    if (String.isNotBlank(meta.CalcItemWhereClause__c)) {
      String whereClause = '(' + meta.CalcItemWhereClause__c + ') AND ';
      wrapper.setQuery(whereClause + wrapper.getQuery());
    }
    return wrapper;
  }

  public static Integer getCountFromDb(String countQuery, Set<String> objIds) {
    return getCountFromDb(countQuery, objIds, null);
  }

  public static Integer getCountFromDb(String countQuery, Set<String> objIds, Set<String> recordIds) {
    if (countQuery.contains(RollupQueryBuilder.ALL_ROWS)) {
      countQuery = countQuery.replace(RollupQueryBuilder.ALL_ROWS, '');
    }

    Integer countAmount;
    try {
      countAmount = Database.countQuery(countQuery);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query:\n' + countQuery, ex, LoggingLevel.WARN);
      // not all queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      countAmount = RollupQueryBuilder.SENTINEL_COUNT_VALUE;
    }
    return countAmount;
  }

  private static void fillWrapper(QueryWrapper wrapper, String fieldName, SObject calcItem, Map<Id, SObject> oldCalcItems) {
    String lookupId = (String) calcItem.get(fieldName);
    if (String.isNotBlank(lookupId)) {
      wrapper.addRecordId(lookupId);
    }
    if (oldCalcItems.containsKey(calcItem.Id)) {
      String oldLookupId = (String) oldCalcItems.get(calcItem.Id).get(fieldName);
      if (String.isNotBlank(oldLookupId)) {
        wrapper.addRecordId(oldLookupId);
      }
    }
  }

  private static String getFlowRollupContext(FlowInput firstInput, SObject firstRecord, SObjectType sObjectType, List<SObject> oldFlowRecords) {
    String flowContext = firstInput.rollupContext.toUpperCase();
    if (flowContext == 'UPSERT') {
      flowContext = oldFlowRecords.isEmpty() ? 'INSERT' : 'UPDATE';
    }

    TriggerOperation matchingOperation;
    switch on flowContext {
      when 'INSERT', '', null {
        matchingOperation = TriggerOperation.AFTER_INSERT;
      }
      when 'UPDATE' {
        matchingOperation = TriggerOperation.AFTER_UPDATE;
      }
      when 'DELETE' {
        matchingOperation = TriggerOperation.BEFORE_DELETE;
      }
    }
    populateCachedApexOperations(sObjectType, matchingOperation);

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static void winnowOldFlowRecords(FlowInput flowInput) {
    flowInput.oldRecordsToRollup = flowInput.oldRecordsToRollup == null ? new List<SObject>() : flowInput.oldRecordsToRollup.clone();
    for (Integer index = flowInput.oldRecordsToRollup.size() - 1; index >= 0; index--) {
      SObject oldRecord = flowInput.oldRecordsToRollup[index];
      // record-triggered flows set up to run when "A record is created or modified"
      // will pass null in the list if it runs on create - yikes.
      if (oldRecord?.Id == null) {
        flowInput.oldRecordsToRollup.remove(index);
      }
    }
  }

  private static void populateCachedApexOperations(SObjectType calcItemSObjectType, TriggerOperation triggerContext) {
    if (CACHED_APEX_OPERATIONS.containsKey(calcItemSObjectType)) {
      CACHED_APEX_OPERATIONS.get(calcItemSObjectType).add(triggerContext);
    } else {
      CACHED_APEX_OPERATIONS.put(calcItemSObjectType, new Set<TriggerOperation>{ triggerContext });
    }
  }

  private static List<Rollup__mdt> getRollupMetadataBySObject(SObjectType sObjectType) {
    String sObjectName = sObjectType.getDescribe().getName();
    List<Rollup__mdt> rollupMetadatas = getMetadataFromCache(Rollup__mdt.SObjectType);
    for (Integer index = rollupMetadatas.size() - 1; index >= 0; index--) {
      Rollup__mdt meta = rollupMetadatas[index];
      if (String.isNotBlank(meta.GrandparentRelationshipFieldPath__c)) {
        if (getPartOfGrandparentChain(meta, sObjectType) != null) {
          continue;
        } else if (isNotTriggeredByMatchingObject(meta, sObjectName)) {
          rollupMetadatas.remove(index);
        }
      } else if (Trigger.operationType == TriggerOperation.AFTER_DELETE && sObjectName == meta.LookupObject__c) {
        continue;
      } else if (Trigger.operationType == TriggerOperation.AFTER_DELETE) {
        rollupMetadatas.remove(index);
      } else if (isNotTriggeredByMatchingObject(meta, sObjectName)) {
        rollupMetadatas.remove(index);
      }
    }
    return rollupMetadatas;
  }

  private static Boolean isNotTriggeredByMatchingObject(Rollup__mdt meta, String sObjectName) {
    return (meta.CalcItem__c != sObjectName && meta.IsRollupStartedFromParent__c == false) ||
      (meta.IsRollupStartedFromParent__c && sObjectName != meta.LookupObject__c);
  }

  private static SObjectField getPartOfGrandparentChain(Rollup__mdt meta, SObjectType sObjectType) {
    List<String> validRelationshipNames = meta.GrandparentRelationshipFieldPath__c.split('\\.');
    // remove the last field since it's not a relationship
    validRelationshipNames.remove(validRelationshipNames.size() - 1);
    for (SObjectField fieldToken : sObjectType.getDescribe().fields.getMap().values()) {
      if (fieldToken.getDescribe().getRelationshipName() == null) {
        continue;
      } else if (validRelationshipNames.contains(fieldToken.getDescribe().getRelationshipName())) {
        return fieldToken;
      } else if (String.isNotBlank(meta.OneToManyGrandparentFields__c)) {
        List<SObjectType> parents = fieldToken.getDescribe().getReferenceTo();
        for (SObjectType parent : parents) {
          for (ChildRelationship child : parent.getDescribe().getChildRelationships()) {
            if (validRelationshipNames.contains(child.getRelationshipName())) {
              return fieldToken;
            }
          }
        }
      }
    }
    return null;
  }

  private static RollupAsyncProcessor getRollup(
    List<Rollup__mdt> rollupOperations,
    SObjectType sObjectType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    InvocationPoint rollupInvokePoint
  ) {
    calcItems = CALC_ITEM_REPLACER.replace(calcItems, rollupOperations);
    if (oldCalcItems?.isEmpty() == false) {
      oldCalcItems = new Map<Id, SObject>(CALC_ITEM_REPLACER.replace(oldCalcItems.values(), rollupOperations));
    }
    RollupAsyncProcessor rollupConductor = RollupAsyncProcessor.getConductor(rollupInvokePoint, calcItems, oldCalcItems);
    if (rollupOperations.isEmpty() || calcItems.isEmpty()) {
      return rollupConductor;
    } else if (rollupOperations.size() == 1) {
      rollupConductor.metadata = rollupOperations[0];
    }
    if (sObjectType == null) {
      sObjectType = calcItems[0].getSObjectType();
    }
    /**
     * We have rollup operations to perform. That's great!
     * Let's get ready to rollup!
     */
    Map<String, SObjectField> calcItemFields = sObjectType.getDescribe().fields.getMap();
    RollupFieldInitializer init = RollupFieldInitializer.Current;

    for (Rollup__mdt rollupMetadata : rollupOperations) {
      Op rollupOp = Op.valueOf(rollupMetadata.RollupOperation__c);
      SObjectField rollupFieldOnCalcItem = init.getSObjectFieldByName(calcItemFields, rollupMetadata.RollupFieldOnCalcItem__c);
      SObjectField calcLookupField = init.getSObjectFieldByName(calcItemFields, rollupMetadata.LookupFieldOnCalcItem__c);

      // NB - this SHOULD work even for SObjects part of managed packages
      SObjectType lookupSObjectType = init.getSObjectFromName(rollupMetadata.LookupObject__c).getSObjectType();
      Map<String, SObjectField> lookuopItemFields = lookupSObjectType.getDescribe().fields.getMap();
      SObjectField lookupFieldOnOpObject = init.getSObjectFieldByName(lookuopItemFields, rollupMetadata.LookupFieldOnLookupObject__c);
      SObjectField rollupFieldOnOpObject = init.getSObjectFieldByName(lookuopItemFields, rollupMetadata.RollupFieldOnLookupObject__c);

      // reset the CMDT field-level definitions using the SObjectField tokens
      rollupMetadata.RollupFieldOnCalcItem__c = rollupFieldOnCalcItem.getDescribe().getName();
      rollupMetadata.LookupFieldOnCalcItem__c = calcLookupField.getDescribe().getName();
      rollupMetadata.LookupFieldOnLookupObject__c = lookupFieldOnOpObject.getDescribe().getName();
      rollupMetadata.RollupFieldOnLookupObject__c = rollupFieldOnOpObject.getDescribe().getName();

      if (rollupMetadata.IsFullRecordSet__c != true && isFullRecalcOp(getBaseOperationName(rollupMetadata.RollupOperation__c))) {
        rollupMetadata.IsFullRecordSet__c = true;
      }
      if (rollupOp.name().contains(Op.FIRST.name()) || rollupOp.name().contains(Op.LAST.name())) {
        rollupMetadata = getFirstLastMetadata(rollupMetadata);
      }

      RollupControl__mdt localControl;
      if (rollupMetadata.RollupControl__c != null) {
        // for CMDT-driven rollups, the rollup record is always tied to a RollupControl__mdt record
        localControl = getSingleControlOrDefault(RollupControl__mdt.Id, rollupMetadata.RollupControl__c, specificControl);
      } else {
        String controlKey = getRollupControlKey(rollupInvokePoint, rollupFieldOnCalcItem, lookupSObjectType, rollupFieldOnOpObject);
        localControl = getSingleControlOrDefault(RollupControl__mdt.TriggerOrInvocableName__c, controlKey, specificControl);
      }
      setControlToSyncForSingularParentRecalcs(localControl, rollupInvokePoint);

      FilterResults filterResults = filter(calcItems, oldCalcItems, eval, rollupMetadata, sObjectType, rollupConductor.calcItemReplacer);

      loadRollups(
        rollupFieldOnCalcItem,
        calcLookupField,
        lookupFieldOnOpObject,
        rollupFieldOnOpObject,
        lookupSObjectType,
        sObjectType, // calc item SObjectType
        rollupOp,
        filterResults,
        rollupConductor,
        localControl,
        rollupInvokePoint,
        rollupMetadata
      );
    }
    rollupConductor.isNoOp = rollupConductor.rollups.isEmpty();
    return rollupConductor;
  }

  private static Rollup__mdt getFirstLastMetadata(Rollup__mdt meta) {
    List<RollupOrderBy__mdt> replacementOrderBys;
    if (meta.RollupOrderBys__r.isEmpty() && String.isNotBlank(meta.OrderByFirstLast__c)) {
      List<String> unparsedOrderBys = meta.OrderByFirstLast__c.split(',');
      replacementOrderBys = new List<RollupOrderBy__mdt>();
      for (Integer index = 0; index < unparsedOrderBys.size(); index++) {
        String unparsedOrderBy = unparsedOrderBys[index].trim();
        String fieldName = unparsedOrderBy.indexOf(' ') > -1 ? unparsedOrderBy.substringBefore(' ') : unparsedOrderBy;
        RollupOrderBy__mdt orderBy = new RollupOrderBy__mdt(Ranking__c = index, FieldName__c = fieldName);
        Boolean isAscendingSortOrder = unparsedOrderBy.containsIgnoreCase(RollupMetaPicklists.SortOrder.Ascending);
        if (isAscendingSortOrder || unparsedOrderBy.containsIgnoreCase(RollupMetaPicklists.SortOrder.Descending)) {
          orderBy.SortOrder__c = isAscendingSortOrder ? RollupMetaPicklists.SortOrder.Ascending : RollupMetaPicklists.SortOrder.Descending;
        }
        Boolean isAscendingNullSortOrder = unparsedOrderBy.containsIgnoreCase(RollupMetaPicklists.NullSortOrder.NullsFirst);
        if (isAscendingNullSortOrder || unparsedOrderBy.containsIgnoreCase(RollupMetaPicklists.NullSortOrder.NullsLast)) {
          orderBy.NullSortOrder__c = isAscendingNullSortOrder ? RollupMetaPicklists.NullSortOrder.NullsFirst : RollupMetaPicklists.NullSortOrder.NullsLast;
        }
        replacementOrderBys.add(orderBy);
      }
    } else if (meta.RollupOrderBys__r.isEmpty()) {
      replacementOrderBys = new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = meta.RollupFieldOnCalcItem__c) };
    }
    return replacementOrderBys != null ? Rollup.appendOrderByMetadata(meta, replacementOrderBys) : meta;
  }

  private static Boolean isFullRecalcOp(String baseOperationName) {
    Boolean isFullRecalcOp = false;
    switch on Op.valueOf(baseOperationName) {
      when AVERAGE, CONCAT_DISTINCT, CONCAT, COUNT_DISTINCT, FIRST, LAST, MOST {
        isFullRecalcOp = true;
      }
    }
    return isFullRecalcOp;
  }

  private static String getRollupControlKey(
    InvocationPoint invokePoint,
    SObjectField rollupFieldOnCalcItem,
    SObjectType lookupSObjectType,
    SObjectField rollupFieldOnOpObject
  ) {
    return (invokePoint.name().replace('FROM_', '') +
      '_' +
      rollupFieldOnCalcItem +
      '_to_' +
      lookupSObjectType +
      '_' +
      rollupFieldOnOpObject +
      '_rollup')
      .toLowerCase();
  }

  private static void setControlToSyncForSingularParentRecalcs(RollupControl__mdt control, InvocationPoint invokePoint) {
    if (invokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC) {
      control.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;
    }
  }

  private static Boolean shouldRunFromTrigger() {
    shouldRun = shouldRun || Trigger.isExecuting;
    // in order to accomodate CDC; we set the apexContext manually there
    // since technically all CDC is done from an AFTER_INSERT context
    if (Trigger.operationType != null && isCDC == false) {
      apexContext = Trigger.operationType;
    }
    switch on apexContext {
      when AFTER_INSERT, AFTER_UPDATE, BEFORE_DELETE, AFTER_DELETE, AFTER_UNDELETE {
        shouldRun = shouldRun && true;
      }
      when else {
        shouldRun = false;
      }
    }
    // an undelete behaviors **strictly** the same as an insert
    // because the underlying SObject can't be modified till afterwards
    if (apexContext == TriggerOperation.AFTER_UNDELETE) {
      apexContext = TriggerOperation.AFTER_INSERT;
    }
    return shouldRun;
  }

  private static List<SObject> getTriggerRecords() {
    if (records != null) {
      return records;
    }

    return (Trigger.isDelete ? Trigger.old : Trigger.new).deepClone(true, true, true);
  }

  private static Map<Id, SObject> getOldTriggerRecordsMap() {
    if (oldRecordsMap != null) {
      return oldRecordsMap;
    } else if (Trigger.oldMap != null) {
      return Trigger.oldMap.deepClone();
    }

    return new Map<Id, SObject>();
  }

  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  private static Boolean reparentAndGetMergedRecordIds(
    List<SObject> calcItems,
    List<Rollup__mdt> rollupMetadata,
    Set<String> mergedParentIds,
    RollupControl__mdt control,
    Boolean shouldReturn
  ) {
    String mergeFieldIndicator = 'MasterRecordId';
    // titled objIds because it's used as a bind variable in SOQL below
    Set<String> objIds = new Set<String>();
    Map<Id, Id> mergedIdToCurrentParentId = new Map<Id, Id>();
    for (SObject record : calcItems) {
      Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
      if (populatedFields.containsKey(mergeFieldIndicator) && populatedFields.get(mergeFieldIndicator) != null) {
        String mergedFieldValue = String.valueOf(populatedFields.get(mergeFieldIndicator));
        objIds.add(record.Id);
        mergedIdToCurrentParentId.put(record.Id, Id.valueOf(mergedFieldValue));
        mergedParentIds.add(mergedFieldValue);
      }
    }

    if (objIds.isEmpty() || control.IsMergeReparentingEnabled__c == false) {
      shouldReturn = true;
      return shouldReturn;
    }

    // only M/D relationships specifically set to reparent do so automatically
    // for everything else - there's rollup
    List<SObject> recordsToUpdate = new List<SObject>();
    Set<SObjectType> updatedChildTypes = new Set<SObjectType>();
    for (Rollup__mdt meta : rollupMetadata) {
      if (meta.LookupObject__c != String.valueOf(calcItems.getSObjectType())) {
        continue;
      }

      SObjectType calcItemSObject = RollupFieldInitializer.Current.getSObjectFromName(meta.CalcItem__c).getSObjectType();

      // SOQL in a for loop - with the caveat that it's once per child object of any given parent
      if (updatedChildTypes.contains(calcItemSObject) == false) {
        updatedChildTypes.add(calcItemSObject);

        String queryString = RollupQueryBuilder.Current.getQuery(
          calcItemSObject,
          new List<String>{ 'Id', meta.LookupFieldOnCalcItem__c },
          meta.LookupFieldOnCalcItem__c,
          '='
        );
        List<SObject> recordsToReparent = Database.query(queryString);
        for (SObject childToReparent : recordsToReparent) {
          childToReparent.put(meta.LookupFieldOnCalcItem__c, mergedIdToCurrentParentId.get((Id) childToReparent.get(meta.LookupFieldOnCalcItem__c)));
          recordsToUpdate.add(childToReparent);
        }
      }
    }
    performNonRecursiveUpdate(recordsToUpdate, control);
    return shouldReturn;
  }

  private static void performNonRecursiveUpdate(List<SObject> recordsToUpdate, RollupControl__mdt control) {
    // prevent downstream rollups from running on this code path; we are already in the midst
    // of calculating each of the record's new rollup values
    RollupControl__mdt earlyExitControl = control.clone(true);
    earlyExitControl.ShouldAbortRun__c = true;
    defaultControl = earlyExitControl;
    specificControl = earlyExitControl;

    DML.doUpdate(recordsToUpdate);

    defaultControl = null;
    specificControl = null;
  }

  private static Rollup loadRollups(
    SObjectField rollupFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOpObject,
    SObjectField rollupFieldOnOpObject,
    SObjectType lookupSObjectType,
    SObjectType calcItemSObjectType,
    Op rollupOp,
    FilterResults filterResults,
    Rollup rollupConductor,
    RollupControl__mdt rollupControl,
    InvocationPoint invokePoint,
    Rollup__mdt rollupMetadata
  ) {
    RollupAsyncProcessor processor = RollupAsyncProcessor.getProcessor(
      filterResults,
      rollupFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOpObject,
      rollupFieldOnOpObject,
      lookupSObjectType,
      calcItemSObjectType,
      rollupOp,
      invokePoint,
      rollupControl,
      rollupMetadata
    );
    return loadRollups(processor, rollupConductor);
  }

  private static Rollup loadRollups(RollupAsyncProcessor processor, Rollup rollupConductor) {
    if (rollupConductor != null && processor != null && processor.isNoOp == false) {
      rollupConductor.rollups.add(processor);
    }
    return rollupConductor;
  }

  private static RollupControl__mdt getSingleControlOrDefault(SObjectField whereField, Object whereValue, RollupControl__mdt testOverrideData) {
    // there are multiple spots where testOverrideData can be supplied, which is why it's necessary to pass the argument to this method
    if (testOverrideData != null) {
      return testOverrideData;
    } else if (whereField == RollupControl__mdt.Id || whereField == RollupControl__mdt.DeveloperName) {
      String whereKey = (String) whereValue;
      RollupControl__mdt potentialControl = RollupControl__mdt.getInstance(whereKey);
      if (potentialControl != null) {
        return potentialControl.clone(true, true);
      }
    }
    List<RollupControl__mdt> rollupControls = getMetadataFromCache(RollupControl__mdt.SObjectType);
    for (RollupControl__mdt rollupControl : rollupControls) {
      if (rollupControl.get(whereField) == whereValue) {
        return rollupControl;
      }
    }

    return getSensibleControlDefault();
  }

  private static RollupControl__mdt getSensibleControlDefault() {
    if (defaultControl != null) {
      return defaultControl;
    } else if (cachedOrgDefault == null) {
      // hack for additional code coverage; use one of the TestVisible variables to test getting the below defaults instead
      RollupControl__mdt sensibleDefault = records != null ? null : RollupControl__mdt.getInstance(CONTROL_ORG_DEFAULTS);
      if (sensibleDefault == null) {
        // this *should* be impossible, since the record is included on install, but ...
        sensibleDefault = new RollupControl__mdt(
          DeveloperName = CONTROL_ORG_DEFAULTS,
          BatchChunkSize__c = 2000,
          IsMergeReparentingEnabled__c = true,
          IsRollupLoggingEnabled__c = false,
          MaxLookupRowsBeforeBatching__c = Limits.getLimitQueryRows() / 3,
          MaxNumberOfQueries__c = Limits.getLimitQueries() / 2,
          MaxParentRowsUpdatedAtOnce__c = Limits.getLimitDmlRows() / 2,
          MaxRollupRetries__c = 10,
          ReplaceCalcItemsAsyncWhenOverCount__c = 1,
          ShouldAbortRun__c = false,
          ShouldDuplicateRulesBeIgnored__c = false,
          ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable,
          ShouldRunSingleRecordsSynchronously__c = false
        );
      } else {
        sensibleDefault = sensibleDefault.clone(true, true);
      }
      cachedOrgDefault = sensibleDefault;
    }
    return cachedOrgDefault;
  }

  private static FilterResults filter(
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    Rollup__mdt metadata,
    SObjectType calcItemType,
    RollupCalcItemReplacer calcItemReplacer
  ) {
    FilterResults results = new FilterResults();
    results.eval = RollupEvaluator.getEvaluator(eval, metadata, oldCalcItems, calcItemType);

    // for custom evaluators / where clauses / calc item changed fields, etc ... mutating the initial "calcItems" passed in would
    // mean inadvertently filtering the items for other rollups on the same child SObject type. Instead, we track the matching Ids
    // to avoid unintended side-effects
    for (SObject item : calcItems) {
      // if the where clause would exclude something, but we're in an update
      // and the old value wouldn't have been excluded, pass it on through
      // to be handled further downstream
      if (results.eval.matches(item) || calcItemReplacer.hasProcessedMetadata(new List<Rollup__mdt>{ metadata }, calcItems) == false) {
        results.matchingItemIds.add(item.Id);
      } else if (oldCalcItems != null && oldCalcItems.containsKey(item.Id) && results.eval.matches(oldCalcItems.get(item.Id))) {
        results.matchingItemIds.add(item.Id);
      } else if (metadata?.IsFullRecordSet__c == true) {
        results.matchingItemIds.add(item.Id);
      }
    }
    return results;
  }
}
