global virtual without sharing class RollupAsyncProcessor extends Rollup implements Database.Batchable<SObject>, System.Comparable {
  private final SObjectField opFieldOnCalcItem;
  private final SObjectField lookupFieldOnCalcItem;
  private final SObjectField lookupFieldOnLookupObject;
  private final SObjectField opFieldOnLookupObject;
  private final SObjectType lookupObj;
  private final Evaluator eval;
  private final Op op;

  private final List<RollupAsyncProcessor> deferredRollups = new List<RollupAsyncProcessor>();
  private final List<RollupAsyncProcessor> syncRollups = new List<RollupAsyncProcessor>();

  protected final List<SObject> calcItems;
  protected final Map<Id, SObject> oldCalcItems;
  protected final Rollup__mdt metadata;
  protected final SObjectType calcItemType;

  private RollupRelationshipFieldFinder.Traversal traversal;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private Map<SObjectType, Set<String>> calcObjectToUniqueFieldNames;
  private List<SObject> lookupItems;
  private RollupAsyncProcessor fullRecalcProcessor;

  private static final RollupSettings__c SETTINGS = RollupSettings__c.getInstance();
  private static Integer stackDepth = 0;
  private static Boolean isRunningAsync = false;
  @testVisible
  private static Boolean shouldRunAsBatch = false;

  private class RollupAsyncSaver implements System.Queueable {
    private final List<SObject> records;
    public RollupAsyncSaver(List<SObject> records) {
      this.records = records;
    }

    public void execute(QueueableContext context) {
      new DMLHelper().doUpdate(this.records);
    }
  }

  public static void flatten(List<RollupAsyncProcessor> stackedRollups) {
    Map<String, RollupAsyncProcessor> rollupOperationToRollup = new Map<String, RollupAsyncProcessor>();
    Integer counter = 0;
    Map<String, List<String>> operationToProcessedRecords = new Map<String, List<String>>();
    for (RollupAsyncProcessor stackedRollup : stackedRollups) {
      // If the hashed contents are the same, we can't collapse
      // the two rollup operations, and instead have to juggle the updated values for the parent in memory
      String rollupKey = stackedRollup.getHashedContents();
      Boolean shouldAddSameRollupOperation = false;

      if (rollupOperationToRollup.containsKey(rollupKey)) {
        RollupAsyncProcessor matchingRollup = rollupOperationToRollup.get(rollupKey);
        for (Integer index = stackedRollup.calcItems.size() - 1; index >= 0; index--) {
          SObject calcItem = stackedRollup.calcItems[index];
          if (matchingRollup.calcItems.contains(calcItem) == false && operationToProcessedRecords.containsKey(rollupKey) == false) {
            doBookkeepingOnCachedItems(matchingRollup, stackedRollup, operationToProcessedRecords, calcItem, rollupKey, index);
          } else if (
            matchingRollup.calcItems.contains(calcItem) == false &&
            operationToProcessedRecords.containsKey(rollupKey) &&
            operationToProcessedRecords.get(rollupKey).contains(calcItem.Id) == false
          ) {
            doBookkeepingOnCachedItems(matchingRollup, stackedRollup, operationToProcessedRecords, calcItem, rollupKey, index);
          }
        }

        if (stackedRollup.calcItems.isEmpty() == false) {
          shouldAddSameRollupOperation = true;
        }
      } else {
        rollupOperationToRollup.put(rollupKey, stackedRollup);
      }
      if (shouldAddSameRollupOperation) {
        counter++;
        rollupOperationToRollup.put(rollupKey + counter, stackedRollup);
      }
    }
    stackedRollups.clear();
    stackedRollups.addAll(rollupOperationToRollup.values());
  }

  public static RollupAsyncProcessor getProcessor(
    List<SObject> calcItems,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItem,
    Op operation,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    InvocationPoint rollupInvokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt metadata
  ) {
    return new QueueableProcessor(
      calcItems,
      opFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnLookupObject,
      opFieldOnLookupObject,
      lookupObj,
      calcItem,
      operation,
      oldCalcItems,
      eval,
      rollupInvokePoint,
      rollupControl,
      metadata
    );
  }

  public RollupAsyncProcessor(InvocationPoint invokePoint) {
    super(invokePoint);
    this.isBatched = true;
    // a batch only becomes valid if other Rollups are added to it
    this.isNoOp = true;
  }

  public RollupAsyncProcessor(RollupAsyncProcessor innerRollup, Op op, List<SObject> calcItems) {
    this(
      calcItems,
      innerRollup.opFieldOnCalcItem,
      innerRollup.lookupFieldOnCalcItem,
      innerRollup.lookupFieldOnLookupObject,
      innerRollup.opFieldOnLookupObject,
      innerRollup.lookupObj,
      innerRollup.calcItemType,
      op,
      innerRollup.oldCalcItems,
      null, // eval gets assigned below
      innerRollup.invokePoint,
      innerRollup.rollupControl,
      innerRollup.metadata
    );

    this.rollups.addAll(innerRollup.rollups);
    this.isNoOp = this.rollups.isEmpty() && innerRollup.metadata?.IsFullRecordSet__c == false;
    this.isFullRecalc = innerRollup.isFullRecalc;
    this.isCDCUpdate = innerRollup.isCDCUpdate;
    this.eval = innerRollup.eval;
  }

  public RollupAsyncProcessor(RollupAsyncProcessor innerRollup) {
    this(innerRollup, innerRollup.op, innerRollup.calcItems);
  }

  public RollupAsyncProcessor(
    List<SObject> calcItems,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItemType,
    Op op,
    Map<Id, SObject> oldCalcItems,
    Evaluator eval,
    InvocationPoint invokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt rollupMetadata
  ) {
    super();
    this.calcItems = calcItems;
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.lookupFieldOnCalcItem = lookupFieldOnCalcItem;
    this.lookupFieldOnLookupObject = lookupFieldOnLookupObject;
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.lookupObj = lookupObj;
    this.calcItemType = calcItemType;
    this.op = op;
    this.oldCalcItems = oldCalcItems;
    this.invokePoint = invokePoint;
    this.rollupControl = rollupControl;
    this.metadata = rollupMetadata;
    this.isBatched = false;

    if (eval != null) {
      this.eval = eval;
    }

    this.isNoOp = this.calcItems?.isEmpty() == true && this.metadata?.IsFullRecordSet__c == false;
  }

  public Integer compareTo(Object otherRollup) {
    Integer numberToReturn = 0;
    if (otherRollup instanceof Rollup) {
      RollupAsyncProcessor that = (RollupAsyncProcessor) otherRollup;
      Boolean thisDelete = this.op.name().contains('DELETE');
      Boolean thatDelete = that.op.name().contains('DELETE');
      Boolean thisUpdate = this.op.name().contains('UPDATE');
      Boolean thatUpdate = that.op.name().contains('UPDATE');
      Boolean thisInsert = thisDelete == false && thisUpdate == false;
      Boolean thatInsert = thatDelete == false && thatUpdate == false;

      // INSERT operations always come first, then UPDATEs, then DELETEs (UNDELETEs are transformed to INSERT)
      if (thisInsert && (thatUpdate || thatDelete)) {
        numberToReturn = -1;
      } else if ((thisUpdate || thisDelete) && thatInsert) {
        numberToReturn = 1;
      } else if (thatUpdate && thisDelete) {
        numberToReturn = 1;
      } else if (thisUpdate && thatDelete) {
        numberToReturn = -1;
      }
    }

    return numberToReturn;
  }

  public override String toString() {
    Map<String, String> props = new Map<String, String>{
      'Invocation Point' => this.invokePoint.name(),
      'Calc Items' => JSON.serializePretty(this.calcItems),
      'Old Calc Items' => JSON.serializePretty(this.oldCalcItems),
      'Rollup Metadata' => JSON.serializePretty(this.metadata),
      'Rollup Control' => JSON.serializePretty(this.rollupControl),
      'Is Full Recalc' => String.valueOf(this.isFullRecalc),
      'Is No Op' => String.valueOf(this.isNoOp)
    };
    String baseString = '';
    for (String key : props.keySet()) {
      baseString += key + ': ' + props.get(key) + '\n';
    }
    return baseString.removeEnd('\n');
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
    for (RollupAsyncProcessor rollup : this.rollups) {
      sObjectType = rollup.lookupObj;
      lookupFieldForLookupObject = rollup.lookupFieldOnLookupObject.getDescribe().getName();
      objIds.addAll(this.getCalcItemsByLookupField(rollup, this.lookupObjectToUniqueFieldNames.get(sObjectType)).keySet());
    }
    String query = RollupQueryBuilder.Current.getQuery(
      sObjectType,
      new List<String>(this.lookupObjectToUniqueFieldNames.get(sObjectType)),
      lookupFieldForLookupObject,
      '='
    );
    RollupLogger.Instance.log('starting batch with query: ', query, LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
    return Database.getQueryLocator(query);
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> lookupItems) {
    for (RollupAsyncProcessor rollup : this.rollups) {
      this.initializeRollupFieldDefaults(lookupItems, rollup);
    }
    this.lookupItems = lookupItems;
    this.process(this.rollups);
    RollupLogger.Instance.save();
  }

  public virtual void finish(Database.BatchableContext context) {
    RollupLogger.Instance.log('batch finished successfully', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
  }

  public override String runCalc() {
    // side effect in the below method - rollups can be removed from this.rollups if a control record ShouldAbortRun__c == true
    this.ingestRollupControlData();

    if (this.isNoOp) {
      this.isNoOp = this.rollups.isEmpty() && this.syncRollups.isEmpty();
    }

    String rollupProcessId = 'No process Id';
    if (this.isNoOp || this.rollupControl.ShouldAbortRun__c || SETTINGS.IsEnabled__c == false) {
      RollupLogger.Instance.save();
      return rollupProcessId;
    }

    Boolean hasMoreThanOneTarget = false;
    Integer totalCountOfRecords = this.getLookupRecordsCount(hasMoreThanOneTarget);

    shouldRunAsBatch =
      shouldRunAsBatch ||
      hasMoreThanOneTarget == false &&
      ((this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.BATCHABLE &&
      totalCountOfRecords >= this.rollupControl.MaxLookupRowsBeforeBatching__c) || totalCountOfRecords == RollupQueryBuilder.SENTINEL_COUNT_VALUE);
    if (this.syncRollups.isEmpty() == false) {
      RollupLogger.Instance.log('about to process sync rollups', LoggingLevel.DEBUG);
      this.process(this.syncRollups);
      rollupProcessId = 'Running rollups flagged to go synchronously';
    } else {
      rollupProcessId = this.getAsyncRollup().beginAsyncRollup();
    }
    RollupLogger.Instance.save();
    return rollupProcessId;
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    // swap off on which async process is running to achieve infinite scaling
    isRunningAsync = true;
    Boolean canEnqueue = Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
    Boolean isAsyncInnerClass = this instanceof QueueableProcessor;
    RollupAsyncProcessor roll;
    // deferred rollups delay the full batch recalc
    // till all the others have gone
    if (this.rollups.size() == 1 && this.rollups[0] instanceof RollupFullBatchRecalculator) {
      roll = this.rollups[0];
    } else if (this instanceof RollupFullBatchRecalculator) {
      roll = this;
    } else if (shouldRunAsBatch && System.isBatch() == false) {
      // safe to batch because the QueryLocator will only return one type of SObject
      // we have to re-initialize the rollup because it's the Queueable inner class
      // at this point, and without re-initialization we get "System.UnexpectedException: Error processing messages"
      roll = new RollupAsyncProcessor(this);
    } else if (canEnqueue && System.isQueueable() == false && isAsyncInnerClass == false) {
      roll = new QueueableProcessor(this);
    } else if (canEnqueue && isAsyncInnerClass) {
      roll = this;
    } else {
      // the end of the line
      this.throwWithRollupData(this.rollups);
    }

    return roll;
  }

  private class QueueableProcessor extends RollupAsyncProcessor implements System.Queueable {
    private QueueableProcessor(
      List<SObject> calcItems,
      SObjectField opFieldOnCalcItem,
      SObjectField lookupFieldOnCalcItem,
      SObjectField lookupFieldOnLookupObject,
      SObjectField opFieldOnLookupObject,
      SObjectType lookupObj,
      SObjectType calcItem,
      Op operation,
      Map<Id, SObject> oldCalcItems,
      Evaluator eval,
      InvocationPoint rollupInvokePoint,
      RollupControl__mdt rollupControl,
      Rollup__mdt metadata
    ) {
      super(
        calcItems,
        opFieldOnCalcItem,
        lookupFieldOnCalcItem,
        lookupFieldOnLookupObject,
        opFieldOnLookupObject,
        lookupObj,
        calcItem,
        operation,
        oldCalcItems,
        eval,
        rollupInvokePoint,
        rollupControl,
        metadata
      );
    }

    private QueueableProcessor(InvocationPoint rollupInvokePoint) {
      super(rollupInvokePoint);
    }

    private QueueableProcessor(RollupAsyncProcessor roll) {
      super(roll);
    }

    protected override String beginAsyncRollup() {
      RollupLogger.Instance.log('about to queue', LoggingLevel.DEBUG);
      RollupLogger.Instance.save();
      return System.enqueueJob(this);
    }

    protected override List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
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
          String queryString = RollupQueryBuilder.Current.getQuery(
            rollup.lookupObj,
            new List<String>(uniqueQueryFieldNames),
            String.valueOf(rollup.lookupFieldOnLookupObject),
            '='
          );
          // non-obvious coupling between "objIds" and the computed "queryString", which uses dynamic variable binding
          localLookupItems = Database.query(queryString);
        }
        this.initializeRollupFieldDefaults(localLookupItems, rollup);
        return localLookupItems;
      }
    }

    public void execute(System.QueueableContext qc) {
      this.process(this.rollups);
      RollupLogger.Instance.log('queueable finished successfully', LoggingLevel.DEBUG);
      RollupLogger.Instance.save();
    }
  }

  protected virtual String beginAsyncRollup() {
    RollupLogger.Instance.log('about to start batch', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
    return Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
  }

  protected virtual List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute method"
    return this.lookupItems;
  }

  protected void processDelegatedFullRecalcRollup(List<Rollup__mdt> rollupInfo, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    isRunningAsync = true; // the first rollup can immediately start rolling up, instead of dispatching to a queueable / another batchable
    RollupAsyncProcessor roll = this.getAsyncRollup(rollupInfo, this.calcItemType, calcItems, oldCalcItems, null, this.invokePoint);
    roll.isFullRecalc = true;
    roll.fullRecalcProcessor = this;
    roll.runCalc();
  }

  protected virtual void retrieveAdditionalCalcItems(Map<String, Rollup.CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    // TODO - incorporate grandparent rollups into this, as well
    if (rollup.isFullRecalc == false || String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c)) {
      return;
    }

    Set<String> objIds = new Set<String>();
    for (String lookupKey : lookupToCalcItems.keySet()) {
      Rollup.CalcItemBag bag = lookupToCalcItems.get(lookupKey);
      if (bag.hasQueriedForAdditionalItems == false) {
        bag.hasQueriedForAdditionalItems = true;
        for (SObject calcItem : bag.originals) {
          objIds.add(calcItem.Id);
        }
      }
    }

    if (objIds.isEmpty() == false) {
      Set<String> lookupKeys = lookupToCalcItems.keySet();
      String whereClause = String.valueOf(rollup.lookupFieldOnCalcItem) + ' = :lookupKeys';
      Map<Schema.SObjectType,Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null ? rollup.calcObjectToUniqueFieldNames : this.calcObjectToUniqueFieldNames;
      String query = RollupQueryBuilder.Current.getQuery(
        rollup.calcItemType,
        new List<String>(localCalcToUniqueFieldNames.get(rollup.calcItemType)),
        'Id',
        '!=',
        whereClause
      );
      List<SObject> additionalCalcItems = Database.query(query);

      for (SObject additionalCalcItem : additionalCalcItems) {
        String lookupKey = (String) additionalCalcItem.get(rollup.lookupFieldOnCalcItem);
        if (lookupToCalcItems.containsKey(lookupKey)) {
          Rollup.CalcItemBag bag = lookupToCalcItems.get(lookupKey);
          bag.additional.add(additionalCalcItem);
        }
      }
    }
  }

  protected void process(List<RollupAsyncProcessor> rollups) {
    this.handleMultipleDMLRollupsEnqueuedInTheSameTransaction(rollups);
    this.getFieldNamesForRollups(rollups); // populates this.lookupObjectToUniqueFieldNames

    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<SObjectType, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<SObjectType, RollupRelationshipFieldFinder.Traversal>();
    for (RollupAsyncProcessor roll : rollups) {
      RollupLogger.Instance.log('starting rollup for: ', roll, LoggingLevel.DEBUG);
      // for each iteration, ensure we're not operating beyond the bounds of our query limits
      if (hasExceededCurrentRollupLimits(roll.rollupControl) || roll instanceof RollupFullBatchRecalculator) {
        this.deferredRollups.add(roll);
        continue;
      }

      if (grandparentRollups.containsKey(roll.lookupObj) && roll.traversal == null) {
        roll.traversal = grandparentRollups.get(roll.lookupObj);
      }

      Map<String, Rollup.CalcItemBag> calcItemsByLookupField = this.getCalcItemsByLookupField(roll, this.lookupObjectToUniqueFieldNames.get(roll.lookupObj));
      // some rollups may not finish retrieving all parent rows the first time around - and that's ok! we can keep
      // trying until all necessary records have been retrieved
      if (roll.traversal?.getIsFinished() == false) {
        this.deferredRollups.add(roll);
        continue;
      } else if (roll.traversal != null && grandparentRollups.containsKey(roll.lookupObj) == false) {
        // cache the traversal for any future callers - because we queried for ALL unique grand(or greater)parent fields
        // we don't need to re-traverse the whole object chain again if there are other grandparent rollups in the list
        grandparentRollups.put(roll.lookupObj, roll.traversal);
      }

      List<SObject> localLookupItems = this.getLookupItems(calcItemsByLookupField, updatedLookupRecords, roll);
      List<SObject> updatedParentRecords = this.getUpdatedLookupItemsByRollup(roll, calcItemsByLookupField, localLookupItems);
      for (SObject updatedRecord : updatedParentRecords) {
        updatedLookupRecords.put(updatedRecord.Id, updatedRecord);
      }
    }

    this.splitUpdates(updatedLookupRecords);

    this.getDML().doUpdate(updatedLookupRecords.values());

    this.processDeferredRollups();
  }

  private String getHashedContents() {
    // the only thing that necessarily makes a rollup unique is the sum total of the metadata behind it
    // as well as the calc items driving that calculation.
    // you could have multiple rollups with different calc item where clauses all rolling up to the same field
    // even worse - in situations where multiple DML operations are enqueued in the same transaction
    // the same calc items by Id might differ slightly by field value.
    return String.valueOf(this.metadata);
  }

  private void handleMultipleDMLRollupsEnqueuedInTheSameTransaction(List<Rollup> rolls) {
    // if items are inserted, updated, deleted (etc ...)
    // all in the same transaction, they can be introduced out of order
    // (e.g. the update rollup appears first in the list)
    // this sort restores the rollups to their proper ordering
    for (Rollup cachedRoll : this.getCachedRollups()) {
      if (cachedRoll.isNoOp == false) {
        rolls.add(cachedRoll);
      }
    }
    this.getCachedRollups().clear();
    rolls.sort();
  }

  private List<SObject> getLookupItems(
    Map<String, Rollup.CalcItemBag> calcItemsByLookupField,
    Map<String, SObject> updatedLookupRecords,
    RollupAsyncProcessor roll
  ) {
    List<SObject> localLookupItems = new List<SObject>();
    Set<String> lookupItemKeys = new Set<String>(calcItemsByLookupField.keySet());
    for (String lookupId : calcItemsByLookupField.keySet()) {
      if (updatedLookupRecords.containsKey(lookupId)) {
        lookupItemKeys.remove(lookupId);
        // this way, the updated values are persisted for each field, and the default values are initialized
        SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
        this.resetLookupFieldsForNullOrFullRecalcs(updatedLookupObject, roll);
        localLookupItems.add(updatedLookupObject);
      }
    }
    localLookupItems.addAll(roll.getExistingLookupItems(lookupItemKeys, roll, this.lookupObjectToUniqueFieldNames.get(roll.lookupObj)));
    return localLookupItems;
  }

  private void splitUpdates(Map<String, SObject> updatedLookupRecords) {
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
  }

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty() == false && this.getIsDeferralAllowed() && stackDepth < this.rollupControl?.MaxRollupRetries__c) {
      stackDepth++;
      // tragic, but necessary due to limits on requeueing allowed during testing
      this.setIsDeferralAllowed(Test.isRunningTest() == false && this.rollupControl.MaxRollupRetries__c > stackDepth);

      this.rollups.clear();
      this.rollups.addAll(this.deferredRollups);
      this.deferredRollups.clear();

      this.getAsyncRollup().beginAsyncRollup();
    } else if (this.deferredRollups.isEmpty() == false) {
      this.throwWithRollupData(this.deferredRollups);
    }
  }

  private void throwWithRollupData(List<Rollup> rolls) {
    String exceptionString = 'rollup failed to re-queue for: ';
    RollupLogger.Instance.log(exceptionString, rolls, LoggingLevel.ERROR);
    throw new AsyncException(exceptionString + rolls);
  }

  private void getFieldNamesForRollups(List<RollupAsyncProcessor> rollups) {
    this.lookupObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    this.calcObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    for (RollupAsyncProcessor rollup : rollups) {
      if (rollup.lookupObj == null) {
        continue;
      }
      String rollupField = rollup.opFieldOnLookupObject.getDescribe().getName();
      String lookupfield = rollup.lookupFieldOnLookupObject.getDescribe().getName();
      if (this.lookupObjectToUniqueFieldNames.containsKey(rollup.lookupObj)) {
        this.lookupObjectToUniqueFieldNames.get(rollup.lookupObj).addAll(new List<String>{ rollupField, lookupField });
      } else {
        this.lookupObjectToUniqueFieldNames.put(rollup.lookupObj, new Set<String>{ rollupField, lookupfield });
      }

      List<String> whereFields = RollupEvaluator.getWhereEval(rollup.metadata.CalcItemWhereClause__c, rollup.calcItemType).getQueryFields();
      whereFields.addAll(new List<String>{ rollup.opFieldOnCalcItem.getDescribe().getName(), rollup.lookupFieldOnCalcItem.getDescribe().getName() });
      if (this.calcObjectToUniqueFieldNames.containsKey(rollup.calcItemType)) {
        this.calcObjectToUniqueFieldNames.get(rollup.calcItemType).addAll(whereFields);
      } else {
        this.calcObjectToUniqueFieldNames.put(rollup.calcItemType, new Set<String>(whereFields));
      }
    }
  }

  private Map<String, Rollup.CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    Map<String, Rollup.CalcItemBag> lookupFieldToCalcItems = new Map<String, Rollup.CalcItemBag>();
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
      return rollup.traversal.getIsFinished() ? rollup.traversal.getParentLookupToRecords() : lookupFieldToCalcItems;
    }
    for (SObject calcItem : rollup.calcItems) {
      String key = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new Rollup.CalcItemBag(new List<SObject>{ calcItem }));
      } else {
        lookupFieldToCalcItems.get(key).originals.add(calcItem);
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
          lookupFieldToCalcItems.put(oldKey, new Rollup.CalcItemBag(new List<SObject>{ potentialOldCalcItem }));
        } else {
          lookupFieldToCalcItems.get(oldKey).originals.add(potentialOldCalcItem);
        }
      }
    }
    return lookupFieldToCalcItems;
  }

  private void initializeRollupFieldDefaults(List<SObject> lookupItems, RollupAsyncProcessor rollup) {
    // prior to returning, we need to ensure the default value for the rollup field is set
    for (SObject lookupItem : lookupItems) {
      this.resetLookupFieldsForNullOrFullRecalcs(lookupItem, rollup);
    }
  }

  private void resetLookupFieldsForNullOrFullRecalcs(SObject lookupItem, RollupAsyncProcessor rollup) {
    if (lookupItem.get(rollup.opFieldOnLookupObject) == null || rollup.isFullRecalc) {
      lookupItem.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
    }
  }

  private void ingestRollupControlData() {
    RollupControl__mdt orgDefaults = this.rollupControl;
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = this.rollups[index];
      rollup.isFullRecalc = rollup.isFullRecalc || this.isFullRecalc;

      Boolean shouldRunSyncDeferred = this.getShouldRunSyncDeferred(rollup);
      Boolean couldRunSync =
        rollup.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.SYNCHRONOUS ||
        (hasExceededCurrentRollupLimits(rollup.rollupControl) == false) && isRunningAsync;

      if (rollup.rollupControl.ShouldAbortRun__c || orgDefaults.ShouldAbortRun__c) {
        this.rollups.remove(index);
      } else if (couldRunSync && shouldRunSyncDeferred == false) {
        this.rollups.remove(index);
        this.syncRollups.add(rollup);
      } else if (couldRunSync && shouldRunSyncDeferred) {
        this.rollups.remove(index);
        this.getCachedRollups().add(rollup);
      }

      // you can increase the default limits, but it would be too messy to try to rank the individual rollup operations in a batched context
      if (rollup.rollupControl.MaxLookupRowsBeforeBatching__c > orgDefaults.MaxLookupRowsBeforeBatching__c) {
        orgDefaults.MaxLookupRowsBeforeBatching__c = rollup.rollupControl.MaxLookupRowsBeforeBatching__c;
      }
      if (rollup.rollupControl.ShouldRunAs__c != orgDefaults.ShouldRunAs__c) {
        orgDefaults.ShouldRunAs__c = rollup.rollupControl.ShouldRunAs__c;
      }
      if (rollup.rollupControl.MaxParentRowsUpdatedAtOnce__c == null) {
        rollup.rollupControl.MaxParentRowsUpdatedAtOnce__c = orgDefaults.MaxParentRowsUpdatedAtOnce__c;
      }
    }
  }

  private Boolean getShouldRunSyncDeferred(RollupAsyncProcessor roll) {
    if (roll.isNoOp || this.getCachedApexOperations().containsKey(roll.calcItemType) == false) {
      return false;
    }
    Set<TriggerOperation> apexOperations = this.getCachedApexOperations().get(roll.calcItemType);
    if (apexOperations.contains(TriggerOperation.AFTER_INSERT) && roll.op.name().contains('UPDATE')) {
      return true;
    } else if (
      (apexOperations.contains(TriggerOperation.AFTER_INSERT) || apexOperations.contains(TriggerOperation.AFTER_UPDATE)) && roll.op.name().contains('DELETE')
    ) {
      return true;
    }

    return false;
  }

  private Integer getLookupRecordsCount(Boolean hasMoreThanOneTarget) {
    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupControl__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
    // if there's more than one SObjectType involved we bail on retrieving the actual count
    // because you can only return one list of SObjects from a batch job's QueryLocator
    SObjectType targetType;
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();

    for (RollupAsyncProcessor roll : this.rollups) {
      if (targetType == null) {
        targetType = roll.lookupObj;
      } else if (roll.lookupObj != targetType) {
        hasMoreThanOneTarget = true;
      }

      if (String.isNotBlank(roll.metadata?.GrandparentRelationshipFieldPath__c)) {
        // getting the count for grandparent (or greater) relationships will be handled further
        // downstream; for our purposes, it isn't useful to try to get all of the records while
        // we're still in a sync context
        continue;
      } else if (roll.calcItems?.isEmpty() != false) {
        continue;
      }

      if (hasMoreThanOneTarget) {
        break;
      }

      Set<String> uniqueIds = new Set<String>();

      for (SObject calcItem : roll.calcItems) {
        String lookupKey = (String) calcItem.get(roll.lookupFieldOnCalcItem);
        if (String.isNotBlank(lookupKey)) {
          uniqueIds.add(lookupKey);
        }
      }

      String countQuery = RollupQueryBuilder.Current.getQuery(
        roll.lookupObj,
        new List<String>{ 'Count()' },
        String.valueOf(roll.lookupFieldOnLookupObject),
        '='
      );
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
        if (countForSObject == RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
          totalCountOfRecords = countForSObject;
          break;
        } else {
          totalCountOfRecords += countForSObject;
        }
      }
    }
    return totalCountOfRecords;
  }

  private List<SObject> getUpdatedLookupItemsByRollup(
    RollupAsyncProcessor rollup,
    Map<String, Rollup.CalcItemBag> calcItemsByLookupField,
    List<SObject> lookupItems
  ) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    Set<SObject> unprocessedCalcItems = new Set<SObject>();
    RollupSObjectUpdater updater = new RollupSObjectUpdater(rollup.opFieldOnLookupObject);
    if (this.fullRecalcProcessor != null) {
      rollup.fullRecalcProcessor = this.fullRecalcProcessor;
      rollup.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames;
      this.fullRecalcProcessor.retrieveAdditionalCalcItems(calcItemsByLookupField, rollup);
    } else {
      this.retrieveAdditionalCalcItems(calcItemsByLookupField, rollup);
    }

    for (Integer index = lookupItems.size() - 1; index >= 0; index--) {
      SObject lookupRecord = lookupItems[index];
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        Rollup.CalcItemBag bag = calcItemsByLookupField.get(key);
        // You might find yourself looking at this, wondering what the point of the bag is if we're just going to combine
        // the two lists here and move on with our lives. And, in truth, it serves little purpose at the moment - but it will
        // in the future! This is because the AVERAGE / CONCAT_DISTINCT / COUNT_DISTINCT / FIRST / LAST operations are ALWAYS full recalc operations -
        // they're just not labeled as such at the moment by the rollup.isFullRecalc property, a fact that has always bothered me.
        // those full recalc operations can be completely bulkified by completing the torch-passing of CalcItemBag downstream.
        List<SObject> localCalcItems = bag.originals;
        localCalcItems.addAll(bag.additional);

        if (hasExceededCurrentRollupLimits(this.rollupControl)) {
          unprocessedCalcItems.addAll(localCalcItems);
          lookupItems.remove(index);
          continue;
        }

        this.winnowCalcItemsAndCheckReparenting(rollup, localCalcItems, oldLookupItems);

        // Check for changed values
        RollupLogger.Instance.log('lookup record prior to rolling up: ', lookupRecord, LoggingLevel.DEBUG);
        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(rollup, localCalcItems, priorVal, key, rollup.lookupFieldOnCalcItem);
        if (priorVal != newVal || this.isFullRecalc) {
          updater.updateField(lookupRecord, newVal);
          recordsToUpdate.put(key, lookupRecord);
        }
        RollupLogger.Instance.log('lookup record after rolling up: ', lookupRecord, LoggingLevel.DEBUG);
      }
    }

    this.removeRolledUpValuesFromReparentedRecords(lookupItems, oldLookupItems, recordsToUpdate, rollup);
    this.deferCalculationsWhenApproachingLimits(rollup, unprocessedCalcItems);

    return recordsToUpdate.values();
  }

  private void deferCalculationsWhenApproachingLimits(RollupAsyncProcessor roll, Set<SObject> unprocessedCalcItems) {
    // remove the calc items that were successfully processed -
    // they're the ones that aren't in the unprocessed Set
    for (Integer index = roll.calcItems.size() - 1; index >= 0; index--) {
      SObject calcItem = roll.calcItems[index];
      if (unprocessedCalcItems.contains(calcItem) == false) {
        roll.calcItems.remove(index);
      }
    }
    // if all of the calc items have been processed, we're golden - no need to proceed
    // otherwise, the newly trimmed-down Rollup will get picked up downstream for
    // reprocessing!
    if (roll.calcItems.isEmpty() == false) {
      this.deferredRollups.add(roll);
    }
  }

  private void winnowCalcItemsAndCheckReparenting(RollupAsyncProcessor roll, List<SObject> localCalcItems, Map<String, List<SObject>> oldLookupItems) {
    for (Integer index = localCalcItems.size() - 1; index >= 0; index--) {
      SObject calcItem = localCalcItems[index];
      if (
        roll.metadata?.IsFullRecordSet__c == true &&
        (roll.eval.matches(calcItem) == false &&
        (roll.oldCalcItems.containsKey(calcItem.Id) == false || roll.eval.matches(roll.oldCalcItems.get(calcItem.Id)) == false))
      ) {
        // technically it should only be possible for a calc item that doesn't match
        // to still exist if it is a Full Record Set operation; this gives people the chance
        // to reset rollup values if none of the records passed in match the eval criteria
        localCalcItems.remove(index);
        continue;
      }
      // Check for reparented records
      SObject oldCalcItem = roll.oldCalcItems.get(calcItem.Id);

      if (oldCalcItem == null) {
        continue;
      }

      String priorLookup = (String) oldCalcItem.get(roll.lookupFieldOnCalcItem);
      // if the lookup wasn't previously populated, there's nothing to update
      if (String.isBlank(priorLookup)) {
        continue;
      }
      Object newLookup = calcItem.get(roll.lookupFieldOnCalcItem);

      if (newLookup != priorLookup && roll.traversal == null) {
        this.populateOldLookupItems(priorLookup, oldCalcItem, oldLookupItems);
      } else if (roll.traversal?.isUltimatelyReparented(calcItem, roll.lookupFieldOnCalcItem.getDescribe().getName()) == true) {
        // slightly different, but with the same end result
        // note that when the reparented record is not null
        // it should be the same as the current "lookupRecord"
        SObject reparentedRecord = roll.traversal.retrieveParent(oldCalcItem.Id);
        if (reparentedRecord != null) {
          priorLookup = (String) reparentedRecord.get(roll.lookupFieldOnLookupObject);
          if (String.isNotBlank(priorLookup)) {
            Id oldLookupId = roll.traversal.getOldLookupId(calcItem, roll.lookupFieldOnCalcItem.getDescribe().getName());
            oldCalcItem = this.reassignOldCalcItemIfValueChanged(oldLookupId, oldCalcItem, roll);
            this.populateOldLookupItems(priorLookup, oldCalcItem, oldLookupItems);
          }
        }
      }
    }
  }

  private void populateOldLookupItems(String priorLookup, SObject oldCalcItem, Map<String, List<SObject>> oldLookupItems) {
    if (oldLookupItems.containsKey(priorLookup) == false) {
      oldLookupItems.put(priorLookup, new List<SObject>{ oldCalcItem });
    } else {
      oldLookupItems.get(priorLookup).add(oldCalcItem);
    }
  }

  private SObject reassignOldCalcItemIfValueChanged(String lookupId, SObject oldCalcItem, RollupAsyncProcessor rollup) {
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

  private Object getRollupVal(RollupAsyncProcessor roll, List<SObject> calcItems, Object priorVal, String lookupRecordKey, SObjectField lookupKeyField) {
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

  private void removeRolledUpValuesFromReparentedRecords(
    List<SObject> lookupItems,
    Map<String, List<SObject>> oldLookupItems,
    Map<String, SObject> recordsToUpdate,
    RollupAsyncProcessor roll
  ) {
    for (SObject lookupRecord : lookupItems) {
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      if (oldLookupItems.containsKey(key)) {
        // Yes, old parent record has already had a new rollup established in memory
        List<SObject> reparentedCalcItems = oldLookupItems.get(key);

        if (reparentedCalcItems.isEmpty()) {
          continue;
        }

        String currentOp = getBaseOperationName(roll.op.name());
        String deleteOpName = 'DELETE_' + currentOp;
        Op deleteOp = opNameToOp.get(deleteOpName);
        RollupAsyncProcessor oldLookupsRollup = new RollupAsyncProcessor(roll, deleteOp, reparentedCalcItems);

        RollupLogger.Instance.log('reparenting operation: ', oldLookupsRollup, LoggingLevel.DEBUG);
        RollupLogger.Instance.log('Reparented item prior to reparenting rollup: ', lookupRecord, LoggingLevel.DEBUG);

        Object priorVal = lookupRecord.get(roll.opFieldOnLookupObject);
        Object newVal = this.getRollupVal(oldLookupsRollup, reparentedCalcItems, priorVal, key, roll.lookupFieldOnCalcItem);

        if (priorVal != newVal) {
          lookupRecord.put(roll.opFieldOnLookupObject, newVal);
          recordsToUpdate.put(key, lookupRecord);
        }
        RollupLogger.Instance.log('Reparented item after reparenting rollup: ', lookupRecord, LoggingLevel.DEBUG);
      }
    }
  }

  private static void doBookkeepingOnCachedItems(
    RollupAsyncProcessor matchingRollup,
    RollupAsyncProcessor stackedRollup,
    Map<String, List<String>> operationToProcessedRecords,
    SObject calcItem,
    String rollupKey,
    Integer index
  ) {
    List<String> processedRecords = operationToProcessedRecords.containsKey(rollupKey)
      ? operationToProcessedRecords.get(rollupKey)
      : new List<String>{ calcItem.Id };
    operationToProcessedRecords.put(rollupKey, processedRecords);
    Map<Id, SObject> idToCalcItem = new Map<Id, SObject>(matchingRollup.calcItems);
    idToCalcItem.put(calcItem.Id, calcItem);
    matchingRollup.calcItems.clear();
    matchingRollup.calcItems.addAll(idToCalcItem.values());
    stackedRollup.calcItems.remove(index);

    if (stackedRollup.oldCalcItems.isEmpty() == false && stackedRollup.oldCalcItems.containsKey(calcItem.Id) == false) {
      matchingRollup.oldCalcItems.put(calcItem.Id, stackedRollup.oldCalcItems.get(calcItem.Id));
    }
  }
}
