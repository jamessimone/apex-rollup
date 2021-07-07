global without sharing virtual class Rollup {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @testVisible
  private static Boolean shouldRun = false;
  @testVisible
  private static TriggerOperation apexContext;
  @testVisible
  private static List<SObject> records;
  @testVisible
  private static Map<Id, SObject> oldRecordsMap;
  @testVisible
  private static List<Rollup__mdt> rollupMetadata;
  @testVisible
  private static RollupControl__mdt defaultControl;
  @testVisible
  private static RollupControl__mdt specificControl;
  @testVisible
  private static Integer maxQueryRowOverride;
  @testVisible
  private static final List<RollupAsyncProcessor> CACHED_ROLLUPS = new List<RollupAsyncProcessor>();

  private static Map<SObjectType, Set<TriggerOperation>> CACHED_APEX_OPERATIONS = new Map<SObjectType, Set<TriggerOperation>>();
  private static Boolean isCDC = false;
  private static Boolean isDeferralAllowed = true;
  private static final String CONTROL_ORG_DEFAULTS = 'Org_Defaults';
  private static final Set<String> ALWAYS_FULL_RECALC_OPS = new Set<String>{
    Op.FIRST.name(),
    Op.LAST.name(),
    Op.AVERAGE.name(),
    Op.CONCAT_DISTINCT.name(),
    Op.COUNT_DISTINCT.name()
  };

  protected final RollupControl__mdt rollupControl;
  protected final InvocationPoint invokePoint;
  protected final Boolean isBatched;
  protected final List<RollupAsyncProcessor> rollups = new List<RollupAsyncProcessor>();

  // non-final instance variables
  protected Boolean isFullRecalc = false;
  protected Boolean isNoOp;
  protected Boolean isCDCUpdate = false;

  /**
   * receiving an interface/subclass from a property get/set (from the book "The Art Of Unit Testing") is an old technique;
   * useful in limited contexts to get around the classic approach to dependency injection
   * (such as in this case, when constructor-based DI isn't possible).
   * It's more palatable in Apex than in many other languages, as a matter of fact -
   * this is because the @testVisible annotation enforces for us the override only being possible while testing
   */
  @testVisible
  private static DMLHelper DML {
    get {
      if (DML == null) {
        DML = new DMLHelper();
      }
      return DML;
    }
    set;
  }

  public static Map<String, Op> opNameToOp {
    get {
      if (opNameToOp == null) {
        opNameToOp = new Map<String, Op>();
        for (Op operation : Op.values()) {
          opNameToOp.put(operation.name(), operation);
        }
      }
      return opNameToOp;
    }
    set;
  }

  private static Map<String, InvocationPoint> invokeNameToInvokePoint {
    get {
      if (invokeNameToInvokePoint == null) {
        invokeNameToInvokePoint = new Map<String, InvocationPoint>();
        for (InvocationPoint invocation : InvocationPoint.values()) {
          invokeNameToInvokePoint.put(invocation.name(), invocation);
        }
      }
      return invokeNameToInvokePoint;
    }
    set;
  }

  public enum Op {
    SUM,
    UPDATE_SUM,
    DELETE_SUM,
    COUNT_DISTINCT,
    UPDATE_COUNT_DISTINCT,
    DELETE_COUNT_DISTINCT,
    COUNT,
    UPDATE_COUNT,
    DELETE_COUNT,
    MAX,
    UPDATE_MAX,
    DELETE_MAX,
    MIN,
    UPDATE_MIN,
    DELETE_MIN,
    CONCAT,
    UPDATE_CONCAT,
    DELETE_CONCAT,
    CONCAT_DISTINCT,
    UPDATE_CONCAT_DISTINCT,
    DELETE_CONCAT_DISTINCT,
    AVERAGE,
    UPDATE_AVERAGE,
    DELETE_AVERAGE,
    FIRST,
    UPDATE_FIRST,
    DELETE_FIRST,
    LAST,
    UPDATE_LAST,
    DELETE_LAST
  }

  private class FilterResults {
    public List<SObject> matchingItems { get; set; }
    public Evaluator eval { get; set; }
  }

  public class CalcItemBag {
    public CalcItemBag(List<SObject> originals) {
      this.originals = originals;
      this.additional = originals.clone(); // retain SObjectType info
      this.additional.clear();
    }
    public final List<SObject> originals;
    public final List<SObject> additional;
    public Boolean hasQueriedForAdditionalItems = false;
  }

  public virtual class DMLHelper {
    public virtual void doUpdate(List<SObject> recordsToUpdate) {
      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.AllowFieldTruncation = true;
      Database.update(recordsToUpdate, dmlOptions);
    }
  }

  global interface Evaluator {
    Boolean matches(Object calcItem);
  }

  global enum InvocationPoint {
    FROM_APEX,
    FROM_INVOCABLE,
    FROM_SCHEDULED,
    FROM_LWC,
    FROM_SINGULAR_PARENT_RECALC_LWC,
    FROM_STATIC_LOGGER
  }

  protected Rollup() {
  }

  protected Rollup(InvocationPoint invokePoint) {
    this.invokePoint = invokePoint;
    this.rollupControl = getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl);
  }

  protected List<RollupAsyncProcessor> getCachedRollups() {
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

  protected DMLHelper getDML() {
    return DML;
  }

  public virtual String runCalc() {
    return 'Not implemented';
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

  @AuraEnabled
  global static String performBulkFullRecalc(List<Rollup__mdt> matchingMetadata, String invokePointName) {
    InvocationPoint localInvokePoint = invokeNameToInvokePoint.get(invokePointName);

    Integer amountOfCalcItems = 0;
    Set<String> objIds = new Set<String>(); // will always be present as a bind var, below
    Set<Id> recordIds = new Set<Id>(); // always empty, here, but necessary for the "getCountFromDb" call
    SObjectType childType; // always the same for this route, so we can just take whatever the last assignment is
    Set<String> queryFields = new Set<String>();
    String potentialWhereClause = '';
    String delimiter = ' ||| ';

    for (Rollup__mdt matchingMeta : matchingMetadata) {
      if (localInvokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC && String.isBlank(potentialWhereClause)) {
        Integer delimiterIndex = matchingMeta.CalcItemWhereClause__c.indexOf(delimiter);
        potentialWhereClause = matchingMeta.CalcItemWhereClause__c.substring(delimiterIndex + delimiter.length(), matchingMeta.CalcItemWhereClause__c.length());
      }
      if (String.isNotBlank(matchingMeta.CalcItemWhereClause__c) && localInvokePoint == InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC) {
        matchingMeta.CalcItemWhereClause__c = matchingMeta.CalcItemWhereClause__c.substringBeforeLast(delimiter);
      }

      childType = getSObjectFromName(matchingMeta.CalcItem__c).getSObjectType();
      queryFields.addAll(getQueryFieldsFromMetadata(matchingMeta, RollupEvaluator.getWhereEval(matchingMeta.CalcItemWhereClause__c, childType)));

      if (amountOfCalcItems != RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
        String countQuery = RollupQueryBuilder.Current.getQuery(childType, new List<String>{ 'Count()' }, matchingMeta.LookupFieldOnLookupObject__c, '!=');
        Integer currentCount = getCountFromDb(countQuery, objIds, recordIds);
        if (currentCount == RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
          amountOfCalcItems = currentCount;
        } else {
          amountOfCalcItems += currentCount;
        }
      }
    }

    String queryString = RollupQueryBuilder.Current.getQuery(childType, new List<String>(queryFields), 'Id', '!=', potentialWhereClause);
    return buildFullRecalcRollup(matchingMetadata, amountOfCalcItems, queryString, objIds, recordIds, childType, null, localInvokePoint).runCalc();
  }

  @AuraEnabled
  global static String getBatchRollupStatus(String jobId) {
    return [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1]?.Status;
  }

  @AuraEnabled
  global static String performFullRecalculation(Rollup__mdt metadata) {
    FlowInput validationRuleWrapper = new FlowInput();
    validationRuleWrapper.rollupOperation = metadata.RollupOperation__c.toUpperCase();
    validationRuleWrapper.concatDelimiter = metadata.ConcatDelimiter__c;
    validationRuleWrapper.fullRecalculationDefaultStringValue = metadata.FullRecalculationDefaultStringValue__c;
    validationRuleWrapper.fullRecalculationDefaultNumberValue = metadata.FullRecalculationDefaultNumberValue__c;
    validationRuleWrapper.orderByFirstLast = metadata.OrderByFirstLast__c;
    enforceValidationRules(validationRuleWrapper);

    QueryWrapper wrapper = new QueryWrapper(metadata.LookupObject__c, metadata.LookupFieldOnLookupObject__c);
    wrapper.setQuery(metadata.CalcItemWhereClause__c);
    return getFullRecalcRollup(metadata, wrapper, InvocationPoint.FROM_LWC).runCalc();
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

    // optional fields
    @InvocableVariable(
      label='Calc Item Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;
    @InvocableVariable(label='Defer processing')
    global Boolean deferProcessing = false;

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
    @InvocableVariable(
      label='Is Full Record Set'
      description='If provided, does not try to abort rollup calculation early if no records match, and instead resets the rollup field value'
    )
    global Boolean isFullRecordSet;
    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(label='Order By (First/Last)' description='First/Last order by field')
    global String orderByFirstLast;

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
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;
    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;
  }

  global class FlowOutput {
    global FlowOutput() {
      this.isSuccess = true;
      this.Message = 'SUCCESS';
    }

    @InvocableVariable(label='Is Success' description='Was rollup enqueued successfully?')
    global Boolean isSuccess;
    @InvocableVariable(label='Status Message' description='"SUCCESS" when isSuccess is true, otherwise the encountered error message')
    global String message;
  }

  @InvocableMethod(
    category='Rollups'
    label='Perform rollup on records'
    description='Returns a single FlowOutput record with "SUCCESS" as the message if async rollup operation is enqueued successfully, and the encountered error otherwise'
  )
  global static List<FlowOutput> performRollup(List<FlowInput> flowInputs) {
    List<FlowOutput> flowOutputs = new List<FlowOutput>();
    List<RollupAsyncProcessor> localRollups = new List<RollupAsyncProcessor>();
    InvocationPoint fromInvocable = InvocationPoint.FROM_INVOCABLE;

    for (FlowInput flowInput : flowInputs) {
      FlowOutput flowOutput = new FlowOutput();
      flowOutputs.add(flowOutput);

      if (flowInput.recordsToRollup?.isEmpty() != false) {
        flowOutput.message = 'No records to rollup, returning early';
        continue;
      }
      SObject firstRecord = flowInput.recordsToRollup[0];
      // flow collections are not strongly typed, so we grab from the first record
      SObjectType sObjectType = firstRecord.getSObjectType();

      // this will throw back up to the Flow engine if the inputs don't pass validation
      enforceValidationRules(flowInput);
      enforceFlowSpecificRules(flowInput, sObjectType);

      flowInput.rollupOperation = flowInput.rollupOperation.toUpperCase();
      Map<Id, SObject> oldFlowRecords = getOldFlowRecords(flowInput, sObjectType);
      String rollupContext = getFlowRollupContext(flowInput, firstRecord, oldFlowRecords);

      Rollup__mdt rollupMeta = new Rollup__mdt(
        RollupFieldOnCalcItem__c = flowInput.rollupFieldOnCalcItem,
        LookupObject__c = flowInput.rollupSObjectName,
        LookupFieldOnCalcItem__c = flowInput.lookupFieldOnCalcItem,
        LookupFieldOnLookupObject__c = flowInput.lookupFieldOnOpObject,
        RollupFieldOnLookupObject__c = flowInput.rollupFieldOnOpObject,
        RollupOperation__c = rollupContext + flowInput.rollupOperation,
        ChangedFieldsOnCalcItem__c = flowInput.calcItemChangedFields,
        FullRecalculationDefaultNumberValue__c = flowInput.fullRecalculationDefaultNumberValue,
        FullRecalculationDefaultStringValue__c = flowInput.fullRecalculationDefaultStringValue,
        CalcItemWhereClause__c = flowInput.calcItemWhereClause,
        IsFullRecordSet__c = flowInput.isFullRecordSet,
        OrderByFirstLast__c = flowInput.orderByFirstLast,
        GrandparentRelationshipFieldPath__c = flowInput.grandparentRelationshipFieldPath,
        ConcatDelimiter__c = flowInput.concatDelimiter,
        UltimateParentLookup__c = flowInput.ultimateParentLookup,
        RollupToUltimateParent__c = flowInput.rollupToUltimateParent,
        CalcItem__c = flowInput.isRollupStartedFromParent || String.isNotBlank(flowInput.calcItemTypeWhenRollupStartedFromParent)
          ? flowInput.calcItemTypeWhenRollupStartedFromParent
          : String.valueOf(sObjectType),
        IsRollupStartedFromParent__c = flowInput.isRollupStartedFromParent
      );

      List<Rollup__mdt> metas = new List<Rollup__mdt>{ rollupMeta };
      processCustomMetadata(localRollups, metas, flowInput.recordsToRollup, oldFlowRecords, new Set<String>(), rollupContext, fromInvocable);

      if (metas.isEmpty() == false) {
        RollupAsyncProcessor batchedRollup = getRollup(
          new List<Rollup__mdt>{ rollupMeta },
          sObjectType,
          flowInput.recordsToRollup,
          oldFlowRecords,
          null,
          fromInvocable
        );
        String logMessage = 'adding invocable rollup to list';
        if (flowInput.deferProcessing) {
          logMessage = 'deferring processing for rollup';
          CACHED_ROLLUPS.addAll(batchedRollup.rollups);
        } else {
          localRollups.addAll(batchedRollup.rollups);
        }
        RollupLogger.Instance.log(logMessage, batchedRollup.rollups, LoggingLevel.DEBUG);
      }
    }

    try {
      if (localRollups.isEmpty() == false) {
        batch(localRollups, fromInvocable);
      }
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred during invocable action', ex, LoggingLevel.ERROR);
      for (FlowOutput flowOutput : flowOutputs) {
        flowOutput.IsSuccess = false;
        flowOutput.Message = ex.getMessage() + '\n' + ex.getStackTraceString();
      }
    }
    RollupLogger.Instance.save();
    RollupAsyncProcessor.flatten(CACHED_ROLLUPS);

    return flowOutputs;
  }

  global static Id schedule(String jobName, String cronExp, String query, String rollupObjectName, Evaluator eval) {
    RollupSchedulable scheduledRollup = new RollupSchedulable(query, rollupObjectName, eval);
    return System.schedule(jobName, cronExp, scheduledRollup);
  }

  global static void batch(Rollup rollup, Rollup secondRollup) {
    batch(new List<Rollup>{ rollup, secondRollup });
  }

  global static void batch(Rollup rollup, Rollup secondRollup, Rollup thirdRollup) {
    batch(new List<Rollup>{ rollup, secondRollup, thirdRollup });
  }

  global static void batch(List<Rollup> rollups) {
    batch(rollups, InvocationPoint.FROM_APEX);
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
    return operateFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT_DISTINCT,
      defaultRecalculationValue,
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
    return operateFromApex(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT,
      defaultRecalculationValue,
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
    return operateFromApex(
      firstFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      firstFieldOnOpObject,
      lookupSobjectType,
      Op.FIRST,
      defaultRecalculationValue,
      orderByFirstLast,
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
    return operateFromApex(
      lastFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      lastFieldOnOpObject,
      lookupSobjectType,
      Op.LAST,
      defaultRecalculationValue,
      orderByFirstLast,
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
    String orderByFirstLast,
    Evaluator eval
  ) {
    Rollup__mdt meta = new Rollup__mdt(
      RollupFieldOnCalcItem__c = operationFieldOnCalcItem.getDescribe().getName(),
      LookupObject__c = String.valueOf(lookupSObjectType),
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.getDescribe().getName(),
      LookupFieldOnLookupObject__c = lookupFieldOnOperationObject.getDescribe().getName(),
      RollupFieldOnLookupObject__c = operationFieldOnOperationObject.getDescribe().getName(),
      RollupOperation__c = rollupOperation.name(),
      OrderByFirstLast__c = orderByFirstLast
    );
    if (defaultRecalculationValue instanceof Decimal) {
      meta.FullRecalculationDefaultNumberValue__c = (Decimal) defaultRecalculationValue;
    } else if (defaultRecalculationValue instanceof String) {
      meta.FullRecalculationDefaultStringValue__c = (String) defaultRecalculationValue;
    }
    return runFromApex(new List<Rollup__mdt>{ meta }, eval, getTriggerRecords(), getOldTriggerRecordsMap());
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
    SObjectType sObjectType = getSObjectFromName(header.getEntityName()).getSObjectType();

    List<Rollup__mdt> matchingMetadata = getRollupMetadataBySObject(sObjectType);
    if (matchingMetadata.isEmpty()) {
      return;
    }

    Set<String> uniqueFieldNames = new Set<String>();
    for (Rollup__mdt rollupInfo : matchingMetadata) {
      uniqueFieldNames.addAll(getQueryFieldsFromMetadata(rollupInfo, RollupEvaluator.getWhereEval(rollupInfo.CalcItemWhereClause__c, sObjectType)));
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
      uniqueFieldNames.addAll(header.changedfields);
      objIds.add(header.getRecordIds()[0]);
    }

    String queryString = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(uniqueFieldNames), 'Id', '=');
    // getting the items back from the database before putting them into the map is an important step
    // we COULD just initialize the map with the query, but then the map's .values() list doesn't return
    // anything for .getSObjectType() - which we need, further downstream
    List<SObject> cdcCalcItems = Database.query(queryString);
    Map<Id, SObject> cdcCalcItemsMap = new Map<Id, SObject>(cdcCalcItems);

    Rollup rollupToReturn = runFromApex(rollupMetadata, null, cdcCalcItems, cdcCalcItemsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isCDCUpdate = apexContext == TriggerOperation.AFTER_UPDATE;
    // we're already async, so let's not waste any more time
    rollupToReturn.rollupControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.SYNCHRONOUS;
    rollupToReturn.runCalc();
  }

  global static void runFromTrigger() {
    List<SObject> triggerRecords = getTriggerRecords();
    List<Rollup__mdt> matchingMetadata = getRollupMetadataBySObject(triggerRecords.getSObjectType());
    runFromApex(matchingMetadata, null, triggerRecords, getOldTriggerRecordsMap()).runCalc();
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
    Rollup batchRollup = new RollupAsyncProcessor(InvocationPoint.FROM_APEX);
    if (shouldRunFromTrigger() == false) {
      return batchRollup;
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
        reparentAndGetMergedRecordIds(calcItems, rollupMetadata, mergedParentIds, batchRollup.rollupControl);
      }
      when else {
        shouldReturn = true;
      }
    }

    if (shouldReturn) {
      return batchRollup;
    }

    List<Rollup> localRollups = new List<Rollup>();
    processCustomMetadata(localRollups, rollupMetadata, calcItems, oldCalcItems, mergedParentIds, rollupContext, InvocationPoint.FROM_APEX);

    SObjectType calcItemSObjectType = calcItems.getSObjectType();
    populateCachedApexOperations(calcItemSObjectType, apexContext);

    if (rollupMetadata.isEmpty() == false) {
      localRollups.addAll(getRollup(rollupMetadata, calcItemSObjectType, calcItems, oldCalcItems, eval, InvocationPoint.FROM_APEX).rollups);
    }

    flattenBatches(batchRollup, localRollups);
    return batchRollup;
  }

  /** end global-facing section, begin public/private static helpers */

  public static void processStoredFlowRollups() {
    RollupLogger.Instance.log('processing deferred flow rollups', LoggingLevel.DEBUG);
    List<RollupAsyncProcessor> rollupsToProcess = new List<RollupAsyncProcessor>(CACHED_ROLLUPS);
    CACHED_ROLLUPS.clear();
    batch(rollupsToProcess, InvocationPoint.FROM_INVOCABLE);
  }

  private static List<Rollup__mdt> cachedMetadata;
  public static List<SObject> getMetadataFromCache(SObjectType metadataType) {
    List<SObject> matchingMetadata;
    // We need to clean up the Entity Definition / Field Definition
    // particles for custom objects and custom fields
    if (metadataType == Rollup__mdt.SObjectType) {
      if (cachedMetadata == null) {
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
            OrderByFirstLast__c,
            RollupControl__c,
            RollupOperation__c,
            RollupToUltimateParent__c
          FROM Rollup__mdt
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
      }
      if (rollupMetadata != null) {
        cachedMetadata.addAll(rollupMetadata);
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
    Boolean hasExceededLimits =
      control?.MaxNumberOfQueries__c < Limits.getQueries() ||
      control?.MaxLookupRowsBeforeBatching__c < Limits.getQueryRows() ||
      (Limits.getLimitHeapSize() / 2) < Limits.getHeapSize() ||
      control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();
    return hasExceededLimits && isDeferralAllowed;
  }

  public static String getBaseOperationName(String fullOpName) {
    Set<String> operationsWithUnderscores = new Set<String>{ Op.COUNT_DISTINCT.name(), Op.CONCAT_DISTINCT.name() };
    return operationsWithUnderscores.contains(fullOpName) == false && fullOpName.contains('_') ? fullOpName.substringAfter('_') : fullOpName;
  }

  private static void processCustomMetadata(
    List<Rollup> rollups,
    List<Rollup__mdt> metas,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Set<String> mergedParentIds,
    String rollupContext,
    InvocationPoint invokePoint
  ) {
    SObjectType calcItemSObjectType = calcItems.getSObjectType();
    for (Integer index = metas.size() - 1; index >= 0; index--) {
      Rollup__mdt meta = metas[index];
      Boolean isIntermediateRollupForGrandparent =
        meta.CalcItem__c != String.valueOf(calcItemSObjectType) &&
        String.isNotBlank(meta.GrandparentRelationshipFieldPath__c) &&
        calcItems.isEmpty() == false &&
        meta.IsRollupStartedFromParent__c == false &&
        meta.LookupObject__c != String.valueOf(calcItemSObjectType);

      if (String.isBlank(meta.CalcItem__c)) {
        meta.CalcItem__c = String.valueOf(calcItemSObjectType);
      }

      if (meta.IsRollupStartedFromParent__c || isIntermediateRollupForGrandparent) {
        QueryWrapper queryWrapper = isIntermediateRollupForGrandparent == false
          ? getParentWhereClause(
              calcItems,
              meta.LookupFieldOnLookupObject__c,
              meta.LookupObject__c,
              meta.LookupFieldOnCalcItem__c,
              meta.GrandparentRelationshipFieldPath__c,
              meta.CalcItemWhereClause__c
            )
          : getIntermediateGrandparentQueryWrapper(meta.GrandparentRelationshipFieldPath__c, calcItems, oldCalcItems);
        if (meta.IsRollupStartedFromParent__c || isIntermediateRollupForGrandparent && (queryWrapper.hasQuery || isCDC)) {
          metas.remove(index);
          rollups.add(getFullRecalcRollup(meta, queryWrapper, invokePoint));
          continue;
        }
      } else if (apexContext == TriggerOperation.AFTER_DELETE) {
        if (mergedParentIds.isEmpty() == false) {
          QueryWrapper wrapper = new QueryWrapper('', meta.LookupFieldOnCalcItem__c);
          for (String mergedParentId : mergedParentIds) {
            wrapper.addRecordId(mergedParentId);
          }
          if (String.isNotBlank(meta.CalcItemWhereClause__c)) {
            wrapper.setQuery(meta.CalcItemWhereClause__c + ' AND ' + wrapper.getQuery());
          }
          rollups.add(getFullRecalcRollup(meta, wrapper, invokePoint));
        }
        metas.remove(index);
        continue;
      }

      // if the same items get run through different rollup operations in the same transaction (rare, but not impossible ...)
      // we need to reset the CMDT to the correct base operation prior to appending the new context
      meta.RollupOperation__c =
        rollupContext +
        (meta.RollupOperation__c.contains('UPDATE_') || meta.RollupOperation__c.contains('DELETE_')
          ? meta.RollupOperation__c.substringAfter('_')
          : meta.RollupOperation__c);
    }
  }

  private static Set<String> getQueryFieldsFromMetadata(Rollup__mdt meta, RollupEvaluator.WhereFieldEvaluator eval) {
    Set<String> queryFields = new Set<String>{ 'Id', meta.RollupFieldOnCalcItem__c, meta.LookupFieldOnCalcItem__c, meta.OrderByFirstLast__c };
    queryFields.addAll(eval.getQueryFields());
    return queryFields;
  }

  private static String getFullRecalcQueryString(List<Rollup__mdt> metas) {
    List<String> orderByFields = new List<String>();
    for (Rollup__mdt meta : metas) {
      orderByFields.add(meta.LookupFieldOnCalcItem__c);
    }
    return '\nORDER BY ' + String.join(orderByFields, ',');
  }

  private static RollupAsyncProcessor getFullRecalcRollup(Rollup__mdt meta, QueryWrapper queryWrapper, InvocationPoint invokePoint) {
    // just how many items are we talking, here? If it's less than the query limit, we can proceed
    // otherwise, kick off a batch to fetch the calc items and then chain into the regular code path
    SObjectType childType = getSObjectFromName(meta.CalcItem__c).getSObjectType();
    String countQuery = RollupQueryBuilder.Current.getQuery(
      childType,
      new List<String>{ 'Count()' },
      meta.LookupFieldOnLookupObject__c,
      '!=',
      queryWrapper.getQuery()
    );

    Set<String> objIds = new Set<String>(); // get everything that doesn't have a null Id - a pretty trick
    Set<Id> recordIds = queryWrapper.recordIds;
    Integer amountOfCalcItems = getCountFromDb(countQuery, objIds, recordIds);

    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(queryWrapper.toString(), childType);
    Set<String> queryFields = getQueryFieldsFromMetadata(meta, whereEval);
    String queryString = RollupQueryBuilder.Current.getQuery(childType, new List<String>(queryFields), 'Id', '!=', queryWrapper.getQuery());

    return buildFullRecalcRollup(new List<Rollup__mdt>{ meta }, amountOfCalcItems, queryString, objIds, recordIds, childType, whereEval, invokePoint);
  }

  private static RollupAsyncProcessor buildFullRecalcRollup(
    List<Rollup__mdt> matchingMeta,
    Integer amountOfCalcItems,
    String queryString,
    Set<String> objIds,
    Set<Id> recordIds,
    SObjectType calcItemType,
    Evaluator eval,
    InvocationPoint invokePoint
  ) {
    for (Rollup__mdt meta : matchingMeta) {
      meta.IsFullRecordSet__c = true;
    }
    RollupAsyncProcessor instance = new RollupAsyncProcessor(invokePoint);
    Boolean shouldQueue =
      amountOfCalcItems != RollupQueryBuilder.SENTINEL_COUNT_VALUE &&
      amountOfCalcItems < instance.rollupControl.MaxLookupRowsBeforeBatching__c;
    if (shouldQueue) {
      List<SObject> calculationItems = Database.query(queryString);
      RollupAsyncProcessor thisRollup = getRollup(matchingMeta, calcItemType, calculationItems, new Map<Id, SObject>(calculationItems), eval, invokePoint);
      thisRollup.isFullRecalc = true;
      return thisRollup;
    } else {
      String queryWithOrderBy = queryString + getFullRecalcQueryString(matchingMeta);
      return new RollupFullBatchRecalculator(queryString, invokePoint, matchingMeta, calcItemType, recordIds);
    }
  }

  private static void batch(List<Rollup> rollups, InvocationPoint invokePoint) {
    Rollup batchRollup = new RollupAsyncProcessor(invokePoint);
    flattenBatches(batchRollup, rollups);
    batchRollup.runCalc();
  }

  private static void flattenBatches(Rollup outerRollup, List<Rollup> rollups) {
    for (Rollup rollup : rollups) {
      if (rollup.rollups.isEmpty() == false) {
        for (Rollup innerRoll : rollup.rollups) {
          innerRoll.isFullRecalc = rollup.isFullRecalc;
        }
        // recurse through lists until there aren't any more nested rollups
        flattenBatches(outerRollup, rollup.rollups);
      } else {
        loadRollups(rollup, outerRollup);
      }
    }
  }

  private static void enforceValidationRules(FlowInput flowInput) {
    String errorMessage;
    if (
      (flowInput.rollupOperation == 'FIRST' ||
      flowInput.rollupOperation == 'LAST') &&
      String.isBlank(flowInput.orderByFirstLast) &&
      String.isBlank(flowInput.rollupFieldOnCalcItem)
    ) {
      errorMessage = 'Order By First/Last field required for ' + flowInput.rollupOperation + ' operation';
    } else if (
      (flowInput.rollupToUltimateParent && String.isBlank(flowInput.ultimateParentLookup)) ||
      (String.isNotBlank(flowInput.ultimateParentLookup) && flowInput.rollupToUltimateParent == false)
    ) {
      errorMessage = 'Rollup To Ultimate Parent and Ultimate Parent Lookup must both be set for hierarchical rollups';
    } else if (flowInput.rollupOperation.contains(Op.CONCAT.name()) == false && String.isNotBlank(flowInput.concatDelimiter)) {
      errorMessage = 'Concat delimiter should only be supplied for CONCAT-based rollups';
    } else if (String.isNotBlank(flowInput.fullRecalculationDefaultStringValue) && flowInput.fullRecalculationDefaultNumberValue != null) {
      errorMessage = 'Only one override - the default string value or number value - can be supplied for each rollup';
    }

    if (String.isNotBlank(errorMessage)) {
      Exception ex = new IllegalArgumentException(errorMessage);
      RollupLogger.Instance.log('an error occurred while validating flow inputs', ex, LoggingLevel.ERROR);
      RollupLogger.Instance.save();
      throw ex;
    }
  }

  private static void enforceFlowSpecificRules(FlowInput flowInput, SObjectType sObjectType) {
    try {
      if ((flowInput.rollupContext == 'UPDATE' || flowInput.rollupContext == 'UPSERT') && flowInput.oldRecordsToRollup?.isEmpty() == true) {
        throw new IllegalArgumentException('Prior records to rollup collection required for rollup context: ' + flowInput.rollupContext);
      } else if (String.isBlank(flowInput.grandparentRelationshipFieldPath)) {
        SObject firstRecord = flowInput.recordsToRollup[0];
        SObject lookupItem = getSObjectFromName(
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
      RollupLogger.Instance.log('an error occurred while validating flow-specific rules', ex, LoggingLevel.ERROR);
      RollupLogger.Instance.save();
      throw ex;
    }
  }

  private static QueryWrapper getIntermediateGrandparentQueryWrapper(String grandparentFieldPath, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    if (isCDC) {
      return new QueryWrapper();
    }

    SObjectType sObjectType = calcItems[0].getSObjectType();
    SObjectField fieldToken = getPartOfGrandparentChain(grandparentFieldPath, sObjectType);
    String relationshipName = fieldToken.getDescribe().getRelationshipName();
    Integer relationshipIndex = grandparentFieldPath.indexOf(relationshipName) + relationshipName.length();
    String priorFieldPath = grandparentFieldPath.substring(0, relationshipIndex) + '.Id';
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
    private QueryWrapper() {
    }
    private QueryWrapper(String lookupObject, String lookupField) {
      String base = String.isBlank(lookupObject) ? '' : lookupObject.replace('__c', '__r') + '.';
      this.query = base + lookupField + ' = :recordIds';
    }

    private Boolean hasQuery = false;
    private String query;
    public final Set<Id> recordIds = new Set<Id>();
    private final List<String> stringifiedRecordIds = new List<String>();

    public void addRecordId(String recordId) {
      if (String.isNotBlank(recordId)) {
        this.hasQuery = true;
        if (this.recordIds.contains(recordId) == false) {
          this.recordIds.add(recordId);
          this.stringifiedRecordIds.add('\'' + recordId + '\'');
        }
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
      return this.hasQuery ? this.query.replace('= :recordIds', 'IN (' + String.join(this.stringifiedRecordIds, ',') + ')') : '';
    }
  }

  private static QueryWrapper getParentWhereClause(
    List<SObject> calcItems,
    String lookupFieldOnLookupObject,
    String lookupObjectName,
    String lookupFieldOnCalcItem,
    String grandparentFieldPath,
    String potentialWhereClause
  ) {
    String fieldName = lookupFieldOnLookupObject;
    if (String.isNotBlank(grandparentFieldPath)) {
      lookupObjectName = '';
      fieldName = grandparentFieldPath.substringBeforeLast('.') + '.Id';
    } else if (lookupFieldOnCalcItem.endsWith('Id') || lookupFieldOnCalcItem.endsWith('__c')) {
      lookupObjectName = '';
      fieldName = lookupFieldOnCalcItem;
    }

    QueryWrapper wrapper = new QueryWrapper(lookupObjectName, fieldName);
    for (SObject calcItem : calcItems) {
      String lookupId = (String) calcItem.get(lookupFieldOnLookupObject);
      if (String.isNotBlank(lookupId)) {
        wrapper.addRecordId(lookupId);
      }
    }
    String whereClause = String.isNotBlank(potentialWhereClause) ? potentialWhereClause + ' AND ' : '';
    wrapper.setQuery(whereClause + wrapper.getQuery());
    return wrapper;
  }

  public static Integer getCountFromDb(String countQuery, Set<String> objIds) {
    return getCountFromDb(countQuery, objIds, null);
  }

  public static Integer getCountFromDb(String countQuery, Set<String> objIds, Set<Id> recordIds) {
    if (countQuery.contains('ALL ROWS')) {
      countQuery = countQuery.replace('ALL ROWS', '');
    }

    try {
      return Database.countQuery(countQuery);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query:\n' + countQuery, ex, LoggingLevel.WARN);
      // not all queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      return RollupQueryBuilder.SENTINEL_COUNT_VALUE;
    }
  }

  private static String getFlowRollupContext(FlowInput firstInput, SObject firstRecord, Map<Id, SObject> oldFlowRecords) {
    String flowContext = firstInput.rollupContext.toUpperCase();
    if (String.isBlank(flowContext) || flowContext == 'UPSERT' && oldFlowRecords.containsKey(firstRecord.Id) == false) {
      flowContext = 'INSERT';
    } else if (flowContext == 'UPSERT') {
      flowContext = 'UPDATE';
    }

    TriggerOperation matchingOperation;
    switch on flowContext {
      when 'INSERT' {
        matchingOperation = TriggerOperation.AFTER_INSERT;
      }
      when 'UPDATE' {
        matchingOperation = TriggerOperation.AFTER_UPDATE;
      }
      when 'DELETE' {
        matchingOperation = TriggerOperation.BEFORE_DELETE;
      }
    }
    populateCachedApexOperations(firstRecord.getSObjectType(), matchingOperation);

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static Map<Id, SObject> getOldFlowRecords(FlowInput flowInput, SObjectType sObjectType) {
    Map<Id, SObject> oldFlowRecords = new Map<Id, SObject>();
    if (flowInput.recordsToRollup?.isEmpty() == true || (flowInput.rollupContext != 'UPDATE' && flowInput.rollupContext != 'UPSERT')) {
      return oldFlowRecords;
    } else if (flowInput.oldRecordsToRollup?.isEmpty() == false) {
      // normally, you could use a shortcut to initialize a Set<Id> like this
      // by calling new Map<Id, SObject>(oldRecordsToRollup).keyset() -
      // but that code path fails if there are null Ids in the list
      for (SObject oldRecord : flowInput.oldRecordsToRollup) {
        // record-triggered flows set up to run when "A record is created or modified"
        // will pass null in the list if it runs on create - yikes.
        if (oldRecord?.Id != null) {
          oldFlowRecords.put(oldRecord.Id, oldRecord);
        }
      }
    }

    return oldFlowRecords;
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
        if (getPartOfGrandparentChain(meta.GrandparentRelationshipFieldPath__c, sObjectType) != null) {
          continue;
        }
      } else if (Trigger.operationType == TriggerOperation.AFTER_DELETE && sObjectName == meta.LookupObject__c) {
        continue;
      } else if (meta.CalcItem__c != sObjectName && meta.IsRollupStartedFromParent__c == false) {
        rollupMetadatas.remove(index);
      } else if (meta.IsRollupStartedFromParent__c && sObjectName != meta.LookupObject__c) {
        rollupMetadatas.remove(index);
      }
    }
    return rollupMetadatas;
  }

  private static SObjectField getPartOfGrandparentChain(String grandParentFieldPath, SObjectType sObjectType) {
    List<String> validRelationshipNames = grandParentFieldPath.split('\\.');
    // remove the last field since it's not a relationship
    validRelationshipNames.remove(validRelationShipNames.size() - 1);
    DescribeSObjectResult describeObject = sObjectType.getDescribe();
    List<SObjectField> fieldTokens = describeObject.fields.getMap().values();
    for (SObjectField fieldToken : fieldTokens) {
      if (validRelationshipNames.contains(fieldToken.getDescribe().getRelationshipName())) {
        return fieldToken;
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
    if (rollupOperations.isEmpty() || calcItems.isEmpty()) {
      return new RollupAsyncProcessor(rollupInvokePoint);
    }
    if (sObjectType == null) {
      sObjectType = calcItems[0].getSObjectType();
    }
    /**
     * We have rollup operations to perform. That's great!
     * Let's get ready to rollup!
     */
    RollupAsyncProcessor batchRollup = new RollupAsyncProcessor(rollupInvokePoint);
    DescribeSObjectResult describeForSObject = sObjectType.getDescribe();
    Map<String, SObjectField> fieldNameToField = describeForSObject.fields.getMap();

    for (Rollup__mdt rollupMetadata : rollupOperations) {
      Op rollupOp = opNameToOp.get(rollupMetadata.RollupOperation__c.toUpperCase());
      SObjectField rollupFieldOnCalcItem = getSObjectFieldByName(describeForSObject, rollupMetadata.RollupFieldOnCalcItem__c);
      SObjectField calcLookupField = getSObjectFieldByName(describeForSObject, rollupMetadata.LookupFieldOnCalcItem__c);

      // NB - this SHOULD work even for SObjects part of managed packages
      SObjectType lookupSObjectType = getSObjectFromName(rollupMetadata.LookupObject__c).getSObjectType();
      DescribeSObjectResult lookupObjectDescribe = lookupSObjectType.getDescribe();
      Map<String, SObjectField> lookupFieldNameToLookupFields = lookupObjectDescribe.fields.getMap();
      SObjectField lookupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.LookupFieldOnLookupObject__c);
      SObjectField rollupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.RollupFieldOnLookupObject__c);

      // reset the CMDT field-level definitions using the SObjectField tokens
      rollupMetadata.RollupFieldOnCalcItem__c = rollupFieldOnCalcItem.getDescribe().getName();
      rollupMetadata.LookupFieldOnCalcItem__c = calcLookupField.getDescribe().getName();
      rollupMetadata.LookupFieldOnLookupObject__c = lookupFieldOnOpObject.getDescribe().getName();
      rollupMetadata.RollupFieldOnLookupObject__c = rollupFieldOnOpObject.getDescribe().getName();

      if (rollupMetadata.IsFullRecordSet__c != true && ALWAYS_FULL_RECALC_OPS.contains(getBaseOperationName(rollupMetadata.RollupOperation__c))) {
        rollupMetadata.IsFullRecordSet__c = true;
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

      FilterResults filterResults = filter(calcItems, oldCalcItems, eval, rollupMetadata, sObjectType);

      loadRollups(
        rollupFieldOnCalcItem,
        calcLookupField,
        lookupFieldOnOpObject,
        rollupFieldOnOpObject,
        lookupSObjectType,
        sObjectType, // calc item SObjectType
        rollupOp,
        filterResults.matchingItems,
        oldCalcItems,
        batchRollup,
        filterResults.eval,
        localControl,
        rollupInvokePoint,
        rollupMetadata
      );
    }
    return batchRollup;
  }

  private static SObjectField getSObjectFieldByName(DescribeSObjectResult objectDescribe, String desiredField) {
    Map<String, SObjectField> fieldNameToField = objectDescribe.fields.getMap();
    if (fieldNameToField.containsKey(desiredField)) {
      return fieldNameToField.get(desiredField);
    } else if (fieldNameToField.containsKey(desiredField + 'Id')) {
      // for lookup fields, CMDT field-level definition fields store the field name, which is outrageous
      return fieldNameToField.get(desiredField + 'Id');
    }

    return null;
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
      control.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.SYNCHRONOUS;
    }
  }

  private static Boolean shouldRunFromTrigger() {
    shouldRun = shouldRun || Trigger.isExecuting;
    // in order to accomodate CDC; we set the apexContext manually there
    // since technically all CDC is done from an AFTER_INSERT context
    if (Trigger.operationType != null && isCDC == false) {
      apexContext = Trigger.operationType;
    }
    Set<TriggerOperation> validTriggerOps = new Set<TriggerOperation>{
      TriggerOperation.AFTER_INSERT,
      TriggerOperation.AFTER_UPDATE,
      TriggerOperation.BEFORE_DELETE,
      TriggerOperation.AFTER_DELETE,
      TriggerOperation.AFTER_UNDELETE
    };
    if (shouldRun && validTriggerOps.contains(apexContext) == false) {
      shouldRun = false;
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

    return Trigger.isDelete ? Trigger.old : Trigger.new;
  }

  private static Map<Id, SObject> getOldTriggerRecordsMap() {
    if (oldRecordsMap != null) {
      return oldRecordsMap;
    } else if (Trigger.oldMap != null) {
      return Trigger.oldMap;
    }

    return new Map<Id, SObject>();
  }

  private static SObject getSObjectFromName(String sObjectName) {
    return ((SObject) Type.forName(sObjectName).newInstance());
  }

  private static void reparentAndGetMergedRecordIds(
    List<SObject> calcItems,
    List<Rollup__mdt> rollupMetadata,
    Set<String> mergedParentIds,
    RollupControl__mdt control
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
      return;
    }

    // only M/D relationships specifically set to reparent do so automatically
    // for everything else - there's rollup
    List<SObject> recordsToUpdate = new List<SObject>();
    Set<SObjectType> updatedChildTypes = new Set<SObjectType>();
    for (Rollup__mdt meta : rollupMetadata) {
      if (meta.LookupObject__c != String.valueOf(calcItems.getSObjectType())) {
        continue;
      }

      SObjectType calcItemSObject = getSObjectFromName(meta.CalcItem__c).getSObjectType();

      // SOQL in a for loop - with the caveat that it's once per child object of any given parent
      if (updatedChildTypes.contains(calcItemSObject) == false) {
        updatedChildTypes.add(calcItemSObject);

        List<SObject> recordsToReparent = Database.query(
          RollupQueryBuilder.Current.getQuery(calcItemSObject, new List<String>{ 'Id', meta.LookupFieldOnCalcItem__c }, meta.LookupFieldOnCalcItem__c, '=')
        );

        for (SObject childToReparent : recordsToReparent) {
          childToReparent.put(meta.LookupFieldOnCalcItem__c, mergedIdToCurrentParentId.get((Id) childToReparent.get(meta.LookupFieldOnCalcItem__c)));
          recordsToUpdate.add(childToReparent);
        }
      }
    }
    // prevent downstream rollups from running on this code path; we are already in the midst
    // of calculating each of the parent record's new rollup values
    RollupControl__mdt earlyExitControl = new RollupControl__mdt(ShouldAbortRun__c = true);
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
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Rollup batchRollup,
    Evaluator eval,
    RollupControl__mdt rollupControl,
    InvocationPoint invokePoint,
    Rollup__mdt rollupMetadata
  ) {
    Rollup rollup = RollupAsyncProcessor.getProcessor(
      calcItems,
      rollupFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOpObject,
      rollupFieldOnOpObject,
      lookupSObjectType,
      calcItemSObjectType,
      rollupOp,
      oldCalcItems,
      eval,
      invokePoint,
      rollupControl,
      rollupMetadata
    );
    return loadRollups(rollup, batchRollup);
  }

  private static Rollup loadRollups(Rollup rollup, Rollup batchRollup) {
    RollupAsyncProcessor processor = (RollupAsyncProcessor) rollup;
    if (batchRollup != null && rollup != null && rollup.isNoOp == false) {
      batchRollup.rollups.add(processor);
    } else if (rollup != null && rollup.isNoOp == false) {
      rollup.rollups.add(processor);
    }
    return batchRollup != null ? batchRollup : rollup;
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

  private static RollupControl__mdt cachedOrgDefault;
  private static RollupControl__mdt getSensibleControlDefault() {
    if (defaultControl != null) {
      return defaultControl;
    } else if (cachedOrgDefault == null) {
      // hack for additional code coverage; use one of the testVisible variables to test getting the below defaults instead
      RollupControl__mdt sensibleDefault = records != null ? null : RollupControl__mdt.getInstance(CONTROL_ORG_DEFAULTS);
      if (sensibleDefault == null) {
        // this *should* be impossible, since the record is included on install, but ...
        sensibleDefault = new RollupControl__mdt(
          DeveloperName = CONTROL_ORG_DEFAULTS,
          BatchChunkSize__c = 2000,
          MaxLookupRowsBeforeBatching__c = Limits.getLimitQueryRows() / 3,
          MaxParentRowsUpdatedAtOnce__c = Limits.getLimitDmlRows() / 2,
          MaxRollupRetries__c = 100,
          MaxNumberOfQueries__c = Limits.getLimitQueries() / 2,
          ShouldAbortRun__c = false,
          ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.QUEUEABLE
        );
      } else {
        sensibleDefault = sensibleDefault.clone(true, true);
      }
      cachedOrgDefault = sensibleDefault;
    }
    return cachedOrgDefault;
  }

  private static FilterResults filter(List<SObject> calcItems, Map<Id, SObject> oldCalcItems, Evaluator eval, Rollup__mdt metadata, SObjectType calcItemType) {
    FilterResults results = new FilterResults();
    List<SObject> matchingItems = calcItems == null ? new List<SObject>() : calcItems.clone();
    results.matchingItems = matchingItems;
    if (matchingItems.isEmpty()) {
      return results;
    }
    matchingItems.clear(); // retains the strong-typing on the list for downstream calls to List.getSbjectType()
    calcItems = replaceCalcItemsForPolymorphicWhereClause(calcItems, metadata);

    results.eval = RollupEvaluator.getEvaluator(eval, metadata, oldCalcItems, calcItemType);

    // while we iterate through calcItems, the only possible mutation to that array is through "replaceCalcItemsForPolymorphicWhereClause"
    // otherwise, for custom evaluators / where clauses / calc item changed fields, etc ... mutating the initial "calcItems" passed in would
    // mean inadvertently filtering the items for other rollups on the same child SObject type. For this reason, we use the cloned "matchingItems"
    // list to avoid unintended side-effects
    for (SObject item : calcItems) {
      // if the where clause would exclude something, but we're in an update
      // and the old value wouldn't have been excluded, pass it on through
      // to be handled further downstream
      SObject potentialOldItem = oldCalcItems?.isEmpty() == false && oldCalcItems.containsKey(item.Id) ? oldCalcItems.get(item.Id) : item;
      if (results.eval.matches(item) || results.eval.matches(potentialOldItem)) {
        matchingItems.add(item);
        // metadata shouldn't be null, but it's good to check; unfortunately, if(null) throws so we
        // have to do this EXTRA explicit check
      } else if (metadata?.IsFullRecordSet__c == true) {
        matchingItems.add(item);
      }
    }
    return results;
  }

  private static List<SObject> replaceCalcItemsForPolymorphicWhereClause(List<SObject> calcItems, Rollup__mdt metadata) {
    final String typeField = '.Type';
    final String owner = 'Owner.';

    // first we check to see if there is a calc item where clause, and that it contains any of the common polymorphic fields
    SObject firstItem = calcItems[0];
    if (String.isBlank(metadata?.CalcItemWhereClause__c)) {
      return calcItems;
    }
    Boolean hasOwnerClause = metadata.CalcItemWhereClause__c.contains(owner);
    Boolean hasTypeClause = metadata.CalcItemWhereClause__c.contains(typeField);
    SObjectType sObjectType = firstItem.getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
    Boolean hasPolyMorphicFields = hasOwnerClause || hasTypeClause || fieldMap.get(metadata.LookupFieldOnCalcItem__c)?.getDescribe().isNamePointing() == true;

    if (hasPolyMorphicFields) {
      if (hasTypeClause == false && hasOwnerClause == false) {
        return calcItems;
      }

      // the calc item where clause contains at least one polymorphic field, but before re-querying we validate whether or not the fields are already provided
      Map<String, Object> populatedFields = firstItem.getPopulatedFieldsAsMap();
      Set<String> additionalQueryFields = new Set<String>();
      List<String> optionalWhereClauses = new List<String>();

      processWhereClauseForDownstreamEvals(optionalWhereClauses, additionalQueryFields, sObjectType, typeField, owner, metadata);

      // we have to manually iterate through these fields because the "fieldMap" keySet is all in lowercase because it's ... special
      // and only responds properly to proper-cased fields when you call the map "containsKey" method - if the field names in the keySet were
      // proper-cased, we could just call additionalQueryFields.addAll(populatedFields.keySet().removeAll(fieldMap.keySet())) - alas
      // this awesome one-liner doesn't work for us
      for (String fieldName : populatedFields.keySet()) {
        if (fieldMap.containsKey(fieldName)) {
          additionalQueryFields.add(fieldName);
        }
      }

      String queryString = RollupQueryBuilder.Current.getQuery(
        sObjectType,
        new List<String>(additionalQueryFields),
        'Id',
        '=',
        String.join(optionalWhereClauses, ' AND ')
      );
      List<String> objIds = new List<String>();
      for (SObject record : calcItems) {
        if (String.isNotBlank(record.Id)) {
          objIds.add(record.Id);
        }
      }
      calcItems = Database.query(queryString);
    }
    return calcItems;
  }

  private static void processWhereClauseForDownstreamEvals(
    List<String> optionalWhereClauses,
    Set<String> additionalQueryFields,
    SObjectType sObjectType,
    String typeField,
    String owner,
    Rollup__mdt metadata
  ) {
    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(metadata.CalcItemWhereClause__c, sObjectType);
    for (String whereClause : whereEval.getWhereClauses()) {
      if (whereClause.contains(typeField) || whereClause.contains(owner)) {
        List<String> splitWheres = whereClause.split(' ');
        if (splitWheres.size() > 0) {
          additionalQueryFields.add(splitWheres[0]);
        }
        // "consume" the metadata where clause for downstream evaluators
        metadata.CalcItemWhereClause__c = metadata.CalcItemWhereClause__c.replace(whereClause, '');
        optionalWhereClauses.add(whereClause);
      }
    }
  }

  private class RollupSchedulable implements System.Schedulable {
    private final String query;
    private final SObjectType rollupObject;
    private final Evaluator eval;

    public RollupSchedulable(String query, String rollupObjectName, Evaluator eval) {
      this.query = query;
      this.rollupObject = getSObjectFromName(rollupObjectName).getSObjectType();
      this.eval = eval;
      try {
        Database.query(this.query);
      } catch (QueryException ex) {
        throw new QueryException('There\'s a problem with your query: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
      }
    }

    public void execute(SchedulableContext sc) {
      List<Rollup__mdt> metadata = getRollupMetadataBySObject(this.rollupObject);
      List<SObject> calcItems = Database.query(this.query);
      getRollup(metadata, calcItems.getSObjectType(), calcItems, new Map<Id, SObject>(calcItems), this.eval, InvocationPoint.FROM_SCHEDULED).runCalc();
    }
  }
}
