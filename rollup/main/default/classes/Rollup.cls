global without sharing virtual class Rollup implements Database.Batchable<SObject> {
  /**
   * Test override / bookkeeping section. Normally I would do this through dependency injection,
   * but this keeps things much simpler
   */
  @testVisible
  private static Boolean shouldRun;
  @testVisible
  private static Boolean shouldRunAsBatch = false;
  @testVisible
  private static TriggerOperation triggerContext;
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
  @testVisible
  private static Integer maxQueryRowOverride;

  private static Boolean isCDC = false;

  private static final String LIMIT_ORG_DEFAULTS = 'Org_Defaults';
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
  private Boolean isFullRecalc = false;
  private Boolean isForcedRecalc = false;
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

  public enum RollupInvocationPoint {
    FROM_TRIGGER,
    FROM_INVOCABLE,
    FROM_SCHEDULED,
    FROM_LWC
  }

  protected Rollup(RollupInvocationPoint invokePoint) {
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
    this.isFullRecalc = innerRollup.isFullRecalc;
    this.isForcedRecalc = innerRollup.isForcedRecalc;
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

  global interface Evaluator {
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

  private class WhereFieldCondition {
    private final SObjectType sObjectType;
    private final String fieldName;
    private final String criteria;
    private final String value;
    private final List<String> values;
    private final Set<String> positiveEqualities = new Set<String>{ '=', 'like' };

    public WhereFieldCondition(String fieldName, String criteria, String value, SObjectType sObjectType) {
      this.fieldName = fieldName;
      this.criteria = criteria;
      this.value = value;
      this.sObjectType = sObjectType;
    }
    public WhereFieldCondition(String fieldName, String criteria, List<String> values, SObjectType sObjectType) {
      this.fieldName = fieldName;
      this.criteria = criteria;
      this.values = values;
      this.sObjectType = sObjectType;
    }

    public Boolean equals(Object o) {
      if (this.values != null) {
        Boolean isEqual = true;
        for (Integer index = 0; index < this.values.size(); index++) {
          String criteriaVal = this.values[index];
          isEqual = this.equals(o, criteriaVal);
          if (this.criteria.contains('!') && isEqual == false) {
            break;
          } else if (this.positiveEqualities.contains(this.criteria) && isEqual) {
            break;
          } else if (index < this.values.size() - 1) {
            isEqual = true;
          }
        }
        return isEqual;
      }
      return this.equals(o, this.value);
    }

    private Boolean equals(Object o, String criteriaVal) {
      Boolean isEqual = o instanceof SObject;
      if (isEqual == false) {
        return isEqual;
      }

      SObject item = (SObject) o;
      criteriaVal = criteriaVal.trim();
      String storedValue = this.getFieldValue(item, this.fieldName, this.sObjectType).toString();
      switch on this.criteria {
        when '=' {
          isEqual = storedValue == criteriaVal;
        }
        when '!=' {
          isEqual = storedValue != criteriaVal;
        }
        when 'like' {
          isEqual = storedValue.contains(criteriaVal);
        }
        when '!like' {
          isEqual = storedValue.contains(criteriaVal) == false;
        }
      }
      return isEqual;
    }

    private Object getFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      DescribesObjectResult sObjectDescribe = sObjectType.getDescribe();
      Map<String, SObjectField> fieldMap = sObjectDescribe.fields.getMap();
      if(fieldPath.contains('.') && fieldMap.containsKey(fieldPath) == false) {
        List<String> fieldNameParts = fieldPath.split('\\.');
        String relationshipName = fieldNameParts.remove(0);
        String originalName = relationshipName;
        if(relationshipName.contains('__r')) {
          relationshipName = relationshipName.replace('__r', '__c');
        } else {
          relationshipName += 'Id';
        }
        SObjectField fieldToken = fieldMap.get(relationshipName);
        SObjectType parentSObjectType;
        if(fieldToken.getDescribe().isNamePointing()) {
          Id fieldValue = (Id)item.get(relationshipName);
          parentSObjectType = fieldValue.getSobjectType();
        } else {
          parentSObjectType = fieldToken.getDescribe().getReferenceTo()[0];
        }
        SObject parentSObject = item.getSObject(originalName);
        if(fieldNameParts.isEmpty() == false) {
          return this.getFieldValue(parentSObject, String.join(fieldNameParts, '.'), parentSObjectType);
        } else {
          return parentSObject.get(originalName);
        }
      }
      return item.get(fieldPath);
    }

    public override String toString() {
      String baseString = this.fieldName + ' ' + this.criteria + ' ';
      if(this.values != null) {
        baseString += '(';
        for(String val : this.values) {
          String escapedVal = '\''+ val +'\'';
          baseString += this.values.indexOf(val) > 0 ? ', ' + escapedVal : escapedVal;
        }
        baseString += ')';
      } else {
        baseString += '\''+ this.value +'\'';
      }
      return baseString;
    }
  }

  public class WhereFieldEvaluator implements Evaluator {
    private final String whereClause;
    private final Map<String, String> conditionMapping = new Map<String, String>{
      '<>' => '!=',
      'not in' => '!=',
      'NOT IN' => '!=',
      'in' => '=',
      'IN' => '=',
      'not like' => '!like',
      'LIKE' => 'like',
      'NOT LIKE' => '!like'
    };
    private final List<WhereFieldCondition> conditions = new List<WhereFieldCondition>();

    public WhereFieldEvaluator(String whereClause, SObjectType calcItemSObjectType) {
      for (String conditionKey : this.conditionMapping.keySet()) {
        whereClause = whereClause.replace(conditionKey, conditionMapping.get(conditionKey));
      }
      this.whereClause = whereClause;
      List<String> splitWhere = whereClause.split('(and|AND|OR|or)');

      try {
        for (String splitWhereClause : splitWhere) {
          splitWhereClause = splitWhereClause.trim();
          String fieldName = splitWhereClause.substring(0, splitWhereClause.indexOf(' '));
          splitWhereClause = splitWhereClause.replace(fieldName, '').trim();
          String criteria = splitWhereClause.substring(0, splitWhereClause.indexOf(' '));
          String value = splitWhereClause.replace(criteria, '').trim().replaceAll('\'', '').trim();
          // is it a list? we'll create conditions for each entry in the list
          if (value.startsWith('(') && value.endsWith(')')) {
            List<String> values = value.substring(1, value.length() - 1).split(',');
            this.conditions.add(new WhereFieldCondition(fieldName, criteria, values, calcItemSObjectType));
          } else {
            this.conditions.add(new WhereFieldCondition(fieldName, criteria, value, calcItemSObjectType));
          }
        }
      } catch (Exception ex) {
        System.debug(LoggingLevel.ERROR, ex.getMessage() + '\n' + ex.getStackTraceString());
        throw new IllegalArgumentException('Where clause entered with incorrect number of args: ' + whereClause);
      }
    }

    public Boolean matches(Object calcItem) {
      // if there's only one condition, you only need to prove that condition
      // otherwise, if there's more than one condition, you either have to prove them all or
      // have an OR statement be true
      Boolean matches = this.conditions.isEmpty() || this.conditions.size() == 1;
      for (WhereFieldCondition condition : this.conditions) {
        // == works here because .equals() is overridden in the WhereFieldCondition class
        Boolean isOrCondition = this.whereClause.containsIgnoreCase('or ' + condition.toString());
        if(isOrCondition) {
          matches = matches || condition == calcItem;
        } else {
          matches = matches && condition == calcItem;
        }
      }
      return matches;
    }
  }

  public String runCalc() {
    RollupLimit__mdt orgDefaults = this.getSingleLimitOrDefault('DeveloperName', LIMIT_ORG_DEFAULTS, defaultRollupLimit);
    // side effect in the below method - rollups can be removed from this.rollups if a limit record ShouldAbortRun__c == true
    this.ingestRollupLimitData(orgDefaults);

    this.isNoOp = this.rollups.isEmpty();
    if (this.isNoOp || orgDefaults.ShouldAbortRun__c) {
      return 'No process Id';
    }

    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupLimit__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
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

      Set<String> uniqueLookupFields = new Set<String>();
      for (SObject calcItem : rollup.calcItems) {
        String lookupKey = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
        if (String.isNotBlank(lookupKey)) {
          uniqueLookupFields.add(lookupKey);
        }
      }

      String countQuery = getQueryString(rollup.lookupObj, new List<String>{ 'Count()' }, 'Id', '=');
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
      return Database.executeBatch(new Rollup(this));
    } else if (
      shouldRunAsBatch == false && (orgDefaults.MaxLookupRowsForQueueable__c == null || totalCountOfRecords <= orgDefaults.MaxLookupRowsForQueueable__c)
    ) {
      return System.enqueueJob(this);
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

  public virtual Database.QueryLocator start(Database.BatchableContext context) {
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
      query = getQueryString(
        sObjectType,
        new List<String>(this.lookupObjectToUniqueFieldNames.get(sObjectType)),
        String.valueOf(this.rollups[0].lookupFieldOnLookupObject),
        '='
      );
    }
    return Database.getQueryLocator(query);
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> lookupItems) {
    for (Rollup rollup : this.rollups) {
      this.initializeRollupFieldDefaults(lookupItems, rollup);
    }
    this.lookupItems = lookupItems;
    this.processAsync();
  }

  public virtual void finish(Database.BatchableContext context) {
    System.debug('Rollup: batch finished successfully');
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
      String queryString = getQueryString(rollup.lookupObj, new List<String>(uniqueQueryFieldNames), String.valueOf(rollup.lookupFieldOnLookupObject), '=');
      List<SObject> lookupItems = Database.query(queryString);
      this.initializeRollupFieldDefaults(lookupItems, rollup);
      return lookupItems;
    }

    public void execute(System.QueueableContext qc) {
      this.processAsync();
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
    // just how many items are we talking, here? If it's less than the query limit, we can proceed
    // otherwise, kick off a batch to fetch the calc items and then chain into the regular code path
    SObjectType calcItemType = getSObjectTypeFromName(calcItemSObjectName);
    String countQuery = getQueryString(calcItemType, new List<String>{ 'Count()' }, 'Id', '!=');
    Set<Id> objIds = new Set<Id>(); // get everything that doesn't have a null Id - a pretty trick
    Integer amountOfCalcItems = Database.countQuery(countQuery);

    // emptyRollup only used to call "getMaxQueryRows" below
    Rollup emptyRollup = new Rollup(RollupInvocationPoint.FROM_LWC);
    SObjectType lookupType = getSObjectTypeFromName(lookupSObjectName);
    Rollup__mdt rollupInfo = new Rollup__mdt(
      RollupFieldOnCalcItem__c = opFieldOnCalcItem,
      LookupObject__c = lookupSObjectName,
      LookupFieldOnCalcItem__c = lookupFieldOnCalcItem,
      LookupFieldOnLookupObject__c = lookupFieldOnLookupObject,
      RollupFieldOnLookupObject__c = rollupFieldOnLookupObject,
      RollupType__c = operationName
    );
    String queryString = getQueryString(calcItemType, new List<String>{ 'Id', opFieldOnCalcItem, lookupFieldOnCalcItem }, 'Id', '!=');
    if (amountOfCalcItems < emptyRollup.getMaxQueryRows()) {
      List<SObject> calcItems = Database.query(queryString);
      Rollup thisRollup = getRollup(
        new List<Rollup__mdt>{ rollupInfo },
        calcItemType,
        calcItems,
        new Map<Id, SObject>(calcItems),
        String.isNotblank(potentialWhereClause) ? new WhereFieldEvaluator(potentialWhereClause, calcItemType) : null,
        RollupInvocationPoint.FROM_LWC
      );
      thisRollup.isFullRecalc = true;
      return thisRollup.runCalc();
    } else {
      //batch to get calc items and then batch to rollup
      return Database.executeBatch(new RollupFullBatchRecalculator(queryString, RollupInvocationPoint.FROM_LWC, rollupInfo, calcItemType));
    }
  }

  global class FlowInput {
    @InvocableVariable(label='Records to rollup' description='Records to rollup to parent/related item(s)' required=true)
    global List<SObject> recordsToRollup;

    @InvocableVariable(label='Rollup target\'s SObject Name' description='The API Name of the SObject where the rollup value will be stored.' required=true)
    global String rollupSObjectName;

    @InvocableVariable(label='Rollup Operation' description='SUM, COUNT, COUNT_DISTINCT, MAX, MIN, AVG, CONCAT' required=true)
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
        Map<Id, SObject> oldFlowRecords = getOldFlowRecords(flowInput.recordsToRollup, sObjectType, flowInput.rollupFieldOnCalcItem);
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

  global static Id schedule(String jobName, String cronExp, String query, List<Id> rollupMetadataIds, Evaluator eval) {
    RollupSchedulable scheduledRollup = new RollupSchedulable(query, rollupMetadataIds, eval);
    return System.schedule(jobName, cronExp, scheduledRollup);
  }

  global static void batch(Rollup rollup, Rollup secondRollup) {
    batch(new List<Rollup>{ rollup, secondRollup });
  }

  global static void batch(Rollup rollup, Rollup secondRollup, Rollup thirdRollup) {
    batch(new List<Rollup>{ rollup, secondRollup, thirdRollup });
  }

  global static void batch(List<Rollup> rollups) {
    Rollup batchRollup = new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER);
    flattenBatches(batchRollup, rollups);
    batchRollup.runCalc();
  }

  global static Rollup averageFromTrigger(
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

  global static Rollup averageFromTrigger(
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

  global static Rollup countDistinctFromTrigger(
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

  global static Rollup countDistinctFromTrigger(
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

  global static Rollup concatDistinctFromTrigger(
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

  global static Rollup concatDistinctFromTrigger(
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

  global static Rollup concatFromTrigger(
    SObjectField concatFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField concatFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return concatFromTrigger(concatFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, concatFieldOnOperationObject, lookupSobjectType, null);
  }

  global static Rollup concatFromTrigger(
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

  global static Rollup countFromTrigger(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField countFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return countFromTrigger(countFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, countFieldOnOperationObject, lookupSobjectType, null);
  }

  global static Rollup countFromTrigger(
    SObjectField countFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(countFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, Op.COUNT, eval);
  }

  global static Rollup maxFromTrigger(
    SObjectField maxFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField maxFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return maxFromTrigger(maxFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, maxFieldOnOperationObject, lookupSobjectType, null);
  }

  global static Rollup maxFromTrigger(
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

  global static Rollup minFromTrigger(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOperationObject,
    SObjectType lookupSobjectType
  ) {
    return minFromTrigger(minFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, minFieldOnOperationObject, lookupSobjectType, null);
  }

  global static Rollup minFromTrigger(
    SObjectField minFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField minFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(minFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, minFieldOnOpOject, lookupSobjectType, Op.MIN, eval);
  }

  global static Rollup sumFromTrigger(
    SObjectField sumFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnOperationObject,
    SObjectField sumFieldOnOpOject,
    SObjectType lookupSobjectType,
    Evaluator eval
  ) {
    return operateFromTrigger(sumFieldOnCalcItem, lookupFieldOnCalcItem, lookupFieldOnOperationObject, sumFieldOnOpOject, lookupSobjectType, Op.SUM, eval);
  }

  global static Rollup sumFromTrigger(
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
    return runFromTrigger(new List<Rollup__mdt>{ rollupMetadata }, eval, getTriggerRecords(), getOldTriggerRecordsMap());
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
    SObjectType sObjectType = getSObjectTypeFromName(header.getEntityName());

    List<Rollup__mdt> rollupMetadata = getTriggerRollupMetadata(sObjectType);
    if (rollupMetadata.isEmpty()) {
      return;
    }

    DescribeSObjectResult objectDescribe = sObjectType.getDescribe();
    Set<String> uniqueFieldNames = new Set<String>{ 'Id' };
    for (Rollup__mdt rollupInfo : rollupMetadata) {
      uniqueFieldNames.add(getParedFieldName(rollupInfo.LookupFieldOnCalcItem__c, objectDescribe));
      uniqueFieldNames.add(getParedFieldName(rollupInfo.ROllupFieldOnCalcItem__c, objectDescribe));
    }

    // it would have been nice if this was an enum!
    switch on header.changeType {
      when 'CREATE', 'GAP_CREATE' {
        triggerContext = TriggerOperation.AFTER_INSERT;
      }
      when 'UPDATE', 'GAP_UPDATE' {
        triggerContext = TriggerOperation.AFTER_UPDATE;
      }
      when 'DELETE' {
        triggerContext = TriggerOperation.BEFORE_DELETE;
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

    Rollup rollupToReturn = runFromTrigger(rollupMetadata, null, cdcRecordsMap.values(), cdcRecordsMap);
    // because CDC is async, the DB will always be updated by the time we get there
    // for update, that means we always have to trigger a full recalc
    // the performance downsides should be negligible, given that we're already within an async context
    rollupToReturn.isForcedRecalc = triggerContext == TriggerOperation.AFTER_UPDATE;
    rollupToReturn.runCalc();
  }

  global static void runFromTrigger() {
    SObjectType sObjectType = getTriggerRecords().getSObjectType();
    List<Rollup__mdt> rollupMetadata = getTriggerRollupMetadata(sObjectType);
    runFromTrigger(rollupMetadata, null, getTriggerRecords(), getOldTriggerRecordsMap()).runCalc();
  }

  private static Rollup runFromTrigger(List<Rollup__mdt> rollupMetadata, Evaluator eval, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    if (shouldRunFromTrigger() == false) {
      return new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER);
    }

    String rollupContext;
    Boolean shouldReturn = false;

    switch on triggerContext {
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
      rollupInfo.RollupType__c = rollupContext + rollupInfo.RollupType__c;
    }

    return shouldReturn
      ? new RollupAsyncProcessor(RollupInvocationPoint.FROM_TRIGGER)
      : getRollup(rollupMetadata, calcItems.getSObjectType(), calcItems, oldCalcItems, eval, RollupInvocationPoint.FROM_TRIGGER);
  }

  /** end global-facing section, begin private static helpers */

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
    String flowContext = firstInput.rollupContext;
    if (String.isBlank(flowContext)) {
      flowContext = 'INSERT';
    } else if (flowContext == 'UPSERT') {
      flowContext = 'UPDATE';
    }

    return flowContext == 'INSERT' ? '' : flowContext + '_';
  }

  private static Map<Id, SObject> getOldFlowRecords(List<SObject> currentRecords, SObjectType sObjectType, String rollupFieldOnCalcItem) {
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
    Map<Id, SObject> existingOldRecordsMap = new Map<Id, SObject>(
      Database.query(getQueryString(sObjectType, new List<String>{ rollupFieldOnCalcItem }, 'Id', '='))
    );
    for (SObject currentRecord : currentRecords) {
      SObject existingRecordOrDefault = currentRecord.Id != null && existingOldRecordsMap.containsKey(currentRecord.Id)
        ? existingOldRecordsMap.get(currentRecord.Id)
        : (SObject) Type.forName(sObjectDescribe.getName()).newInstance();
      existingRecordOrDefault.Id = currentRecord.Id;
      SObjectField fieldToken = fieldTokensForObject.get(rollupFieldOnCalcItem);
      if (existingRecordOrDefault.get(rollupFieldOnCalcItem) != null || fieldToken.getDescribe().isUpdateable() == false) {
        continue;
      } else {
        existingRecordOrDefault.put(rollupFieldOnCalcItem, FieldInitializer.getDefaultValue(fieldToken));
      }
      existingOldRecordsMap.put(currentRecord.Id, existingRecordOrDefault);
    }
    return existingOldRecordsMap;
  }

  private static List<Rollup__mdt> getTriggerRollupMetadata(SObjectType sObjectType) {
    // Even after Spring '21, can't call .getAll here because the Developer Name restriction would disallow multiple rules per SObject
    return rollupMetadata != null
      ? rollupMetadata
      : [
          SELECT
            CalcItem__c,
            RollupFieldOnCalcItem__c,
            LookupObject__c,
            LookupFieldOnCalcItem__c,
            LookupFieldOnLookupObject__c,
            RollupFieldOnLookupObject__c,
            RollupType__c,
            ChangedFieldsOnCalcItem__c,
            FullRecalculationDefaultNumberValue__c,
            FullRecalculationDefaultStringValue__c,
            CalcItemWhereClause__c
          FROM Rollup__mdt
          WHERE CalcItem__c = :String.valueOf(sObjectType)
          ORDER BY LookupObject__c
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
      Op rollupOp = opNameToOp.get(rollupMetadata.RollupType__c);
      SObjectField rollupFieldOnCalcItem = getSObjectFieldByName(describeForSObject, rollupMetadata.RollupFieldOnCalcItem__c);
      SObjectField lookupFieldOnCalcItem = getSObjectFieldByName(describeForSObject, rollupMetadata.LookupFieldOnCalcItem__c);

      // NB - this SHOULD work even for SObjects part of managed packages
      SObjectType lookupSObjectType = getSObjectTypeFromName(rollupMetadata.LookupObject__c);
      DescribeSObjectResult lookupObjectDescribe = lookupSObjectType.getDescribe();
      Map<String, SObjectField> lookupFieldNameToLookupFields = lookupObjectDescribe.fields.getMap();
      SObjectField lookupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.LookupFieldOnLookupObject__c);
      SObjectField rollupFieldOnOpObject = getSObjectFieldByName(lookupObjectDescribe, rollupMetadata.RollupFieldOnLookupObject__c);

      // TODO: if they're BOTH not null
      if (eval == null && String.isNotBlank(rollupMetadata.ChangedFieldsOnCalcItem__c)) {
        eval = new SObjectChangedFieldEvaluator(rollupMetadata.ChangedFieldsOnCalcItem__c.split(','), oldCalcItems);
      } else if (eval == null && String.isNotBlank(rollupMetadata.CalcItemWhereClause__c)) {
        eval = new WhereFieldEvaluator(rollupMetadata.CalcItemWhereClause__c, sObjectType);
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

  // "entityDefinitionToFields" is lazy loaded, since it's only needed for custom fields
  private static Map<String, Map<String, String>> entityDefinitionToFields;
  private static SObjectField getSObjectFieldByName(DescribeSObjectResult objectDescribe, String desiredField) {
    Map<String, SObjectField> fieldNameToField = objectDescribe.fields.getMap();
    String paredFieldName = getParedFieldName(desiredField, objectDescribe);
    if (fieldNameToField.containsKey(paredFieldName)) {
      return fieldNameToField.get(paredFieldName);
    } else if (fieldNameToField.containsKey(paredFieldName + 'Id')) {
      // for lookup fields, CMDT field-level definition fields store the field name, which is outrageous
      return fieldNameToField.get(paredFieldName + 'Id');
    }
    // if the field name still doesn't match, chances are it's a custom field, which are stored differently in CMDT
    try {
      // this will throw if the pared field name is not an actual Id value
      Id testCustomField = Id.valueOf(paredFieldName);
      String currentObject = objectDescribe.getName();
      if (entityDefinitionToFields == null) {
        entityDefinitionToFields = new Map<String, Map<String, String>>();
      }
      if (entityDefinitionToFields.containsKey(currentObject) == false) {
        List<FieldDefinition> fieldDefinitions = [SELECT QualifiedApiName, DurableId FROM FieldDefinition WHERE EntityDefinitionId = :currentObject];
        for (FieldDefinition fieldDef : fieldDefinitions) {
          if (entityDefinitionToFields.containsKey(currentObject)) {
            entityDefinitionToFields.get(currentObject).put(fieldDef.DurableId, fieldDef.QualifiedApiName);
          } else {
            entityDefinitionToFields.put(currentObject, new Map<String, String>{ fieldDef.DurableId => fieldDef.QualifiedApiName });
          }
        }
      }
      String actualFieldName = entityDefinitionToFields.get(currentObject).get(desiredField);
      return fieldNameToField.get(actualFieldName);
    } catch (Exception ex) {
      // do nothing, it didn't work
    }

    return null;
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
    shouldRun = (shouldRun != null && shouldRun) || Trigger.isExecuting;
    // in order to accomodate CDC; we set the triggerContext manually there
    // since technically all CDC is done from an AFTER_INSERT context
    if (Trigger.operationType != null && isCDC == false) {
      triggerContext = Trigger.operationType;
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
    if (oldRecordsMap != null) {
      return oldRecordsMap;
    } else if (Trigger.oldMap != null) {
      return Trigger.oldMap;
    }

    return new Map<Id, SObject>();
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

  private static String getQueryString(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String lookupFieldOnLookupObject, String equality) {
    // again noting the coupling for consumers of this method
    // "objIds" is required to be present in the scope where the query is run
    return 'SELECT ' + String.join(uniqueQueryFieldNames, ',') + '\nFROM ' + sObjectType + '\nWHERE ' + lookupFieldOnLookupObject + ' ' + equality + ' :objIds';
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
          if (updatedLookupObject.get(rollup.opFieldOnLookupObject) == null || this.isFullRecalc) {
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
      if (lookupItem.get(rollup.opFieldOnLookupObject) == null || rollup.isFullRecalc) {
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
        Object newVal = this.getRollupVal(rollup, calcItems, priorVal, key, rollup.lookupFieldOnCalcItem);
        lookupRecord.put(rollup.opFieldOnLookupObject, newVal);
        if (priorVal != newVal) {
          recordsToUpdate.add(lookupRecord);
        }
      }
    }

    return recordsToUpdate;
  }

  private Object getRollupVal(Rollup rollup, List<SObject> calcItems, Object priorVal, String lookupRecordKey, SObjectField lookupKeyField) {
    RollupCalculator rollupCalc = this.getRollupType(priorVal, rollup, lookupRecordKey, lookupKeyField);
    rollupCalc.setisForcedRecalc(this.isForcedRecalc);
    rollupCalc.performRollup(rollup.op, calcItems, rollup.oldCalcItems, rollup.opFieldOnCalcItem);
    return rollupCalc.getReturnValue();
  }

  private RollupCalculator getRollupType(Object priorVal, Rollup roll, String lookupRecordKey, SObjectField lookupKeyField) {
    if (roll.op.name().contains(Rollup.Op.COUNT_DISTINCT.name())) {
      return new CountDistinctRollupCalculator(0, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (roll.op.name().contains(Rollup.Op.COUNT.name())) {
      return new CountRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (roll.op.name().contains(Rollup.Op.AVERAGE.name())) {
      return new AverageRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (priorVal instanceof Decimal) {
      return new DecimalRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (priorVal instanceof String) {
      return new PicklistRollupCalculator(priorVal, roll.opFieldOnCalcItem, roll.overrideForStringRollups, lookupRecordKey, lookupKeyField);
    } else if (priorVal instanceof Date) {
      // not obvious: the order of these else if's is of supreme importance
      // Date has to go before Datetime; in the same way that all numbers test true as an instanceof Decimal
      // all Dates test true as Datetimes ...
      return new DateRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (priorVal instanceof Time) {
      return new TimeRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
    } else if (priorval instanceof Datetime) {
      return new DatetimeRollupCalculator(priorVal, roll.opFieldOnLookupObject, roll.overrideForNumberRollups, lookupRecordKey, lookupKeyField);
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
      if (fieldDescribe.isDefaultedOnCreate() && fieldDescribe.getDefaultValue() != null) {
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
    private Boolean isForcedRecalc = false;
    private Boolean isFirstTimeThrough = true;

    protected final String lookupKeyQuery;

    protected Boolean shouldShortCircuit = false;
    protected Object returnVal;
    public RollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      if (defaultVal != null) {
        this.returnVal = defaultVal;
      } else {
        this.returnVal = priorVal == null ? FieldInitializer.getDefaultValue(operationField) : priorVal;
      }
      this.lookupKeyQuery = ' AND ' + lookupKeyField + ' = \'' + lookupRecordKey + '\'';
    }
    public virtual Object getReturnValue() {
      return this.returnVal;
    }

    public void setisForcedRecalc(Boolean isForcedRecalc) {
      this.isForcedRecalc = isForcedRecalc;
    }

    public virtual void performRollup(Op op, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      for (Integer index = 0; index < calcItems.size(); index++) {
        SObject calcItem = calcItems[index];
        if (this.shouldShortCircuit) {
          this.handleShortCircuit(op, calcItem, operationField);
          continue;
        } else if (this.isForcedRecalc) {
          // here we don't exclude items because the calc items have already been updated
          this.returnVal = this.calculateNewAggregateValue(new Set<Id>(), op, operationField, calcItem.getSObjectType());
          // not just a break, a return. We don't want to pass go - we don't want to call "setReturnValue" below
          return;
        } else {
          switch on op {
            when COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
              this.handleCountDistinct(op, calcItem, operationField);
            }
            when UPDATE_COUNT_DISTINCT {
              this.handleUpdateCountDistinct(op, calcItem, operationField, oldCalcItems);
            }
            when SUM, COUNT {
              this.handleSumOrCount(op, calcItem, operationField);
            }
            when UPDATE_SUM, UPDATE_COUNT {
              this.handleUpdateSumOrCount(op, calcItem, operationField, oldCalcItems);
            }
            when DELETE_SUM, DELETE_COUNT {
              this.handleDeleteSumOrCount(op, calcItem, operationField);
            }
            when MIN {
              this.handleMin(op, calcItem, operationField);
            }
            when MAX {
              this.handleMax(op, calcItem, operationField);
            }
            when UPDATE_MAX, UPDATE_MIN, DELETE_MAX, DELETE_MIN {
              this.handleUpdateMinOrMax(op, calcItem, operationField, oldCalcItems);
            }
            when CONCAT, CONCAT_DISTINCT {
              this.handleConcat(op, calcItem, operationField);
            }
            when UPDATE_CONCAT, UPDATE_CONCAT_DISTINCT {
              this.handleUpdateConcat(op, calcItem, operationField, oldCalcItems);
            }
            when DELETE_CONCAT, DELETE_CONCAT_DISTINCT {
              this.handleDeleteConcat(op, calcItem, operationField);
            }
          }
        }

        if (this.shouldShortCircuit && this.isFirstTimeThrough) {
          /**
           * an example of short circuiting - halfway through the list during a MIN operation,
           * Rollup encounters a calcItem whose previous value equals the current min, but the new value
           * is greater than the min. This triggers a full recalc, since it is at once both possible
           * for items outside the list of calcItems to contain the new min, as WELL as for an item
           * WITHIN the existing calcItems to be the new min. This means we have to go back and re-process
           * the records that were already iterated on to ensure that the current operation successfully accounts
           * for everything in-memory and in the database
           */
          this.isFirstTimeThrough = false;
          index = 0; // resets the for-loop
        }
      }
      this.setReturnValue();
    }

    // all of these are no-ops by default; child classes opt-in to the rollup types applicable
    public virtual void handleCountDistinct(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleUpdateCountDistinct(Op op, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
    }
    public virtual void handleSumOrCount(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleUpdateSumOrCount(Op op, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
    }
    public virtual void handleDeleteSumOrCount(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleMin(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleMax(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleUpdateMinOrMax(Op op, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
    }
    public virtual void handleConcat(Op op, SObject calcItem, SObjectField operationField) {
    }
    public virtual void handleUpdateConcat(Op op, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
    }
    public virtual void handleDeleteConcat(Op op, SObject calcItem, SObjectField operationField) {
    }
    protected virtual void handleShortCircuit(Op op, SObject calcItem, SObjectField operationField) {
    }
    protected virtual void setReturnValue() {
    }

    protected virtual Object calculateNewAggregateValue(Set<Id> objIds, Op operation, SObjectField operationField, SObjectType sObjectType) {
      String operationName = operation.name().contains('_') ? operation.name().substringAfter('_') : operation.name();
      String alias = operationName.toLowerCase() + 'Field';
      String query = getQueryString(sObjectType, new List<String>{ operationName + '(' + operationField + ')' + alias }, 'Id', '!=') + this.lookupKeyQuery;
      List<SObject> aggregate = Database.query(query);
      return aggregate.isEmpty() == false ? aggregate[0].get(alias) : null;
    }
  }

  private class CountDistinctRollupCalculator extends RollupCalculator {
    private final Set<Object> distinctValues;
    public CountDistinctRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
      this.distinctValues = new Set<Object>();
      if (this.returnVal != FieldInitializer.getDefaultValue(operationfield)) {
        this.distinctValues.add(this.returnVal);
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.distinctValues.size();
    }

    protected override void handleShortCircuit(Op op, SObject calcItem, SObjectField operationField) {
      Object currentVal = calcItem.get(operationField);
      if (currentVal != null) {
        this.distinctValues.add(currentVal);
      }
    }

    public override void handleCountDistinct(Op operation, SObject calcItem, SObjectField operationField) {
      if (operation != Op.DELETE_COUNT_DISTINCT && calcItem.get(operationField) != null) {
        this.distinctValues.add(calcItem.get(operationField));
      }
      this.shouldShortCircuit = true;
      this.calculateNewAggregateValue(new Set<Id>{ calcItem.Id }, operation, operationField, calcItem.getSObjectType());
    }

    public override void handleUpdateCountDistinct(Op operation, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      Object currentVal = calcItem.get(operationField);
      Object priorCalcVal = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : currentVal;
      if (currentVal != priorCalcVal) {
        this.distinctValues.add(currentVal);
        this.shouldShortCircuit = true;
        this.calculateNewAggregateValue(oldCalcItems.keySet(), operation, operationField, calcItem.getSObjectType());
      }
    }

    protected override Object calculateNewAggregateValue(Set<Id> objIds, Op operation, SObjectField operationField, SObjectType sObjectType) {
      Boolean isGroupable = operationField.getDescribe().isGroupable();
      List<String> queryFields = new List<String>{ String.valueOf(operationField) };
      if (isGroupable) {
        queryFields.add('COUNT(Id)');
      }
      String query = getQueryString(sObjectType, queryFields, 'Id', '!=') + this.lookupKeyQuery + (isGroupable ? (' GROUP BY ' + operationField) : '');
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
    private Decimal returnDecimal;
    public DecimalRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
      this.returnDecimal = (Decimal) this.returnVal;
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

    protected override void handleShortCircuit(Op op, SObject calcItem, SObjectField operationField) {
      switch on op {
        when UPDATE_MAX {
          // re-maxing by way of query has occurred, but is it **correct**?
          // if one of the other updated calcItems is numerically superior, assign the new max
          Decimal newVal = this.getNumericValue(calcItem, operationField);
          if (newVal > returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
        when UPDATE_MIN {
          // re-"min"-ing has occurred by way of query, but is an in-memory calcItem even less?
          Decimal newVal = this.getNumericValue(calcItem, operationField);
          if (newVal < returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
      }
    }

    public override void handleSumOrCount(Op op, SObject calcItem, SObjectField operationField) {
      this.returnDecimal += this.getNumericValue(calcItem, operationField);
    }

    public override void handleUpdateSumOrCount(Op op, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      this.returnDecimal += this.getNumericChangedValue(calcItem, operationField, oldCalcItems);
    }

    public override void handleDeleteSumOrCount(Op op, SObject calcItem, SObjectField operationField) {
      this.returnDecimal -= this.getNumericValue(calcItem, operationField);
    }

    public override void handleMax(Op op, SObject calcItem, SObjectField operationField) {
      Decimal numericValue = this.getNumericValue(calcItem, operationField);
      if (numericValue > this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleMin(Op op, SObject calcItem, SObjectField operationField) {
      Decimal numericValue = this.getNumericValue(calcItem, operationField);
      if (numericValue < this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleUpdateMinOrMax(Op operation, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      Decimal newVal = this.getNumericValue(calcItem, operationField);
      Decimal thisPriorVal = this.getNumericValue((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem), operationField);
      if (
        (operation.name().contains(Op.MAX.name()) && thisPriorVal != 0 && thisPriorVal == this.returnDecimal && newVal <= thisPriorVal) ||
        (operation.name().contains(Op.MIN.name()) &&
        thisPriorVal != 0 &&
        thisPriorVal == this.returnDecimal &&
        newVal >= thisPriorVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = (Decimal) this.calculateNewAggregateValue(oldCalcItems.keySet(), operation, operationField, calcItem.getSObjectType());
        this.returnDecimal = this.getDecimalOrDefault(potentialReturnValue);
        if (this.returnDecimal == 0) {
          this.returnDecimal = operation == Op.UPDATE_MAX ? FieldInitializer.minimumLongValue : FieldInitializer.maximumLongValue;
        }
      } else if (operation == Op.UPDATE_MAX && newVal > this.returnDecimal) {
        this.returnDecimal = newVal;
      } else if (operation == Op.UPDATE_MIN && newVal < this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = newVal;
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.returnDecimal;
    }

    protected virtual override Object calculateNewAggregateValue(Set<Id> objIds, Op operation, SObjectField operationField, SObjectType sObjectType) {
      Object aggregate;
      try {
        aggregate = super.calculateNewAggregateValue(objIds, operation, operationField, sObjectType);
      } catch (Exception ex) {
        Decimal minOrMax;
        List<SObject> allOtherItems = Database.query(
          getQueryString(sObjectType, new List<String>{ String.valueOf(operationField) }, 'Id', '!=') + this.lookupKeyQuery
        );
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
    public DatetimeRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(((Datetime) priorVal).getTime(), operationField, defaultVal, lookupRecordKey, lookupKeyField);
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
    public DateRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(Datetime.newInstanceGmt((Date) priorVal, Time.newInstance(0, 0, 0, 0)), operationField, defaultVal, lookupRecordKey, lookupKeyField);
    }

    public override Object getReturnValue() {
      return ((Datetime) super.getReturnValue()).dateGmt();
    }
  }

  private class TimeRollupCalculator extends DatetimeRollupCalculator {
    public TimeRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(Datetime.newInstanceGmt(FieldInitializer.defaultDateTime.dateGmt(), (Time) priorVal), operationField, defaultVal, lookupRecordKey, lookupKeyField);
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
    public CountRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
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
    // for now, hard-coding to comma here. We may update this to allow for CMDT-based overrides of the delimiter
    private final String concatDelimiter = ', ';
    private String stringVal;
    public StringRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
      this.stringVal = (String) this.returnVal;
    }

    protected override void setReturnValue() {
      String possibleReturnValue = this.stringVal.normalizeSpace();
      String withoutEndingComma = possibleReturnValue.endsWith(',') ? possibleReturnValue.substring(0, possibleReturnValue.length() - 1) : possibleReturnValue;
      this.returnVal = (withoutEndingComma.startsWith(',') ? withoutEndingComma.substring(1, withoutEndingComma.length()) : withoutEndingComma).trim();
    }

    protected override void handleShortCircuit(Op op, SObject calcItem, SObjectField operationField) {
      String newVal = (String) calcItem.get(operationField);
      switch on op {
        when UPDATE_MAX, UPDATE_MIN {
          if (this.isTrueFor(op, newVal, this.stringVal)) {
            this.stringVal = newVal;
          }
        }
      }
    }

    public override void handleConcat(Op operation, SObject calcItem, SObjectField operationField) {
      Boolean isConcatDistinct = operation.name().contains(Op.CONCAT_DISTINCT.name());
      String newVal = (String) calcItem.get(operationField);
      if (isConcatDistinct && this.stringVal.contains(newVal)) {
        // skip
      } else {
        this.stringVal += this.concatWithDelimiter(newVal);
      }
    }

    public override void handleUpdateConcat(Op operation, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      Boolean isConcatDistinct = operation.name().contains(Op.CONCAT_DISTINCT.name());
      String newVal = (String) calcItem.get(operationField);
      String priorString = (String) (oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : newVal);
      if (isConcatDistinct && this.stringVal.contains(newVal) == false || !isConcatDistinct) {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, priorString, newVal);
      }
    }

    public override void handleDeleteConcat(Op operation, SObject calcItem, SObjectField operationField) {
      String existingVal = (String) calcItem.get(operationField);
      this.stringVal = this.replaceWithDelimiter(this.stringVal, existingVal, '');
    }

    public override void handleMin(Op operation, SObject calcItem, SObjectField operationField) {
      String newVal = (String) calcItem.get(operationField);
      if (this.isTrueFor(operation, newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }
    public override void handleMax(Op operation, SObject calcItem, SObjectField operationField) {
      this.handleMin(operation, calcItem, operationField);
    }
    public override void handleUpdateMinOrMax(Op operation, SObject calcItem, SObjectField operationField, Map<Id, SObject> oldCalcItems) {
      String newVal = (String) calcItem.get(operationField);
      String priorString = (String) (oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(operationField) : newVal);

      if (
        (operation.name().contains(Op.MAX.name()) && priorString == this.stringVal && newVal <= this.stringVal) ||
        (operation.name().contains(Op.MIN.name()) &&
        priorString == this.stringVal &&
        newVal >= this.stringVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(oldCalcItems.keySet(), operation, operationField, calcItem.getSObjectType());
        this.stringVal = potentialReturnValue == null ? '' : (String) potentialReturnValue;
      } else if (this.isTrueFor(operation, newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    protected virtual Boolean isTrueFor(Op operation, String newVal, String priorVal) {
      if (operation.name().contains(Op.MAX.name())) {
        return newVal > priorVal || String.isBlank(priorVal);
      } else if (operation.name().contains(Op.MIN.name())) {
        return newVal < priorVal || String.isBlank(priorVal);
      }
      return false;
    }

    private String concatWithDelimiter(String newVal) {
      return this.concatDelimiter + newVal + this.concatDelimiter;
    }

    private String replaceWithDelimiter(String existingVal, String matchingVal, String replacementVal) {
      if (existingVal.contains(matchingVal)) {
        return existingVal.replace(matchingVal, replacementVal) + this.concatDelimiter;
      }
      return existingVal += replacementVal + this.concatDelimiter;
    }
  }

  private class PicklistRollupCalculator extends StringRollupCalculator {
    private final PicklistController picklistController;
    public PicklistRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
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
    public AverageRollupCalculator(Object priorVal, SObjectField operationField, Object defaultVal, String lookupRecordKey, SObjectField lookupKeyField) {
      super(priorVal, operationField, defaultVal, lookupRecordKey, lookupKeyField);
    }
    public override void performRollup(Op operation, List<SObject> calcItems, Map<Id, SObject> oldCalcItems, SObjectField operationField) {
      Decimal average = (Decimal) this.returnVal;
      if (calcItems.isEmpty()) {
        return;
      }

      // the List isn't strongly typed at this point, otherwise we could avoid this shameful statement
      SObjectType sObjectType = calcItems[0].getSobjectType();
      Set<Id> objIds = new Map<Id, SObject>(calcItems).keySet();
      Integer countOfPreExistingItems = Database.countQuery(getQueryString(sObjectType, new List<String>{ 'Count()' }, 'Id', '!=') + this.lookupKeyQuery);
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
          LookupFieldOnLookupObject__c,
          RollupFieldOnLookupObject__c,
          RollupType__c,
          ChangedFieldsOnCalcItem__c,
          FullRecalculationDefaultNumberValue__c,
          FullRecalculationDefaultStringValue__c,
          CalcItemWhereClause__c
        FROM Rollup__mdt
        WHERE Id = :this.rollupMetadataIds
        ORDER BY LookupObject__c
      ];
      List<SObject> calcItems = Database.query(this.query);
      getRollup(rollupMetadata, calcItems.getSObjectType(), calcItems, new Map<Id, SObject>(calcItems), this.eval, RollupInvocationPoint.FROM_SCHEDULED)
        .runCalc();
    }
  }
}
