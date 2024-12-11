@SuppressWarnings('PMD.NcssTypeCount')
global without sharing virtual class Rollup implements RollupLogger.ToStringObject {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @TestVisible
  private static Boolean shouldRun;
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
  @TestVisible
  private static Boolean shouldRefreshCachedControl = false;
  @TestVisible
  private static Boolean shouldFlattenAsyncProcesses = false;

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
  protected Boolean isNoOpOverridden = false;
  protected Boolean isCDCUpdate = false;
  protected Integer queryCount;
  protected RollupCalcItemReplacer calcItemReplacer;
  protected TriggerOperation triggerContext;
  protected RollupRepository.RunAsMode runAsMode = RollupRepository.RunAsMode.SYSTEM_LEVEL;

  private Boolean hasResetLogger = false;

  // Lazy-load section. Lots of additional lines, but with the benefit that we keep the heap size down for instances of Rollup
  // that never reference these variables
  private static final Map<SObjectType, Set<TriggerOperation>> CACHED_APEX_OPERATIONS {
    get {
      CACHED_APEX_OPERATIONS = CACHED_APEX_OPERATIONS ?? new Map<SObjectType, Set<TriggerOperation>>();
      return CACHED_APEX_OPERATIONS;
    }
    set;
  }

  @TestVisible
  private static List<RollupFullRecalcProcessor> CACHED_FULL_RECALCS {
    get {
      CACHED_FULL_RECALCS = CACHED_FULL_RECALCS ?? new List<RollupFullRecalcProcessor>();
      return CACHED_FULL_RECALCS;
    }
    set;
  }

  private static Set<String> CACHED_COUNT_QUERIES {
    get {
      CACHED_COUNT_QUERIES = CACHED_COUNT_QUERIES ?? new Set<String>();
      return CACHED_COUNT_QUERIES;
    }
    set;
  }

  @TestVisible
  private static List<Rollup> CACHED_ROLLUPS {
    get {
      CACHED_ROLLUPS = CACHED_ROLLUPS ?? new List<Rollup>();
      return CACHED_ROLLUPS;
    }
    set;
  }

  private static final RollupCalcItemReplacer CALC_ITEM_REPLACER {
    get {
      CALC_ITEM_REPLACER = CALC_ITEM_REPLACER ?? new RollupCalcItemReplacer(CACHED_DEFAULT);
      return CALC_ITEM_REPLACER;
    }
    set;
  }

  protected Map<Id, SObject> oldCalcItems {
    get {
      this.oldCalcItems = this.oldCalcItems ?? new Map<Id, SObject>();
      return this.oldCalcItems;
    }
    set;
  }

  protected final Set<Id> matchingCalcItemIds {
    get {
      this.matchingCalcItemIds = this.matchingCalcItemIds ?? new Set<Id>();
      return matchingCalcItemIds;
    }
    set;
  }

  @TestVisible
  protected final List<RollupAsyncProcessor> rollups {
    get {
      this.rollups = this.rollups ?? new List<RollupAsyncProcessor>();
      return this.rollups;
    }
    set;
  }

  protected final RollupLogger.ILogger logger {
    get {
      this.logger = this.logger ?? RollupLogger.Instance;
      if (this.getIsRunningAsync() && this.hasResetLogger == false) {
        this.hasResetLogger = true;
        RollupLogger.setLogger(this.logger);
      }
      return this.logger;
    }
    private set;
  }

  private Map<String, String> baseProps {
    get {
      this.baseProps = this.baseProps ??
        new Map<String, String>{
          'Type' => this.getTypeName(),
          'Invocation Point' => this.invokePoint?.name(),
          'Is Full Recalc' => String.valueOf(this.isFullRecalc),
          'Is No Op' => String.valueOf(this.isNoOp),
          'Is Conductor' => String.valueOf(this.isConductor),
          'Inner rollups' => String.valueOf(this.rollups.size())
        };
      return this.baseProps;
    }
    set;
  }

  /**
   * receiving an interface/subclass from a property get/set (from the book "The Art Of Unit Testing") is an old technique;
   * useful in limited contexts to get around the classic approach to dependency injection
   * (such as in this case, when constructor-based DI isn't possible).
   * It's more palatable in Apex than in many other languages, as a matter of fact -
   * this is because the @TestVisible annotation enforces that the override is only possible while testing
   */
  @TestVisible
  private static RollupSObjectUpdater DML {
    get {
      DML = DML ?? new RollupSObjectUpdater();
      return DML;
    }
    set;
  }

  private static final Map<String, Op> OP_NAME_TO_OP {
    get {
      if (OP_NAME_TO_OP == null) {
        OP_NAME_TO_OP = new Map<String, Op>();
        for (Op op : Op.values()) {
          OP_NAME_TO_OP.put(op.name(), op);
        }
      }
      return OP_NAME_TO_OP;
    }
    set;
  }

  private static RollupControl__mdt CACHED_DEFAULT {
    get {
      if (CACHED_DEFAULT == null || shouldRefreshCachedControl == true) {
        CACHED_DEFAULT = getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl);
        defaultControl = null;
      }
      return CACHED_DEFAULT;
    }
    set;
  }

  public enum Op {
    ALL,
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
    DELETE_SUM,
    FIRST,
    LAST,
    MAX,
    MIN,
    MOST,
    NONE,
    SOME,
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
    UPDATE_SUM
  }

  public class FilterResults {
    public final Set<Id> matchingItemIds = new Set<Id>();
    public Evaluator eval { get; set; }
  }

  private class RollupMetadata {
    public final Map<Schema.SObjectType, Set<Id>> typeToOldIntermediateParents = new Map<Schema.SObjectType, Set<Id>>();
    public final Set<String> recordIds = new Set<String>();
    public final Set<String> queryFields = new Set<String>();
    public final List<Rollup__mdt> metadata = new List<Rollup__mdt>();
    public final List<SObject> parentRecordsToReset = new List<SObject>();
    public final Set<String> possibleWhereClauses = new Set<String>();
    public String whereClause = '';
    public Integer recordCount = 0;

    public String concatenateWhereClauses() {
      if (this.possibleWhereClauses.isEmpty()) {
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

  public class CalcItemBag {
    private Map<String, SObject> idToCalcItem = new Map<String, SObject>();
    private Boolean hasBeenCleared = false;
    public Boolean hasQueriedForAdditionalItems = false;
    public CalcItemBag(List<SObject> calcItems) {
      for (SObject calcItem : calcItems) {
        this.add(calcItem);
      }
    }

    public Set<String> getAllIds() {
      return this.idToCalcItem.keySet();
    }

    public List<SObject> getAll() {
      return this.idToCalcItem.values();
    }

    public void clear() {
      if (this.hasBeenCleared == false) {
        this.idToCalcItem = new Map<String, SObject>();
        this.hasBeenCleared = true;
      }
    }

    public void add(SObject calcItem) {
      this.idToCalcItem.put(calcItem.Id, calcItem);
    }

    public void removeKey(String key) {
      this.idToCalcItem.remove(key);
    }
  }

  global interface Evaluator {
    Boolean matches(Object calcItem);
  }

  global enum InvocationPoint {
    FROM_APEX,
    FROM_INVOCABLE,
    FROM_SCHEDULED,
    FROM_FULL_RECALC_APEX,
    FROM_FULL_RECALC_LWC,
    FROM_FULL_RECALC_FLOW,
    FROM_SINGULAR_PARENT_RECALC_LWC
  }

  protected Rollup() {
  }

  protected Rollup(InvocationPoint invokePoint) {
    this.invokePoint = invokePoint;
    this.rollupControl = CACHED_DEFAULT;
    this.calcItemReplacer = CALC_ITEM_REPLACER;
    this.isConductor = true;
    // a conductor only becomes valid if other Rollups are added to it
    this.isNoOp = true;
  }

  protected Rollup(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    this(invokePoint);
    this.calcItems = calcItems;
    this.oldCalcItems = oldCalcItems;
  }

  public override String toString() {
    String baseString = '';
    if (this.rollupControl?.IsRollupLoggingEnabled__c == true) {
      Map<String, String> props = this.customizeToStringEntries(this.baseProps);
      for (String key : props.keySet()) {
        baseString += key + ': ' + props.get(key) + '\n';
      }
    }
    return baseString.removeEnd('\n');
  }

  global virtual String runCalc() {
    this.logger.log('no-op!', this.getTypeName(), System.LoggingLevel.INFO);
    return 'no-op';
  }

  global virtual Rollup addLimit(Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    for (Rollup roll : this.rollups) {
      this.addLimitToMetadata(roll.metadata, limitAmount, calcItemRollupField);
    }
    return this;
  }

  global virtual Rollup addOrderBys(List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    for (Rollup roll : this.rollups) {
      roll.metadata = this.addOrderBys(roll.metadata, orderBys, calcItemRollupField);
    }
    return this;
  }

  global virtual Rollup modifyMetadata(Rollup__mdt template) {
    List<Rollup__mdt> metasToModify = new List<Rollup__mdt>{ this.metadata };
    for (Rollup roll : this.rollups) {
      metasToModify.add(roll.metadata);
    }
    this.modifyMetadata(metasToModify, template);
    return this;
  }

  protected void modifyMetadata(List<Rollup__mdt> metas, Rollup__mdt template) {
    for (Rollup__mdt meta : metas) {
      if (meta != null) {
        for (String fieldName : template.getPopulatedFieldsAsMap().keySet()) {
          meta.put(fieldName, template.get(fieldName));
        }
      }
    }
  }

  protected Rollup__mdt addOrderBys(Rollup__mdt localMeta, List<RollupOrderBy__mdt> orderBys, Schema.SObjectField calcItemRollupField) {
    if (localMeta.RollupFieldOnCalcItem__c == calcItemRollupField.toString()) {
      localMeta = appendOrderByMetadata(localMeta, orderBys);
    }
    return localMeta;
  }

  protected void addLimitToMetadata(Rollup__mdt localMeta, Integer limitAmount, Schema.SObjectField calcItemRollupField) {
    if (localMeta.RollupFieldOnCalcItem__c == calcItemRollupField.toString()) {
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

  protected Map<String, Op> getOpMap() {
    return OP_NAME_TO_OP;
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

  protected Boolean getIsRunningAsync() {
    return isContextAsync();
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

  protected void cleanupStaticVars() {
    Rollup.records = null;
    Rollup.oldRecordsMap = null;
  }

  protected Boolean isEmptyReparentingOp(Op op) {
    return isFullRecalcOp(getBaseOperationName(op.name()));
  }

  /**
   * global facing RollupAsyncProcessor calculation section
   * - Trigger operations
   * - Batch (multiple RollupAsyncProcessor operations chained into one job)
   * - Invocable
   * - Schedulable
   * - LWC-based full recalculation calls
   */

  public class NamespaceInfo {
    @AuraEnabled
    public final String safeObjectName = Rollup__mdt.SObjectType.toString();
    @AuraEnabled
    public final String safeRollupOperationField = this.safeObjectName + '.' + Rollup__mdt.RollupOperation__c.toString();
    @AuraEnabled
    public final String namespace = Rollup.class.getName() == 'Rollup' ? '' : Rollup.class.getName().substringBefore('.Rollup') + '__';
  }

  @AuraEnabled(cacheable=true)
  public static NamespaceInfo getNamespaceInfo() {
    return new NamespaceInfo();
  }

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
    updateLoggingControl(matchingMetadata);
    RollupLogger.Instance.log('bulk full recalc called with data:', matchingMetadata, System.LoggingLevel.INFO);

    String delimiter = ' ||| ';
    String possibleParentId;

    Map<SObjectType, RollupMetadata> childToMetaWrapper = new Map<SObjectType, RollupMetadata>();
    for (Rollup__mdt matchingMeta : matchingMetadata) {
      FlowInput validationRuleWrapper = new FlowInput();
      validationRuleWrapper.rollupOperation = matchingMeta.RollupOperation__c.toUpperCase();
      validationRuleWrapper.concatDelimiter = matchingMeta.ConcatDelimiter__c;
      validationRuleWrapper.fullRecalculationDefaultStringValue = matchingMeta.FullRecalculationDefaultStringValue__c;
      validationRuleWrapper.fullRecalculationDefaultNumberValue = matchingMeta.FullRecalculationDefaultNumberValue__c;
      enforceValidationRules(validationRuleWrapper);

      if (localInvokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC && possibleParentId == null) {
        Integer delimiterIndex = matchingMeta.CalcItemWhereClause__c?.indexOf(delimiter) ?? -1;
        if (delimiterIndex > -1) {
          possibleParentId = matchingMeta.CalcItemWhereClause__c.substring(delimiterIndex + delimiter.length(), matchingMeta.CalcItemWhereClause__c.length())
            .substringAfter(' = ')
            .remove('\'');
        }
      }
      if (possibleParentId != null) {
        String lookupFieldName = String.isNotBlank(matchingMeta.GrandparentRelationshipFieldPath__c)
          ? matchingMeta.GrandparentRelationshipFieldPath__c.substringBeforeLast('.') + '.' + matchingMeta.LookupFieldOnLookupObject__c
          : matchingMeta.LookupFieldOnCalcItem__c;
        matchingMeta.CalcItemWhereClause__c = matchingMeta.CalcItemWhereClause__c?.substringBeforeLast(delimiter) ?? '';
        matchingMeta.CalcItemWhereClause__c +=
          (String.isNotBlank(matchingMeta.CalcItemWhereClause__c) ? ' AND ' : '') +
          lookupFieldName +
          ' = ' +
          '\'' +
          possibleParentId +
          '\'';
      }

      SObjectType childType = RollupFieldInitializer.Current.getDescribeFromName(matchingMeta.CalcItem__c).getSObjectType();
      RollupMetadata wrappedMeta = getWrappedMeta(childType, childToMetaWrapper, matchingMeta, matchingMeta.CalcItemWhereClause__c);
      // duplicate check to the above, but since the CalcItemWhereClause__c is modified in the original guard clause
      // we need to wait till after that guard clause to initialize wrappedMeta
      if (possibleParentId != null) {
        wrappedMeta.recordIds.add(possibleParentId);
      }
      wrappedMeta.possibleWhereClauses.add(matchingMeta.CalcItemWhereClause__c);
      appendQueryCount(wrappedMeta, matchingMeta, matchingMeta.CalcItemWhereClause__c, childType);
    }

    List<RollupFullRecalcProcessor> processors = transformWrappedMetadataToFullRecalcRollups(childToMetaWrapper, localInvokePoint);
    isFullRecalcApp = false;
    if (processors.size() > 1 && processors[0].rollupControl.ShouldRunAs__c != RollupMetaPicklists.ShouldRunAs.Synchronous) {
      RollupFullRecalcProcessor conductor = processors[0];
      while (processors.size() > 1) {
        conductor.rollups.add(processors.remove(1));
      }
      return conductor.runCalc();
    }
    return batch(processors, localInvokePoint);
  }

  @AuraEnabled
  global static String getBatchRollupStatus(String jobId) {
    String jobStatus = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1]?.Status;
    if ([SELECT COUNT() FROM RollupState__c WHERE RelatedJobId__c = :jobId LIMIT 1] > 0) {
      jobStatus = 'Processing';
    }
    return jobStatus;
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
    @InvocableVariable(label='Child Object Calc Field' description='The API Name of the field on each of the records passed in to rollup.' required=true)
    global String rollupFieldOnCalcItem;
    @InvocableVariable(
      label='Child Object Lookup Field'
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
    @InvocableVariable(label='Defer processing' defaultValue='false')
    global Boolean deferProcessing = false;
    @InvocableVariable(label='Child Object Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
    // rest of optional fields
    @InvocableVariable(
      label='Child Object Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;
    @InvocableVariable(
      label='Concat Delimiter Split Should Apply On Child Object'
      description='the text values on the Child Object\'s field being rolled up can also be split if this field is enabled and set to {!$GlobalConstant.True}'
    )
    global Boolean splitConcatDelimiterOnCalcItem;
    @InvocableVariable(
      label='Advanced Currency Field Mapping (Comma-separated)'
      description='For parent-level Date/Datetime fields, use the relationship name for the parent object and then the API name of the field - otherwise just use the API name of the field'
    )
    global String currencyFieldMapping;
    @InvocableVariable(
      label='Full Recalculation Default Number Value'
      description='If provided, used in place of the existing value on the rollup field for the parent object for number-based rollups'
    )
    global Decimal fullRecalculationDefaultNumberValue;
    @InvocableVariable(
      label='Full Recalculation Default String Value'
      description='If provided, used in place of the existing value on the rollup field for the parent object for String-based rollups'
    )
    global String fullRecalculationDefaultStringValue;

    @InvocableVariable(label='Grandparent Relationship Field Path' description='Used for grand(or greater)parent rollups')
    global String grandparentRelationshipFieldPath;
    @InvocableVariable(label='Group By Fields (Comma-separated)' description='Transforms a rollup into a group by rollup based on the fields provided')
    global String groupByFields;
    @InvocableVariable(label='Group By Row End Delimiter' description='The text value to suffix grouped field rows with')
    global String groupByRowEndDelimiter;
    @InvocableVariable(label='Group By Row Start Delimiter' description='The text value to prefix grouped field rows with')
    global String groupByRowStartDelimiter;
    @InvocableVariable(label='One To Many Grandparent Fields (Comma separated list)')
    global String oneToManyGrandparentFields;
    @InvocableVariable(
      label='Is Distinct'
      defaultValue='false'
      description='If provided, children item values are de-duplicated prior to calculating rollup values'
    )
    global Boolean isDistinct = false;
    @InvocableVariable(
      label='Is Full Record Set'
      defaultValue='false'
      description='If true, SUM and COUNT-based rollups retrieve other related children records prior to performing rollup'
    )
    global Boolean isFullRecordSet = false;
    @InvocableVariable(
      label='Is Rollup Started From Parent'
      defaultValue='false'
      description='If the provided records are the parent records, set this to true'
    )
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(
      label='Is Table Formatted'
      defaultValue='false'
      description='If rolling up to a group by text field and you want a table, set this to true'
    )
    global Boolean isTableFormatted = false;
    @InvocableVariable(label='Order By (First/Last)')
    global String orderByFirstLast;
    @InvocableVariable(label='Limit Amount')
    global Decimal limitAmount;

    // these are listed with the optional properties because otherwise Flow builders always have to check for null after using a Get Records
    // element with filter conditions; the Flow engine otherwise isn't satisfied because Get Records returns null instead of an empty list
    // and null isn't a valid collection variable reference for a required field. Listed as transient to avoid blowing up the heap while logging
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)')
    global transient List<SObject> recordsToRollup = new List<SObject>();
    @InvocableVariable(label='Prior records to rollup' description='The old version of the records for update/upsert')
    global transient List<SObject> oldRecordsToRollup = new List<SObject>();
    @InvocableVariable(
      label='Parent Record Id for Empty Children Collections'
      description='Runs rollup calculations even if no matching children when passed. Must also fill out Child Object Type When Rollup Started From Parent property'
    )
    global Id parentRecordIdForEmptyChildrenCollections;
    @InvocableVariable(
      label='Should rollup to ultimate hierarchy parent'
      defaultValue='false'
      description='Used in conjunction with Ultimate Parent Field to drive hierarchical parent rollups'
    )
    global Boolean rollupToUltimateParent = false;
    @InvocableVariable(label='Sharing Mode' defaultValue='System' description='Defaults to System, set to User to run with sharing')
    global String sharingMode;
    @InvocableVariable(label='Should run sync?' defaultValue='false' description='Runs rollup calculations synchronously when set to true')
    global Boolean shouldRunSync = false;
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;
    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;

    // internal state
    public Id rollupControlId;
    public String developerName;
    public RollupGrouping__mdt rollupGrouping;

    public Boolean shouldOverrideNoOp() {
      return this.parentRecordIdForEmptyChildrenCollections != null && this.calcItemTypeWhenRollupStartedFromParent != null;
    }
  }

  global class FlowOutput {
    @InvocableVariable(label='Is Success' description='Was rollup enqueued successfully?')
    global Boolean isSuccess;
    @InvocableVariable(label='Status Message' description='"SUCCESS" (or more info) when isSuccess is true, otherwise the encountered error message')
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
    private final Set<Rollup__mdt> rollupMetadata = new Set<Rollup__mdt>();
    private final Map<Id, SObject> children = new Map<Id, SObject>();
    private final Map<Id, SObject> oldChildren = new Map<Id, SObject>();
    private final Boolean shouldOverrideNoOp;

    private FlowInputWrapper(FlowInput flowInput, String rollupContext, SObjectType sObjectType) {
      this.flowInput = flowInput;
      this.rollupContext = rollupContext;
      this.sObjectType = sObjectType;
      this.shouldOverrideNoOp = this.flowInput.shouldOverrideNoOp();
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
    RollupSettings__c settings = RollupSettings__c.getInstance();
    for (FlowInput flowInput : flowInputs) {
      FlowOutput flowOutput = new FlowOutput();
      flowOutputs.add(flowOutput);
      if (settings.IsEnabled__c == false) {
        continue;
      }

      flowInput.rollupOperation = flowInput.rollupOperation.toUpperCase();
      RollupLogger.Instance.log('processing invocable data:', flowInput, System.LoggingLevel.INFO);

      if (flowInput.shouldOverrideNoOp() && flowInput.recordsToRollup?.isEmpty() != false) {
        flowInput.recordsToRollup = new List<SObject>();
        Schema.DescribeSObjectResult childDescribe = RollupFieldInitializer.Current.getDescribeFromName(flowInput.calcItemTypeWhenRollupStartedFromParent);
        SObject stubChild = childDescribe.getSObjectType().newSObject(childDescribe.getKeyPrefix() + '0'.repeat(12));
        stubChild.put(flowInput.lookupFieldOnCalcItem, flowInput.parentRecordIdForEmptyChildrenCollections);
        flowInput.recordsToRollup.add(stubChild);
      }

      if (flowInput.recordsToRollup?.isEmpty() != false) {
        flowOutput.message = 'No records to rollup, returning early';
      } else {
        // flow collections are not strongly typed, so we grab from the first record
        Schema.SObjectType sObjectType = flowInput.recordsToRollup[0].getSObjectType();
        if (String.isNotBlank(flowInput.grandparentRelationshipFieldPath) && String.isNotBlank(flowInput.calcItemTypeWhenRollupStartedFromParent)) {
          Rollup__mdt grandparentMeta = new Rollup__mdt(
            GrandparentRelationshipFieldPath__c = flowInput.grandparentRelationshipFieldPath,
            OneToManyGrandparentFields__c = flowInput.oneToManyGrandparentFields
          );
          if (getPartOfGrandparentChain(grandparentMeta, sObjectType) != null) {
            sObjectType = RollupFieldInitializer.Current.getDescribeFromName(flowInput.calcItemTypeWhenRollupStartedFromParent).getSObjectType();
          }
        }

        // this will throw back up to the Flow engine if the inputs don't pass validation
        enforceValidationRules(flowInput);
        enforceFlowSpecificRules(flowInput, sObjectType);
        winnowOldFlowRecords(flowInput);

        String rollupContext = getFlowRollupContext(flowInput, flowInput.recordsToRollup[0], sObjectType, flowInput.oldRecordsToRollup);

        Rollup__mdt meta = transformFlowInputToRollupMetadata(flowInput, rollupContext, sObjectType);
        if (shouldSkipRollupForFlow(meta, rollupContext)) {
          continue;
        }
        FlowInputWrapper wrapper = metaToInputWrapper.get(meta);
        if (wrapper == null) {
          wrapper = new FlowInputWrapper(flowInput, rollupContext, sObjectType);
          metaToInputWrapper.put(meta, wrapper);
        }
        wrapper.children.putAll(flowInput.recordsToRollup);
        wrapper.oldChildren.putAll(flowInput.oldRecordsToRollup);
        wrapper.rollupMetadata.add(meta);
      }
    }
    if (metaToInputWrapper.isEmpty()) {
      return flowOutputs;
    } else {
      updateLoggingControl(new List<Rollup__mdt>(metaToInputWrapper.keySet()));
    }

    Map<SObjectType, List<Rollup>> localRollups = new Map<SObjectType, List<Rollup>>();
    Map<SObjectType, RollupMetadata> typeToWrappedMeta = new Map<SObjectType, RollupMetadata>();
    for (FlowInputWrapper wrapper : metaToInputWrapper.values()) {
      // here we clone the list because it can get winnowed in "processCustomMetadata"
      List<Rollup__mdt> metas = new List<Rollup__mdt>(wrapper.rollupMetadata);
      Map<Schema.SObjectType, List<Rollup>> typeToWinnowedRollups;
      List<SObject> children = wrapper.children.values();
      Map<Id, SObject> oldFlowRecords = RollupFieldInitializer.Current.createSafeMap(wrapper.oldChildren.values());

      if (wrapper.flowInput.deferProcessing) {
        typeToWinnowedRollups = new Map<Schema.SObjectType, List<Rollup>>{ wrapper.sObjectType => new List<Rollup>() };
      }

      Map<Schema.SObjectType, List<Rollup>> typeToLocalRollups = typeToWinnowedRollups ?? localRollups;
      processCustomMetadata(typeToLocalRollups, metas, children, oldFlowRecords, new Set<String>(), wrapper.rollupContext, fromInvocable, typeToWrappedMeta);

      if (wrapper.shouldOverrideNoOp) {
        List<Rollup> rollups = typeToLocalRollups.get(wrapper.sObjectType) ?? new List<Rollup>();
        for (Rollup roll : rollups) {
          roll.isNoOp = false;
          roll.isNoOpOverridden = true;
          roll.calcItems = children;
        }
      }

      for (Schema.SObjectType typeKey : (typeToWinnowedRollups?.keyset() ?? new Set<Schema.SObjectType>())) {
        CACHED_ROLLUPS.addAll(typeToWinnowedRollups.get(typeKey));
      }

      if (metas.isEmpty() == false) {
        Rollup rollupConductor = getRollup(metas, wrapper.sObjectType, children, oldFlowRecords, null, fromInvocable);
        String logMessage;
        if (rollupConductor.isNoOp) {
          logMessage = 'skipping no-op conductor';
        } else if (wrapper.flowInput.deferProcessing) {
          logMessage = 'deferring processing for rollup';
          CACHED_ROLLUPS.add(rollupConductor);
        } else {
          logMessage = 'adding invocable rollup to list';
          populateRollupByType(localRollups, wrapper.sObjectType, rollupConductor);
        }
        if (wrapper.flowInput.shouldRunSync) {
          for (Rollup roll : rollupConductor.rollups) {
            roll.rollupControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;
          }
        }
        RollupLogger.Instance.log(logMessage + ':', rollupConductor, System.LoggingLevel.INFO);
      }
    }

    try {
      if (localRollups.isEmpty() == false) {
        batch(getFlattenedProcessors(localRollups), fromInvocable);
      }
    } catch (Exception ex) {
      logAndThrowFlowException(ex, 'an error occurred during invocable action');
    }
    RollupLogger.Instance.save();

    return flowOutputs;
  }

  global static Id schedule(String jobName, String cronExp, String query, String rollupObjectName, Evaluator eval) {
    Rollup rollToSchedule;
    query = query.toUpperCase();
    if (query.contains('\nFROM ') == false) {
      query = query.substringBeforeLast(' FROM ') + '\nFROM ' + query.substringAfterLast(' FROM ');
    }
    try {
      RollupRepository repo = new RollupRepository(RollupRepository.RunAsMode.SYSTEM_LEVEL).setQuery(query);
      Integer queryCount = repo.getCount();
      if (queryCount < CACHED_DEFAULT.MaxQueryRows__c) {
        List<SObject> localCalcItems = repo.get();
        rollToSchedule = getRollup(
          getRollupMetadataBySObject(localCalcItems.getSObjectType()),
          localCalcItems.getSObjectType(),
          localCalcItems,
          new Map<Id, SObject>(),
          eval,
          InvocationPoint.FROM_SCHEDULED
        );
      } else {
        Schema.SObjectType childType = RollupFieldInitializer.Current.getDescribeFromName(rollupObjectName).getSObjectType();
        rollToSchedule = new RollupFullBatchRecalculator.NonResettingBulkFullRecalc(
          query,
          InvocationPoint.FROM_SCHEDULED,
          getRollupMetadataBySObject(childType),
          childType
        );
      }
    } catch (QueryException ex) {
      throw new QueryException('There\'s a problem with your query: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
    }
    RollupSchedulable scheduledRollup = new RollupSchedulable(rollToSchedule);
    return System.schedule(jobName + ' for ' + rollToSchedule.getTypeName(), cronExp, scheduledRollup);
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
    List<SObject> cdcRecords = records ?? Trigger.new;
    if (cdcRecords.isEmpty()) {
      return;
    }
    SObject firstRecord = cdcRecords[0];
    EventBus.ChangeEventHeader header = (EventBus.ChangeEventHeader) firstRecord.get('ChangeEventHeader');
    Schema.SObjectType sObjectType = RollupFieldInitializer.Current.getDescribeFromName(header.getEntityName()).getSObjectType();

    List<Rollup__mdt> matchingMetadata = getRollupMetadataBySObject(sObjectType);
    if (matchingMetadata.isEmpty()) {
      return;
    }

    Set<String> uniqueFieldNames = new Set<String>(firstRecord.getPopulatedFieldsAsMap().keySet());
    uniqueFieldNames.remove('ChangeEventHeader');
    RollupRepository.RunAsMode permissionLevel = RollupRepository.RunAsMode.SYSTEM_LEVEL;
    for (Rollup__mdt rollupInfo : matchingMetadata) {
      permissionLevel = RollupMetaPicklists.getAccessLevel(rollupInfo);
      RollupEvaluator.WhereFieldEvaluator eval = String.isBlank(rollupInfo.CalcItemWhereClause__c)
        ? null
        : RollupEvaluator.getWhereEval(rollupInfo.CalcItemWhereClause__c, sObjectType);
      uniqueFieldNames.addAll(getQueryFieldsFromMetadata(rollupInfo, eval));
    }

    // it would have been nice if this was an enum!
    switch on header.changeType {
      when 'CREATE', 'UNDELETE' {
        apexContext = TriggerOperation.AFTER_INSERT;
      }
      when 'UPDATE' {
        apexContext = TriggerOperation.AFTER_UPDATE;
      }
      when 'DELETE' {
        apexContext = TriggerOperation.BEFORE_DELETE;
      }
    }

    List<Id> updatedRecordIds = new List<Id>();
    for (SObject cdcRecord : cdcRecords) {
      header = (EventBus.ChangeEventHeader) cdcRecord.get('ChangeEventHeader');
      uniqueFieldNames.addAll(header.changedfields);
      updatedRecordIds.addAll(header.getRecordIds());
    }

    String queryString = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(uniqueFieldNames), 'Id', '=');
    // getting the items back from the database before putting them into the map is an important step
    // we COULD just initialize the map with the query, but then the map's .values() list doesn't return
    // anything for .getSObjectType() - which we need, further downstream
    List<SObject> cdcCalcItems = new RollupRepository(permissionLevel).setQuery(queryString).setArg(updatedRecordIds).get();
    Map<Id, SObject> cdcCalcItemsMap = new Map<Id, SObject>(cdcCalcItems);

    Rollup rollupToReturn = runFromApex(matchingMetadata, null, cdcCalcItems, cdcCalcItemsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isCDCUpdate = apexContext == TriggerOperation.AFTER_UPDATE;
    // we're already async, so let's not waste any more time
    rollupToReturn.rollupControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;
    rollupToReturn.runCalc();
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
   */
  global static void runFromApex(List<SObject> calcItems, System.TriggerOperation rollupContext) {
    shouldRun = shouldRun ?? true;
    records = calcItems;
    apexContext = rollupContext;

    runFromTrigger();

    records = null;
    shouldRun = false;
    apexContext = null;
  }

  global static void runFromApex(List<SObject> children, Map<Id, SObject> oldChildrenMap, System.TriggerOperation rollupContext) {
    oldChildrenMap = oldChildrenMap;
    runFromApex(children, rollupContext);
    oldChildrenMap = null;
  }

  global static Rollup runFromApex(List<Rollup__mdt> localMetas, Evaluator eval, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    Rollup rollupConductor = RollupAsyncProcessor.getConductor(InvocationPoint.FROM_APEX, calcItems, oldCalcItems);
    if (shouldRunFromTrigger() == false || localMetas.isEmpty()) {
      rollupConductor.calcItems = new List<SObject>();
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
        if (rollupConductor.rollupControl.IsMergeReparentingEnabled__c == false) {
          shouldReturn = true;
        } else {
          reparentAndGetMergedRecordIds(calcItems, localMetas, mergedParentIds, rollupConductor.rollupControl);
          shouldReturn = mergedParentIds.isEmpty();
        }
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
    processCustomMetadata(localRollups, localMetas, calcItems, oldCalcItems, mergedParentIds, rollupContext, InvocationPoint.FROM_APEX, typeToWrappedMeta);

    SObjectType calcItemSObjectType = calcItems.getSObjectType();
    populateCachedApexOperations(calcItemSObjectType, apexContext);

    if (localMetas.isEmpty() == false) {
      populateRollupByType(
        localRollups,
        calcItemSObjectType,
        getRollup(localMetas, calcItemSObjectType, calcItems, oldCalcItems, eval, InvocationPoint.FROM_APEX)
      );
    }

    flattenBatches(rollupConductor, getFlattenedProcessors(localRollups));
    return rollupConductor;
  }

  private class ChildrenSObject {
    public final List<SObject> records;
    public final Boolean done = true;
    public final Integer totalSize;

    public ChildrenSObject(List<SObject> records) {
      this.records = records;
      this.totalSize = records.size();
    }
  }

  /**
   * @return `Rollup__mdt` the metadata with the `List<RollupOrderBy__mdt>` RollupOrderBys__r relationship set
   * <br>
   * Credit for this method (with some tweaking) goes to: https://github.com/tsalb
   */
  global static Rollup__mdt appendOrderByMetadata(Rollup__mdt meta, List<RollupOrderBy__mdt> children) {
    if (children?.isEmpty() != false) {
      return meta;
    }
    meta.OrderByFirstLast__c = null;
    String serializedMeta = JSON.serialize(meta).removeEnd('}');

    String orderByRelationshipName;
    List<Schema.ChildRelationship> potentiallyMatchingRelationships = Rollup__mdt.SObjectType.getDescribe(SObjectDescribeOptions.FULL).getChildRelationships();
    for (Schema.ChildRelationship relationship : potentiallyMatchingRelationships) {
      if (relationship.getChildSObject() == RollupOrderBy__mdt.SObjectType) {
        orderByRelationshipName = relationship.getRelationshipName();
      }
    }
    String childrenJson = '"' + orderByRelationshipName + '" : ' + JSON.serialize(new ChildrenSObject(children));
    serializedMeta += ',' + childrenJson + '}';

    return (Rollup__mdt) JSON.deserialize(serializedMeta, Rollup__mdt.class);
  }

  /** end global-facing section, begin public/private static helpers */

  public static RollupControl__mdt getDefaultControl() {
    return CACHED_DEFAULT;
  }

  public static void processStoredFlowRollups() {
    flatten(CACHED_ROLLUPS);
    List<Rollup> rollupsToProcess = new List<Rollup>(CACHED_ROLLUPS);
    CACHED_ROLLUPS = null;
    CACHED_FULL_RECALCS = null;
    CACHED_COUNT_QUERIES = null;
    batch(rollupsToProcess, InvocationPoint.FROM_INVOCABLE);
  }

  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static List<SObject> getMetadataFromCache(SObjectType metadataType) {
    List<SObject> matchingMetadata;
    if (metadataType == Rollup__mdt.SObjectType) {
      cachedMetadata = cachedMetadata ?? (onlyUseMockMetadata ? new List<Rollup__mdt>() : RollupRepository.getRollupMetadata());
      if (rollupMetadata != null) {
        cachedMetadata.addAll(rollupMetadata);
        rollupMetadata = null;
      }
      // downstream callers can modify this collection - clone prevents the cache from being modified too
      matchingMetadata = cachedMetadata.clone();
    } else if (metadataType == RollupControl__mdt.SObjectType) {
      // CMDT is read-only when returned from the cache
      // use "deepClone" to get access to mutable versions of the CMDT records.
      matchingMetadata = RollupControl__mdt.getAll().deepClone().values();
    }
    return matchingMetadata;
  }

  public static Boolean hasExceededCurrentRollupLimits(RollupControl__mdt control) {
    RollupLimits.Tester limitTester = new RollupLimits.Tester(control, isContextAsync());
    Boolean hasExceededLimits = limitTester.hasExceededLimits() && isDeferralAllowed;
    if (limitTester.hasExceededLimits() && isDeferralAllowed) {
      Boolean isLoggingCurrentlyDisabled = control?.IsRollupLoggingEnabled__c == false;
      if (isLoggingCurrentlyDisabled) {
        control.IsRollupLoggingEnabled__c = true;
        RollupLogger.Instance.updateRollupControl(control);
      }
      RollupLogger.Instance.log('exceeded limits:', limitTester, System.LoggingLevel.WARN);
      if (isLoggingCurrentlyDisabled) {
        RollupLogger.Instance.log('disabling logging again', System.LoggingLevel.INFO);
        control.isRollupLoggingEnabled__c = false;
        RollupLogger.Instance.updateRollupControl(control);
      }
    }
    return hasExceededLimits;
  }

  public static String getBaseOperationName(String fullOpName) {
    Set<String> operationsWithUnderscores = new Set<String>{ Op.COUNT_DISTINCT.name(), Op.CONCAT_DISTINCT.name() };
    return operationsWithUnderscores.contains(fullOpName) == false && fullOpName.contains('_') ? fullOpName.substringAfter('_') : fullOpName;
  }

  private static Rollup__mdt transformFlowInputToRollupMetadata(FlowInput flowInput, String rollupContext, SObjectType sObjectType) {
    Rollup__mdt transformedMeta = getMetadataWithOrderBys(
      new Rollup__mdt(
        CalcItem__c = flowInput.isRollupStartedFromParent || String.isNotBlank(flowInput.calcItemTypeWhenRollupStartedFromParent)
          ? flowInput.calcItemTypeWhenRollupStartedFromParent
          : String.valueOf(sObjectType),
        CalcItemWhereClause__c = flowInput.calcItemWhereClause,
        ChangedFieldsOnCalcItem__c = flowInput.calcItemChangedFields,
        ConcatDelimiter__c = flowInput.concatDelimiter,
        CurrencyFieldMapping__c = flowInput.currencyFieldMapping,
        DeveloperName = flowInput.DeveloperName,
        FullRecalculationDefaultNumberValue__c = flowInput.fullRecalculationDefaultNumberValue,
        FullRecalculationDefaultStringValue__c = flowInput.fullRecalculationDefaultStringValue,
        GrandparentRelationshipFieldPath__c = flowInput.grandparentRelationshipFieldPath,
        GroupByFields__c = flowInput.groupByFields,
        GroupByRowEndDelimiter__c = flowInput.groupByRowEndDelimiter,
        GroupByRowStartDelimiter__c = flowInput.groupByRowStartDelimiter,
        IsDistinct__c = flowInput.isDistinct,
        IsFullRecordSet__c = flowInput.isFullRecordSet,
        IsRollupStartedFromParent__c = flowInput.isRollupStartedFromParent,
        IsTableFormatted__c = flowInput.isTableFormatted,
        LookupFieldOnCalcItem__c = flowInput.lookupFieldOnCalcItem,
        LookupFieldOnLookupObject__c = flowInput.lookupFieldOnOpObject,
        LookupObject__c = flowInput.rollupSObjectName,
        OneToManyGrandparentFields__c = flowInput.oneToManyGrandparentFields,
        OrderByFirstLast__c = flowInput.orderByFirstLast,
        RollupControl__r = getSingleControlOrDefault(RollupControl__mdt.Id, flowInput.rollupControlId, defaultControl),
        RollupGrouping__r = flowInput.rollupGrouping,
        RollupFieldOnCalcItem__c = flowInput.rollupFieldOnCalcItem,
        RollupFieldOnLookupObject__c = flowInput.rollupFieldOnOpObject,
        RollupOperation__c = rollupContext + flowInput.rollupOperation,
        RollupToUltimateParent__c = flowInput.rollupToUltimateParent,
        SharingMode__c = flowInput.sharingMode,
        SplitConcatDelimiterOnCalcItem__c = flowInput.splitConcatDelimiterOnCalcItem,
        UltimateParentLookup__c = flowInput.ultimateParentLookup
      ),
      flowInput.rollupOperation
    );
    transformedMeta.RollupControl__c = transformedMeta.RollupControl__r.Id;
    return transformedMeta;
  }

  private static Boolean isContextAsync() {
    return System.isBatch() || System.isQueueable() || System.isScheduled() || System.isFuture() || shouldFlattenAsyncProcesses == true;
  }

  private static Boolean shouldSkipRollupForFlow(Rollup__mdt meta, String flowContext) {
    if (String.isBlank(meta.RollupControl__r?.OnlyRunInFlowContexts__c)) {
      return false;
    }
    Set<String> allowedContexts = new Set<String>();
    for (String specificAllowedContext : meta.RollupControl__r.OnlyRunInFlowContexts__c.split(',')) {
      allowedContexts.add(specificAllowedContext.trim());
    }
    return allowedContexts.contains(flowContext) == false;
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
    List<SObject> triggerRecords = getTriggerRecords();
    Rollup__mdt meta = appendOrderByMetadata(
      new Rollup__mdt(
        CalcItem__c = triggerRecords.getSObjectType()?.toString(),
        LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.toString(),
        LookupFieldOnLookupObject__c = lookupFieldOnOperationObject.toString(),
        LookupObject__c = lookupSObjectType.toString(),
        RollupFieldOnCalcItem__c = operationFieldOnCalcItem.toString(),
        RollupFieldOnLookupObject__c = operationFieldOnOperationObject.toString(),
        RollupOperation__c = rollupOperation.name()
      ),
      orderByMetas
    );
    if (defaultRecalculationValue instanceof Decimal) {
      meta.FullRecalculationDefaultNumberValue__c = (Decimal) defaultRecalculationValue;
    } else if (defaultRecalculationValue instanceof String) {
      meta.FullRecalculationDefaultStringValue__c = (String) defaultRecalculationValue;
    }
    return runFromApex(new List<Rollup__mdt>{ meta }, eval, triggerRecords, getOldTriggerRecordsMap());
  }

  private static void flatten(List<Rollup> stackedRollups) {
    Map<String, Rollup> rollupOperationToRollup = new Map<String, Rollup>();
    for (Rollup stackedRollup : stackedRollups) {
      // If the hashed content doesn't match, we can't collapse the two rollup operations
      String rollupKey = stackedRollup?.getHashedContents();
      if (stackedRollup?.calcItems != null && rollupOperationToRollup.containsKey(rollupKey)) {
        Rollup matchingRollup = rollupOperationToRollup.get(rollupKey);
        Map<Id, SObject> stackedMatchingItems = new Map<Id, SObject>(stackedRollup.calcItems);
        stackedMatchingItems.putAll(matchingRollup.calcItems);
        stackedRollup.calcItems = stackedMatchingItems.values();
        stackedRollup.oldCalcItems.putAll(matchingRollup.oldCalcItems);

        for (Integer index = 0; index < matchingRollup.rollups.size(); index++) {
          Rollup innerRollup = matchingRollup.rollups[index];
          if (stackedRollup.rollups.size() > index) {
            Rollup matchingInnerRollup = stackedRollup.rollups[index];
            matchingInnerRollup.matchingCalcItemIds.addAll(innerRollup.matchingCalcItemIds);
            matchingInnerRollup.matchingCalcItemIds.addAll(innerRollup.oldCalcItems.keySet());
          }
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
    for (Integer index = metas.size() - 1; index >= 0; index--) {
      Rollup__mdt meta = metas[index];
      Schema.SObjectType initialType = calcItems.getSObjectType();
      if (initialType == null && calcItems.isEmpty() == false) {
        initialType = calcItems.get(0).getSObjectType();
      }
      Boolean nonMatchingGrandparent = String.isNotBlank(meta.GrandparentRelationshipFieldPath__c) && meta.CalcItem__c != String.valueOf(initialType);
      SObjectType calcItemSObjectType = meta.IsRollupStartedFromParent__c == false &&
        apexContext != TriggerOperation.AFTER_DELETE &&
        nonMatchingGrandparent == false &&
        calcItems.isEmpty() == false
        ? calcItems[0].getSObjectType()
        : RollupFieldInitializer.Current.getDescribeFromName(meta.CalcItem__c).getSObjectType();
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
        queryWrapper.setQuery(meta.CalcItemWhereClause__c);
      } else if (isRefresh) {
        // the order of operations is important here - REFRESH *also* needs to check for
        // meta.IsRollupStartedFromParent__c, so that check can't come first
        queryWrapper = getFullRecalcQueryWrapper(meta, calcItems, oldCalcItems);
      } else if (meta.IsRollupStartedFromParent__c) {
        queryWrapper = getParentQueryWrapper(calcItems, oldCalcItems, meta);
      } else if (isIntermediateRollupForGrandparent) {
        queryWrapper = getIntermediateGrandparentQueryWrapper(meta, calcItems, oldCalcItems, rollupContext);
      }

      if (queryWrapper?.hasQuery == true) {
        metas.remove(index);
        String query = queryWrapper.getQuery();
        RollupMetadata wrappedMeta = getWrappedMeta(
          calcItemSObjectType,
          typeToWrappedMeta,
          meta,
          query + (String.isNotBlank(meta.CalcItemWhereClause__c) ? ' AND ' + meta.CalcItemWhereClause__c : '')
        );
        rollups.get(calcItemSObjectType)?.clear();
        wrappedMeta.recordIds.addAll(queryWrapper.recordIds);
        wrappedMeta.typeToOldIntermediateParents.putAll(queryWrapper.typeToOldIntermediateParents);
        if (wrappedMeta.recordIds.isEmpty() == false) {
          wrappedMeta.possibleWhereClauses.add(query);
          wrappedMeta.whereClause = query;
        }
        wrappedMeta.parentRecordsToReset.addAll(queryWrapper.parentRecordsToReset);
        appendQueryCount(wrappedMeta, meta, wrappedMeta.whereClause, calcItemSObjectType);
      } else if (isRefresh || queryWrapper != null) {
        // remove non-matches
        metas.remove(index);
      } else {
        // if the same items get run through different rollup operations in the same transaction (rare, but not impossible ...)
        // we need to reset the CMDT to the correct base operation prior to appending the new context
        meta.RollupOperation__c = (meta.RollupOperation__c.contains('UPDATE_') || meta.RollupOperation__c.contains('DELETE_')
          ? meta.RollupOperation__c.substringAfter('_')
          : meta.RollupOperation__c);
        if (OP_NAME_TO_OP.containsKey(rollupContext + meta.RollupOperation__c)) {
          meta.RollupOperation__c = rollupContext + meta.RollupOperation__c;
        }
      }
    }

    List<RollupFullRecalcProcessor> fullRecalcs = transformWrappedMetadataToFullRecalcRollups(typeToWrappedMeta, invokePoint);
    for (RollupFullRecalcProcessor fullRecalc : fullRecalcs) {
      populateRollupByType(rollups, fullRecalc.getCalcItemType(), fullRecalc);
    }
  }

  private static QueryWrapper getFullRecalcQueryWrapper(Rollup__mdt meta, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    QueryWrapper wrapper;
    meta.RollupOperation__c = meta.RollupOperation__c.replace('REFRESH_', '');
    if (String.isNotBlank(meta.CalcItemWhereClause__c)) {
      SObjectType calcItemType = calcItems[0].getSObjectType();
      RollupEvaluator.WhereFieldEvaluator eval = RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, calcItemType);
      Boolean matches = false;
      FilterResults filter = filter(calcItems, oldCalcItems, eval, meta, calcItemType, matches);
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

  private static Set<String> getQueryFieldsFromMetadata(Rollup__mdt meta, RollupEvaluator.WhereFieldEvaluator eval) {
    Set<String> queryFields = new Set<String>{ 'Id', meta.RollupFieldOnCalcItem__c, meta.LookupFieldOnCalcItem__c };
    if (eval != null) {
      queryFields.addAll(eval.getQueryFields());
    }
    List<String> groupByFields = meta.GroupByFields__c?.split(',') ?? new List<String>();
    for (String groupByField : groupByFields) {
      queryFields.add(groupByField.trim());
    }
    for (RollupOrderBy__mdt orderByInfo : meta.RollupOrderBys__r) {
      queryFields.add(orderByInfo.FieldName__c.trim());
    }
    return queryFields;
  }

  private static String getFullRecalcQueryString(List<Rollup__mdt> metas) {
    Set<String> orderByFields = new Set<String>();
    for (Rollup__mdt meta : metas) {
      if (meta.GrandparentRelationshipFieldPath__c != null) {
        orderByFields.add(meta.GrandparentRelationshipFieldPath__c.substringBeforeLast('.') + '.Id');
      }
      orderByFields.add(meta.LookupFieldOnCalcItem__c);
      orderByFields.add('Id');
    }
    return '\nORDER BY ' + String.join(orderByFields, ',');
  }

  private static RollupMetadata getWrappedMeta(
    Schema.SObjectType childType,
    Map<Schema.SObjectType, RollupMetadata> typeToWrappedMeta,
    Rollup__mdt innerMeta,
    String whereClause
  ) {
    RollupMetadata wrappedMeta = typeToWrappedMeta.get(childType);
    if (wrappedMeta == null) {
      wrappedMeta = new RollupMetadata();
      typeToWrappedMeta.put(childType, wrappedMeta);
    }
    wrappedMeta.metadata.add(innerMeta);
    RollupEvaluator.WhereFieldEvaluator eval = String.isBlank(whereClause) ? null : RollupEvaluator.getWhereEval(whereClause, childType);
    wrappedMeta.queryFields.addAll(getQueryFieldsFromMetadata(innerMeta, eval));
    if (innerMeta.IsRollupStartedFromParent__c && innerMeta.GrandparentRelationshipFieldPath__c != null) {
      wrappedMeta.queryFields.add(innerMeta.GrandparentRelationshipFieldPath__c);
    }
    return wrappedMeta;
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
        wrappedMeta.recordCount = RollupRepository.SENTINEL_COUNT_VALUE;
      }
      String queryString = RollupQueryBuilder.Current.getQuery(calcType, new List<String>(wrappedMeta.queryFields), 'Id', '!=', wrappedMeta.whereClause);
      RollupFullRecalcProcessor fullRecalc = buildFullRecalcRollup(wrappedMeta, queryString, calcType, localInvokePoint);
      setControlToSyncForSingularParentRecalcs(fullRecalc.rollupControl, localInvokePoint);
      if (fullRecalc.isNoOp) {
        fullRecalc.isNoOp = wrappedMeta.recordCount == 0;
      }
      fullRecalc.queryCount = wrappedMeta.recordCount;
      RollupLogger.Instance.log('full recalc prepared:', fullRecalc, System.LoggingLevel.INFO);
      fullRecalcRollups.add(fullRecalc);
      CACHED_FULL_RECALCS.add(fullRecalc);
    }
    return fullRecalcRollups;
  }

  private static void appendQueryCount(RollupMetadata metaWrapper, Rollup__mdt meta, String whereClause, Schema.SObjectType childType) {
    if (metaWrapper.recordCount != RollupRepository.SENTINEL_COUNT_VALUE) {
      String query = RollupQueryBuilder.Current.getQuery(childType, new List<String>(), meta.LookupFieldOnLookupObject__c, '!=', whereClause);
      String hashedQuery = query + meta.LookupObject__c + metaWrapper.recordIds;
      Integer currentCount;
      if (CACHED_COUNT_QUERIES.contains(hashedQuery)) {
        currentCount = 0;
      } else {
        currentCount = new RollupRepository(RollupMetaPicklists.getAccessLevel(meta))
          .setQuery(query)
          .setArg(new Set<String>())
          .setArg('recordIds', metaWrapper.recordIds)
          .getCount();
        CACHED_COUNT_QUERIES.add(hashedQuery);
      }
      metaWrapper.recordCount = currentCount == RollupRepository.SENTINEL_COUNT_VALUE ? currentCount : metaWrapper.recordCount + currentCount;
    }
  }

  private static RollupFullRecalcProcessor buildFullRecalcRollup(
    RollupMetadata wrappedMeta,
    String queryString,
    SObjectType calcItemType,
    InvocationPoint invokePoint
  ) {
    Id rollupControlId;
    String keyField = 'Id';
    Set<String> lookupFields = new Set<String>{ keyField };
    for (Rollup__mdt meta : wrappedMeta.metadata) {
      meta.IsFullRecordSet__c = true;
      meta.RollupOperation__c = getBaseOperationName(meta.RollupOperation__c);
      rollupControlId = meta.RollupControl__c;
      lookupFields.add(meta.LookupFieldOnLookupObject__c.toLowerCase());
      lookupFields.add(meta.RollupFieldOnLookupObject__c.toLowerCase());
      keyField = meta.LookupFieldOnLookupObject__c;
    }
    RollupControl__mdt control = getSingleControlOrDefault(RollupControl__mdt.Id, rollupControlId, defaultControl);
    Schema.SObjectType parentType = RollupFieldInitializer.Current.getDescribeFromName(wrappedMeta.metadata[0].LookupObject__c).getSObjectType();
    String equality = invokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC ? '=' : '!=';
    lookupFields.retainAll(parentType.getDescribe().fields.getMap().keyset());
    String parentQuery = RollupQueryBuilder.Current.getQuery(parentType, new List<String>(lookupFields), keyField, equality);

    RollupParentResetProcessor parentResetProcessor = new RollupParentResetProcessor(
      wrappedMeta.metadata,
      parentType,
      parentQuery,
      // here we duplicate the recordId list because it's also passed to the fullRecalc instance initialized below and
      // "bad things" can happen if both collections have the same reference
      new Set<String>(wrappedMeta.recordIds),
      invokePoint
    );
    Boolean shouldQueue =
      wrappedMeta.recordCount != RollupRepository.SENTINEL_COUNT_VALUE &&
      wrappedMeta.recordCount < parentResetProcessor.rollupControl.MaxLookupRowsBeforeBatching__c;
    if (wrappedMeta.recordCount == 0 && wrappedMeta.metadata.isEmpty() == false && isFullRecalcApp && control.ShouldSkipResettingParentFields__c == false) {
      return parentResetProcessor;
    } else if (
      (invokePoint != InvocationPoint.FROM_FULL_RECALC_LWC && invokePoint != InvocationPoint.FROM_FULL_RECALC_FLOW) ||
      control.ShouldSkipResettingParentFields__c
    ) {
      parentResetProcessor = null;
    }

    RollupFullRecalcProcessor fullRecalc = shouldQueue
      ? (RollupFullRecalcProcessor) new RollupDeferredFullRecalcProcessor(
          wrappedMeta.metadata,
          calcItemType,
          queryString,
          wrappedMeta.recordIds,
          invokePoint,
          parentResetProcessor
        )
      : (RollupFullRecalcProcessor) new RollupFullBatchRecalculator(
          (queryString + getFullRecalcQueryString(wrappedMeta.metadata)),
          invokePoint,
          wrappedMeta.metadata,
          calcItemType,
          wrappedMeta.recordIds,
          parentResetProcessor
        );

    if (wrappedMeta.parentRecordsToReset.isEmpty() == false) {
      fullRecalc.storeParentFieldsToClear(wrappedMeta.parentRecordsToReset);
      fullRecalc.isNoOp = false;
    }
    if (wrappedMeta.typeToOldIntermediateParents.isEmpty() == false) {
      fullRecalc.setOldIntermediateGrandparents(wrappedMeta.typeToOldIntermediateParents);
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
    List<Rollup> processors = rollups.get(calcType) ?? new List<Rollup>();
    processors.add(processor);
    rollups.put(calcType, processors);
  }

  private static List<Rollup> getFlattenedProcessors(Map<Schema.SObjectType, List<Rollup>> typeToProcessors) {
    List<Rollup> flattenedRollups = new List<Rollup>();
    for (List<Rollup> rolls : typeToProcessors.values()) {
      flattenedRollups.addAll(rolls);
    }
    return flattenedRollups;
  }

  private static void flattenBatches(Rollup rollupConductor, List<Rollup> rollups) {
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
        flattenBatches(rollupConductor, rollup.rollups);
      } else {
        addRollup(rollupConductor, rollup);
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
    } else if (flowInput.groupByRowStartDelimiter != null && flowInput.groupByFields == null) {
      errorMessage = 'You must set group by fields when supplying a group by delimiter';
    } else if (flowInput.rollupOperation.contains(Op.CONCAT.name()) == false) {
      if (String.isNotBlank(flowInput.concatDelimiter) && flowInput.groupByFields == null) {
        errorMessage = 'Concat delimiter should only be supplied for CONCAT-based rollups. ';
      }
      if (flowInput.splitConcatDelimiterOnCalcItem == true) {
        errorMessage = (errorMessage ?? '') + 'Concat options should only be set for CONCAT_DISTINCT operations';
      }
    }

    if (errorMessage != null) {
      Exception ex = new IllegalArgumentException(errorMessage);
      logAndThrowFlowException(ex, 'an error occurred while validating flow inputs');
    }
  }

  private static void enforceFlowSpecificRules(FlowInput flowInput, SObjectType sObjectType) {
    try {
      if (flowInput.rollupContext.startsWith('UP') && flowInput.oldRecordsToRollup?.isEmpty() == true) {
        throw new IllegalArgumentException('Prior records to rollup collection required for rollup context: ' + flowInput.rollupContext);
      } else if (String.isBlank(flowInput.grandparentRelationshipFieldPath)) {
        SObject firstRecord = flowInput.recordsToRollup[0];
        SObject lookupItem = RollupFieldInitializer.Current.getDescribeFromName(
            flowInput.isRollupStartedFromParent ? flowInput.calcItemTypeWhenRollupStartedFromParent : flowInput.rollupSObjectName
          )
          .getSObjectType()
          .newSObject();

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
    RollupLogger.Instance.log(logString + ':', ex, System.LoggingLevel.ERROR);
    RollupLogger.Instance.save();
    throw ex;
  }

  private static QueryWrapper getIntermediateGrandparentQueryWrapper(
    Rollup__mdt meta,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    String rollupContext
  ) {
    Boolean isDelete = rollupContext.startsWithIgnoreCase('delete');
    if (isCDC || oldCalcItems?.isEmpty() != false && isDelete == false) {
      return new QueryWrapper();
    }

    SObjectType sObjectType = calcItems[0].getSObjectType();
    SObjectField fieldToken = getPartOfGrandparentChain(meta, sObjectType);
    String relationshipName = fieldToken.getDescribe().getRelationshipName();
    Integer relationshipIndex = meta.GrandparentRelationshipFieldPath__c.indexOf(relationshipName) + relationshipName.length();
    String priorFieldPath = meta.GrandparentRelationshipFieldPath__c.substring(0, relationshipIndex) + '.Id';
    if (meta.OneToManyGrandparentFields__c != null && meta.OneToManyGrandparentFields__c.contains(fieldToken.toString())) {
      List<String> fieldPathTuples = meta.OneToManyGrandparentFields__c.split(',');
      for (String fieldPathTuple : fieldPathTuples) {
        if (fieldToken.toString().equalsIgnoreCase(fieldPathTuple.substringAfter('.'))) {
          priorFieldPath = 'Id';
          break;
        }
      }
    }

    QueryWrapper wrapper = new QueryWrapper('', priorFieldPath);
    SObject possibleOldItem = sObjectType.newSObject();
    for (SObject calcItem : calcItems) {
      SObject oldCalcItem = isDelete ? possibleOldItem : oldCalcItems.get(calcItem.Id);
      String currentLookup = (String) calcItem.get(fieldToken);
      String oldLookup = (String) oldCalcItem?.get(fieldToken);
      if (oldCalcItem == null || currentLookup == oldLookup) {
        continue;
      }

      wrapper.addRecordId(currentLookup);
      if (isDelete) {
        oldLookup = currentLookup;
        currentLookup = null;
      }
      if (oldLookup != null) {
        wrapper.addRecordId(oldLookup);
        Set<Id> oldIntermediateParents = wrapper.typeToOldIntermediateParents.get(calcItem.getSObjectType());
        if (oldIntermediateParents == null) {
          oldIntermediateParents = new Set<Id>();
          wrapper.typeToOldIntermediateParents.put(calcItem.getSObjectType(), oldIntermediateParents);
        }
        oldIntermediateParents.add((Id) oldLookup);
      }
    }
    return wrapper;
  }

  private class QueryWrapper {
    private Boolean hasQuery = false;
    private String query;
    private final List<SObject> parentRecordsToReset = new List<SObject>();
    private final Set<String> recordIds = new Set<String>();
    private final Map<Schema.SObjectType, Set<Id>> typeToOldIntermediateParents = new Map<Schema.SObjectType, Set<Id>>();

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
      }
    }

    public String getQuery() {
      return this.hasQuery ? this.query : '';
    }

    public void setQuery(String appendedQuery) {
      if (String.isNotBlank(appendedQuery)) {
        this.hasQuery = true;
        this.query = '(' + appendedQuery + ') AND ' + this.query;
      }
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
    wrapper.setQuery(meta.CalcItemWhereClause__c);
    return wrapper;
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
    // recursive updates from Apex - particularly from merges, but possible elsewhere - can trigger downstream flows
    // and it's important the original context be maintained in those situations
    apexContext = apexContext ?? matchingOperation;
    populateCachedApexOperations(sObjectType, matchingOperation);

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static void winnowOldFlowRecords(FlowInput flowInput) {
    flowInput.oldRecordsToRollup = flowInput.oldRecordsToRollup?.clone() ?? new List<SObject>();
    for (Integer index = flowInput.oldRecordsToRollup.size() - 1; index >= 0; index--) {
      SObject oldRecord = flowInput.oldRecordsToRollup[index];
      // record-triggered flows set up to run when "A record is created or modified"
      // will pass null in the list if it runs on create - yikes.
      if (oldRecord?.Id == null) {
        flowInput.oldRecordsToRollup.remove(index);
      }
    }
  }

  private static void populateCachedApexOperations(Schema.SObjectType calcItemSObjectType, TriggerOperation triggerContext) {
    Set<TriggerOperation> cachedOperations = CACHED_APEX_OPERATIONS.get(calcItemSObjectType);
    if (cachedOperations == null) {
      cachedOperations = new Set<TriggerOperation>();
      CACHED_APEX_OPERATIONS.put(calcItemSObjectType, cachedOperations);
    }
    cachedOperations.add(triggerContext);
  }

  private static List<Rollup__mdt> getRollupMetadataBySObject(SObjectType sObjectType) {
    String sObjectName = '' + sObjectType;
    List<Rollup__mdt> rollupMetadatas = getMetadataFromCache(Rollup__mdt.SObjectType);
    Set<String> rollupGroupings = new Set<String>();
    List<Rollup__mdt> runoffMetas = new List<Rollup__mdt>();
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
        runoffMetas.add(rollupMetadatas.remove(index));
      } else if (isNotTriggeredByMatchingObject(meta, sObjectName)) {
        runoffMetas.add(rollupMetadatas.remove(index));
      } else {
        rollupGroupings.add(meta.RollupGrouping__r.Id);
      }
    }
    rollupGroupings.remove(null);
    for (Rollup__mdt meta : runoffMetas) {
      if (rollupGroupings.contains(meta.RollupGrouping__r.Id)) {
        rollupMetadatas.add(meta);
      }
    }
    return rollupMetadatas;
  }

  private static Boolean isNotTriggeredByMatchingObject(Rollup__mdt meta, String sObjectName) {
    return (meta.CalcItem__c != sObjectName && meta.IsRollupStartedFromParent__c == false) ||
      (meta.IsRollupStartedFromParent__c && sObjectName != meta.LookupObject__c);
  }

  @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
  public static Schema.SObjectField getPartOfGrandparentChain(Rollup__mdt meta, Schema.SObjectType sObjectType) {
    List<String> validRelationshipNames = meta.GrandparentRelationshipFieldPath__c.split('\\.');
    // remove the last field since it's not a relationship
    validRelationshipNames.remove(validRelationshipNames.size() - 1);
    Schema.SObjectDescribeOptions loadOptions = String.isNotBlank(meta.OneToManyGrandparentFields__c)
      ? SObjectDescribeOptions.FULL
      : SObjectDescribeOptions.DEFERRED;
    Set<String> uniqueRelationshipNames = new Set<String>(validRelationshipNames);
    for (Schema.SObjectField fieldToken : sObjectType.getDescribe(loadOptions).fields.getMap().values()) {
      String relationshipName = fieldToken.getDescribe().getRelationshipName();
      if (relationshipName == null) {
        continue;
      } else if (uniqueRelationshipNames.contains(relationshipName)) {
        return fieldToken;
      } else if (loadOptions == SObjectDescribeOptions.FULL) {
        List<Schema.SObjectType> parents = fieldToken.getDescribe().getReferenceTo();
        for (Schema.SObjectType parent : parents) {
          for (Schema.ChildRelationship child : parent.getDescribe().getChildRelationships()) {
            if (uniqueRelationshipNames.contains(child.getRelationshipName())) {
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
    switch on rollupInvokePoint {
      when FROM_APEX, FROM_INVOCABLE {
        calcItems = CALC_ITEM_REPLACER.replace(calcItems, rollupOperations);
        if (oldCalcItems?.isEmpty() == false) {
          oldCalcItems = new Map<Id, SObject>(CALC_ITEM_REPLACER.replace(oldCalcItems.values(), rollupOperations));
        }
      }
    }

    RollupAsyncProcessor rollupConductor = RollupAsyncProcessor.getConductor(rollupInvokePoint, calcItems, oldCalcItems);
    if (rollupOperations.isEmpty() || calcItems.isEmpty()) {
      return rollupConductor;
    } else if (rollupOperations.size() == 1) {
      rollupConductor.metadata = rollupOperations[0];
    }
    sObjectType = sObjectType ?? calcItems[0].getSObjectType();

    Boolean shouldFilterCalcItems = CALC_ITEM_REPLACER.hasProcessedMetadata(rollupOperations, calcItems);

    /**
     * We have rollup operations to perform. That's great!
     * Let's get ready to rollup!
     */
    Map<String, SObjectField> calcItemFields = sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    RollupFieldInitializer init = RollupFieldInitializer.Current;
    updateLoggingControl(rollupOperations);

    for (Rollup__mdt rollupMetadata : rollupOperations) {
      Op rollupOp = OP_NAME_TO_OP.get(rollupMetadata.RollupOperation__c.toUpperCase());
      if (rollupMetadata.RollupGrouping__r.Id != null && rollupMetadata.CalcItem__c != null && rollupMetadata.CalcItem__c != sObjectType.toString()) {
        Schema.DescribeSObjectResult childDescribe = init.getDescribeFromName(rollupMetadata.CalcItem__c);
        sObjectType = childDescribe.getSObjectType();
        calcItemFields = childDescribe.fields.getMap();
      }
      SObjectField rollupFieldOnCalcItem = init.getSObjectFieldByName(calcItemFields, rollupMetadata.RollupFieldOnCalcItem__c);
      SObjectField calcLookupField = init.getSObjectFieldByName(calcItemFields, rollupMetadata.LookupFieldOnCalcItem__c);

      Schema.DescribeSObjectResult lookupDescribe = init.getDescribeFromName(rollupMetadata.LookupObject__c);
      Map<String, SObjectField> lookupItemFields = lookupDescribe.fields.getMap();
      SObjectField lookupFieldOnOpObject = init.getSObjectFieldByName(lookupItemFields, rollupMetadata.LookupFieldOnLookupObject__c);
      SObjectField rollupFieldOnOpObject = init.getSObjectFieldByName(lookupItemFields, rollupMetadata.RollupFieldOnLookupObject__c);

      if (rollupFieldOnCalcItem == null || calcLookupField == null || lookupFieldOnOpObject == null || rollupFieldOnOpObject == null) {
        Map<String, String> errorMap = new Map<String, String>{
          'Child rollup field' => '' + rollupFieldOnCalcItem,
          'Child lookup field' => '' + calcLookupField,
          'Label' => rollupMetadata.MasterLabel,
          'Parent lookup field' => '' + lookupFieldOnOpObject,
          'Parent rollup field' => '' + rollupFieldOnOpObject
        };
        throw new System.IllegalArgumentException(
          'At least one of the following values is null when it should not be. Check your rollup configs for possible misspellings: ' + JSON.serialize(errorMap)
        );
      }

      if (isFullRecalcOp(getBaseOperationName(rollupMetadata.RollupOperation__c)) || rollupMetadata.GroupByFields__c != null) {
        rollupMetadata.IsFullRecordSet__c = true;
      }
      rollupMetadata = getMetadataWithOrderBys(rollupMetadata, rollupOp.name());

      RollupControl__mdt localControl;
      if (rollupMetadata.RollupControl__c != null) {
        // for CMDT-driven rollups, the rollup record is always tied to a RollupControl__mdt record
        localControl = getSingleControlOrDefault(RollupControl__mdt.Id, rollupMetadata.RollupControl__c, specificControl);
      } else {
        String controlKey = getRollupControlKey(rollupInvokePoint, rollupFieldOnCalcItem, lookupDescribe.getSObjectType(), rollupFieldOnOpObject);
        localControl = getSingleControlOrDefault(RollupControl__mdt.TriggerOrInvocableName__c, controlKey, specificControl);
      }
      setControlToSyncForSingularParentRecalcs(localControl, rollupInvokePoint);
      if (rollupConductor.rollupControl != null && rollupConductor.rollupControl != localControl) {
        rollupConductor.rollupControl.IsRollupLoggingEnabled__c = localControl.IsRollupLoggingEnabled__c;
      }

      FilterResults filterResults = filter(calcItems, oldCalcItems, eval, rollupMetadata, sObjectType, shouldFilterCalcItems);
      if (filterResults.matchingItemIds.isEmpty() == false) {
        loadRollups(
          rollupFieldOnCalcItem,
          calcLookupField,
          lookupFieldOnOpObject,
          rollupFieldOnOpObject,
          lookupDescribe.getSObjectType(),
          sObjectType, // child object SObjectType
          rollupOp,
          filterResults,
          rollupConductor,
          localControl,
          rollupInvokePoint,
          rollupMetadata
        );
      }
    }
    rollupConductor.isNoOp = rollupConductor.rollups.isEmpty();
    return rollupConductor;
  }

  private static Rollup__mdt getMetadataWithOrderBys(Rollup__mdt meta, String rollupOpName) {
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
    } else if (
      meta.RollupOrderBys__r.isEmpty() && (rollupOpName.contains(Op.FIRST.name()) || rollupOpName.contains(Op.LAST.name())) || meta.LimitAmount__c != null
    ) {
      replacementOrderBys = new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = meta.RollupFieldOnCalcItem__c) };
    }
    return appendOrderByMetadata(meta, replacementOrderBys);
  }

  private static Boolean isFullRecalcOp(String baseOperationName) {
    Boolean isFullRecalcOp = false;
    switch on OP_NAME_TO_OP.get(baseOperationName) {
      when ALL, AVERAGE, CONCAT_DISTINCT, CONCAT, COUNT_DISTINCT, FIRST, LAST, MOST, NONE, SOME {
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

  /**
   * - in order to accomodate CDC, we set the apexContext manually there
   * since technically all CDC is done from an AFTER_INSERT context
   * - an undelete behaves _strictly_ the same as an insert
   * because the underlying SObject can't be modified till afterwards
   */
  private static Boolean shouldRunFromTrigger() {
    shouldRun = Trigger.isExecuting || (shouldRun ?? false);
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
    if (apexContext == TriggerOperation.AFTER_UNDELETE) {
      apexContext = TriggerOperation.AFTER_INSERT;
    }
    return shouldRun;
  }

  private static List<SObject> getTriggerRecords() {
    return records ?? (Trigger.isDelete ? Trigger.old : Trigger.new).deepClone(true, true, true);
  }

  private static Map<Id, SObject> getOldTriggerRecordsMap() {
    return oldRecordsMap ?? Trigger.oldMap?.deepClone() ?? new Map<Id, SObject>();
  }

  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  private static void reparentAndGetMergedRecordIds(
    List<SObject> calcItems,
    List<Rollup__mdt> rollupMetadata,
    Set<String> mergedParentIds,
    RollupControl__mdt control
  ) {
    Schema.SObjectType itemType = calcItems.getSObjectType();
    if (
      itemType != Schema.Account.SObjectType &&
      itemType != Schema.Case.SObjectType &&
      itemType != Schema.Contact.SObjectType &&
      itemType != Schema.Lead.SObjectType
    ) {
      return;
    }
    String mergeFieldIndicator = 'MasterRecordId';
    Map<Id, Id> mergedIdToCurrentParentId = new Map<Id, Id>();
    String lookupObjectName;
    for (SObject record : calcItems) {
      if (record.get(mergeFieldIndicator) != null) {
        Id mergedFieldValue = (Id) record.get(mergeFieldIndicator);
        mergedIdToCurrentParentId.put(record.Id, mergedFieldValue);
        mergedParentIds.add(mergedFieldValue);
      }
      lookupObjectName = lookupObjectName ?? String.valueOf(record.getSObjectType());
    }

    if (mergedIdToCurrentParentId.isEmpty()) {
      return;
    }

    // only M/D relationships specifically set to reparent do so automatically
    // for everything else - there's rollup
    List<SObject> recordsToUpdate = new List<SObject>();
    Set<SObjectType> updatedChildTypes = new Set<SObjectType>();
    for (Rollup__mdt meta : rollupMetadata) {
      if (meta.LookupObject__c != lookupObjectName) {
        continue;
      }

      SObjectType calcItemSObject = RollupFieldInitializer.Current.getDescribeFromName(meta.CalcItem__c).getSObjectType();

      // SOQL in a for loop - with the caveat that it's once per child object of any given parent
      if (updatedChildTypes.contains(calcItemSObject) == false) {
        updatedChildTypes.add(calcItemSObject);

        List<SObject> recordsToReparent = new RollupRepository(RollupMetaPicklists.getAccessLevel(meta))
          .setQuery(
            RollupQueryBuilder.Current.getQuery(calcItemSObject, new List<String>{ 'Id', meta.LookupFieldOnCalcItem__c }, meta.LookupFieldOnCalcItem__c, '=')
          )
          .setArg(mergedIdToCurrentParentId.keySet())
          .get();
        for (SObject childToReparent : recordsToReparent) {
          childToReparent.put(meta.LookupFieldOnCalcItem__c, mergedIdToCurrentParentId.get((Id) childToReparent.get(meta.LookupFieldOnCalcItem__c)));
          recordsToUpdate.add(childToReparent);
        }
      }
    }
    performNonRecursiveUpdate(recordsToUpdate, control);
  }

  private static void performNonRecursiveUpdate(List<SObject> recordsToUpdate, RollupControl__mdt control) {
    // prevent downstream rollups from running on this code path; we are already in the midst
    // of calculating each of the record's new rollup values
    shouldRefreshCachedControl = true;
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
    processor.triggerContext = apexContext;
    processor.runAsMOde = RollupMetaPicklists.getAccessLevel(rollupMetadata);
    rollupConductor.runAsMode = processor.runAsMode;
    return addRollup(rollupConductor, processor);
  }

  private static Rollup addRollup(Rollup rollupConductor, Rollup processor) {
    if (processor.isNoOp == false) {
      rollupConductor.rollups.add((RollupAsyncProcessor) processor);
    }
    return rollupConductor;
  }

  private static RollupControl__mdt getSingleControlOrDefault(SObjectField whereField, Object whereValue, RollupControl__mdt testOverrideData) {
    // there are multiple spots where testOverrideData can be supplied, which is why it's necessary to pass the argument to this method
    if (testOverrideData != null) {
      return testOverrideData;
    } else if (whereValue != null && (whereField == RollupControl__mdt.Id || whereField == RollupControl__mdt.DeveloperName)) {
      String whereKey = (String) whereValue;
      RollupControl__mdt potentialControl = RollupControl__mdt.getInstance(whereKey);
      if (potentialControl != null) {
        return potentialControl.clone(true, true);
      }
    } else if (whereValue != null) {
      List<RollupControl__mdt> rollupControls = getMetadataFromCache(RollupControl__mdt.SObjectType);
      for (RollupControl__mdt rollupControl : rollupControls) {
        if (rollupControl.get(whereField) == whereValue) {
          return rollupControl;
        }
      }
    }

    return CACHED_DEFAULT ?? getSensibleControlDefault();
  }

  private static RollupControl__mdt getSensibleControlDefault() {
    if (defaultControl != null) {
      return defaultControl;
    } else if (cachedOrgDefault == null) {
      // hack for additional code coverage; use one of the TestVisible variables to test getting the below defaults instead
      RollupControl__mdt sensibleDefault = records != null ? null : RollupControl__mdt.getInstance(CONTROL_ORG_DEFAULTS);
      cachedOrgDefault = sensibleDefault?.clone(true, true) ?? getControlWithDefaultValues();
    }
    return cachedOrgDefault;
  }

  private static RollupControl__mdt getControlWithDefaultValues() {
    RollupControl__mdt sensibleDefault = new RollupControl__mdt(DeveloperName = CONTROL_ORG_DEFAULTS);
    for (Schema.SObjectField fieldToken : RollupControl__mdt.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
      if (fieldToken != RollupControl__mdt.DeveloperName && fieldToken != RollupControl__mdt.Id) {
        sensibleDefault.put(fieldToken, fieldToken.getDescribe().getDefaultValue());
      }
    }
    return sensibleDefault;
  }

  private static FilterResults filter(
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    Rollup__mdt metadata,
    SObjectType calcItemType,
    Boolean shouldFilterCalcItems
  ) {
    FilterResults results = new FilterResults();
    results.eval = RollupEvaluator.getEvaluator(eval, metadata, oldCalcItems, calcItemType);
    if (shouldFilterCalcItems == false) {
      results.matchingItemIds.addAll(new Map<Id, SObject>(calcItems).keySet());
      return results;
    }

    // for custom evaluators / where clauses / child object changed fields, etc ... mutating the initial "calcItems" passed in would
    // mean inadvertently filtering the items for other rollups on the same child SObject type. Instead, we track the matching Ids
    // to avoid unintended side-effects
    for (SObject item : calcItems) {
      if (
        metadata.IsRollupStartedFromParent__c == false &&
        item.get(metadata.LookupFieldOnCalcItem__c) == null &&
        oldCalcItems?.get(item.Id)?.get(metadata.LookupFieldOnCalcItem__c) == null
      ) {
        continue;
      } else if (results.eval.matches(item)) {
        results.matchingItemIds.add(item.Id);
      } else if (oldCalcItems?.containsKey(item.Id) == true && results.eval.matches(oldCalcItems.get(item.Id))) {
        // if the where clause would exclude something, but we're in an update
        // and the old value wouldn't have been excluded, pass it on through
        // to be handled further downstream
        results.matchingItemIds.add(item.Id);
      } else if (metadata.IsFullRecordSet__c == true) {
        results.matchingItemIds.add(item.Id);
      } else if (metadata.FullRecalculationDefaultNumberValue__c != null || metadata.FullRecalculationDefaultStringValue__c != null) {
        results.matchingItemIds.add(item.Id);
      }
    }
    return results;
  }

  private static void updateLoggingControl(List<Rollup__mdt> metadatas) {
    Id controlId;
    for (Rollup__mdt meta : metadatas) {
      if (controlId == null && meta.RollupControl__c != null && meta.RollupControl__c != CACHED_DEFAULT.Id) {
        controlId = meta.RollupControl__c;
      } else if (meta.RollupControl__c == CACHED_DEFAULT.Id) {
        controlId = null;
        break;
      }
    }
    if (controlId != null) {
      RollupControl__mdt possibleNewControl = getSingleControlOrDefault(RollupControl__mdt.Id, controlId, defaultControl);
      if (possibleNewControl != null) {
        CACHED_DEFAULT = possibleNewControl;
        RollupLogger.Instance.updateRollupControl(CACHED_DEFAULT);
      }
    }
  }
}
