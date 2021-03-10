global without sharing virtual class Rollup implements Database.Batchable<SObject> {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @testVisible
  private static Boolean shouldRun = false;
  @testVisible
  private static Boolean shouldRunAsBatch = false;
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
  // in this case, we promote the visiblity of this variable for tests
  // specially to validate that the buffer is flushed when "processStoredFlowRollups" is called
  @testVisible
  private static List<Rollup> FLOW_ROLLUPS = new List<Rollup>();

  private static Boolean isCDC = false;
  private static Boolean isDeferralAllowed = true;
  private static Integer stackDepth = 0;
  private static final String CONTROL_ORG_DEFAULTS = 'Org_Defaults';

  private final List<SObject> calcItems;
  private final Map<Id, SObject> oldCalcItems;
  private final SObjectField opFieldOnCalcItem;
  private final SObjectField lookupFieldOnCalcItem;
  private final SObjectField lookupFieldOnLookupObject;
  private final SObjectField opFieldOnLookupObject;
  private final SObjectType lookupObj;
  private final Op op;
  private final Evaluator eval;
  private final Boolean isBatched;
  private final Id rollupControlId;
  private final Rollup__mdt metadata;

  protected final RollupInvocationPoint invokePoint;

  // non-final instance variables
  private Boolean isFullRecalc = false;
  private Boolean isCDCUpdate = false;
  private Boolean isNoOp;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private List<SObject> lookupItems;
  private RollupControl__mdt rollupControl;

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

  private List<Rollup> syncRollups {
    get {
      if (syncRollups == null) {
        syncRollups = new List<Rollup>();
      }
      return syncRollups;
    }
    set;
  }

  private List<Rollup> rollups {
    get {
      if (rollups == null) {
        rollups = new List<Rollup>();
      }
      return rollups;
    }
    set;
  }

  private List<Rollup> deferredRollups {
    get {
      if (deferredRollups == null) {
        deferredRollups = new List<Rollup>();
      }
      return deferredRollups;
    }
    set;
  }

  private static Map<String, Op> opNameToOp {
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

  public enum RollupInvocationPoint {
    FROM_APEX,
    FROM_INVOCABLE,
    FROM_SCHEDULED,
    FROM_LWC
  }

  protected Rollup(RollupInvocationPoint invokePoint) {
    this.isBatched = true;
    // a batch only becomes valid if other Rollups are added to it
    this.isNoOp = true;
    this.invokePoint = invokePoint;
    this.rollupControl = getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl);
  }

  private Rollup(Rollup innerRollup, Op op, List<SObject> calcItems) {
    this(
      calcItems,
      innerRollup.opFieldOnCalcItem,
      innerRollup.lookupFieldOnCalcItem,
      innerRollup.lookupFieldOnLookupObject,
      innerRollup.opFieldOnLookupObject,
      innerRollup.lookupObj,
      op,
      innerRollup.oldCalcItems,
      innerRollup.eval,
      innerRollup.invokePoint,
      innerRollup.rollupControlId,
      innerRollup.metadata
    );

    this.rollups = innerRollup.rollups;
    this.isNoOp = this.rollups.isEmpty() && innerRollup.metadata?.IsFullRecordSet__c == false;
    this.isFullRecalc = innerRollup.isFullRecalc;
    this.isCDCUpdate = innerRollup.isCDCUpdate;
    this.rollupControl = innerRollup.rollupControl;
  }

  private Rollup(Rollup innerRollup) {
    this(innerRollup, innerRollup.op, innerRollup.calcItems);
  }

  private Rollup(
    List<SObject> calcItems,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    Op op,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    RollupInvocationPoint invokePoint,
    Id rollupControlId,
    Rollup__mdt rollupMetadata
  ) {
    this.eval = eval;
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.lookupFieldOnCalcItem = lookupFieldOnCalcItem;
    this.lookupFieldOnLookupObject = lookupFieldOnLookupObject;
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.lookupObj = lookupObj;
    this.op = op;
    this.oldCalcItems = oldCalcItems;
    this.isBatched = false;
    this.invokePoint = invokePoint;
    this.rollupControlId = rollupControlId;
    this.metadata = rollupMetadata;
    this.calcItems = this.filter(calcItems, eval, rollupMetadata);
    this.isNoOp = this.calcItems.isEmpty() && rollupMetadata?.IsFullRecordSet__c == false;
  }

  global interface Evaluator {
    Boolean matches(Object calcItem);
  }

  public String runCalc() {
    RollupControl__mdt orgDefaults = getSingleControlOrDefault(RollupControl__mdt.DeveloperName, CONTROL_ORG_DEFAULTS, defaultControl);
    this.rollupControl = orgDefaults;
    // side effect in the below method - rollups can be removed from this.rollups if a control record ShouldAbortRun__c == true
    this.ingestRollupControlData(orgDefaults);

    this.isNoOp = this.rollups.isEmpty() && this.syncRollups.isEmpty();
    if (this.isNoOp || orgDefaults.ShouldAbortRun__c) {
      return 'No process Id';
    }

    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupControl__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
    Boolean hasMoreThanOneTarget = false;
    SObjectType targetType;
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();
    for (Rollup rollup : this.rollups) {
      rollup.isFullRecalc = this.isFullRecalc;
      if (targetType == null) {
        targetType = rollup.lookupObj;
      } else if (rollup.lookupObj != targetType) {
        hasMoreThanOneTarget = true;
      }

      Set<String> uniqueIds = new Set<String>();
      for (SObject calcItem : rollup.calcItems) {
        String lookupKey = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
        if (String.isNotBlank(lookupKey)) {
          uniqueIds.add(lookupKey);
        }
      }

      String countQuery = getQueryString(rollup.lookupObj, new List<String>{ 'Count()' }, String.valueOf(rollup.lookupFieldOnLookupObject), '=');
      if (queryCountsToLookupIds.containsKey(countQuery)) {
        queryCountsToLookupIds.get(countQuery).addAll(uniqueIds);
      } else {
        queryCountsToLookupIds.put(countQuery, uniqueIds);
      }
    }

    Integer totalCountOfRecords = 0;
    for (String countQuery : queryCountsToLookupIds.keySet()) {
      Set<String> objIds = queryCountsToLookupIds.get(countQuery);
      totalCountOfRecords += getCountFromDb(countQuery, objIds);
    }

    Boolean shouldRunAsBatch =
      shouldRunAsBatch || (orgDefaults.ShouldRunAs__c == 'Batchable' && totalCountOfRecords >= orgDefaults.MaxLookupRowsBeforeBatching__c);
    if (this.syncRollups.isEmpty() == false) {
      this.process(this.syncRollups);
      return 'Running rollups flagged to go synchronously';
    } else if (shouldRunAsBatch && hasMoreThanOneTarget == false) {
      // safe to batch because the QueryLocator will only return one type of SObject
      return Database.executeBatch(new Rollup(this), this.rollupControl.BatchChunkSize__c.intValue());
    } else {
      return System.enqueueJob(this);
    }
  }

  protected virtual List<SObject> getExistingLookupItems(Set<String> objIds, Rollup rollup, Set<String> uniqueQueryFieldNames) {
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute method"
    return this.lookupItems;
  }

  public virtual Database.QueryLocator start(Database.BatchableContext context) {
    /**
     * for batch, we know 100% for sure there's only 1 SObjectType / Set<String> in the map.
     * NB: we have to call "getFieldNamesForRollups" in both the "start" and "execute" methods because
     * trying to use Database.Stateful on the top-level class ** in addition to Batchable ** results in the dreaded:
     * "System.AsyncException: Queueable cannot be implemented with other system interfaces" exception
     */
    this.getFieldNamesForRollups(this.rollups);
    String query;
    String lookupFieldOnLookupObject;
    Set<String> objIds = new Set<String>();
    for (Rollup rollup : this.rollups) {
      lookupFieldOnLookupObject = rollup.lookupFieldOnLookupObject.getDescribe().getName();
      objIds.addAll(this.getCalcItemsByLookupField(rollup).keySet());
    }
    for (SObjectType sObjectType : this.lookupObjectToUniqueFieldNames.keySet()) {
      query = getQueryString(sObjectType, new List<String>(this.lookupObjectToUniqueFieldNames.get(sObjectType)), lookupFieldOnLookupObject, '=');
    }
    return Database.getQueryLocator(query);
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> lookupItems) {
    for (Rollup rollup : this.rollups) {
      this.initializeRollupFieldDefaults(lookupItems, rollup);
    }
    this.lookupItems = lookupItems;
    this.process(this.rollups);
  }

  public virtual void finish(Database.BatchableContext context) {
    System.debug('Rollup: batch finished successfully');
  }

  private class RollupAsyncSaver implements System.Queueable {
    private final List<SObject> records;
    public RollupAsyncSaver(List<SObject> records) {
      this.records = records;
    }

    public void execute(QueueableContext context) {
      new DMLHelper().doUpdate(this.records);
    }
  }

  private class RollupAsyncProcessor extends Rollup implements System.Queueable {
    public RollupAsyncProcessor(
      List<SObject> calcItems,
      SObjectField opFieldOnCalcItem,
      SObjectField lookupFieldOnCalcItem,
      SObjectField lookupFieldOnLookupObject,
      SObjectField opFieldOnLookupObject,
      SObjectType lookupObj,
      Op operation,
      Map<Id, SObject> oldCalcItems,
      Evaluator eval,
      Id rollupControlId,
      RollupInvocationPoint rollupInvokePoint,
      Rollup__mdt metadata
    ) {
      super(
        calcItems,
        opFieldOnCalcItem,
        lookupFieldOnCalcItem,
        lookupFieldOnLookupObject,
        opFieldOnLookupObject,
        lookupObj,
        operation,
        oldCalcItems,
        eval,
        rollupInvokePoint,
        rollupControlId,
        metadata
      );
    }

    public RollupAsyncProcessor(RollupInvocationPoint rollupInvokePoint) {
      super(rollupInvokePoint);
    }

    protected override List<SObject> getExistingLookupItems(Set<String> objIds, Rollup rollup, Set<String> uniqueQueryFieldNames) {
      if (objIds.isEmpty()) {
        return new List<SObject>();
      }
      // non-obvious coupling between "objIds" and the computed "queryString", which uses dynamic variable binding
      String queryString = getQueryString(rollup.lookupObj, new List<String>(uniqueQueryFieldNames), String.valueOf(rollup.lookupFieldOnLookupObject), '=');
      List<SObject> lookupItems = Database.query(queryString);
      this.initializeRollupFieldDefaults(lookupItems, rollup);
      return lookupItems;
    }

    public void execute(System.QueueableContext qc) {
      this.process(this.rollups);
    }
  }

  /**
   * global facing Rollup calculation section
   * - Trigger operations
   * - Batch (multiple Rollup operations chained into one job)
   * - Invocable
   * - Schedulable
   * - LWC-based full recalculation calls
   */

  @AuraEnabled
  global static String getBatchRollupStatus(String jobId) {
    return [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1]?.Status;
  }

  @AuraEnabled
  global static String performFullRecalculation(
    String opFieldOnCalcItem,
    String lookupFieldOnCalcItem,
    String lookupFieldOnLookupObject,
    String rollupFieldOnLookupObject,
    String lookupSObjectName,
    String calcItemSObjectName,
    String operationName,
    String potentialWhereClause
  ) {
    QueryWrapper wrapper = new QueryWrapper(lookupSObjectName, lookupFieldOnLookupObject);
    wrapper.setQuery(potentialWhereClause);
    return performFullRecalculationInner(
      opFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnLookupObject,
      rollupFieldOnLookupObject,
      lookupSObjectName,
      calcItemSObjectName,
      operationName,
      wrapper
    );
  }

  global class FlowInput {
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)')
    global List<SObject> recordsToRollup;

    @InvocableVariable(label='Rollup target\'s SObject Name' description='The API Name of the SObject where the rollup value will be stored.' required=true)
    global String rollupSObjectName;

    @InvocableVariable(label='Rollup Operation' description='SUM, COUNT, COUNT_DISTINCT, MAX, MIN, AVG, CONCAT, CONCAT_DISTINCT, FIRST, LAST' required=true)
    global String rollupOperation;

    @InvocableVariable(label='Rollup Context' description='INSERT, UPDATE, UPSERT, or DELETE' required=true)
    global String rollupContext;

    @InvocableVariable(label='Calc Item Rollup Field' description='The API Name of the field on each of the records passed in to consider.' required=true)
    global String rollupFieldOnCalcItem;

    @InvocableVariable(
      label='Rollup Object Field'
      description='The API Name of the field on the target object where the rollup value will be stored'
      required=true
    )
    global String rollupFieldOnOpObject;

    @InvocableVariable(
      label='Lookup Field On Calc Item'
      description='The API Name of the field on the record to rollup that matches a field on the object where the rollup will be stored'
      required=true
    )
    global String lookupFieldOnCalcItem;

    @InvocableVariable(
      label='Lookup Field On Rollup Object'
      description='The API Name of the field on the SObject matching the value found in "lookupFieldOnCalcItem" where the rollup will be stored'
      required=true
    )
    global String lookupFieldOnOpObject;

    // optional fields
    @InvocableVariable(
      label='Calc Item Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;

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
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;

    @InvocableVariable(
      label='Is Full Record Set'
      description='If provided, does not try to abort rollup calculation early if no records match, and instead resets the rollup field value'
    )
    global Boolean isFullRecordSet;

    @InvocableVariable(label='Order By (First/Last)' description='First/Last order by field')
    global String orderByFirstLast;

    @InvocableVariable(label='Defer processing')
    global Boolean deferProcessing = false;

    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
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
    List<FlowOutput> flowOutputReturns = new List<FlowOutput>();
    List<Rollup> rollups = new List<Rollup>();

    try {
      FlowInput firstInput = flowInputs.isEmpty() == false ? flowInputs[0] : new FlowInput();
      String rollupContext = getFlowRollupContext(firstInput);

      for (FlowInput flowInput : flowInputs) {
        FlowOutput flowOutput = new FlowOutput();
        flowOutputReturns.add(flowOutput);

        if (flowInput.recordsToRollup == null || flowInput.recordsToRollup.isEmpty()) {
          continue;
        } else {
          if (flowInput.isRollupStartedFromParent) {
            String whereClause = String.isNotBlank(flowInput.calcItemWhereClause) ? flowInput.calcItemWhereClause + '\nAND ' : '';
            QueryWrapper wrapper = getParentWhereClause(flowInput.recordsToRollup, flowInput.lookupFieldOnOpObject, flowInput.rollupSObjectName);
            wrapper.setQuery(whereClause + wrapper.getQuery());
            performFullRecalculationInner(
              flowInput.rollupFieldOnCalcItem,
              flowInput.lookupFieldOnCalcItem,
              flowInput.lookupFieldOnOpObject,
              flowInput.rollupFieldOnOpObject,
              flowInput.rollupSObjectName,
              flowInput.calcItemTypeWhenRollupStartedFromParent,
              flowInput.rollupOperation.toUpperCase(),
              wrapper
            );
            continue;
          }

          SObjectType sObjectType = flowInput.recordsToRollup[0].getSObjectType();
          Rollup__mdt rollupMeta = new Rollup__mdt(
            RollupFieldOnCalcItem__c = flowInput.rollupFieldOnCalcItem,
            LookupObject__c = flowInput.rollupSObjectName,
            LookupFieldOnCalcItem__c = flowInput.lookupFieldOnCalcItem,
            LookupFieldOnLookupObject__c = flowInput.lookupFieldOnOpObject,
            RollupFieldOnLookupObject__c = flowInput.rollupFieldOnOpObject,
            RollupOperation__c = rollupContext + flowInput.rollupOperation.toUpperCase(),
            ChangedFieldsOnCalcItem__c = flowInput.calcItemChangedFields,
            FullRecalculationDefaultNumberValue__c = flowInput.fullRecalculationDefaultNumberValue,
            FullRecalculationDefaultStringValue__c = flowInput.fullRecalculationDefaultStringValue,
            CalcItemWhereClause__c = flowInput.calcItemWhereClause,
            IsFullRecordSet__c = flowInput.isFullRecordSet,
            OrderByFirstLast__c = flowInput.orderByFirstLast
          );

          Set<String> uniqueFieldNames = new Set<String>{ 'Id' };
          if (String.isNotBlank(rollupMeta.LookupFieldOnCalcItem__c)) {
            uniqueFieldNames.add(rollupMeta.LookupFieldOnCalcItem__c);
          }
          if (String.isNotBlank(rollupMeta.RollupFieldOnCalcItem__c)) {
            uniqueFieldNames.add(rollupMeta.RollupFieldOnCalcItem__c);
          }
          Map<Id, SObject> oldFlowRecords = getOldFlowRecords(flowInput.recordsToRollup, sObjectType, new List<String>(uniqueFieldNames));
          Rollup roll = getRollup(
            new List<Rollup__mdt>{ rollupMeta },
            sObjectType,
            flowInput.recordsToRollup,
            oldFlowRecords,
            null,
            RollupInvocationPoint.FROM_INVOCABLE
          );
          if (flowInput.deferProcessing) {
            FLOW_ROLLUPS.add(roll);
          } else {
            rollups.add(roll);
          }
        }
        batch(rollups);
      }
    } catch (Exception ex) {
      for (FlowOutput flowOutput : flowOutputReturns) {
        flowOutput.IsSuccess = false;
        flowOutput.Message = ex.getMessage() + '\n' + ex.getStackTraceString();
      }
    }

    return flowOutputReturns;
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
    Rollup batchRollup = new RollupAsyncProcessor(RollupInvocationPoint.FROM_APEX);
    flattenBatches(batchRollup, rollups);
    batchRollup.runCalc();
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
    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupFieldOnCalcItem__c = operationFieldOnCalcItem.getDescribe().getName(),
      LookupObject__c = String.valueOf(lookupSObjectType),
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.getDescribe().getName(),
      LookupFieldOnLookupObject__c = lookupFieldOnOperationObject.getDescribe().getName(),
      RollupFieldOnLookupObject__c = operationFieldOnOperationObject.getDescribe().getName(),
      RollupOperation__c = rollupOperation.name(),
      OrderByFirstLast__c = orderByFirstLast
    );
    if (defaultRecalculationValue instanceof Decimal) {
      rollupMetadata.FullRecalculationDefaultNumberValue__c = (Decimal) defaultRecalculationValue;
    } else if (defaultRecalculationValue instanceof String) {
      rollupMetadata.FullRecalculationDefaultStringValue__c = (String) defaultRecalculationValue;
    }
    return runFromApex(new List<Rollup__mdt>{ rollupMetadata }, eval, getTriggerRecords(), getOldTriggerRecordsMap());
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

    List<Rollup__mdt> rollupMetadata = getRollupMetadataBySObject(sObjectType);
    if (rollupMetadata.isEmpty()) {
      return;
    }

    Set<String> uniqueFieldNames = new Set<String>{ 'Id' };
    for (Rollup__mdt rollupInfo : rollupMetadata) {
      uniqueFieldNames.add(getParedFieldName(rollupInfo.LookupFieldOnCalcItem__c));
      uniqueFieldNames.add(getParedFieldName(rollupInfo.ROllupFieldOnCalcItem__c));
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

    // non-obvious coupling between objIds and the "fullQuery" below
    List<Id> objIds = new List<Id>();
    for (SObject cdcRecord : cdcRecords) {
      uniqueFieldNames.addAll(header.changedfields);
      objIds.add(header.getRecordIds()[0]);
    }

    String fullQuery = getQueryString(sObjectType, new List<String>(uniqueFieldNames), 'Id', '=');
    Map<Id, SObject> cdcRecordsMap = new Map<Id, SObject>(Database.query(fullQuery));

    Rollup rollupToReturn = runFromApex(rollupMetadata, null, cdcRecordsMap.values(), cdcRecordsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isCDCUpdate = apexContext == TriggerOperation.AFTER_UPDATE;
    rollupToReturn.runCalc();
  }

  global static void runFromTrigger() {
    List<SObject> triggerRecords = getTriggerRecords();
    List<Rollup__mdt> rollupMetadata = getRollupMetadataBySObject(triggerRecords.getSObjectType());
    runFromApex(rollupMetadata, null, triggerRecords, getOldTriggerRecordsMap()).runCalc();
  }

  /**
   * @param `List<SObject>` calcItems - the records whose values you'd like to roll up
   * @param `TriggerOperation` rollupContext - acceptable values are:
   * - TriggerOperation.AFTER_INSERT
   * - TriggerOperation.AFTER_UDATE
   * - TriggerOperation.BEFORE_DELETE
   * - TriggerOperation.AFTER_UNDELETE
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

  private static Rollup runFromApex(List<Rollup__mdt> rollupMetadata, Evaluator eval, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    if (shouldRunFromTrigger() == false) {
      return new RollupAsyncProcessor(RollupInvocationPoint.FROM_APEX);
    }

    String rollupContext;
    Boolean shouldReturn = false;

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
      when else {
        shouldReturn = true;
      }
    }

    for (Rollup__mdt rollupInfo : rollupMetadata) {
      if (rollupInfo.IsRollupStartedFromParent__c) {
        shouldReturn = true;
        QueryWrapper wrapper = getParentWhereClause(calcItems, rollupInfo.LookupFieldOnLookupObject__c, rollupInfo.LookupObject__c);
        performFullRecalculationInner(
          rollupInfo.RollupFieldOnCalcItem__c,
          rollupInfo.LookupFieldOnCalcItem__c,
          rollupInfo.LookupFieldOnLookupObject__c,
          rollupInfo.RollupFieldOnLookupObject__c,
          rollupInfo.LookupObject__c,
          rollupInfo.CalcItem__c,
          rollupInfo.RollupOperation__c,
          wrapper
        );
      }
      rollupInfo.RollupOperation__c = rollupContext + rollupInfo.RollupOperation__c;
    }

    return shouldReturn
      ? new RollupAsyncProcessor(RollupInvocationPoint.FROM_APEX)
      : getRollup(rollupMetadata, calcItems.getSObjectType(), calcItems, oldCalcItems, eval, RollupInvocationPoint.FROM_APEX);
  }

  /** end global-facing section, begin public/private static helpers */

  private static String performFullRecalculationInner(
    String opFieldOnCalcItem,
    String lookupFieldOnCalcItem,
    String lookupFieldOnLookupObject,
    String rollupFieldOnLookupObject,
    String lookupSObjectName,
    String calcItemSObjectName,
    String operationName,
    QueryWrapper queryWrapper
  ) {
    // just how many items are we talking, here? If it's less than the query limit, we can proceed
    // otherwise, kick off a batch to fetch the calc items and then chain into the regular code path
    SObjectType calcItemType = getSObjectFromName(calcItemSObjectName).getSObjectType();
    String countQuery = getQueryString(calcItemType, new List<String>{ 'Count()' }, lookupFieldOnLookupObject, '!=');

    // TODO need to pass wrapper.getQuery() to getCountFromDb, as well, or set the query again and pass just the wrapper?
    Set<String> objIds = new Set<String>(); // get everything that doesn't have a null Id - a pretty trick
    Integer amountOfCalcItems = getCountFromDb(countQuery, objIds);

    // emptyRollup used to call "getMaxQueryRows" below, as well as the default rollupControl.BatchChunkSize__c
    Rollup emptyRollup = new Rollup(RollupInvocationPoint.FROM_LWC);
    SObjectType lookupType = getSObjectFromName(lookupSObjectName).getSObjectType();
    Rollup__mdt rollupInfo = new Rollup__mdt(
      RollupFieldOnCalcItem__c = opFieldOnCalcItem,
      LookupObject__c = lookupSObjectName,
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem,
      LookupFieldOnLookupObject__c = lookupFieldOnLookupObject,
      RollupFieldOnLookupObject__c = rollupFieldOnLookupObject,
      RollupOperation__c = operationName
    );
    Set<String> queryFields = new Set<String>{ 'Id', opFieldOnCalcItem, lookupFieldOnCalcItem };
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryWrapper.toString(), calcItemType);
    queryFields.addAll(eval.getRelationshipFieldNames());
    String queryString = getQueryString(
      calcItemType,
      new List<String>(queryFields),
      'Id',
      '!=',
      queryWrapper.getQuery()
    );
    if (amountOfCalcItems < emptyRollup.getMaxQueryRows()) {
      Set<Id> recordIds = queryWrapper.recordIds;
      List<SObject> calcItems = Database.query(queryString);
      Rollup thisRollup = getRollup(
        new List<Rollup__mdt>{ rollupInfo },
        calcItemType,
        calcItems,
        new Map<Id, SObject>(calcItems),
        eval,
        RollupInvocationPoint.FROM_LWC
      );
      thisRollup.isFullRecalc = true;
      return thisRollup.runCalc();
    } else {
      //batch to get calc items and then batch to rollup
      return Database.executeBatch(
        new RollupFullBatchRecalculator(queryString, RollupInvocationPoint.FROM_LWC, rollupInfo, calcItemType),
        emptyRollup.rollupControl.BatchChunkSize__c.intValue()
      );
    }
  }

  public static String getQueryString(
    SObjectType sObjectType,
    List<String> uniqueQueryFieldNames,
    String lookupFieldOnLookupObject,
    String equality,
    String optionalWhereClause
  ) {
    DescribeSObjectResult sObjectToken = sObjectType.getDescribe();
    Map<String, SObjectField> baseFields = sObjectToken.fields.getMap();
    for (Integer index = 0; index < uniqueQueryFieldNames.size(); index++) {
      String uniqueFieldName = uniqueQueryFieldNames[index];
      String paredFieldName = getParedFieldName(uniqueFieldName);
      // ensure that the base relationship name field is transformed appropriately
      if (baseFields.containsKey(paredFieldName + 'Id') || baseFields.containsKey(paredFieldName + '__c')) {
        SObjectField baseField = baseFields.get(paredFieldName + 'Id') == null ? baseFields.get(paredFieldName + '__c') : baseFields.get(paredFieldName + 'Id');
        DescribeFieldResult fieldToken = baseField.getDescribe();
        if (fieldToken.getType() == DisplayType.REFERENCE && uniqueQueryFieldNames.contains(fieldToken.getName()) == false) {
          uniqueQueryFieldNames[index] = fieldToken.getName();
        }
      } else if (
        baseFields.containsKey(uniqueFieldName) == false &&
        baseFields.containsKey(paredFieldName) &&
        sObjectToken.getName() == uniqueFieldName.substringBefore('.') &&
        uniqueQueryFieldNames.contains(paredFieldName) == false
      ) {
        uniqueQueryFieldNames[index] = paredFieldName;
      }
    }
    // again noting the coupling for consumers of this method
    // "objIds" is required to be present in the scope where the query is run
    String baseQuery =
      'SELECT ' +
      String.join(uniqueQueryFieldNames, ',') +
      '\nFROM ' +
      sObjectType +
      '\nWHERE ' +
      lookupFieldOnLookupObject +
      ' ' +
      equality +
      ' :objIds';
    if (String.isNotBlank(optionalWhereClause)) {
      if (optionalWhereClause.startsWith('\nAND') || optionalWhereClause.startsWith('\nOR')) {
        baseQuery += optionalWhereClause;
      } else {
        baseQuery += '\nAND ' + optionalWhereClause;
      }
    }
    if (sObjectType == Task.SObjectType || sObjectType == Event.SObjectType) {
      // handle archived rows
      baseQuery += '\nAND IsDeleted = false ALL ROWS';
    }
    return baseQuery;
  }

  public static String getQueryString(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String lookupFieldOnLookupObject, String equality) {
    return getQueryString(sObjectType, uniqueQueryFieldNames, lookupFieldOnLookupObject, equality, null);
  }

  public static void processStoredFlowRollups() {
    batch(FLOW_ROLLUPS);
    FLOW_ROLLUPS.clear();
  }

  private static List<Rollup__mdt> cachedMetadata;
  public static List<SObject> getMetadataFromCache(SObjectType metadataType) {
    List<SObject> metadata;
    // CMDT is read-only when returned from the cache
    // use "deepClone" to get access to mutable versions
    // of the CMDT records. We also need to clean up the Entity Definition / Field Definition
    // particles for custom objects and custom fields
    if (metadataType == Rollup__mdt.SObjectType) {
      if (cachedMetadata == null) {
        cachedMetadata = [
          SELECT
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
            // rest of the fields
            CalcItemWhereClause__c,
            ChangedFieldsOnCalcItem__c,
            FullRecalculationDefaultNumberValue__c,
            FullRecalculationDefaultStringValue__c,
            IsFullRecordSet__c,
            IsRollupStartedFromParent__c,
            OrderByFirstLast__c,
            RollupControl__c,
            RollupOperation__c
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
        }
      }
      metadata = cachedMetadata.clone();
      if (rollupMetadata != null) {
        metadata.addAll(rollupMetadata);
      }
    } else if (metadataType == RollupControl__mdt.SObjectType) {
      metadata = RollupControl__mdt.getAll().deepClone().values();
    }
    return metadata;
  }

  private class QueryWrapper {
    public QueryWrapper(String lookupObject, String lookupField) {
      this.query = lookupObject.replace('__c', '__r') + '.' + lookupField + ' = :recordIds';
    }
    private Boolean hasQuery = false;
    private String query;
    public final Set<Id> recordIds = new Set<Id>();
    private final List<String> stringifiedRecordIds = new List<String>();

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
      return this.hasQuery ? this.query.replace('= :recordIds', 'IN (' + String.join(this.stringifiedRecordIds, ',') + ')') : '';
    }
  }

  private static QueryWrapper getParentWhereClause(List<SObject> calcItems, String lookupFieldOnLookupObject, String lookupObjectName) {
    QueryWrapper wrapper = new QueryWrapper(lookupObjectName, lookupFieldOnLookupObject);
    for (SObject calcItem : calcItems) {
      String lookupId = (String) calcItem.get(lookupFieldOnLookupObject);
      wrapper.addRecordId(lookupId);
    }
    return wrapper;
  }

  private static Integer getCountFromDb(String countQuery, Set<String> objIds) {
    if (countQuery.contains('ALL ROWS')) {
      countQuery = countQuery.replace('ALL ROWS', '');
    }
    return Database.countQuery(countQuery);
  }

  private static void flattenBatches(Rollup outerRollup, List<Rollup> rollups) {
    for (Rollup rollup : rollups) {
      if (rollup.rollups.isEmpty() == false) {
        // recurse through lists until there aren't any more nested rollups
        flattenBatches(outerRollup, rollup.rollups);
      } else {
        loadRollups(rollup, outerRollup);
      }
    }
  }

  private static String getFlowRollupContext(FlowInput firstInput) {
    String flowContext = firstInput.rollupContext.toUpperCase();
    if (String.isBlank(flowContext)) {
      flowContext = 'INSERT';
    } else if (flowContext == 'UPSERT') {
      flowContext = 'UPDATE';
    }

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static Map<Id, SObject> getOldFlowRecords(List<SObject> currentRecords, SObjectType sObjectType, List<String> calcItemFields) {
    if (currentRecords.isEmpty()) {
      return new Map<Id, SObject>();
    } else if (oldRecordsMap != null) {
      return oldRecordsMap;
    }

    // normally, you could use a shortcut to initialize a Set<Id> like this
    // by calling new Map<Id, SObject>(currentRecords).keyset() -
    // but that code path fails if there are null Ids in the list
    Set<Id> objIds = new Set<Id>();
    for (SObject currentRecord : currentRecords) {
      if (currentRecord.Id != null) {
        objIds.add(currentRecord.Id);
      }
    }
    // we need to do two things: get the old records, and initialize default values for both existing records and the ones that don't have matches in the db
    DescribeSObjectResult sObjectDescribe = sObjectType.getDescribe();
    Map<String, SObjectField> fieldTokensForObject = sObjectDescribe.fields.getMap();
    Map<Id, SObject> existingOldRecordsMap = new Map<Id, SObject>(Database.query(getQueryString(sObjectType, calcItemFields, 'Id', '=')));
    for (SObject currentRecord : currentRecords) {
      SObject existingRecordOrDefault = currentRecord.Id != null && existingOldRecordsMap.containsKey(currentRecord.Id)
        ? existingOldRecordsMap.get(currentRecord.Id)
        : getSObjectFromName(sObjectDescribe.getName());
      existingRecordOrDefault.Id = currentRecord.Id;
      for (String fieldName : calcItemFields) {
        SObjectField fieldToken = fieldTokensForObject.get(fieldName);
        if (existingRecordOrDefault.get(fieldName) != null || fieldToken.getDescribe().isUpdateable() == false) {
          continue;
        } else {
          existingRecordOrDefault.put(fieldName, RollupFieldInitializer.Current.getDefaultValue(fieldToken));
        }
      }
      existingOldRecordsMap.put(currentRecord.Id, existingRecordOrDefault);
    }
    return existingOldRecordsMap;
  }

  private static List<Rollup__mdt> getRollupMetadataBySObject(SObjectType sObjectType) {
    String sObjectName = sObjectType.getDescribe().getName();
    List<Rollup__mdt> rollupMetadatas = getMetadataFromCache(Rollup__mdt.SObjectType);
    for (Integer index = rollupMetadatas.size() - 1; index >= 0; index--) {
      Rollup__mdt rollupMetadata = rollupMetadatas[index];
      if (rollupMetadata.CalcItem__c != sObjectName && rollupMetadata.IsRollupStartedFromParent__c == false) {
        rollupMetadatas.remove(index);
      } else if (rollupMetadata.IsRollupStartedFromParent__c && sObjectName != rollupMetadata.LookupObject__c) {
        rollupMetadatas.remove(index);
      }
    }
    return rollupMetadatas;
  }

  private static Rollup getRollup(
    List<Rollup__mdt> rollupOperations,
    SObjectType sObjectType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    RollupInvocationPoint rollupInvokePoint
  ) {
    if (rollupOperations.isEmpty() || calcItems.isEmpty()) {
      return new RollupAsyncProcessor(rollupInvokePoint);
    }
    if (sObjectType == null) {
      sObjectType = calcItems[0].getSObjectType();
    }
    /**
     * We have rollup operations to perform. That's great!
     * BUT Field Definition CMDT records are stored like such: `Account.NumberOfEmployees`
     * The generic "put" operation for SObjects (necessary later) doesn't support these "full length" field names
     * Let's pare them down and get ready to rollup!
     */
    Rollup batchRollup = new RollupAsyncProcessor(rollupInvokePoint);
    DescribeSObjectResult describeForSObject = sObjectType.getDescribe();
    Map<String, SObjectField> fieldNameToField = describeForSObject.fields.getMap();
    for (Rollup__mdt rollupMetadata : rollupOperations) {
      Op rollupOp = opNameToOp.get(rollupMetadata.RollupOperation__c.toUpperCase());
      SObjectField rollupFieldOnCalcItem = getSObjectFieldByName(describeForSObject, rollupMetadata.RollupFieldOnCalcItem__c);
      SObjectField lookupFieldOnCalcItem = getSObjectFieldByName(describeForSObject, rollupMetadata.LookupFieldOnCalcItem__c);

      // NB - this SHOULD work even for SObjects part of managed packages
      SObjectType lookupSObjectType = getSObjectFromName(rollupMetadata.LookupObject__c).getSObjectType();
      DescribeSObjectResult lookupObjectDescribe = lookupSObjectType.getDescribe();
      Map<String, SObjectField> lookupFieldNameToLookupFields = lookupObjectDescribe.fields.getMap();
      SObjectField lookupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.LookupFieldOnLookupObject__c);
      SObjectField rollupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.RollupFieldOnLookupObject__c);

      // reset the CMDT field-level definitions using the SObjectField tokens
      rollupMetadata.RollupFieldOnCalcItem__c = rollupFieldOnCalcItem.getDescribe().getName();
      rollupMetadata.LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.getDescribe().getName();
      rollupMetadata.LookupFieldOnLookupObject__c = lookupFieldOnOpObject.getDescribe().getName();
      rollupMetadata.RollupFieldOnLookupObject__c = rollupFieldOnOpObject.getDescribe().getName();

      RollupControl__mdt rollupControl;
      if (rollupMetadata.RollupControl__c != null) {
        // for CMDT-driven rollups, the rollup record is always tied to a RollupControl__mdt record
        rollupControl = new RollupControl__mdt(Id = rollupMetadata.RollupControl__c);
      } else {
        String controlKey = getRollupControlKey(rollupInvokePoint, rollupFieldOnCalcItem, lookupSObjectType, rollupFieldOnOpObject);
        rollupControl = getSingleControlOrDefault(RollupControl__mdt.TriggerOrInvocableName__c, controlKey, null);
      }

      loadRollups(
        rollupFieldOnCalcItem,
        lookupFieldOnCalcItem,
        lookupFieldOnOpObject,
        rollupFieldOnOpObject,
        lookupSObjectType,
        rollupOp,
        calcItems,
        oldCalcItems,
        batchRollup,
        RollupEvaluator.getEvaluator(eval, rollupMetadata, oldCalcItems, sObjectType),
        rollupControl?.Id,
        rollupInvokePoint,
        rollupMetadata
      );
    }
    return batchRollup;
  }

  private static SObjectField getSObjectFieldByName(DescribeSObjectResult objectDescribe, String desiredField) {
    Map<String, SObjectField> fieldNameToField = objectDescribe.fields.getMap();
    String paredFieldName = getParedFieldName(desiredField);
    if (fieldNameToField.containsKey(paredFieldName)) {
      return fieldNameToField.get(paredFieldName);
    } else if (fieldNameToField.containsKey(paredFieldName + 'Id')) {
      // for lookup fields, CMDT field-level definition fields store the field name, which is outrageous
      return fieldNameToField.get(paredFieldName + 'Id');
    }

    return null;
  }

  private static String getRollupControlKey(
    RollupInvocationPoint invokePoint,
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

  private static Boolean shouldRunFromTrigger() {
    shouldRun = shouldRun || Trigger.isExecuting;
    // in order to accomodate CDC; we set the apexContext manually there
    // since technically all CDC is done from an AFTER_INSERT context
    if (Trigger.operationType != null && isCDC == false) {
      apexContext = Trigger.operationType;
    }
    // there are only four allowed trigger operations that qualify
    if (
      shouldRun &&
      apexContext != TriggerOperation.AFTER_INSERT &&
      apexContext != TriggerOperation.AFTER_UPDATE &&
      apexContext != TriggerOperation.BEFORE_DELETE &&
      apexContext != TriggerOperation.AFTER_UNDELETE
    ) {
      shouldRun = false;
    }
    // for our purposes, an undelete behaviors **strictly** the same as an insert
    // the implications are that if you programmatically changed the lookup field
    // before undeleting a record in Apex, things might get weird, but aside from that
    // edge case ...
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

  private static String getParedFieldName(String fullFieldName) {
    if (String.isBlank(fullFieldName)) {
      return '';
    }
    return fullFieldName.contains('.') ? fullFieldName.substringAfter('.') : fullFieldName;
  }

  private static Rollup loadRollups(
    SObjectField rollupFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOpObject,
    SObjectField rollupFieldOnOpObject,
    SObjectType sObjectType,
    Op rollupOp,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Rollup batchRollup,
    Evaluator eval,
    Id rollupControlId,
    RollupInvocationPoint invokePoint,
    Rollup__mdt rollupMetadata
  ) {
    Rollup rollup = new RollupAsyncProcessor(
      calcItems,
      rollupFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOpObject,
      rollupFieldOnOpObject,
      sObjectType,
      rollupOp,
      oldCalcItems,
      eval,
      rollupControlId,
      invokePoint,
      rollupMetadata
    );
    return loadRollups(rollup, batchRollup);
  }

  private static Rollup loadRollups(Rollup rollup, Rollup batchRollup) {
    if (batchRollup != null && rollup != null && rollup.isNoOp == false) {
      batchRollup.rollups.add(rollup);
    } else if (rollup != null && rollup.isNoOp == false) {
      rollup.rollups.add(rollup);
    }
    return batchRollup != null ? batchRollup : rollup;
  }

  private static RollupControl__mdt getSingleControlOrDefault(SObjectField whereField, Object whereValue, RollupControl__mdt testOverrideData) {
    // there are multiple spots where testOverrideData can be supplied, which is why it's necessary to pass the argument to this method
    if (testOverrideData != null) {
      return testOverrideData;
    } else if (whereField == RollupControl__mdt.Id) {
      return RollupControl__mdt.getInstance((Id) whereValue)?.clone(true, true);
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
    }
    RollupControl__mdt sensibleDefault = RollupControl__mdt.getInstance(CONTROL_ORG_DEFAULTS);
    if (sensibleDefault == null) {
      // this *should* be impossible, since the record is included on install, but ...
      sensibleDefault = new RollupControl__mdt(
        DeveloperName = CONTROL_ORG_DEFAULTS,
        BatchChunkSize__c = 2000,
        MaxLookupRowsBeforeBatching__c = Limits.getLimitDmlRows() / 3,
        MaxParentRowsUpdatedAtOnce__c = Limits.getLimitDmlRows() / 2,
        MaximumRollupRetries__c = 100,
        MaxQueryRows__c = Limits.getLimitQueryRows() / 2,
        ShouldAbortRun__c = false,
        ShouldRunAs__c = 'Queueable'
      );
    } else {
      sensibleDefault = sensibleDefault.clone(true, true);
    }
    return sensibleDefault;
  }

  /** End static section, begin protected + private instance methods */

  protected Rollup getDelegatedRollup(
    Rollup__mdt rollupInfo,
    SObjectType calcItemType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    RollupInvocationPoint invokePoint
  ) {
    return getRollup(new List<Rollup__mdt>{ rollupInfo }, calcItemType, calcItems, oldCalcItems, eval, invokePoint);
  }

  protected virtual Integer getMaxQueryRows() {
    return maxQueryRowOverride != null ? maxQueryRowOverride : Limits.getLimitQueryRows() - Limits.getQueryRows();
  }

  protected void process(List<Rollup> rollups) {
    this.getFieldNamesForRollups(rollups);
    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    for (Integer index = 0; index < rollups.size(); index++) {
      // for each iteration, ensure we're not operating beyond the bounds of our query limits
      Rollup rollup = rollups[index];
      if (this.hasExceededCurrentRollupQueryLimit(rollup.rollupControl)) {
        this.deferredRollups.add(rollup);
        continue;
      }
      Map<String, List<SObject>> calcItemsByLookupField = this.getCalcItemsByLookupField(rollup);
      List<SObject> lookupItems = new List<SObject>();
      Set<String> lookupItemKeys = new Set<String>(calcItemsByLookupField.keySet());
      for (String lookupId : calcItemsByLookupField.keySet()) {
        if (updatedLookupRecords.containsKey(lookupId)) {
          lookupItemKeys.remove(lookupId);
          // this way, the updated values are persisted for each field, and the default values are initialized
          SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
          if (updatedLookupObject.get(rollup.opFieldOnLookupObject) == null || this.isFullRecalc) {
            updatedLookupObject.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
          }
          lookupItems.add(updatedLookupObject);
        }
      }
      lookupItems.addAll(this.getExistingLookupItems(lookupItemKeys, rollup, this.lookupObjectToUniqueFieldNames.get(rollup.lookupObj)));
      List<SObject> updatedParentRecords = this.getUpdatedLookupItemsByRollup(rollup, calcItemsByLookupField, lookupItems);
      for (SObject updatedRecord : updatedParentRecords) {
        updatedLookupRecords.put(updatedRecord.Id, updatedRecord);
      }
    }

    if (this.rollupControl.MaxParentRowsUpdatedAtOnce__c < updatedLookupRecords.size()) {
      Integer maxIndexToRemove = updatedLookupRecords.size() / 2;
      Integer removalIndex = 0;
      List<SObject> asyncUpdateList = new List<SObject>();
      for (String lookupKey : updatedLookupRecords.keySet()) {
        SObject lookupRecordToUpdate = updatedLookupRecords.get(lookupKey);
        asyncUpdateList.add(lookupRecordToUpdate);
        updatedLookupRecords.remove(lookupKey);
        removalIndex++;
        if (removalIndex >= maxIndexToRemove) {
          break;
        }
      }
      System.enqueueJob(new RollupAsyncSaver(asyncUpdateList));
    }

    DML.doUpdate(updatedLookupRecords.values());

    this.processDeferredRollups();
  }

  private Boolean hasExceededCurrentRollupQueryLimit(RollupControl__mdt control) {
    return Limits.getQueries() >= control?.MaxQueryRows__c && isDeferralAllowed;
  }

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty() == false && isDeferralAllowed && stackDepth < this.rollupControl?.MaxRollupRetries__c) {
      stackDepth++;
      // tragic, but necessary due to limits on requeueing allowed during testing
      isDeferralAllowed = Test.isRunningTest() == false && this.rollupControl.MaximumRollupRetries__c > stackDepth;
      this.rollups.clear();
      this.rollups.addAll(this.deferredRollups);
      this.deferredRollups.clear();
      if (System.isBatch()) {
        Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
      } else {
        System.enqueueJob(this);
      }
    }
  }

  private List<SObject> filter(List<SObject> calcItems, Evaluator eval, Rollup__mdt rollupMetadata) {
    List<SObject> applicableItems = new List<SObject>();
    if (calcItems == null) {
      return applicableItems;
    }
    for (SObject calcItem : calcItems) {
      if (eval == null || eval.matches(calcItem)) {
        applicableItems.add(calcItem);
        // metadata shouldn't be null, but it's good to check; unfortunately, if(null) throws so we
        // have to do this EXTRA explicit check
      } else if (rollupMetadata?.IsFullRecordSet__c == true) {
        applicableItems.add(calcItem);
      } else if(rollupMetadata?.RollupOperation__c?.contains(Rollup.Op.AVERAGE.name())) {
        applicableItems.add(calcItem);
      }
    }
    return applicableItems;
  }

  private void getFieldNamesForRollups(List<Rollup> rollups) {
    this.lookupObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    for (Rollup rollup : rollups) {
      String rollupField = rollup.opFieldOnLookupObject.getDescribe().getName();
      String lookupfield = rollup.lookupFieldOnLookupObject.getDescribe().getName();
      if (lookupObjectToUniqueFieldNames.containsKey(rollup.lookupObj)) {
        lookupObjectToUniqueFieldNames.get(rollup.lookupObj).addAll(new List<String>{ rollupField, lookupField });
      } else {
        lookupObjectToUniqueFieldNames.put(rollup.lookupObj, new Set<String>{ rollupField, lookupfield });
      }
    }
  }

  private Map<String, List<SObject>> getCalcItemsByLookupField(Rollup rollup) {
    Map<String, List<SObject>> lookupFieldToCalcItems = new Map<String, List<SObject>>();
    for (SObject calcItem : rollup.calcItems) {
      String key = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new List<SObject>{ calcItem });
      } else {
        lookupFieldToCalcItems.get(key).add(calcItem);
      }

      SObject potentialOldCalcItem = rollup.oldCalcItems?.get(calcItem.Id);
      if (potentialOldCalcItem != null) {
        String oldKey = (String) potentialOldCalcItem.get(rollup.lookupFieldOnCalcItem);

        if (key == oldKey) {
          continue;
        }

        if (lookupFieldToCalcItems.containsKey(oldKey) == false) {
          lookupFieldToCalcItems.put(oldKey, new List<SObject>{ potentialOldCalcItem });
        } else {
          lookupFieldToCalcItems.get(oldKey).add(potentialOldCalcItem);
        }
      }
    }
    return lookupFieldToCalcItems;
  }

  protected void initializeRollupFieldDefaults(List<SObject> lookupItems, Rollup rollup) {
    // prior to returning, we need to ensure the default value for the rollup field is set
    for (SObject lookupItem : lookupItems) {
      if (lookupItem.get(rollup.opFieldOnLookupObject) == null || rollup.isFullRecalc) {
        lookupItem.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
      }
    }
  }

  private void ingestRollupControlData(RollupControl__mdt orgDefaults) {
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      Rollup rollup = this.rollups[index];
      SObjectField controlWhereField = rollup.rollupControlId == null ? RollupControl__mdt.TriggerOrInvocableName__c : RollupControl__mdt.Id;
      String controlWhereValue = rollup.rollupControlId == null
        ? getRollupControlKey(rollup.invokePoint, rollup.opFieldOnCalcItem, rollup.lookupObj, rollup.opFieldOnLookupObject)
        : rollup.rollupControlId;
      RollupControl__mdt rollupSpecificControl = getSingleControlOrDefault(controlWhereField, controlWhereValue, specificControl);
      rollup.rollupControl = rollupSpecificControl;

      if (rollupSpecificControl.ShouldAbortRun__c) {
        this.rollups.remove(index);
      } else if (rollupSpecificControl.ShouldRunAs__c == 'Synchronous Rollup') {
        this.rollups.remove(index);
        this.syncRollups.add(rollup);
      }

      // you can increase the default limits, but it would be too messy to try to rank the individual rollup operations in a batched context
      if (rollupSpecificControl.MaxLookupRowsBeforeBatching__c > orgDefaults.MaxLookupRowsBeforeBatching__c) {
        orgDefaults.MaxLookupRowsBeforeBatching__c = rollupSpecificControl.MaxLookupRowsBeforeBatching__c;
      }
      if (rollupSpecificControl.MaxParentRowsUpdatedAtOnce__c == null) {
        rollupSpecificControl.MaxParentRowsUpdatedAtOnce__c = orgDefaults.MaxParentRowsUpdatedAtOnce__c;
      }
    }
  }

  private List<SObject> getUpdatedLookupItemsByRollup(Rollup rollup, Map<String, List<SObject>> calcItemsByLookupField, List<SObject> lookupItems) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    for (SObject lookupRecord : lookupItems) {
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        List<SObject> calcItems = calcItemsByLookupField.get(key);

        // Check for reparented records
        Map<Id, SObject> oldCalcItems = rollup.oldCalcItems;
        for (Integer index = calcItems.size() - 1; index >= 0; index--) {
          SObject calcItem = calcItems[index];
          if (rollup.eval?.matches(calcItem) == false && rollup.metadata?.IsFullRecordSet__c == true) {
            // technically it should only be possible for a calc item that doesn't match
            // to still exist if it is a Full Record Set operation; this gives people the chance
            // to reset rollup values if none of the records passed in match the eval criteria
            calcItems.remove(index);
            continue;
          }
          SObject oldCalcItem = oldCalcItems.get(calcItem.Id);

          if (oldCalcItem == null) {
            continue;
          }

          String priorLookup = (String) oldCalcItem.get(rollup.lookupFieldOnCalcItem);
          Object newLookup = calcItem.get(rollup.lookupFieldOnCalcItem);

          if (newLookup != priorLookup) {
            if (!oldLookupItems.containsKey(priorLookup)) {
              oldLookupItems.put(priorLookup, new List<SObject>());
            }
            List<SObject> reparentedCalcItemsForKey = oldLookupItems.get(priorLookup);
            reparentedCalcItemsForKey.add(oldCalcItem);
          }
        }

        // Check for changed values
        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(rollup, calcItems, priorVal, key, rollup.lookupFieldOnCalcItem);
        if (priorVal != newVal) {
          lookupRecord.put(rollup.opFieldOnLookupObject, newVal);
          recordsToUpdate.put(key, lookupRecord);
        }
      }
    }

    // Remove the value from the old parent record when re-parenting has occurred
    for (SObject lookupRecord : lookupItems) {
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (oldLookupItems.containsKey(key)) {
        // Yes, old parent record has already had a new rollup established in memory
        List<SObject> reparentedCalcItems = oldLookupItems.get(key);

        if (reparentedCalcItems.isEmpty()) {
          continue;
        }

        String currentOp = rollup.op.name().contains('_') ? rollup.op.name().substringAfter('_') : rollup.op.name();
        String deleteOpName = 'DELETE_' + currentOp;
        Op deleteOp = opNameToOp.get(deleteOpName);
        Rollup oldLookupsRollup = new Rollup(rollup, deleteOp, reparentedCalcItems);

        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(oldLookupsRollup, reparentedCalcItems, priorVal, key, rollup.lookupFieldOnCalcItem);

        lookupRecord.put(rollup.opFieldOnLookupObject, newVal);

        recordsToUpdate.put(key, lookupRecord);
      }
    }

    return recordsToUpdate.values();
  }

  private Object getRollupVal(Rollup roll, List<SObject> calcItems, Object priorVal, String lookupRecordKey, SObjectField lookupKeyField) {
    RollupCalculator rollupCalc = RollupCalculator.Factory.getCalculator(
      priorVal,
      roll.op,
      roll.opFieldOnCalcItem,
      roll.opFieldOnLookupObject,
      roll.metadata,
      lookupRecordKey,
      lookupKeyField
    );
    rollupCalc.setEvaluator(roll.eval);
    rollupCalc.setCDCUpdate(this.isCDCUpdate);
    rollupCalc.performRollup(calcItems, roll.oldCalcItems);
    return rollupCalc.getReturnValue();
  }

  @testVisible
  private virtual class DMLHelper {
    public virtual void doUpdate(List<SObject> recordsToUpdate) {
      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.AllowFieldTruncation = true;
      Database.update(recordsToUpdate, dmlOptions);
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
      getRollup(metadata, calcItems.getSObjectType(), calcItems, new Map<Id, SObject>(calcItems), this.eval, RollupInvocationPoint.FROM_SCHEDULED).runCalc();
    }
  }
}
