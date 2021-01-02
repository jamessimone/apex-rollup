public without sharing virtual class Rollup implements Database.Batchable<SObject> {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @testVisible
  private static Boolean shouldRun;
  @testVisible
  private static Boolean shouldRunAsBatch = false;
  @testVisible
  private static TriggerOperation triggerContext = Trigger.operationType;
  @testVisible
  private static List<SObject> records;
  @testVisible
  private static Map<Id, SObject> oldRecordsMap;
  @testVisible
  private static List<Rollup__mdt> rollupMetadata;
  @testVisible
  private static RollupLimit__mdt defaultRollupLimit;
  @testVisible
  private static RollupLimit__mdt specificRollupLimit;

  public static final String LIMIT_ORG_DEFAULTS = 'Org_Defaults';
  private static final String LIMIT_INITIALIZED_HERE = 'Sensible_Defaults';

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
  private final RollupInvocationPoint invokePoint;
  private final Id rollupLimitId;
  private final Decimal overrideForNumberRollups;
  private final String overrideForStringRollups;

  // non-final instance variables
  private Boolean isNoOp;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private List<SObject> lookupItems;

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

  private List<Rollup> rollups {
    get {
      if (rollups == null) {
        rollups = new List<Rollup>();
      }
      return rollups;
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

  private static final DefaultSObjectFieldInitializer FieldInitializer = new DefaultSObjectFieldInitializer();

  private enum Op {
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
    DELETE_AVERAGE
  }

  private enum RollupInvocationPoint {
    FROM_TRIGGER,
    FROM_INVOCABLE,
    FROM_SCHEDULED
  }

  private Rollup(RollupInvocationPoint invokePoint) {
    this.isBatched = true;
    // a batch only becomes valid if other Rollups are added to it
    this.isNoOp = true;
    this.invokePoint = invokePoint;
  }

  private Rollup(Rollup innerRollup) {
    this(
      innerRollup.calcItems,
      innerRollup.opFieldOnCalcItem,
      innerRollup.lookupFieldOnCalcItem,
      innerRollup.lookupFieldOnLookupObject,
      innerRollup.opFieldOnLookupObject,
      innerRollup.lookupObj,
      innerRollup.op,
      innerRollup.oldCalcItems,
      innerRollup.eval,
      innerRollup.invokePoint,
      innerRollup.rollupLimitId,
      innerRollup.overrideForNumberRollups,
      innerRollup.overrideForStringRollups
    );
    this.rollups = innerRollup.rollups;
    this.isNoOp = this.rollups.isEmpty() == false;
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
    Id rollupLimitId,
    Decimal overrideForNumberRollups,
    String overrideForStringRollups
  ) {
    this.calcItems = this.filter(calcItems, eval);
    this.eval = eval;
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.lookupFieldOnCalcItem = lookupFieldOnCalcItem;
    this.lookupFieldOnLookupObject = lookupFieldOnLookupObject;
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.lookupObj = lookupObj;
    this.op = op;
    this.oldCalcItems = oldCalcItems;
    this.isNoOp = this.calcItems.isEmpty();
    this.isBatched = false;
    this.invokePoint = invokePoint;
    this.rollupLimitId = rollupLimitId;
    this.overrideForNumberRollups = overrideForNumberRollups;
    this.overrideForStringRollups = overrideForStringRollups;
  }

  public interface Evaluator {
    Boolean matches(Object calcItem);
  }

  public class SObjectChangedFieldEvaluator implements Evaluator {
    private final List<String> changedFieldNames;
    private final Map<Id, SObject> oldRecordsMap;
    public SObjectChangedFieldEvaluator(List<String> changedFieldNames, Map<Id, SObject> oldRecordsMap) {
      this.changedFieldNames = changedFieldNames;
      this.oldRecordsMap = oldRecordsMap;
    }

    public Boolean matches(Object calcItem) {
      SObject calcSObject = (SObject) calcItem;
      SObject oldRecord = oldRecordsMap.get(calcSObject.Id);
      Boolean matches = this.changedFieldNames.isEmpty() || this.oldRecordsMap == null;
      for (String fieldName : this.changedFieldNames) {
        // need to trim because list can be comma-separated with leading/trailing spaces
        if (calcSObject.get(fieldName.trim()) != oldRecord.get(fieldName.trim())) {
          matches = true;
          break;
        }
      }
      return matches;
    }
  }

  public void runCalc() {
    RollupLimit__mdt orgDefaults = this.getSingleLimitOrDefault('DeveloperName', LIMIT_ORG_DEFAULTS, defaultRollupLimit);
    // side effect in the below method - rollups can be removed from this.rollups if a limit record ShouldAbortRun__c == true
    this.ingestRollupLimitData(orgDefaults);

    this.isNoOp = this.rollups.isEmpty();
    if (this.isNoOp || orgDefaults.ShouldAbortRun__c) {
      return;
    }

    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupLimit__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
    Boolean hasMoreThanOneTarget = false;
    SObjectType targetType;
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();
    for (Rollup rollup : this.rollups) {
      if (targetType == null) {
        targetType = rollup.lookupObj;
      } else if (rollup.lookupObj != targetType) {
        hasMoreThanOneTarget = true;
      }

      Set<String> uniqueLookupFields = new Set<String>();
      for (SObject calcItem : rollup.calcItems) {
        uniqueLookupFields.add((String) calcItem.get(rollup.lookupFieldOnCalcItem));
      }

      String countQuery = getCountQueryString(rollup.lookupObj, '=');
      if (queryCountsToLookupIds.containsKey(countQuery)) {
        queryCountsToLookupIds.get(countQuery).addAll(uniqueLookupFields);
      } else {
        queryCountsToLookupIds.put(countQuery, uniqueLookupFields);
      }
    }

    Integer totalCountOfRecords = 0;
    for (String countQuery : queryCountsToLookupIds.keySet()) {
      Set<String> objIds = queryCountsToLookupIds.get(countQuery);
      totalCountOfRecords += Database.countQuery(countQuery);
    }

    Boolean shouldRunAsBatch = shouldRunAsBatch || (orgDefaults.ShouldRunAsBatchable__c && totalCountOfRecords >= orgDefaults.MaxLookupRowsBeforeBatching__c);
    if (shouldRunAsBatch && hasMoreThanOneTarget == false) {
      // safe to batch because the QueryLocator will only return one type of SObject
      Database.executeBatch(new Rollup(this));
    } else if (
      shouldRunAsBatch == false && (orgDefaults.MaxLookupRowsForQueueable__c == null || totalCountOfRecords <= orgDefaults.MaxLookupRowsForQueueable__c)
    ) {
      System.enqueueJob(this);
    } else {
      throw new AsyncException(
        'Number of records that would be rolled up : ' +
        totalCountOfRecords +
        ' exceeds safety threshold, or you tried to run this in Batch mode with more than one target type. (' +
        hasMoreThanOneTarget +
        ')'
      );
    }
  }

  protected virtual List<SObject> getExistingLookupItems(Set<String> objIds, Rollup rollup, Set<String> uniqueQueryFieldNames) {
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute method"
    return this.lookupItems;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    /**
     * for batch, we know 100% for sure there's only 1 SObjectType / Set<String> in the map.
     * NB: we have to call "getFieldNamesForRollups" in both the "start" and "execute" methods because
     * trying to use Database.Stateful on the top-level class ** in addition to Batchable ** results in the dreaded:
     * "System.AsyncException: Queueable cannot be implemented with other system interfaces" exception
     */
    this.getFieldNamesForRollups();
    String query;
    Set<String> objIds = new Set<String>();
    for (Rollup rollup : this.rollups) {
      objIds.addAll(this.getCalcItemsByLookupField(rollup).keySet());
    }
    for (SObjectType sObjectType : this.lookupObjectToUniqueFieldNames.keySet()) {
      query = this.getQueryString(sObjectType, this.lookupObjectToUniqueFieldNames.get(sObjectType), this.rollups[0].lookupFieldOnLookupObject);
    }
    return Database.getQueryLocator(query);
  }

  public void execute(Database.BatchableContext context, List<SObject> lookupItems) {
    for (Rollup rollup : this.rollups) {
      this.initializeRollupFieldDefaults(lookupItems, rollup);
    }
    this.lookupItems = lookupItems;
    this.processAsync();
  }

  public void finish(Database.BatchableContext context) {
    // simply to conform to the demands of the interface; we don't really have any further book-keeping to do once
    // rolling up has concluded - you can always customize this as needed
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
      Id rollupLimitId,
      RollupInvocationPoint rollupInvokePoint,
      Decimal overrideForNumberRollups,
      String overrideForStringRollups
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
        rollupLimitId,
        overrideForNumberRollups,
        overrideForStringRollups
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
      String queryString = this.getQueryString(rollup.lookupObj, uniqueQueryFieldNames, rollup.lookupFieldOnLookupObject);
      List<SObject> lookupItems = Database.query(queryString);
      this.initializeRollupFieldDefaults(lookupItems, rollup);
      return lookupItems;
    }

    public void execute(System.QueueableContext qc) {
      this.processAsync();
    }
  }

  /**
   * public facing Rollup calculation section
   * - Trigger operations
   * - Batch (multiple Rollup operations chained into one job)
   * - Invocable
   */

  public class FlowInput {
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)' required=true)
    public List<SObject> recordsToRollup;

    @InvocableVariable(label='Rollup target\'s SObject Name' description='The API Name of the SObject where the rollup value will be stored.' required=true)
    public String rollupSObjectName;

    @InvocableVariable(label='Rollup Operation' description='SUM, COUNT, COUNT_DISTINCT, MAX, MIN, AVG, CONCAT' required=true)
    public String rollupOperation;

    @InvocableVariable(label='Rollup Context' description='INSERT, UPDATE, UPSERT, or DELETE' required=true)
    public String rollupContext;

    @InvocableVariable(label='Calc Item Rollup Field' description='The API Name of the field on each of the records passed in to consider.' required=true)
    public String rollupFieldOnCalcItem;

    @InvocableVariable(
      label='Rollup Object Field'
      description='The API Name of the field on the target object where the rollup value will be stored'
      required=true
    )
    public String rollupFieldOnOpObject;

    @InvocableVariable(
      label='Lookup Field On Calc Item'
      description='The API Name of the field on the record to rollup that matches a field on the object where the rollup will be stored'
      required=true
    )
    public String lookupFieldOnCalcItem;

    @InvocableVariable(
      label='Lookup Field On Rollup Object'
      description='The API Name of the field on the SObject matching the value found in "lookupFieldOnCalcItem" where the rollup will be stored'
      required=true
    )
    public String lookupFieldOnOpObject;

    // optional fields
    @InvocableVariable(
      label='Calc Item Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    public String calcItemChangedFields;

    @InvocableVariable(
      label='Full Recalculation Default Number Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for number-based rollups'
    )
    public Decimal fullRecalculationDefaultNumberValue;
    @InvocableVariable(
      label='Full Recalculation Default String Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for String-based rollups'
    )
    public String fullRecalculationDefaultStringValue;
  }

  public class FlowOutput {
    public FlowOutput() {
      this.isSuccess = true;
      this.Message = 'SUCCESS';
    }

    @InvocableVariable(label='Is Success' description='Was rollup enqueued successfully?')
    public Boolean isSuccess;
    @InvocableVariable(label='Status Message' description='"SUCCESS" when isSuccess is true, otherwise the encountered error message')
    public String message;
  }

  @InvocableMethod(
    category='Rollups'
    label='Perform rollup on records'
    description='Returns a single FlowOutput record with "SUCCESS" as the message if async rollup operation is enqueued successfully, and the encountered error otherwise'
  )
  public static List<FlowOutput> performRollup(List<FlowInput> flowInputs) {
    List<FlowOutput> flowOutputReturns = new List<FlowOutput>();
    List<Rollup> rollups = new List<Rollup>();

    try {
      Map<Id, SObject> calcItems = new Map<Id, SObject>();
      FlowInput firstInput = flowInputs.isEmpty() == false ? flowInputs[0] : new FlowInput();
      String rollupContext = getFlowRollupContext(firstInput);

      for (FlowInput flowInput : flowInputs) {
        FlowOutput flowOutput = new FlowOutput();
        flowOutputReturns.add(flowOutput);

        if (flowInput.recordsToRollup.isEmpty()) {
          continue;
        }

        SObjectType sObjectType = flowInput.recordsToRollup[0].getSObjectType();

        Rollup__mdt rollupMeta = new Rollup__mdt(
          RollupFieldOnCalcItem__c = flowInput.rollupFieldOnCalcItem,
          LookupObject__c = flowInput.rollupSObjectName,
          LookupFieldOnCalcItem__c = flowInput.lookupFieldOnCalcItem,
          LookupFieldOnLookupObject__c = flowInput.lookupFieldOnOpObject,
          RollupFieldOnLookupObject__c = flowInput.rollupFieldOnOpObject,
          RollupType__c = rollupContext + flowInput.rollupOperation,
          ChangedFieldsOnCalcItem__c = flowInput.calcItemChangedFields,
          FullRecalculationDefaultNumberValue__c = flowInput.fullRecalculationDefaultNumberValue,
          FullRecalculationDefaultStringValue__c = flowInput.fullRecalculationDefaultStringValue
        );
        Map<Id, SObject> oldFlowRecords = getOldFlowRecords(flowInput.recordsToRollup, sObjectType);
        rollups.add(
          getRollup(new List<Rollup__mdt>{ rollupMeta }, sObjectType, flowInput.recordsToRollup, oldFlowRecords, null, RollupInvocationPoint.FROM_INVOCABLE)
        );
      }
      batch(rollups);
    } catch (Exception ex) {
      for (FlowOutput flowOutput : flowOutputReturns) {
        flowOutput.IsSuccess = false;
        flowOutput.Message = ex.getMessage() + '\n' + ex.getStackTraceString();
      }
    }

    return flowOutputReturns;
  }

  /** Static public methods and helper methods */

  public static Id schedule(String jobName, String cronExp, String query, List<Id> rollupMetadataIds, Evaluator eval) {
    RollupSchedulable scheduledRollup = new RollupSchedulable(query, rollupMetadataIds, eval);
    return System.schedule(jobName, cronExp, scheduledRollup);
  }

  public static void batch(Rollup rollup, Rollup secondRollup) {
    batch(new List<Rollup>{ rollup, secondRollup });
  }

  public static void batch(Rollup rollup, Rollup secondRollup, Rollup thirdRollup) {
    batch(new List<Rollup>{ rollup, secondRollup, thirdRollup });
  }

  public static void batch(List<Rollup> rollups) {
    Rollup batchRollup = new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER);
    flattenBatches(batchRollup, rollups);
    batchRollup.runCalc();
  }

  public static Rollup averageFromTrigger(
    SObjectField averageFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField averageFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return averageFromTrigger(
      averageFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      averageFieldOnOperationObject,
      lookupSobjectType,
      null
    );
  }

  public static Rollup averageFromTrigger(
    SObjectField averageFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(
      averageFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      sumFieldOnOpOject,
      lookupSobjectType,
      Op.AVERAGE,
      eval
    );
  }

  public static Rollup countDistinctFromTrigger(
    SObjectField countDistinctFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countDistinctFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return countDistinctFromTrigger(
      countDistinctFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countDistinctFieldOnOperationObject,
      lookupSobjectType,
      null
    );
  }

  public static Rollup countDistinctFromTrigger(
    SObjectField countDistinctFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countDistinctFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(
      countDistinctFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      countDistinctFieldOnOperationObject,
      lookupSobjectType,
      Op.COUNT_DISTINCT,
      eval
    );
  }

  public static Rollup concatDistinctFromTrigger(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return concatDistinctFromTrigger(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      null
    );
  }

  public static Rollup concatDistinctFromTrigger(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT_DISTINCT,
      eval
    );
  }

  public static Rollup concatFromTrigger(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return concatFromTrigger(concatFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, concatFieldOnOperationObject, lookupSobjectType, null);
  }

  public static Rollup concatFromTrigger(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(
      concatFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      concatFieldOnOperationObject,
      lookupSobjectType,
      Op.CONCAT,
      eval
    );
  }

  public static Rollup countFromTrigger(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return countFromTrigger(countFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, countFieldOnOperationObject, lookupSobjectType, null);
  }

  public static Rollup countFromTrigger(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(countFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, Op.COUNT, eval);
  }

  public static Rollup maxFromTrigger(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return maxFromTrigger(maxFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, maxFieldOnOperationObject, lookupSobjectType, null);
  }

  public static Rollup maxFromTrigger(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(
      maxFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnOperationObject,
      maxFieldOnOperationObject,
      lookupSobjectType,
      Op.MAX,
      eval
    );
  }

  public static Rollup minFromTrigger(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return minFromTrigger(minFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, minFieldOnOperationObject, lookupSobjectType, null);
  }

  public static Rollup minFromTrigger(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(minFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, minFieldOnOpOject, lookupSobjectType, Op.MIN, eval);
  }

  public static Rollup sumFromTrigger(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(sumFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, Op.SUM, eval);
  }

  public static Rollup sumFromTrigger(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType
  ) {
    return sumFromTrigger(sumFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, null);
  }

  private static Rollup operateFromTrigger(
    SObjectField operationFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField operationFieldOnOperationObject,
    SObjectType lookupSObjectType,
    Op rollupOperation,
    Evaluator eval
  ) {
    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupFieldOnCalcItem__c = operationFieldOnCalcItem.getDescribe().getName(),
      LookupObject__c = String.valueOf(lookupSObjectType),
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem.getDescribe().getName(),
      LookupFieldOnLookupObject__c = lookupFieldOnOperationObject.getDescribe().getName(),
      RollupFieldOnLookupObject__c = operationFieldOnOperationObject.getDescribe().getName(),
      RollupType__c = rollupOperation.name()
    );
    return runFromTrigger(new List<Rollup__mdt>{ rollupMetadata }, eval);
  }

  public static void runFromTrigger() {
    SObjectType sObjectType = getTriggerRecords().getSObjectType();
    List<Rollup__mdt> rollupMetadata = getTriggerRollupMetadata(sObjectType);
    runFromTrigger(rollupMetadata, null).runCalc();
  }

  private static Rollup runFromTrigger(List<Rollup__mdt> rollupMetadata, Evaluator eval) {
    if (shouldRunFromTrigger() == false) {
      return new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER);
    }

    List<SObject> calcItems = getTriggerRecords();
    SObjectType sObjectType = calcItems.getSObjectType();

    String rollupContext;
    Boolean shouldReturn = false;
    Map<Id, SObject> oldCalcItems;

    switch on triggerContext {
      when AFTER_UPDATE {
        rollupContext = 'UPDATE_';
        oldCalcItems = getOldTriggerRecordsMap();
      }
      when BEFORE_DELETE {
        rollupContext = 'DELETE_';
        oldCalcItems = getOldTriggerRecordsMap();
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
      rollupInfo.RollupType__c = rollupContext + rollupInfo.RollupType__c;
    }

    return shouldReturn
      ? new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER)
      : getRollup(rollupMetadata, sObjectType, calcItems, oldCalcItems, eval, RollupInvocationPoint.FROM_TRIGGER);
  }

  /** end public-facing section, begin private static helpers */

  private static String getCountQueryString(SObjectType sObjectType, String equalityOperatorForIds) {
    return 'SELECT Count() FROM ' + sObjectType + ' WHERE Id ' + equalityOperatorForIds + ' :objIds';
  }

  private static void flattenBatches(Rollup outerRollup, List<Rollup> rollups) {
    for (Rollup rollup : rollups) {
      if (rollup.isBatched || rollup.rollups.isEmpty() == false) {
        // recurse through lists until there aren't any more nested batch types
        flattenBatches(outerRollup, rollup.rollups);
      } else {
        loadRollups(rollup, outerRollup);
      }
    }
  }

  private static String getFlowRollupContext(FlowInput firstInput) {
    String flowContext = firstInput.rollupContext;
    if (String.isBlank(flowContext)) {
      flowContext = 'INSERT';
    } else if (flowContext == 'UPSERT') {
      flowContext = 'UPDATE';
    }

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static Map<Id, SObject> getOldFlowRecords(List<SObject> currentRecords, SObjectType sObjectType) {
    if (currentRecords.isEmpty()) {
      return new Map<Id, SObject>();
    } else if (oldRecordsMap != null) {
      return oldRecordsMap;
    }

    Set<String> fieldNames = currentRecords[0].getPopulatedFieldsAsMap().keySet();
    Set<Id> currentRecordIds = new Set<Id>();
    for (SObject currentRecord : currentRecords) {
      if (currentRecord.Id != null) {
        currentRecordIds.add(currentRecord.Id);
      }
    }
    // we need to do two things: get the old records, and initialize default values for both existing records and the ones that don't have matches in the db
    Map<Id, SObject> existingOldRecordsMap = new Map<Id, SObject>(
      Database.query('SELECT ' + String.join(new List<String>(fieldNames), ',') + '\nFROM ' + String.valueOf(sObjectType) + '\nWHERE Id = :currentRecordIds')
    );
    for (SObject currentRecord : currentRecords) {
      DescribeSObjectResult sObjectDescribe = sObjectType.getDescribe();
      SObject existingRecordOrDefault = currentRecord.Id != null && existingOldRecordsMap.containsKey(currentRecord.Id)
        ? existingOldRecordsMap.get(currentRecord.Id)
        : (SObject) Type.forName(sObjectDescribe.getName()).newInstance();
      Map<String, SObjectField> fieldTokensForObject = sObjectDescribe.fields.getMap();
      for (String fieldName : fieldNames) {
        SObjectField fieldToken = fieldTokensForObject.get(fieldName);
        if (fieldToken.getDescribe().isUpdateable() == false) {
          continue;
        }
        if (existingRecordOrDefault.get(fieldName) == null) {
          existingRecordOrDefault.put(fieldName, FieldInitializer.getDefaultValue(fieldTokensForObject.get(fieldName)));
        }
      }
    }
    return existingOldRecordsMap;
  }

  private static List<Rollup__mdt> getTriggerRollupMetadata(SObjectType sObjectType) {
    // Even after Spring '21, can't call .getAll here because the ApiName restriction would disallow multiple rules per SObject
    return rollupMetadata != null
      ? rollupMetadata
      : [
          SELECT
            CalcItem__c,
            RollupFieldOnCalcItem__c,
            LookupObject__c,
            LookupFieldOnCalcItem__c,
            RollupFieldOnLookupObject__c,
            RollupType__c,
            ChangedFieldsOnCalcItem__c,
            FullRecalculationDefaultNumberValue__c,
            FullRecalculationDefaultStringValue__c
          FROM Rollup__mdt
          WHERE CalcItem__c = :String.valueOf(sObjectType)
        ];
  }

  private static Rollup getRollup(
    List<Rollup__mdt> rollupOperations,
    SObjectType sObjectType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    RollupInvocationPoint rollupInvokePoint
  ) {
    if (rollupOperations.isEmpty()) {
      return new RollupAsyncProcessor(rollupInvokePoint);
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
      Op rollupOp = opNameToOp.get(rollupMetadata.RollupType__c);
      SObjectField rollupFieldOnCalcItem = fieldNameToField.get(getParedFieldName(rollupMetadata.RollupFieldOnCalcItem__c, describeForSObject));
      SObjectField lookupFieldOnCalcItem = fieldNameToField.get(getParedFieldName(rollupMetadata.LookupFieldOnCalcItem__c, describeForSObject));

      // NB - this SHOULD work even for SObjects part of managed packages
      SObjectType lookupSObjectType = getSObjectTypeFromName(rollupMetadata.LookupObject__c);
      DescribeSObjectResult lookupObjectDescribe = lookupSObjectType.getDescribe();
      Map<String, SObjectField> lookupFieldNameToLookupFields = lookupObjectDescribe.fields.getMap();
      SObjectField lookupFieldOnOpObject = lookupFieldNameToLookupFields.get(
        getParedFieldName(rollupMetadata.LookupFieldOnLookupObject__c, lookupObjectDescribe)
      );
      SObjectField rollupFieldOnOpObject = lookupFieldNameToLookupFields.get(
        getParedFieldName(rollupMetadata.RollupFieldOnLookupObject__c, lookupObjectDescribe)
      );

      if (eval == null && String.isNotBlank(rollupMetadata.ChangedFieldsOnCalcItem__c)) {
        eval = new SObjectChangedFieldEvaluator(rollupMetadata.ChangedFieldsOnCalcItem__c.split(','), oldCalcItems);
      }

      Id rollupLimitId;
      if (rollupMetadata.Id != null) {
        // for CMDT-driven rollups, we can tie the rollup operation straight to a RollupLimit__mdt record
        rollupLimitId = [SELECT Id FROM RollupLimit__mdt WHERE Rollup__c = :rollupMetadata.Id LIMIT 1]?.Id;
      } else {
        String limitKey = getRollupLimitMetadataKey(rollupInvokePoint, rollupFieldOnCalcItem, lookupSObjectType, rollupFieldOnOpObject);
        rollupLimitId = [SELECT Id FROM RollupLimit__mdt WHERE TriggerOrInvocableName__c = :limitKey LIMIT 1]?.Id;
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
        eval,
        rollupLimitId,
        rollupInvokePoint,
        rollupMetadata.FullRecalculationDefaultNumberValue__c,
        rollupMetadata.FullRecalculationDefaultStringValue__c
      );
    }
    return batchRollup;
  }

  private static String getRollupLimitMetadataKey(
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
    if (shouldRun == null) {
      shouldRun = Trigger.isExecuting;
    }
    // there are only three allowed trigger operations that qualify
    if (
      shouldRun &&
      triggerContext != TriggerOperation.AFTER_INSERT &&
      triggerContext != TriggerOperation.AFTER_UPDATE &&
      triggerContext != TriggerOperation.BEFORE_DELETE
    ) {
      shouldRun = false;
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
    return oldRecordsMap != null ? oldRecordsMap : Trigger.oldMap;
  }

  private static SObjectType getSObjectTypeFromName(String sobjectName) {
    return ((SObject) Type.forName(sobjectName).newInstance()).getSObjectType();
  }

  private static String getParedFieldName(String fullFieldName, DescribeSObjectResult describeForSObject) {
    return String.isBlank(fullFieldName) ? '' : fullFieldName.replace(describeForSObject.getName() + '.', '');
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
    Id rollupLimitId,
    RollupInvocationPoint invokePoint,
    Decimal overrideForNumberRollups,
    String overrideForStringRollups
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
      rollupLimitId,
      invokePoint,
      overrideForNumberRollups,
      overrideForStringRollups
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

  /** End static section, begin private instance methods */

  protected void processAsync() {
    this.getFieldNamesForRollups();
    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();

    for (Rollup rollup : this.rollups) {
      Map<String, List<SObject>> calcItemsByLookupField = this.getCalcItemsByLookupField(rollup);
      List<SObject> lookupItems = new List<SObject>();
      Set<String> lookupItemKeys = new Set<String>(calcItemsByLookupField.keySet());
      for (String lookupId : calcItemsByLookupField.keySet()) {
        if (updatedLookupRecords.containsKey(lookupId)) {
          lookupItemKeys.remove(lookupId);
          // this way, the updated values are persisted for each field, and the default values are initialized
          SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
          if (updatedLookupObject.get(rollup.opFieldOnLookupObject) == null) {
            updatedLookupObject.put(rollup.opFieldOnLookupObject, FieldInitializer.getDefaultValue(rollup.opFieldOnLookupObject));
          }
          lookupItems.add(updatedLookupObject);
        }
      }
      lookupItems.addAll(this.getExistingLookupItems(lookupItemKeys, rollup, this.lookupObjectToUniqueFieldNames.get(rollup.lookupObj)));
      List<SObject> updatedRecords = this.getUpdatedLookupItemsByRollup(rollup, calcItemsByLookupField, lookupItems);

      for (SObject updatedRecord : updatedRecords) {
        updatedLookupRecords.put(updatedRecord.Id, updatedRecord);
      }
    }

    DML.doUpdate(updatedLookupRecords.values());
  }

  protected String getQueryString(SObjectType sObjectType, Set<String> uniqueQueryFieldNames, SObjectField lookupFieldOnLookupObject) {
    // again noting the coupling for consumers of this method
    // "objIds" is required to be present in the scope where the query is run
    return 'SELECT ' +
      String.join(new List<String>(uniqueQueryFieldNames), ',') +
      '\nFROM ' +
      sObjectType +
      '\nWHERE ' +
      lookupFieldOnLookupObject +
      ' = :objIds';
  }

  private List<SObject> filter(List<SObject> calcItems, Evaluator eval) {
    List<SObject> applicableItems = new List<SObject>();
    if (calcItems == null) {
      return applicableItems;
    }
    for (SObject calcItem : calcItems) {
      if (eval == null || eval.matches(calcItem)) {
        applicableItems.add(calcItem);
      }
    }
    return applicableItems;
  }

  private void getFieldNamesForRollups() {
    this.lookupObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    for (Rollup rollup : this.rollups) {
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
    }
    return lookupFieldToCalcItems;
  }

  protected void initializeRollupFieldDefaults(List<SObject> lookupItems, Rollup rollup) {
    // prior to returning, we need to ensure the default value for the rollup field is set
    for (SObject lookupItem : lookupItems) {
      if (lookupItem.get(rollup.opFieldOnLookupObject) == null) {
        lookupItem.put(rollup.opFieldOnLookupObject, FieldInitializer.getDefaultValue(rollup.opFieldOnLookupObject));
      }
    }
  }

  private RollupLimit__mdt getSingleLimitOrDefault(String whereField, String whereValue, RollupLimit__mdt testOverrideData) {
    // ugly, but OR statements on custom metadata queries results in:
    // System.QueryException: MALFORMED QUERY: Disjunctions not supported
    // which is ridiculous because they run fine in the Salesforce Developer Console!
    if (testOverrideData != null) {
      return testOverrideData;
    }
    String query = 'SELECT Id, MaxLookupRowsBeforeBatching__c, MaxLookupRowsForQueueable__c, Rollup__c, ShouldAbortRun__c, ShouldRunAsBatchable__c, ShouldRunAsQueueable__c, TriggerOrInvocableName__c FROM RollupLimit__mdt WHERE {0} LIMIT 1'
      .replace('{0}', whereField + '= \'' + whereValue + '\'');
    List<RollupLimit__mdt> rollupLimits = (List<RollupLimit__mdt>) Database.query(query);
    if (rollupLimits.isEmpty()) {
      // allow tests to override
      rollupLimits.add(this.getSensibleLimitsDefault());
    }
    return rollupLimits[0];
  }

  private RollupLimit__mdt getSensibleLimitsDefault() {
    return new RollupLimit__mdt(
      DeveloperName = LIMIT_INITIALIZED_HERE,
      MaxLookupRowsBeforeBatching__c = Limits.getLimitDmlRows() / 3,
      MaxLookupRowsForQueueable__c = Limits.getLimitDmlRows() / 2,
      ShouldAbortRun__c = false,
      ShouldRunAsBatchable__c = false,
      ShouldRunAsQueueable__c = false
    );
  }

  private void ingestRollupLimitData(RollupLimit__mdt orgDefaults) {
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      Rollup rollup = this.rollups[index];
      String limitWhereField = rollup.rollupLimitId == null ? 'TriggerOrInvocableName__c' : 'Id';
      String limitWhereValue = rollup.rollupLimitId == null
        ? getRollupLimitMetadataKey(rollup.invokePoint, rollup.opFieldOnCalcItem, rollup.lookupObj, rollup.opFieldOnLookupObject)
        : rollup.rollupLimitId;
      RollupLimit__mdt limitSpecificToRollup = this.getSingleLimitOrDefault(limitWhereField, limitWhereValue, specificRollupLimit);

      if (limitSpecificToRollup.ShouldAbortRun__c) {
        this.rollups.remove(index);
      } else if (limitSpecificToRollup.ShouldRunAsBatchable__c && shouldRunAsBatch == false) {
        shouldRunAsBatch = true;
      } else if (limitSpecificToRollup.ShouldRunAsQueueable__c) {
        // once you've been opted into batching, it should stick
        shouldRunAsBatch = shouldRunAsBatch || false;
      }

      // you can increase the default limits, but it would be too messy to try to rank the individual rollup operations in a batched context
      if (limitSpecificToRollup.MaxLookupRowsBeforeBatching__c > orgDefaults.MaxLookupRowsBeforeBatching__c) {
        orgDefaults.MaxLookupRowsBeforeBatching__c = limitSpecificToRollup.MaxLookupRowsBeforeBatching__c;
      }
      if (limitSpecificToRollup.MaxLookupRowsForQueueable__c > orgDefaults.MaxLookupRowsForQueueable__c) {
        orgDefaults.MaxLookupRowsForQueueable__c = limitSpecificToRollup.MaxLookupRowsForQueueable__c;
      }
    }
  }

  private List<SObject> getUpdatedLookupItemsByRollup(Rollup rollup, Map<String, List<SObject>> calcItemsByLookupField, List<SObject> lookupItems) {
    List<SObject> recordsToUpdate = new List<SObject>();
    for (SObject lookupRecord : lookupItems) {
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        List<SObject> calcItems = calcItemsByLookupField.get(key);
        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(rollup, calcItems, priorVal);
        lookupRecord.put(rollup.opFieldOnLookupObject, newVal);
        if (priorVal != newVal) {
          recordsToUpdate.add(lookupRecord);
        }
      }
    }

    return recordsToUpdate;
  }

  private Object getRollupVal(Rollup rollup, List<SObject> calcItems, Object priorVal) {
    RollupCalculator rollupCalc = this.getRollupType(priorVal, rollup);
    rollupCalc.performRollup(rollup.op, priorVal, calcItems, rollup.oldCalcItems, rollup.opFieldOnCalcItem);
    return rollupCalc.getReturnValue();
  }

  private RollupCalculator getRollupType(Object priorVal, Rollup roll) {
    if (roll.op.name().contains(Rollup.Op.COUNT_DISTINCT.name())) {
      return new CountDistinctRollupCalculator(0, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (roll.op.name().contains(Rollup.Op.COUNT.name())) {
      return new CountRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (roll.op.name().contains(Rollup.Op.AVERAGE.name())) {
      return new AverageRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (priorVal instanceof Decimal) {
      return new DecimalRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (priorVal instanceof String) {
      return new PicklistRollupCalculator(priorVal, roll.opFieldOnCalcItem, roll.overrideForStringRollups);
    } else if (priorVal instanceof Date) {
      // not obvious: the order of these else if's is of supreme importance
      // Date has to go before Datetime; in the same way that all numbers test true as an instanceof Decimal
      // all Dates test true as Datetimes ...
      return new DateRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (priorVal instanceof Time) {
      return new TimeRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else if (priorval instanceof Datetime) {
      return new DatetimeRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups);
    } else {
      throw new IllegalArgumentException('Calculation not defined for: ' + JSON.serialize(priorVal));
    }
  }

  @testVisible
  private virtual class DMLHelper {
    public virtual void doUpdate(List<SObject> recordsToUpdate) {
      update recordsToUpdate;
    }
  }

  private virtual class DefaultSObjectFieldInitializer {
    public final Datetime defaultDateTime = Datetime.newInstanceGmt(1970, 1, 1);
    public final Long maximumLongValue = (Math.pow(2, 63) - 1).longValue();
    public final Long minimumLongValue = this.maximumLongValue * -1;
    public final Integer maximumIntegerValue = 2147483647;
    public final Integer minimumIntegerValue = this.maximumIntegerValue * -1;

    public virtual Object getDefaultValue(SObjectField field) {
      DescribeFieldResult fieldDescribe = field.getDescribe();
      if (fieldDescribe.isDefaultedOnCreate()) {
        return fieldDescribe.getDefaultValue();
      }
      // not surprisingly, "getDefaultValue" on the DescribeFieldResult returns null for fields without default values
      // this is a shame - all types *should* have default values. Instead, we have the privilege of getting to initialize them
      Object initializedDefault;
      switch on fieldDescribe.getType() {
        when CURRENCY, DOUBLE, INTEGER, LONG, PERCENT {
          initializedDefault = 0;
        }
        when DATETIME {
          initializedDefault = this.defaultDateTime;
        }
        when DATE {
          initializedDefault = this.defaultDateTime.dateGmt();
        }
        when TIME {
          initializedDefault = this.defaultDateTime.timeGmt();
        }
        when STRING, ID, TEXTAREA, URL, PHONE, EMAIL, REFERENCE {
          initializedDefault = '';
        }
        when PICKLIST, MULTIPICKLIST {
          initializedDefault = new PicklistController(fieldDescribe).getDefaultValue(field);
        }
        when else {
          throw new IllegalArgumentException('Field: ' + field + ' of type: ' + fieldDescribe.getType().name() + ' specified invalid for rollup operation');
        }
      }
      return initializedDefault;
    }
  }

  private class PicklistController extends DefaultSObjectFieldInitializer {
    private final Boolean isPicklist;
    private final Boolean isMultiSelectPicklist;
    private List<String> activeVals;
    private Map<String, Integer> picklistToRank;

    public PicklistController(DescribeFieldResult fieldDescribe) {
      DisplayType fieldType = fieldDescribe.getType();
      this.isPicklist = fieldType == DisplayType.MULTIPICKLIST || fieldType == DisplayType.PICKLIST;
      this.isMultiSelectPicklist = fieldType == DisplayType.MULTIPICKLIST;

      if (this.isPicklist) {
        this.picklistToRank = new Map<String, Integer>();
        this.activeVals = new List<String>();

        /**
         * not obvious (or even documented) but getPicklistValues ALWAYS returns
         * the picklist values in order of their appearance in the UI, which is also
         * their alleged "rank" - for example, MAX/MIN on picklists is done by which order they appear
         * in the list, instead of by the actual text values
         * */
        List<Schema.PicklistEntry> picklistVals = fieldDescribe.getPicklistValues();
        if (picklistVals.isEmpty()) {
          this.activeVals.add('');
          return;
        }
        /**
         * typically, you iterate through a list in reverse in order to remove something from it
         * here, we don't want to iterate in reverse, we want to take the inverted index of the list so
         * the logic in "isTrueFor" more compelling; an item at the end of the reversed list has GREATER
         * "importance" (in rank) than an item at the start.
         */

        for (Integer index = 0; index < picklistVals.size(); index++) {
          PicklistEntry picklist = picklistVals[index];
          this.doBookkeepingOnPicklist(picklist);
          // all inactive values will use -1 as a sentinel value
          picklistToRank.put(picklist.getValue(), picklist.isActive() ? index : -1);
        }
      }
    }

    private void doBookkeepingOnPicklist(PicklistEntry picklist) {
      if (picklist.isDefaultValue() && this.activeVals.isEmpty()) {
        this.activeVals.add(picklist.getValue());
      } else if (picklist.isDefaultValue() && this.activeVals.isEmpty() == false) {
        this.activeVals.add(0, picklist.getValue());
      } else if (picklist.isActive()) {
        this.activeVals.add(picklist.getValue());
      }
    }

    public override Object getDefaultValue(SObjectField field) {
      if (this.isPicklist == false) {
        return super.getDefaultValue(field);
      }

      return this.activeVals[0];
    }

    public Boolean isPicklist() {
      return this.isPicklist;
    }

    public Boolean isMultiSelectPicklist() {
      return this.isMultiSelectPicklist;
    }

    public Boolean isTrueFor(String picklistVal, String comparisonValue, Op operation) {
      if (this.isPicklist == false) {
        return false;
      }
      Boolean isMin = this.isMin(operation);
      if (String.isNotBlank(comparisonValue) && this.picklistToRank.containsKey(picklistVal) == false) {
        return isMin ? picklistVal < comparisonValue : picklistVal > comparisonValue;
      }
      Integer rank = this.getRank(picklistVal, operation);
      Integer comparisonRank = this.getRank(comparisonValue, operation);
      return isMin ? rank < comparisonRank : rank > comparisonRank;
    }

    public Integer getRank(String picklistVal, Op operation) {
      return this.picklistToRank.containsKey(picklistVal) ? this.picklistToRank.get(picklistVal) : this.getSentinelValue(operation);
    }

    private Boolean isMin(Op operation) {
      return operation.name().contains(Op.MIN.name());
    }

    private Integer getSentinelValue(Op operation) {
      return this.isMin(operation) ? this.maximumIntegerValue : this.minimumIntegerValue;
    }
  }

  private abstract class RollupCalculator {
    protected Boolean shouldShortCircuit = false;
    protected Object returnVal;
    public RollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      if (defaultVal != null) {
        this.returnVal = defaultVal;
      } else {
        this.returnVal = priorVal == null ? FieldInitializer.getDefaultValue(operationField) : priorVal;
      }
    }
    public virtual Object getReturnValue() {
      return this.returnVal;
    }
    public abstract void performRollup(Op op, Object priorVal, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField);

    protected virtual Object calculateNewAggregateValue(Set<Id> excludedItems, Op operation, SObjectField operationField, SObjectType sObjectType) {
      String operationName = operation.name().contains('_') ? operation.name().substringAfter('_') : operation.name();
      String alias = operationName.toLowerCase() + 'field';
      String query = 'SELECT ' + operationName + '(' + operationField + ')' + alias + ' FROM ' + sObjectType + ' WHERE Id != :excludedItems';
      List<SObject> aggregate = Database.query(query);
      return aggregate.isEmpty() == false ? aggregate[0].get(alias) : null;
    }
  }

  private class CountDistinctRollupCalculator extends RollupCalculator {
    private final Set<Object> distinctValues;
    public CountDistinctRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
      this.distinctValues = new Set<Object>();
      if (this.returnVal != FieldInitializer.getDefaultValue(operationfield)) {
        this.distinctValues.add(this.returnVal);
      }
    }

    public override void performRollup(Op operation, Object priorVal, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      Integer returnInt = (Integer) this.returnVal;
      for (SObject calcItem : calcItems) {
        if (this.shouldShortCircuit) {
          Object currentVal = calcItem.get(operationField);
          if (currentVal != null) {
            this.distinctValues.add(currentVal);
          }
          continue;
        }

        switch on operation {
          when COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
            if (operation != Op.DELETE_COUNT_DISTINCT && calcItem.get(operationField) != null) {
              this.distinctValues.add(calcItem.get(operationField));
            }
            this.shouldShortCircuit = true;
            this.calculateNewAggregateValue(new Set<Id>{ calcItem.Id }, operation, operationField, calcItem.getSObjectType());
          }
          when UPDATE_COUNT_DISTINCT {
            Object currentVal = calcItem.get(operationField);
            Object priorCalcVal = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : currentVal;
            if (currentVal != priorCalcVal) {
              this.distinctValues.add(currentVal);
              this.shouldShortCircuit = true;
              this.calculateNewAggregateValue(oldCalcItems.keySet(), operation, operationField, calcItem.getSObjectType());
            }
          }
        }
      }
      this.returnVal = this.distinctValues.size();
    }

    protected override Object calculateNewAggregateValue(Set<Id> excludedItems, Op operation, SObjectField operationField, SObjectType sObjectType) {
      Boolean isGroupable = operationField.getDescribe().isGroupable();
      String query =
        'SELECT ' +
        operationField +
        (isGroupable ? ', COUNT(Id)' : '') +
        ' FROM ' +
        sObjectType +
        ' WHERE Id != :excludedItems AND ' +
        operationField +
        ' != null' +
        // not every field supports grouping for counts. unlucky.
        (isGroupable ? (' GROUP BY ' + operationField) : '');
      List<SObject> results = Database.query(query);
      for (SObject res : results) {
        // have to use the String representation of the operationField to avoid:
        // System.SObjectException: SObject.FieldName does not belong to SObject type AggregateResult
        this.distinctValues.add(res.get(operationField.getDescribe().getName()));
      }
      return null;
    }
  }

  private virtual class DecimalRollupCalculator extends RollupCalculator {
    public DecimalRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
    }

    protected virtual Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      return (Decimal) (potentiallyUnitializedDecimal == null ? 0 : potentiallyUnitializedDecimal);
    }

    protected virtual Decimal getNumericValue(SObject calcItem, SObjectField operationField) {
      return this.getDecimalOrDefault(calcItem.get(operationField));
    }

    protected virtual Decimal getNumericChangedValue(SObject calcItem, SObjectfield operationField, Map<Id, SObject> oldCalcItems) {
      Decimal newVal = this.getNumericValue(calcItem, operationField);
      Decimal oldVal = this.getNumericValue((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem), operationField);
      // could be negative, could be positive ... could be 0!
      return newVal - oldVal;
    }

    public virtual override Object getReturnValue() {
      Decimal potentialReturnValue = (Decimal) this.returnVal;
      if (potentialReturnValue == FieldInitializer.maximumLongValue || potentialReturnValue == FieldInitializer.minimumLongValue) {
        this.returnVal = 0;
      }
      return this.returnVal;
    }

    public override void performRollup(Op operation, Object priorVal, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      Decimal returnDecimal = (Decimal) this.returnVal;
      for (SObject calcItem : calcItems) {
        if (this.shouldShortCircuit) {
          switch on operation {
            when UPDATE_MAX {
              // re-maxing by way of query has occurred, but is it **correct**?
              // if one of the other updated calcItems is numerically superior, assign the new max
              Decimal newVal = this.getNumericValue(calcItem, operationField);
              if (newVal > returnDecimal) {
                returnDecimal = newVal;
              }
            }
            when UPDATE_MIN {
              // re-"min"-ing has occurred by way of query, but is an in-memory calcItem even less?
              Decimal newVal = this.getNumericValue(calcItem, operationField);
              if (newVal < returnDecimal) {
                returnDecimal = newVal;
              }
            }
          }
          continue;
        }

        switch on operation {
          when SUM, COUNT {
            returnDecimal += this.getNumericValue(calcItem, operationField);
          }
          when DELETE_SUM, DELETE_COUNT {
            returnDecimal -= this.getNumericValue(calcItem, operationField);
          }
          when UPDATE_SUM, UPDATE_COUNT {
            returnDecimal += this.getNumericChangedValue(calcItem, operationField, oldCalcItems);
          }
          when MAX {
            Decimal numericValue = this.getNumericValue(calcItem, operationField);
            if (numericValue > returnDecimal || returnDecimal == 0) {
              returnDecimal = numericValue;
            }
          }
          when MIN {
            Decimal numericValue = this.getNumericValue(calcItem, operationField);
            if (numericValue < returnDecimal || returnDecimal == 0) {
              returnDecimal = numericValue;
            }
          }
          when UPDATE_MAX, UPDATE_MIN, DELETE_MAX, DELETE_MIN {
            Decimal newVal = this.getNumericValue(calcItem, operationField);
            Decimal thisPriorVal = this.getNumericValue((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem), operationField);
            if (
              (operation.name().contains(Op.MAX.name()) && thisPriorVal != 0 && thisPriorVal == returnDecimal && newVal <= thisPriorVal) ||
              (operation.name().contains(Op.MIN.name()) &&
              thisPriorVal != 0 &&
              thisPriorVal == returnDecimal &&
              newVal >= thisPriorVal)
            ) {
              this.shouldShortCircuit = true;
              Object potentialReturnValue = (Decimal) this.calculateNewAggregateValue(
                oldCalcItems.keySet(),
                operation,
                operationField,
                calcItem.getSObjectType()
              );
              returnDecimal = this.getDecimalOrDefault(potentialReturnValue);
              if (returnDecimal == 0) {
                returnDecimal = operation == Op.UPDATE_MAX ? FieldInitializer.minimumLongValue : FieldInitializer.maximumLongValue;
              }
            } else if (operation == Op.UPDATE_MAX && newVal > returnDecimal) {
              returnDecimal = newVal;
            } else if (operation == Op.UPDATE_MIN && newVal < returnDecimal || returnDecimal == 0) {
              returnDecimal = newVal;
            }
          }
        }
      }
      this.returnVal = returnDecimal;
    }

    protected virtual override Object calculateNewAggregateValue(Set<Id> excludedItems, Op operation, SObjectField operationField, SObjectType sObjectType) {
      Object aggregate;
      try {
        aggregate = super.calculateNewAggregateValue(excludedItems, operation, operationField, sObjectType);
      } catch (Exception ex) {
        Decimal minOrMax;
        List<SObject> allOtherItems = Database.query('SELECT ' + operationField + ' FROM ' + sObjectType + ' WHERE Id != :excludedItems');
        for (SObject otherItem : allOtherItems) {
          Decimal otherItemDate = this.getDecimalOrDefault(otherItem.get(operationField));
          if (otherItemDate != null && operation.name().contains(Op.MAX.name()) && (minOrMax == null || otherItemDate > minOrMax)) {
            minOrMax = otherItemDate;
          } else if (otherItemDate != null && operation.name().contains(Op.MIN.name()) && (minOrMax == null || otherItemDate < minOrMax)) {
            minOrMax = otherItemDate;
          }
        }
        if (minOrMax == null) {
          aggregate = operation.name().contains(Op.MIN.name()) ? FieldInitializer.maximumLongValue : FieldInitializer.minimumLongValue;
        } else {
          aggregate = minOrMax;
        }
      }

      return aggregate;
    }
  }

  private virtual class DatetimeRollupCalculator extends DecimalRollupCalculator {
    public DatetimeRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(((Datetime) priorVal).getTime(), operationField, defaultVal);
    }

    public virtual override Object getReturnValue() {
      Object superReturnVal = super.getReturnValue();
      if (superReturnVal instanceof Decimal) {
        return Datetime.newInstance(((Decimal) superReturnVal).longValue());
      }
      return superReturnVal;
    }

    protected virtual override Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      if (potentiallyUnitializedDecimal == null) {
        return FieldInitializer.defaultDateTime.getTime();
      }
      // one of the worst things about SOQL is that Datetimes retrieved have the millisecond values truncated
      Datetime datetimeWithMs = potentiallyUnitializedDecimal instanceof Decimal
        ? Datetime.newInstance(((Decimal) potentiallyUnitializedDecimal).longValue())
        : ((Datetime) potentiallyUnitializedDecimal);
      return Datetime.newInstanceGmt(
          datetimeWithMs.yearGmt(),
          datetimeWithMs.monthGmt(),
          datetimeWithMs.dayGmt(),
          datetimeWithMs.hourGmt(),
          datetimeWithMs.minuteGmt(),
          datetimeWithMs.secondGmt()
        )
        .getTime();
    }

    protected override Object calculateNewAggregateValue(Set<Id> excludedItems, Op operation, SObjectField operationField, SObjectType sObjectType) {
      Object aggregate = super.calculateNewAggregateValue(excludedItems, operation, operationField, sObjectType);
      if (aggregate instanceof Datetime) {
        aggregate = ((Datetime) aggregate).getTime();
      }

      return aggregate;
    }
  }

  private class DateRollupCalculator extends DatetimeRollupCalculator {
    // for Date, it's not necessary to override the "getDecimalOrDefault" method in DatetimeRollupCalculator
    // because the conversion only happens in "getReturnValue"
    public DateRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(Datetime.newInstanceGmt((Date) priorVal, Time.newInstance(0, 0, 0, 0)), operationField, defaultVal);
    }

    public override Object getReturnValue() {
      return ((Datetime) super.getReturnValue()).dateGmt();
    }
  }

  private class TimeRollupCalculator extends DatetimeRollupCalculator {
    public TimeRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(Datetime.newInstanceGmt(FieldInitializer.defaultDateTime.dateGmt(), (Time) priorVal), operationField, defaultVal);
    }

    public override Object getReturnValue() {
      return ((Datetime) super.getReturnValue()).timeGmt();
    }

    protected override Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      Datetime defaultDatetime;
      if (potentiallyUnitializedDecimal instanceof Time) {
        defaultDatetime = Datetime.newInstanceGmt(FieldInitializer.defaultDateTime.dateGmt(), (Time) potentiallyUnitializedDecimal);
      } else if (potentiallyUnitializedDecimal instanceof Decimal) {
        defaultDatetime = Datetime.newInstance(((Decimal) potentiallyUnitializedDecimal).longValue());
      } else {
        defaultDatetime = FieldInitializer.defaultDateTime;
      }
      return defaultDatetime.getTime();
    }
  }

  private class CountRollupCalculator extends DecimalRollupCalculator {
    private final Integer existingValue;
    public CountRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
      // cache existing value to ensure we don't dip below 0 in "getReturnValue"
      this.existingValue = Integer.valueOf(this.returnVal);
    }

    public override Object getReturnValue() {
      // we shouldn't encourage negative counts. it's totally possible as a rollup is implemented and updates happen before
      // inserts or deletes, but it doesn't really make sense in the context of tracking
      Integer potentialReturnVal = Integer.valueOf((Decimal) super.getReturnValue());
      return potentialReturnVal - this.existingValue < 0 ? 0 : potentialReturnVal;
    }

    protected override Decimal getNumericValue(SObject calcItem, SObjectField operationField) {
      return calcItem.get(operationField) != null ? 1 : 0;
    }

    protected override Decimal getNumericChangedValue(SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      Object newVal = calcItem.get(operationField);
      Object priorCalcVal = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : newVal;
      // for updates, we have to decrement the count if the value has been cleared out
      return newVal == null && priorCalcVal != null ? -1 : 0;
    }
  }

  private virtual class StringRollupCalculator extends RollupCalculator {
    public StringRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
    }

    public override void performRollup(Op operation, Object priorVal, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      String stringVal = (String) this.returnVal;
      Boolean isConcatDistinct = operation.name().contains(Op.CONCAT_DISTINCT.name());
      for (SObject calcItem : calcItems) {
        if (this.shouldShortCircuit) {
          String newVal = (String) calcItem.get(operationField);
          switch on operation {
            when UPDATE_MAX, UPDATE_MIN {
              if (this.isTrueFor(operation, newVal, stringVal)) {
                stringVal = newVal;
              }
            }
          }
          continue;
        }
        switch on operation {
          when CONCAT, CONCAT_DISTINCT {
            String newVal = (String) calcItem.get(operationField);
            if (isConcatDistinct && stringVal.contains(newVal)) {
              // skip
              continue;
            }
            stringVal += ',' + newVal + ',';
          }
          when UPDATE_CONCAT, UPDATE_CONCAT_DISTINCT {
            String newVal = (String) calcItem.get(operationField);
            String priorString = (String) (oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : newVal);
            if (isConcatDistinct && stringVal.contains(newVal)) {
              // skip
              continue;
            }
            stringVal = stringVal.replace(priorString, newVal) + ',';
          }
          when DELETE_CONCAT, DELETE_CONCAT_DISTINCT {
            String existingVal = (String) calcItem.get(operationField);
            stringVal = stringVal.replace(existingVal, '') + ',';
          }
          when MAX, MIN {
            String newVal = (String) calcItem.get(operationField);
            if (this.isTrueFor(operation, newVal, stringVal)) {
              stringVal = newVal;
            }
          }
          when UPDATE_MAX, UPDATE_MIN, DELETE_MAX, DELETE_MIN {
            String newVal = (String) calcItem.get(operationField);
            String priorString = (String) (oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : newVal);

            if (
              (operation.name().contains(Op.MAX.name()) && priorString == stringVal && newVal <= stringVal) ||
              (operation.name().contains(Op.MIN.name()) &&
              priorString == stringVal &&
              newVal >= stringVal)
            ) {
              this.shouldShortCircuit = true;
              Object potentialReturnValue = this.calculateNewAggregateValue(oldCalcItems.keySet(), operation, operationField, calcItem.getSObjectType());
              stringVal = potentialReturnValue == null ? '' : (String) potentialReturnValue;
            } else if (this.isTrueFor(operation, newVal, stringVal)) {
              stringVal = newVal;
            }
          }
        }
      }

      String possibleReturnValue = stringVal.normalizeSpace();
      String withoutEndingComma = possibleReturnValue.endsWith(',') ? possibleReturnValue.substring(0, possibleReturnValue.length() - 1) : possibleReturnValue;
      this.returnVal = withoutEndingComma.startsWith(',') ? withoutEndingComma.substring(1, withoutEndingComma.length()) : withoutEndingComma;
    }

    protected virtual Boolean isTrueFor(Op operation, String newVal, String priorVal) {
      if (operation.name().contains(Op.MAX.name())) {
        return newVal > priorVal || String.isBlank(priorVal);
      } else if (operation.name().contains(Op.MIN.name())) {
        return newVal < priorVal || String.isBlank(priorVal);
      }
      return false;
    }
  }

  private class PicklistRollupCalculator extends StringRollupCalculator {
    private final PicklistController picklistController;
    public PicklistRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
      this.picklistController = new PicklistController(operationField.getDescribe());
    }

    protected override Boolean isTrueFor(Op operation, String newVal, String priorVal) {
      if (this.picklistController.isPicklist() == false) {
        return super.isTrueFor(operation, newVal, priorVal);
      } else if (this.picklistController.isMultiSelectPicklist()) {
        // this operation isn't valid in SOQL, but at this point we wouldn't let a thing like that slow us down ...
        Integer newValRank = 0;
        Integer priorValRank = 0;
        for (String pickVal : newVal.split(';')) {
          newValRank += this.picklistController.getRank(pickVal, operation);
        }
        for (String priorPickVal : priorVal.split(';')) {
          priorValRank += this.picklistController.getRank(priorPickVal, operation);
        }
        return operation.name().contains(Op.MIN.name()) ? newValRank < priorValRank : newValRank > priorValRank;
      }
      return this.picklistController.isTrueFor(newVal, priorVal, operation);
    }
  }

  private class AverageRollupCalculator extends RollupCalculator {
    public AverageRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal) {
      super(priorVal, operationField, defaultVal);
    }
    public override void performRollup(Op operation, Object priorVal, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      Decimal average = (Decimal) this.returnVal;
      if (calcItems.isEmpty()) {
        return;
      }

      // the List isn't strongly typed at this point, otherwise we could avoid this shameful statement
      SObjectType sObjectType = calcItems[0].getSobjectType();
      Set<Id> objIds = new Map<Id, SObject>(calcItems).keySet();
      Integer countOfPreExistingItems = Database.countQuery(getCountQueryString(sObjectType, '!='));
      Decimal oldSum = (Decimal) this.calculateNewAggregateValue(objIds, Op.SUM, operationField, sObjectType);

      List<SObject> applicableCalcItems = operation == Op.DELETE_AVERAGE ? new List<SObject>() : calcItems;
      Decimal newSum = 0;
      for (SObject calcItem : applicableCalcItems) {
        newSum += (Decimal) calcItem.get(operationField);
      }

      average = (oldSum + newSum) / (countOfPreExistingItems + applicableCalcItems.size());
      this.returnVal = average;
    }
  }

  private class RollupSchedulable implements System.Schedulable {
    private final String query;
    private final List<String> rollupMetadataIds;
    private final Evaluator eval;

    public RollupSchedulable(String query, List<String> rollupMetadataIds, Evaluator eval) {
      this.query = query;
      this.rollupMetadataIds = rollupMetadataIds;
      this.eval = eval;
      try {
        Database.query(this.query);
      } catch (Exception ex) {
        throw new QueryException('There\'s a problem with your query: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
      }
    }

    public void execute(SchedulableContext sc) {
      List<Rollup__mdt> rollupMetadata = [
        SELECT
          CalcItem__c,
          RollupFieldOnCalcItem__c,
          LookupObject__c,
          LookupFieldOnCalcItem__c,
          RollupFieldOnLookupObject__c,
          RollupType__c,
          ChangedFieldsOnCalcItem__c,
          FullRecalculationDefaultNumberValue__c,
          FullRecalculationDefaultStringValue__c
        FROM Rollup__mdt
        WHERE Id = :this.rollupMetadataIds
      ];
      List<SObject> calcItems = Database.query(this.query);
      getRollup(rollupMetadata, calcItems.getSObjectType(), calcItems, new Map<Id, SObject>(calcItems), this.eval, RollupInvocationPoint.FROM_SCHEDULED)
        .runCalc();
    }
  }
}
