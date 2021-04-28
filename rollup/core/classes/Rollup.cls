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
  private static Boolean isRunningAsync = false;
  private static Integer SENTINEL_COUNT_VALUE = -1;

  private static Boolean isCDC = false;
  private static Boolean isDeferralAllowed = true;
  private static Integer stackDepth = 0;
  private static final String CONTROL_ORG_DEFAULTS = 'Org_Defaults';
  private static final RollupSettings__c SETTINGS = RollupSettings__c.getInstance();

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
  private RollupRelationshipFieldFinder.Traversal traversal;

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
    this.calcItems = this.filter(calcItems, eval);
    // we only need to replace the eval in-situ if downstream calc item where clauses have been updated
    if (this.calcItems.isEmpty() == false && rollupMetadata.CalcItemWhereClause__c != this.metadata.CalcItemWhereClause__c) {
      this.eval = RollupEvaluator.getEvaluator(eval, this.metadata, oldCalcItems, this.calcItems[0].getSObjectType());
    } else {
      this.eval = eval;
    }
    this.isNoOp = this.calcItems.isEmpty() && this.metadata?.IsFullRecordSet__c == false;
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
    if (this.isNoOp || orgDefaults.ShouldAbortRun__c || SETTINGS.IsEnabled__c == false) {
      return 'No process Id';
    }

    Boolean hasMoreThanOneTarget = false;
    Integer totalCountOfRecords = this.getLookupRecordsCount(hasMoreThanOneTarget);

    Boolean shouldBatch =
      shouldRunAsBatch ||
      (orgDefaults.ShouldRunAs__c == 'Batchable' &&
      totalCountOfRecords >= orgDefaults.MaxLookupRowsBeforeBatching__c) ||
      totalCountOfRecords == SENTINEL_COUNT_VALUE;
    if (this.syncRollups.isEmpty() == false) {
      this.process(this.syncRollups);
      return 'Running rollups flagged to go synchronously';
    } else if (shouldBatch && hasMoreThanOneTarget == false) {
      isRunningAsync = true;
      // safe to batch because the QueryLocator will only return one type of SObject
      return Database.executeBatch(new Rollup(this), this.rollupControl.BatchChunkSize__c.intValue());
    } else {
      isRunningAsync = true;
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
    String lookupFieldForLookupObject;
    SObjectType sObjectType;
    Set<String> objIds = new Set<String>();
    for (Rollup rollup : this.rollups) {
      sObjectType = rollup.lookupObj;
      lookupFieldForLookupObject = rollup.lookupFieldOnLookupObject.getDescribe().getName();
      objIds.addAll(this.getCalcItemsByLookupField(rollup, this.lookupObjectToUniqueFieldNames.get(sObjectType)).keySet());
    }
    String query = getQueryString(sObjectType, new List<String>(this.lookupObjectToUniqueFieldNames.get(sObjectType)), lookupFieldForLookupObject, '=');
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
      } else {
        List<SObject> localLookupItems;
        if (String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c)) {
          localLookupItems = rollup.traversal.getAllParents();
          // winnow the list, which would otherwise occur because of specifically only querying for the objIds passed in
          for (Integer index = localLookupItems.size() - 1; index >= 0; index--) {
            SObject lookupItem = localLookupItems[index];
            String key = (String) lookupItem.get(rollup.lookupFieldOnLookupObject);
            if (objIds.contains(key) == false) {
              localLookupItems.remove(index);
            }
          }
        } else {
          String queryString = getQueryString(rollup.lookupObj, new List<String>(uniqueQueryFieldNames), String.valueOf(rollup.lookupFieldOnLookupObject), '=');
          // non-obvious coupling between "objIds" and the computed "queryString", which uses dynamic variable binding
          localLookupItems = Database.query(queryString);
        }
        this.initializeRollupFieldDefaults(localLookupItems, rollup);
        return localLookupItems;
      }
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
  global static String performBulkFullRecalc(List<Rollup__mdt> matchingMetadata) {
    Integer amountOfCalcItems = 0;
    Set<String> objIds = new Set<String>(); // will always be present as a bind var, below
    Set<Id> recordIds = new Set<Id>(); // always empty, here, but necessary for the "getCountFromDb" call
    SObjectType calcItemType; // always the same for this route, so we can just take whatever the last assignment is
    Set<String> queryFields = new Set<String>{ 'Id' };

    for (Rollup__mdt matchingMeta : matchingMetadata) {
      calcItemType = getSObjectFromName(matchingMeta.CalcItem__c).getSObjectType();
      queryFields.add(matchingMeta.LookupFieldOnCalcItem__c);
      queryFields.add(matchingMeta.RollupFieldOnCalcItem__c);
      if (String.isNotBlank(matchingMeta.CalcItemWhereClause__c)) {
        queryFields.addAll(new RollupEvaluator.WhereFieldEvaluator(matchingMeta.CalcItemWhereClause__c, calcItemType).getQueryFields());
      }

      String countQuery = getQueryString(calcItemType, new List<String>{ 'Count()' }, matchingMeta.LookupFieldOnLookupObject__c, '!=');
      Integer currentCount = getCountFromDb(countQuery, objIds, recordIds);
      if (currentCount == SENTINEL_COUNT_VALUE) {
        amountOfCalcItems = currentCount;
        continue;
      }
      amountOfCalcItems += currentCount;
    }

    String queryString = getQueryString(calcItemType, new List<String>(queryFields), 'Id', '!=');

    // eval always null via this route, despite having been used to get the relationship fields
    return startFullRecalc(matchingMetadata, amountOfCalcItems, queryString, objIds, recordIds, calcItemType, null, RollupInvocationPoint.FROM_LWC);
  }

  @AuraEnabled
  global static String getBatchRollupStatus(String jobId) {
    return [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1]?.Status;
  }

  @AuraEnabled
  global static String performFullRecalculation(
    Rollup__mdt metadata
  ) {
    FlowInput validationRuleWrapper = new FlowInput();
    validationRuleWrapper.rollupOperation = metadata.RollupOperation__c.toUpperCase();
    validationRuleWrapper.concatDelimiter = metadata.ConcatDelimiter__c;
    validationRuleWrapper.fullRecalculationDefaultStringValue = metadata.FullRecalculationDefaultStringValue__c;
    validationRuleWrapper.fullRecalculationDefaultNumberValue = metadata.FullRecalculationDefaultNumberValue__c;
    validationRuleWrapper.orderByFirstLast = metadata.OrderByFirstLast__c;
    enforceValidationRules(validationRuleWrapper);

    QueryWrapper wrapper = new QueryWrapper(metadata.LookupObject__c, metadata.LookupFieldOnLookupObject__c);
    wrapper.setQuery(metadata.CalcItemWhereClause__c);
    return performFullRecalculationInner(
      metadata,
      wrapper,
      RollupInvocationPoint.FROM_LWC
    );
  }

  global class FlowInput {
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)')
    global List<SObject> recordsToRollup;

    @InvocableVariable(label='Prior records to rollup' description='The old version of the records for update/upsert')
    global List<SObject> oldRecordsToRollup = new List<SObject>();

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
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;

    @InvocableVariable(label='Defer processing')
    global Boolean deferProcessing = false;

    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;

    @InvocableVariable(label='Grandparent Relationship Field Path' description='Used for grand(or greater)parent rollups')
    global String grandparentRelationshipFieldPath;

    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;
    @InvocableVariable(
      label='Should rollup to ultimate hierarchy parent'
      description='Used in conjunction with Ultimate Parent Field to drive hierarchical parent rollups'
    )
    global Boolean rollupToUltimateParent = false;
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
    List<Rollup> rollups = new List<Rollup>();

    for (FlowInput flowInput : flowInputs) {
      FlowOutput flowOutput = new FlowOutput();
      flowOutputs.add(flowOutput);

      if (flowInput.recordsToRollup?.isEmpty() == true) {
        continue;
      } else if (flowInput.rollupContext == 'UPSERT') {
        flowInput.rollupContext = 'UPDATE';
      }

      flowInput.rollupOperation = flowInput.rollupOperation.toUpperCase();
      String rollupContext = getFlowRollupContext(flowInput);

      // this will throw back up to the Flow engine if the inputs don't pass validation
      enforceValidationRules(flowInput);
      enforceFlowSpecificRules(flowInput);

      SObjectType sObjectType = flowInput.recordsToRollup[0].getSObjectType();

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
        CalcItem__c = flowInput.isRollupStartedFromParent ? flowInput.calcItemTypeWhenRollupStartedFromParent : String.valueOf(sObjectType)
      );

      if (flowInput.isRollupStartedFromParent) {
        QueryWrapper wrapper = getParentWhereClause(
          flowInput.recordsToRollup,
          flowInput.lookupFieldOnOpObject,
          flowInput.rollupSObjectName,
          flowInput.lookupFieldOnCalcItem,
          flowInput.grandparentRelationshipFieldPath,
          flowInput.calcItemWhereClause
        );
        performFullRecalculationInner(
          rollupMeta,
          wrapper,
          RollupInvocationPoint.FROM_INVOCABLE
        );
        continue;
      }

      Map<Id, SObject> oldFlowRecords = getOldFlowRecords(flowInput, sObjectType);

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

    try {
      batch(rollups);
    } catch (Exception ex) {
      for (FlowOutput flowOutput : flowOutputs) {
        flowOutput.IsSuccess = false;
        flowOutput.Message = ex.getMessage() + '\n' + ex.getStackTraceString();
      }
    }

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

    Set<String> uniqueFieldNames = new Set<String>{ 'Id' };
    for (Rollup__mdt rollupInfo : matchingMetadata) {
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
    // getting the items back from the database before putting them into the map is an important step
    // we COULD just initialize the map with the query, but then the map's .values() list doesn't return
    // anything for .getSObjectType() - which we need, further downstream
    List<SObject> cdcCalcItems = Database.query(fullQuery);
    Map<Id, SObject> cdcCalcItemsMap = new Map<Id, SObject>(cdcCalcItems);

    Rollup rollupToReturn = runFromApex(rollupMetadata, null, cdcCalcItems, cdcCalcItemsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isCDCUpdate = apexContext == TriggerOperation.AFTER_UPDATE;
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
      Boolean isIntermediateRollupForGrandparent =
        rollupInfo.CalcItem__c != String.valueOf(calcItems.getSObjectType()) &&
        String.isNotBlank(rollupInfo.GrandparentRelationshipFieldPath__c) &&
        calcItems.isEmpty() == false &&
        rollupInfo.IsRollupStartedFromParent__c == false;

      if (rollupInfo.IsRollupStartedFromParent__c || isIntermediateRollupForGrandparent) {
        shouldReturn = true;
        QueryWrapper queryWrapper = isIntermediateRollupForGrandparent == false
          ? getParentWhereClause(
              calcItems,
              rollupInfo.LookupFieldOnLookupObject__c,
              rollupInfo.LookupObject__c,
              rollupInfo.LookupFieldOnCalcItem__c,
              rollupInfo.GrandparentRelationshipFieldPath__c,
              rollupInfo.CalcItemWhereClause__c
            )
          : getIntermediateGrandparentQueryWrapper(rollupInfo.GrandparentRelationshipFieldPath__c, calcItems, oldCalcItems);
        if (rollupInfo.IsRollupStartedFromParent__c || isIntermediateRollupForGrandparent && (queryWrapper.hasQuery || isCDC)) {
          performFullRecalculationInner(
            rollupInfo,
            queryWrapper,
            RollupInvocationPoint.FROM_APEX
          );
        }
      }
      rollupInfo.RollupOperation__c = rollupContext + rollupInfo.RollupOperation__c;
    }

    return shouldReturn
      ? new RollupAsyncProcessor(RollupInvocationPoint.FROM_APEX)
      : getRollup(rollupMetadata, calcItems.getSObjectType(), calcItems, oldCalcItems, eval, RollupInvocationPoint.FROM_APEX);
  }

  /** end global-facing section, begin public/private static helpers */

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
    optionalWhereClause = adjustWhereClauseForPolymorphicFields(sObjectType, uniqueQueryFieldNames, optionalWhereClause);
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
    List<SObject> matchingMetadata;
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
            MasterLabel,
            DeveloperName,
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
      matchingMetadata = RollupControl__mdt.getAll().deepClone().values();
    }
    return matchingMetadata;
  }

  public static Boolean hasExceededCurrentRollupLimits(RollupControl__mdt control) {
    Boolean hasExceededLimits =
      (Limits.getLimitQueries() / 2) < Limits.getQueries() ||
      control?.MaxQueryRows__c < Limits.getQueryRows() ||
      (Limits.getLimitHeapSize() / 2) < Limits.getHeapSize() ||
      control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();
    return hasExceededLimits && isDeferralAllowed;
  }

  private static String performFullRecalculationInner(
    Rollup__mdt meta,
    QueryWrapper queryWrapper,
    RollupInvocationPoint invokePoint
  ) {
    // just how many items are we talking, here? If it's less than the query limit, we can proceed
    // otherwise, kick off a batch to fetch the calc items and then chain into the regular code path
    SObjectType calcItemType = getSObjectFromName(meta.CalcItem__c).getSObjectType();
    String countQuery = getQueryString(calcItemType, new List<String>{ 'Count()' }, meta.LookupFieldOnLookupObject__c, '!=', queryWrapper.getQuery());

    Set<String> objIds = new Set<String>(); // get everything that doesn't have a null Id - a pretty trick
    Set<Id> recordIds = queryWrapper.recordIds; // also used below, bound to the "queryString" variable
    Integer amountOfCalcItems = getCountFromDb(countQuery, objIds, recordIds);

    Set<String> queryFields = new Set<String>{ 'Id', meta.RollupFieldOnCalcItem__c, meta.LookupFieldOnCalcItem__c };
    RollupEvaluator.WhereFieldEvaluator whereEval = new RollupEvaluator.WhereFieldEvaluator(queryWrapper.toString(), calcItemType);
    queryFields.addAll(whereEval.getQueryFields());
    String queryString = getQueryString(calcItemType, new List<String>(queryFields), 'Id', '!=', queryWrapper.getQuery());

    return startFullRecalc(new List<Rollup__mdt>{ meta }, amountOfCalcItems, queryString, objIds, recordIds, calcItemType, whereEval, invokePoint);
  }

  private static String startFullRecalc(
    List<Rollup__mdt> matchingMeta,
    Integer amountOfCalcItems,
    String queryString,
    Set<String> objIds,
    Set<Id> recordIds,
    SObjectType calcItemType,
    Evaluator eval,
    RollupInvocationPoint invokePoint
  ) {
    // emptyRollup used to reference the default RollupControl__mdt.MaxQueryRows__c, as well as BatchChunkSize__c
    Rollup emptyRollup = new Rollup(invokePoint);
    Boolean shouldQueue = amountOfCalcItems != SENTINEL_COUNT_VALUE && amountOfCalcItems < emptyRollup.rollupControl.MaxQueryRows__c;
    if (shouldQueue) {
      List<SObject> calculationItems = Database.query(queryString);
      Rollup thisRollup = getRollup(matchingMeta, calcItemType, calculationItems, new Map<Id, SObject>(calculationItems), eval, invokePoint);
      thisRollup.isFullRecalc = true;
      return thisRollup.runCalc();
    } else {
      // batch to get calc items and then batch to rollup
      return Database.executeBatch(
        new RollupFullBatchRecalculator(queryString, invokePoint, matchingMeta, calcItemType, recordIds),
        emptyRollup.rollupControl.BatchChunkSize__c.intValue()
      );
    }
  }

  private static void enforceValidationRules(FlowInput flowInput) {
    if ((flowInput.rollupOperation == 'FIRST' || flowInput.rollupOperation == 'LAST') && String.isBlank(flowInput.orderByFirstLast)) {
      throw new IllegalArgumentException('Order By First/Last field required for ' + flowInput.rollupOperation + ' operation');
    } else if (
      (flowInput.rollupToUltimateParent && String.isBlank(flowInput.ultimateParentLookup)) ||
      (String.isNotBlank(flowInput.ultimateParentLookup) && flowInput.rollupToUltimateParent == false)
    ) {
      throw new IllegalArgumentException('Rollup To Ultimate Parent and Ultimate Parent Lookup must both be set for hierarchical rollups');
    } else if (flowInput.rollupOperation.contains(Op.CONCAT.name()) == false && String.isNotBlank(flowInput.concatDelimiter)) {
      throw new IllegalArgumentException('Concat delimiter should only be supplied for CONCAT-based rollups');
    } else if (String.isNotBlank(flowInput.fullRecalculationDefaultStringValue) && flowInput.fullRecalculationDefaultNumberValue != null) {
      throw new IllegalArgumentException('Only one override - the default string value or number value - can be supplied for each rollup');
    }
  }

  private static void enforceFlowSpecificRules(FlowInput flowInput) {
    if (flowInput.rollupContext == 'UPDATE' && flowInput.oldRecordsToRollup?.isEmpty() == true) {
      throw new IllegalArgumentException('Prior records to rollup collection required for rollup context: ' + flowInput.rollupContext);
    } else if (flowInput.recordsToRollup?.isEmpty() == false) {
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
  }

  private static String adjustWhereClauseForPolymorphicFields(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String optionalWhereClause) {
    // you can't filter on *.Owner for polymorphic fields - or even select them, for that matter. Instead we have to massage the query to use
    // TYPEOF instead
    if (String.isBlank(optionalWhereClause) || hasPolymorphicOwnerClause(optionalWhereClause) == false) {
      return optionalWhereClause;
    }
    RollupEvaluator.WhereFieldEvaluator whereEval = new RollupEvaluator.WhereFieldEvaluator(optionalWhereClause, sObjectType);
    try {
      for (String whereClause : whereEval.getWhereClauses()) {
        if (hasPolymorphicOwnerClause(whereClause) == false) {
          continue;
        }
        String fieldName = whereClause.split(' ')[0];
        List<String> fieldParts = fieldName.split('\\.');
        String whoOrWhat = fieldParts.remove(0);
        String indexer = whoOrWhat + '.Type = \'';
        String relationshipName = optionalWhereClause.substring(optionalWhereClause.indexOf(indexer) + indexer.length()).substringBeforeLast('\'');
        String typeOfField = String.join(fieldParts, '.');

        uniqueQueryFieldNames.add('TYPEOF ' + whoOrWhat + ' WHEN ' + relationshipName + ' THEN ' + typeOfField + ' END');

        optionalWhereClause = optionalWhereClause.replace(indexer + relationshipName + '\'', '').trim();
        optionalWhereClause = optionalWhereClause.replace(whereClause, '').trim();
      }
      // sanitize what's left of the where clause
      while (optionalWhereClause.endsWith('AND')) {
        optionalWhereClause = optionalWhereClause.substringBeforeLast('AND').trim();
      }
      while (optionalWhereClause.endsWith('OR')) {
        optionalWhereClause = optionalWhereClause.substringBeforeLast('OR').trim();
      }
    } catch (Exception ex) {
      System.debug(LoggingLevel.ERROR, 'An error occurred while formatting where clause: ' + ex.getMessage());
    }
    return optionalWhereClause;
  }

  private static Boolean hasPolymorphicOwnerClause(String whereClause) {
    return whereClause.contains('.Owner');
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

  private static Integer getCountFromDb(String countQuery, Set<String> objIds) {
    return getCountFromDb(countQuery, objIds, null);
  }

  private static Integer getCountFromDb(String countQuery, Set<String> objIds, Set<Id> recordIds) {
    if (countQuery.contains('ALL ROWS')) {
      countQuery = countQuery.replace('ALL ROWS', '');
    }

    try {
      return Database.countQuery(countQuery);
    } catch (Exception ex) {
      // not all queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      return SENTINEL_COUNT_VALUE;
    }
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
    }

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static Map<Id, SObject> getOldFlowRecords(FlowInput flowInput, SObjectType sObjectType) {
    Map<Id, SObject> oldFlowRecords = new Map<Id, SObject>();
    if (flowInput.recordsToRollup?.isEmpty() == true || flowInput.rollupContext != 'UPDATE') {
      return oldFlowRecords;
    } else if (flowInput.oldRecordsToRollup?.isEmpty() == false) {
      // normally, you could use a shortcut to initialize a Set<Id> like this
      // by calling new Map<Id, SObject>(oldRecordsToRollup).keyset() -
      // but that code path fails if there are null Ids in the list
      for (SObject oldRecord : flowInput.oldRecordsToRollup) {
        if (oldRecord == null) {
          continue; // record-triggered flows set up to run when "A record is created or modified" will pass null in the list if it runs on create - yikes
        } else if (oldRecord.Id != null) {
          oldFlowRecords.put(oldRecord.Id, oldRecord);
        }
      }

      Map<String, SObjectField> fieldTokensForObject = sObjectType.getDescribe().fields.getMap();
      for (SObject currentRecord : flowInput.recordsToRollup) {
        Map<String, Object> populatedFields = currentRecord.getPopulatedFieldsAsMap();
        // this is as close as we can get, at present, to detecting upserts. It won't work for records being inserted with the CreatedDate set to a historical value
        if (
          populatedFields.containsKey('CreatedDate') &&
          populatedFields.containsKey('LastModifiedDate') &&
          currentRecord.get('CreatedDate') == currentRecord.get('LastModifiedDate')
        ) {
          SObjectField rollupFieldOnCalcItem = fieldTokensForObject.get(flowInput.rollupFieldOnCalcItem);
          if (rollupFieldOnCalcItem != null && rollupFieldOnCalcItem.getDescribe().isCalculated() == false) {
            SObject clonedRecord = currentRecord.clone(true, true);
            clonedRecord.put(rollupFieldOnCalcItem, RollupFieldInitializer.Current.getDefaultValue(rollupFieldOnCalcItem));
            oldFlowRecords.put(currentRecord.Id, clonedRecord);
          }
        }
      }
    }

    return oldFlowRecords;
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

      RollupControl__mdt localControl;
      if (rollupMetadata.RollupControl__c != null) {
        // for CMDT-driven rollups, the rollup record is always tied to a RollupControl__mdt record
        localControl = new RollupControl__mdt(Id = rollupMetadata.RollupControl__c);
      } else {
        String controlKey = getRollupControlKey(rollupInvokePoint, rollupFieldOnCalcItem, lookupSObjectType, rollupFieldOnOpObject);
        localControl = getSingleControlOrDefault(RollupControl__mdt.TriggerOrInvocableName__c, controlKey, null);
      }

      loadRollups(
        rollupFieldOnCalcItem,
        calcLookupField,
        lookupFieldOnOpObject,
        rollupFieldOnOpObject,
        lookupSObjectType,
        rollupOp,
        calcItems,
        oldCalcItems,
        batchRollup,
        RollupEvaluator.getEvaluator(eval, rollupMetadata, oldCalcItems, sObjectType),
        localControl?.Id,
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
        MaxRollupRetries__c = 100,
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
    List<Rollup__mdt> rollupInfo,
    SObjectType calcItemType,
    List<SObject> calcItems,
    Map<Id, SObject> oldCalcItems,
    RollupInvocationPoint invokePoint
  ) {
    return getRollup(rollupInfo, calcItemType, calcItems, oldCalcItems, null, invokePoint);
  }

  protected void process(List<Rollup> rollups) {
    this.getFieldNamesForRollups(rollups); // populates this.lookupObjectToUniqueFieldNames
    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<SObjectType, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<SObjectType, RollupRelationshipFieldFinder.Traversal>();
    for (Rollup rollup : rollups) {
      // for each iteration, ensure we're not operating beyond the bounds of our query limits
      if (hasExceededCurrentRollupLimits(rollup.rollupControl)) {
        this.deferredRollups.add(rollup);
        continue;
      }

      if (grandparentRollups.containsKey(rollup.lookupObj) && rollup.traversal == null) {
        rollup.traversal = grandparentRollups.get(rollup.lookupObj);
      }

      Map<String, List<SObject>> calcItemsByLookupField = this.getCalcItemsByLookupField(rollup, this.lookupObjectToUniqueFieldNames.get(rollup.lookupObj));
      // some rollups may not finish retrieving all parent rows the first time around - and that's ok! we can keep
      // trying until all necessary records have been retrieved
      if (rollup.traversal?.getIsFinished() == false) {
        this.deferredRollups.add(rollup);
        continue;
      } else if (rollup.traversal != null && grandparentRollups.containsKey(rollup.lookupObj) == false) {
        // cache the traversal for any future callers - because we queried for ALL unique grand(or greater)parent fields
        // we don't need to re-traverse the whole object chain again if there are other grandparent rollups in the list
        grandparentRollups.put(rollup.lookupObj, rollup.traversal);
      }

      List<SObject> localLookupItems = new List<SObject>();
      Set<String> lookupItemKeys = new Set<String>(calcItemsByLookupField.keySet());
      for (String lookupId : calcItemsByLookupField.keySet()) {
        if (updatedLookupRecords.containsKey(lookupId)) {
          lookupItemKeys.remove(lookupId);
          // this way, the updated values are persisted for each field, and the default values are initialized
          SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
          if (updatedLookupObject.get(rollup.opFieldOnLookupObject) == null || this.isFullRecalc) {
            updatedLookupObject.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
          }
          localLookupItems.add(updatedLookupObject);
        }
      }
      localLookupItems.addAll(this.getExistingLookupItems(lookupItemKeys, rollup, this.lookupObjectToUniqueFieldNames.get(rollup.lookupObj)));
      List<SObject> updatedParentRecords = this.getUpdatedLookupItemsByRollup(rollup, calcItemsByLookupField, localLookupItems);
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

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty() == false && isDeferralAllowed && stackDepth < this.rollupControl?.MaxRollupRetries__c) {
      stackDepth++;
      // tragic, but necessary due to limits on requeueing allowed during testing
      isDeferralAllowed = Test.isRunningTest() == false && this.rollupControl.MaxRollupRetries__c > stackDepth;

      this.rollups.clear();
      this.rollups.addAll(this.deferredRollups);
      this.deferredRollups.clear();

      // swap off on which async process is running to achieve infinite scaling
      if (System.isQueueable()) {
        Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
      } else if (Limits.getLimitQueueableJobs() > Limits.getQueueableJobs()) {
        System.enqueueJob(this);
      } else {
        // the end of the line
        this.throwWithRollupData(this.rollups);
      }
    } else if (this.deferredRollups.isEmpty() == false) {
      this.throwWithRollupData(this.deferredRollups);
    }
  }

  private void throwWithRollupData(List<Rollup> rolls) {
    List<Rollup__mdt> failedRollupInfo = new List<Rollup__mdt>();
    for (Rollup roll : rolls) {
      failedRollupInfo.add(roll.metadata);
    }
    throw new AsyncException('Rollup failed to re-queue for: ' + JSON.serialize(failedRollupInfo));
  }

  private List<SObject> filter(List<SObject> calcItems, Evaluator eval) {
    Set<String> alwaysFullRecalcOps = new Set<String>{ 'FIRST', 'LAST', 'AVERAGE' };
    List<SObject> matchingItems = new List<SObject>();
    if (calcItems?.isEmpty() != false) {
      return matchingItems;
    }
    calcItems = this.replaceCalcItemsForPolymorphicWhereClause(calcItems);

    for (SObject item : calcItems) {
      if (eval?.matches(item) != false) {
        matchingItems.add(item);
        // metadata shouldn't be null, but it's good to check; unfortunately, if(null) throws so we
        // have to do this EXTRA explicit check
      } else if (this.metadata?.IsFullRecordSet__c == true) {
        matchingItems.add(item);
      } else if (alwaysFullRecalcOps.contains(this.metadata?.RollupOperation__c)) {
        matchingItems.add(item);
      }
    }
    return matchingItems;
  }

  private List<SObject> replaceCalcItemsForPolymorphicWhereClause(List<SObject> calcItems) {
    final String typeField = '.Type';
    final String owner = 'Owner.';

    // first we check to see if there is a calc item where clause, and that it contains any of the common polymorphic fields
    SObject firstItem = calcItems[0];
    if (String.isBlank(this.metadata?.CalcItemWhereClause__c)) {
      return calcItems;
    }
    Boolean hasOwnerClause = this.metadata.CalcItemWhereClause__c.contains(owner);
    Boolean hasTypeClause = this.metadata.CalcItemWhereClause__c.contains(typeField);
    SObjectType sObjectType = firstItem.getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
    Boolean hasPolyMorphicFields = hasOwnerClause || hasTypeClause || fieldMap.get(this.metadata.LookupFieldOnCalcItem__c)?.getDescribe().isNamePointing() == true;

    if (hasPolyMorphicFields) {

      if (hasTypeClause == false && hasOwnerClause == false) {
        return calcItems;
      }

      // the calc item where clause contains at least one polymorphic field, but before re-querying we validate whether or not the fields are already provided
      Map<String, Object> populatedFields = firstItem.getPopulatedFieldsAsMap();
      Set<String> additionalQueryFields = new Set<String>();
      List<String> optionalWhereClauses = new List<String>();

      this.processWhereClauseForDownstreamEvals(optionalWhereClauses, additionalQueryFields, sObjectType, typeField, owner);

      // we have to manually iterate through these fields because the "fieldMap" keySet is all in lowercase because it's ... special
      // and only responds properly to proper-cased fields when you call the map "containsKey" method - if the field names in the keySet were
      // proper-cased, we could just call additionalQueryFields.addAll(populatedFields.keySet().removeAll(fieldMap.keySet())) - alas
      // this awesome one-liner doesn't work for us
      for (String fieldName : populatedFields.keySet()) {
        if (fieldMap.containsKey(fieldName)) {
          additionalQueryFields.add(fieldName);
        }
      }

      String queryString = getQueryString(sObjectType, new List<String>(additionalQueryFields), 'Id', '=', String.join(optionalWhereClauses, ' AND '));
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

  private void processWhereClauseForDownstreamEvals(
    List<String> optionalWhereClauses,
    Set<String> additionalQueryFields,
    SObjectType sObjectType,
    String typeField,
    String owner
  ) {
    RollupEvaluator.WhereFieldEvaluator whereEval = new RollupEvaluator.WhereFieldEvaluator(this.metadata.CalcItemWhereClause__c, sObjectType);
    for (String whereClause : whereEval.getWhereClauses()) {
      if (whereClause.contains(typeField) || whereClause.contains(owner)) {
        List<String> splitWheres = whereClause.split(' ');
        if (splitWheres.size() > 0) {
          additionalQueryFields.add(splitWheres[0]);
        }
        // "consume" the metadata where clause for downstream evaluators
        this.metadata.CalcItemWhereClause__c = this.metadata.CalcItemWhereClause__c.replace(whereClause, '');
        optionalWhereClauses.add(whereClause);
      }
    }
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

  private Map<String, List<SObject>> getCalcItemsByLookupField(Rollup rollup, Set<String> uniqueQueryFieldNames) {
    if (String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c) || rollup.metadata.RollupToUltimateParent__c) {
      if (rollup.traversal == null) {
        rollup.traversal = new RollupRelationshipFieldFinder(
            rollup.rollupControl,
            rollup.metadata,
            uniqueQueryFieldNames,
            rollup.lookupObj,
            rollup.oldCalcItems
          )
          .getParents(rollup.calcItems);
      } else if (rollup.traversal?.getIsFinished() == false) {
        rollup.traversal.recommence();
      }
      return rollup.traversal.getIsFinished() ? rollup.traversal.getParentLookupToRecords() : new Map<String, List<SObject>>();
    }
    Map<String, List<SObject>> lookupFieldToCalcItems = new Map<String, List<SObject>>();
    for (SObject calcItem : rollup.calcItems) {
      String key = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new List<SObject>{ calcItem });
      } else {
        lookupFieldToCalcItems.get(key).add(calcItem);
      }

      // if the lookup key differs from what it was on the old calc item,
      // include that value as well so that we can fix reparented records' rollup values
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
      } else if (
        rollupSpecificControl.ShouldRunAs__c == 'Synchronous Rollup' || hasExceededCurrentRollupLimits(rollupSpecificControl) == false && isRunningAsync
      ) {
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

  private Integer getLookupRecordsCount(Boolean hasMoreThanOneTarget) {
    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupControl__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
    // if there's more than one SObjectType involved we bail on retrieving the actual count
    // because you can only return one list of SObjects from a batch job's QueryLocator
    SObjectType targetType;
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();
    for (Rollup rollup : this.rollups) {
      rollup.isFullRecalc = this.isFullRecalc;
      if (targetType == null) {
        targetType = rollup.lookupObj;
      } else if (rollup.lookupObj != targetType) {
        hasMoreThanOneTarget = true;
      } else if (String.isNotBlank(rollup.metadata?.GrandparentRelationshipFieldPath__c)) {
        // getting the count for grandparent (or greater) relationships will be handled further
        // downstream; for our purposes, it isn't useful to try to get all of the records while
        // we're still in a sync context
        continue;
      }

      if (hasMoreThanOneTarget) {
        break;
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
    if (hasMoreThanOneTarget == false) {
      for (String countQuery : queryCountsToLookupIds.keySet()) {
        Set<String> objIds = queryCountsToLookupIds.get(countQuery);
        Integer countForSObject = getCountFromDb(countQuery, objIds);
        if (countForSObject == SENTINEL_COUNT_VALUE) {
          totalCountOfRecords = countForSObject;
          break;
        } else {
          totalCountOfRecords += countForSObject;
        }
      }
    }
    return totalCountOfRecords;
  }

  private List<SObject> getUpdatedLookupItemsByRollup(Rollup rollup, Map<String, List<SObject>> calcItemsByLookupField, List<SObject> lookupItems) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    for (SObject lookupRecord : lookupItems) {
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        List<SObject> localCalcItems = calcItemsByLookupField.get(key);

        for (Integer index = localCalcItems.size() - 1; index >= 0; index--) {
          SObject calcItem = localCalcItems[index];
          if (rollup.eval?.matches(calcItem) == false && rollup.metadata?.IsFullRecordSet__c == true) {
            // technically it should only be possible for a calc item that doesn't match
            // to still exist if it is a Full Record Set operation; this gives people the chance
            // to reset rollup values if none of the records passed in match the eval criteria
            localCalcItems.remove(index);
            continue;
          }
          // Check for reparented records
          SObject oldCalcItem = rollup.oldCalcItems.get(calcItem.Id);

          if (oldCalcItem == null) {
            continue;
          }

          String priorLookup = (String) oldCalcItem.get(rollup.lookupFieldOnCalcItem);
          // if the lookup wasn't previously populated, there's nothing to update
          if (String.isBlank(priorLookup)) {
            continue;
          }
          Object newLookup = calcItem.get(rollup.lookupFieldOnCalcItem);

          if (newLookup != priorLookup && rollup.traversal == null) {
            this.populateOldLookupItems(priorLookup, oldCalcItem, oldLookupItems);
          } else if (rollup.traversal != null && rollup.traversal.isUltimatelyReparented(calcItem, rollup.lookupFieldOnCalcItem.getDescribe().getName())) {
            // slightly different, but with the same end result
            // note that when the reparented record is not null
            // it should be the same as the current "lookupRecord"
            SObject reparentedRecord = rollup.traversal.retrieveParent(oldCalcItem.Id);
            if (reparentedRecord != null) {
              priorLookup = (String) reparentedRecord.get(rollup.lookupFieldOnLookupObject);
              if (String.isNotBlank(priorLookup)) {
                Id oldLookupId = rollup.traversal.getOldLookupId(calcItem, rollup.lookupFieldOnCalcItem.getDescribe().getName());
                oldCalcItem = this.reassignOldCalcItemIfValueChanged(oldLookupId, oldCalcItem, rollup);
                this.populateOldLookupItems(priorLookup, oldCalcItem, oldLookupItems);
              }
            }
          }
        }

        // Check for changed values
        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(rollup, localCalcItems, priorVal, key, rollup.lookupFieldOnCalcItem);
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

        if (priorVal != newVal) {
          lookupRecord.put(rollup.opFieldOnLookupObject, newVal);
          recordsToUpdate.put(key, lookupRecord);
        }
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

  private void populateOldLookupItems(String priorLookup, SObject oldCalcItem, Map<String, List<SObject>> oldLookupItems) {
    if (oldLookupItems.containsKey(priorLookup) == false) {
      oldLookupItems.put(priorLookup, new List<SObject>{ oldCalcItem });
    } else {
      oldLookupItems.get(priorLookup).add(oldCalcItem);
    }
  }

  private SObject reassignOldCalcItemIfValueChanged(String lookupId, SObject oldCalcItem, Rollup rollup) {
    if (String.isBlank(lookupId)) {
      return oldCalcItem;
    }
    // truly terrible, but before we pass the old item through the reparenting code path, we need to validate that it's only
    // the lookup field that has changed; otherwise, if the opFieldOnCalcItem has changed too, substitute the item whose value
    // previously corresponded to the parent record
    for (SObject otherOldCalcItem : rollup.oldCalcItems.values()) {
      if (otherOldCalcItem.get(rollup.lookupFieldOnCalcItem) == lookupId) {
        if (otherOldCalcItem.get(rollup.opFieldOnCalcItem) != oldCalcItem.get(rollup.opFieldOnCalcItem)) {
          return otherOldCalcItem;
        }
        break; // break on the match, no matter what
      }
    }
    return oldCalcItem;
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
