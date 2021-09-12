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

  protected final SObjectType calcItemType;
  protected Boolean isProcessed = false;
  protected Boolean overridesRunCalc = false;
  protected FullRecalcProcessor fullRecalcProcessor;

  private RollupRelationshipFieldFinder.Traversal traversal;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private Map<SObjectType, Set<String>> calcObjectToUniqueFieldNames;
  private List<SObject> lookupItems;
  private Map<String, List<SObject>> cachedFullRecalcs;

  private static final RollupSettings__c SETTINGS = RollupSettings__c.getInstance();
  private static Integer stackDepth = 0;
  private static Boolean isRunningAsync = false;
  @TestVisible
  private static Boolean shouldRunAsBatch = false;

  @SuppressWarnings('PMD.UnusedLocalVariable')
  public abstract inherited sharing class FullRecalcProcessor extends QueueableProcessor {
    protected final String queryString;
    protected final List<Rollup__mdt> rollupInfo;
    protected final Set<Id> recordIds;
    protected final Set<Id> objIds = new Set<Id>(); // necessary; there's a bind variable in the query string
    private final Set<String> previouslyResetParents = new Set<String>();

    public FullRecalcProcessor(String queryString, InvocationPoint invokePoint, List<Rollup__mdt> rollupInfo, SObjectType calcItemType, Set<Id> recordIds) {
      super(invokePoint);
      this.isFullRecalc = true;
      this.isNoOp = false;
      this.calcItemType = calcItemType;
      this.queryString = queryString;
      this.rollupInfo = rollupInfo;
      this.recordIds = recordIds;
    }

    protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
      props = super.customizeToStringEntries(props);

      this.addToMap(props, 'Rollup Metadata', this.rollupInfo);
      this.addToMap(props, 'Query String', this.queryString);

      return props;
    }

    private Boolean parentRollupFieldHasBeenReset(RollupAsyncProcessor processor, SObject parent) {
      return this.previouslyResetParents.contains(this.getKey(processor, parent));
    }

    private void storeParentResetField(RollupAsyncProcessor processor, SObject parent) {
      this.previouslyResetParents.add(this.getKey(processor, parent));
    }

    private String getKey(RollupAsyncProcessor processor, SObject parent) {
      return String.valueOf(processor.opFieldOnLookupObject) + parent.Id;
    }
  }

  private class RollupAsyncSaver implements System.Queueable {
    private final List<SObject> records;
    public RollupAsyncSaver(List<SObject> records) {
      this.records = records;
    }

    public void execute(QueueableContext context) {
      new RollupSObjectUpdater().doUpdate(this.records);
    }
  }

  private class CalcItemData {
    public final List<SObject> items;
    public final Map<Id, SObject> oldItems;
    public CalcItemData(List<SObject> items, Map<Id, SObject> oldItems) {
      this.items = items?.clone();
      this.oldItems = oldItems?.clone();
    }
  }

  public static RollupAsyncProcessor getProcessor(
    Set<Id> matchingCalcItemIds,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItem,
    Op operation,
    Evaluator eval,
    InvocationPoint rollupInvokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt metadata
  ) {
    return new QueueableProcessor(
      matchingCalcItemIds,
      opFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnLookupObject,
      opFieldOnLookupObject,
      lookupObj,
      calcItem,
      operation,
      eval,
      rollupInvokePoint,
      rollupControl,
      metadata
    );
  }

  // Conductor constructors - "outer" rollups that orchestrate the proceedings for inner rollups
  public RollupAsyncProcessor(InvocationPoint invokePoint) {
    super(invokePoint);
  }

  public RollupAsyncProcessor(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    super(invokePoint, calcItems, oldCalcItems);
  }

  public RollupAsyncProcessor(RollupAsyncProcessor innerRollup) {
    super(innerRollup.invokePoint, innerRollup.calcItems, innerRollup.oldCalcItems);

    this.rollups.addAll(innerRollup.rollups);
    this.isNoOp = this.rollups.isEmpty();
    this.isFullRecalc = innerRollup.isFullRecalc;
    this.isCDCUpdate = innerRollup.isCDCUpdate;
    this.fullRecalcProcessor = innerRollup.fullRecalcProcessor;
  }

  // Inner rollup constructor - a rollup solely concerned with calculations
  public RollupAsyncProcessor(
    Set<Id> matchingCalcItemIds,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItemType,
    Op op,
    Evaluator eval,
    InvocationPoint invokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt rollupMetadata
  ) {
    super();
    this.matchingCalcItemIds.addAll(matchingCalcItemIds);
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.lookupFieldOnCalcItem = lookupFieldOnCalcItem;
    this.lookupFieldOnLookupObject = lookupFieldOnLookupObject;
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.lookupObj = lookupObj;
    this.calcItemType = calcItemType;
    this.op = op;
    this.invokePoint = invokePoint;
    this.rollupControl = rollupControl;
    this.metadata = rollupMetadata;
    this.isConductor = false;

    if (eval != null) {
      this.eval = eval;
    }

    this.isNoOp = this.matchingCalcItemIds?.isEmpty() == true && this.metadata?.IsFullRecordSet__c == false;
  }

  public Integer compareTo(Object otherRollup) {
    Integer numberToReturn = 0;
    if (otherRollup instanceof RollupAsyncProcessor) {
      RollupAsyncProcessor that = (RollupAsyncProcessor) otherRollup;
      if (this.op == null && that.op != null) {
        numberToReturn = 1;
      } else if (that.op == null && this.op != null) {
        numberToReturn = -1;
      } else if (this.op != null && that.op != null) {
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
    }

    return numberToReturn;
  }

  public virtual Database.QueryLocator start(Database.BatchableContext context) {
    /**
     * for batch, we know 100% for sure there's only 1 SObjectType / Set<String> in the map.
     * NB: we have to call "getFieldNamesForRollups" in both the "start" and "execute" methods because
     * trying to use Database.Stateful on the top-level class ** in addition to Batchable ** results in the dreaded:
     * "System.AsyncException: Queueable cannot be implemented with other system interfaces" exception
     */
    this.winnowRollups(this.rollups);
    this.getFieldNamesForRollups(this.rollups);
    String lookupFieldForLookupObject;
    SObjectType sObjectType;
    String query;
    Set<String> objIds = new Set<String>();
    if (this.rollups.isEmpty()) {
      RollupLogger.Instance.log('No matching rollups remaining, exiting early', LoggingLevel.WARN);
      query = 'SELECT Id FROM Organization WHERE Name != \'' + UserInfo.getOrganizationName() + '\'';
    } else {
      for (RollupAsyncProcessor rollup : this.rollups) {
        sObjectType = rollup.lookupObj;
        lookupFieldForLookupObject = rollup.lookupFieldOnLookupObject.getDescribe().getName();
        objIds.addAll(this.getCalcItemsByLookupField(rollup, this.lookupObjectToUniqueFieldNames.get(sObjectType)).keySet());
      }
      query = RollupQueryBuilder.Current.getQuery(
        sObjectType,
        new List<String>(this.lookupObjectToUniqueFieldNames.get(sObjectType)),
        lookupFieldForLookupObject,
        '='
      );
      RollupLogger.Instance.log('starting batch with query:', query, LoggingLevel.DEBUG);
    }
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
    this.logFinish();
  }

  public virtual override String runCalc() {
    // side effect in the below method - rollups can be removed from this.rollups if a control record ShouldAbortRun__c == true
    // they also can be added to this.syncRollups if we're already async
    this.ingestRollupControlData();

    if (this.isNoOp) {
      this.isNoOp = this.rollups.isEmpty() && this.syncRollups.isEmpty() && this.calcItems?.isEmpty() == true;
    }

    String rollupProcessId = 'No process Id';
    if (this.isNoOp || this.rollupControl.ShouldAbortRun__c || SETTINGS.IsEnabled__c == false) {
      RollupLogger.Instance.log('no-op, exiting early to avoid burning async job', LoggingLevel.FINE);
      RollupLogger.Instance.save();
      return rollupProcessId;
    }

    if (this.syncRollups.isEmpty() == false) {
      RollupLogger.Instance.log('about to process sync rollups', LoggingLevel.DEBUG);
      this.process(this.syncRollups);
      RollupLogger.Instance.log('finished running sync rollups', LoggingLevel.DEBUG);
      rollupProcessId = 'Running rollups flagged to go synchronously';
    } else {
      Boolean hasMoreThanOneTarget = false;
      Integer totalCountOfRecords = this.getLookupRecordsCount(hasMoreThanOneTarget, this.rollups);
      shouldRunAsBatch =
        shouldRunAsBatch ||
        hasMoreThanOneTarget == false &&
        ((this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Batchable &&
        totalCountOfRecords >= this.rollupControl.MaxLookupRowsBeforeBatching__c) || totalCountOfRecords == RollupQueryBuilder.SENTINEL_COUNT_VALUE);
      rollupProcessId = this.getAsyncRollup().beginAsyncRollup();
    }
    RollupLogger.Instance.save();
    return rollupProcessId;
  }

  protected virtual override String getTypeName() {
    return RollupAsyncProcessor.class.getName();
  }

  protected virtual override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    props = super.customizeToStringEntries(props);
    this.addToMap(props, 'Full Recalc Processor', this.fullRecalcProcessor?.getTypeName());
    return props;
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    // swap off on which async process is running to achieve infinite scaling
    isRunningAsync = true;
    Boolean canEnqueue = Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
    RollupAsyncProcessor roll;
    if (this.rollups.size() == 1 && this.rollups[0] instanceof FullRecalcProcessor) {
      roll = this.rollups[0];
    } else if (this instanceof FullRecalcProcessor) {
      roll = this;
    } else if ((shouldRunAsBatch && System.isBatch() == false) || (canEnqueue == false && System.isBatch() == false)) {
      // safe to batch because the QueryLocator will only return one type of SObject
      // we have to re-initialize the rollup because it's the Queueable inner class
      // at this point, and without re-initialization we get "System.UnexpectedException: Error processing messages"
      roll = new RollupAsyncProcessor(this);
    } else if (canEnqueue && System.isQueueable() == false) {
      roll = new QueueableProcessor(this);
    } else if (canEnqueue) {
      roll = this;
    } else {
      this.logFatalRollups(this.rollups);
    }

    return roll;
  }

  private inherited sharing virtual class QueueableProcessor extends RollupAsyncProcessor implements System.Queueable {
    private QueueableProcessor(
      Set<Id> matchingCalcItemIds,
      SObjectField opFieldOnCalcItem,
      SObjectField lookupFieldOnCalcItem,
      SObjectField lookupFieldOnLookupObject,
      SObjectField opFieldOnLookupObject,
      SObjectType lookupObj,
      SObjectType calcItem,
      Op operation,
      Evaluator eval,
      InvocationPoint rollupInvokePoint,
      RollupControl__mdt rollupControl,
      Rollup__mdt metadata
    ) {
      super(
        matchingCalcItemIds,
        opFieldOnCalcItem,
        lookupFieldOnCalcItem,
        lookupFieldOnLookupObject,
        opFieldOnLookupObject,
        lookupObj,
        calcItem,
        operation,
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

    protected virtual override String getTypeName() {
      return QueueableProcessor.class.getName();
    }

    protected virtual override String startAsyncWork() {
      return System.enqueueJob(this);
    }

    protected override List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
      if (objIds.isEmpty()) {
        return new List<SObject>();
      } else {
        List<SObject> localLookupItems;
        if (String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c) || rollup.metadata.RollupToUltimateParent__c) {
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
      this.logFinish();
    }
  }

  protected void logFinish() {
    RollupLogger.Instance.log(this.getTypeName() + ' finished successfully', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
  }

  protected String beginAsyncRollup() {
    RollupLogger.Instance.log('about to start for ' + this.getTypeName(), LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
    return this.startAsyncWork();
  }

  protected virtual String startAsyncWork() {
    return this.startBatchProcessor();
  }

  protected String startBatchProcessor() {
    return Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
  }

  protected virtual List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute method"
    return this.lookupItems;
  }

  protected RollupAsyncProcessor getDelegatedFullRecalcRollup(List<Rollup__mdt> rollupInfo, List<SObject> calcItems, FullRecalcProcessor fullRecalcProcessor) {
    // if we're already queued / batched, free to start running "sync"
    isRunningAsync = System.isBatch() || System.isQueueable();
    RollupAsyncProcessor processor = this.getAsyncRollup(rollupInfo, this.calcItemType, calcItems, oldCalcItems, null, this.invokePoint);
    processor.isFullRecalc = true;
    processor.fullRecalcProcessor = fullRecalcProcessor;
    for (RollupAsyncProcessor innerRoll : processor.rollups) {
      innerRoll.fullRecalcProcessor = fullRecalcProcessor;
      innerRoll.isFullRecalc = true;
      innerRoll.calcItems = calcItems;
    }
    return processor;
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  protected virtual void retrieveAdditionalCalcItems(Map<String, CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    // TODO - incorporate grandparent rollups into this, as well
    if (rollup.isFullRecalc == false || String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c)) {
      return;
    }

    Set<String> objIds = new Set<String>();
    for (String lookupKey : lookupToCalcItems.keySet()) {
      CalcItemBag bag = lookupToCalcItems.get(lookupKey);
      if (bag.hasQueriedForAdditionalItems == false) {
        bag.hasQueriedForAdditionalItems = true;
        for (SObject calcItem : bag.originals) {
          objIds.add(calcItem.Id);
        }
      }
    }

    if (objIds.isEmpty() == false) {
      if (this.cachedFullRecalcs == null) {
        this.cachedFullRecalcs = new Map<String, List<SObject>>();
      }
      Set<String> lookupKeys = lookupToCalcItems.keySet();
      String whereClause = '' + rollup.lookupFieldOnCalcItem + ' = :lookupKeys';
      Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null &&
        rollup.calcObjectToUniqueFieldNames != null
        ? rollup.calcObjectToUniqueFieldNames
        : this.calcObjectToUniqueFieldNames;

      String query = RollupQueryBuilder.Current.getQuery(
        rollup.calcItemType,
        new List<String>(localCalcToUniqueFieldNames.get(rollup.calcItemType)),
        'Id',
        '!=',
        whereClause
      );
      List<SObject> additionalCalcItems;
      String fullRecalcKey = query + rollup.metadata.RollupOperation__c;
      if (this.cachedFullRecalcs.containsKey(fullRecalcKey)) {
        additionalCalcItems = this.cachedFullRecalcs.get(fullRecalcKey);
      } else {
        additionalCalcItems = Database.query(query);
        this.cachedFullRecalcs.put(fullRecalcKey, additionalCalcItems);
      }

      for (SObject additionalCalcItem : additionalCalcItems) {
        String lookupKey = (String) additionalCalcItem.get(rollup.lookupFieldOnCalcItem);
        if (lookupToCalcItems.containsKey(lookupKey)) {
          CalcItemBag bag = lookupToCalcItems.get(lookupKey);
          bag.additional.add(additionalCalcItem);
        }
      }
    }
  }

  protected void process(List<RollupAsyncProcessor> rollups) {
    this.transformRollups(rollups);
    this.handleMultipleDMLRollupsEnqueuedInTheSameTransaction(rollups);
    this.getFieldNamesForRollups(rollups); // populates this.lookupObjectToUniqueFieldNames

    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<SObjectType, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<SObjectType, RollupRelationshipFieldFinder.Traversal>();
    for (RollupAsyncProcessor roll : rollups) {
      roll.isProcessed = true;
      CalcItemData data = new CalcItemData(this.calcItems, this.oldCalcItems);
      this.setupCalcItemData(roll);
      RollupLogger.Instance.log('starting rollup for:', roll, LoggingLevel.DEBUG);
      // for each iteration, ensure we're not operating beyond the bounds of our query limits
      if (hasExceededCurrentRollupLimits(roll.rollupControl)) {
        RollupLogger.Instance.log('deferring current rollup, past limits', LoggingLevel.DEBUG);
        this.deferredRollups.add(roll);
        continue;
      }

      if (grandparentRollups.containsKey(roll.lookupObj) && roll.traversal == null) {
        roll.traversal = grandparentRollups.get(roll.lookupObj);
      }

      Map<String, CalcItemBag> calcItemsByLookupField = this.getCalcItemsByLookupField(roll, this.lookupObjectToUniqueFieldNames.get(roll.lookupObj));
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
      this.resetCalcItemData(data);
    }

    this.splitUpdates(updatedLookupRecords);
    this.getDML().doUpdate(updatedLookupRecords.values());
    this.processDeferredRollups();
  }

  protected virtual List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return new List<RollupAsyncProcessor>();
  }

  protected override String getHashedContents() {
    // the only thing that necessarily makes a rollup unique is the sum total of the metadata behind it
    // as well as the calc items driving that calculation.
    // you could have multiple rollups with different Calc Item Where Clauses all rolling up to the same field
    return String.valueOf(this.metadata);
  }

  private void transformRollups(List<RollupAsyncProcessor> rollupsToProcess) {
    for (Integer index = rollupsToProcess.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = rollupsToProcess[index];
      List<RollupAsyncProcessor> additionalRollups = rollup.transformFullRecalcRollups();
      if (additionalRollups.isEmpty() == false) {
        rollupsToProcess.remove(index);
        rollupsToProcess.addAll(additionalRollups);
      } else if (rollup.overridesRunCalc) {
        rollupsToProcess.remove(index);
        rollup.runCalc();
      }
    }
    rollupsToProcess.addAll(this.transformFullRecalcRollups());
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

  private List<SObject> getLookupItems(Map<String, CalcItemBag> calcItemsByLookupField, Map<String, SObject> updatedLookupRecords, RollupAsyncProcessor roll) {
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
    if (this.rollupControl.MaxParentRowsUpdatedAtOnce__c < updatedLookupRecords.size() && Limits.getLimitQueueableJobs() > Limits.getQueueableJobs()) {
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
    if (this.deferredRollups.isEmpty() == false) {
      Boolean isAllowedToContinue = this.rollupControl.MaxRollupRetries__c >= stackDepth;
      RollupLogger.Instance.log(
        'Number of deferred rollups: ' +
        this.deferredRollups.size() +
        ', still allowed to re-queue?: ' +
        isAllowedToContinue,
        LoggingLevel.DEBUG
      );
      if (this.getIsDeferralAllowed() && isAllowedToContinue) {
        stackDepth++;
        RollupLogger.Instance.log('Processing deferred rollups with stack depth: ' + stackDepth + ', rollup control:', this.rollupControl, LoggingLevel.DEBUG);
        this.setIsDeferralAllowed(isAllowedToContinue);

        this.rollups.clear();
        this.rollups.addAll(this.deferredRollups);
        this.deferredRollups.clear();

        RollupLogger.Instance.log('Deferred rollups remaining:', this.rollups, LoggingLevel.DEBUG);

        this.getAsyncRollup().beginAsyncRollup();
      } else if (this.deferredRollups.isEmpty() == false) {
        this.logFatalRollups(this.deferredRollups);
      }
    }
  }

  private void logFatalRollups(List<Rollup> rolls) {
    RollupLogger.Instance.log('rollup failed to re-queue for:', rolls, LoggingLevel.ERROR);
    RollupLogger.Instance.save();
  }

  private void setupCalcItemData(Rollup roll) {
    // if a rollup has calc items set, we take their calcItem dependencies as the source of truth
    if (roll.calcItems?.isEmpty() == false) {
      this.calcItems = roll.calcItems;
      this.oldCalcItems = roll.oldCalcItems != null ? roll.oldCalcItems : new Map<Id, SObject>();
    } else if (this.calcItems?.isEmpty() == false) {
      roll.calcItems = this.calcItems;
      roll.oldCalcItems = this.oldCalcItems;
    }
  }

  private void resetCalcItemData(CalcItemData data) {
    if (data.items?.isEmpty() == false) {
      this.calcItems = data.items;
    }
    if (data.oldItems?.isEmpty() == false) {
      this.oldCalcItems = data.oldItems;
    }
  }

  private void getFieldNamesForRollups(List<RollupAsyncProcessor> rollups) {
    this.lookupObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    this.calcObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    for (RollupAsyncProcessor roll : rollups) {
      if (roll.lookupObj == null) {
        continue;
      }
      String rollupField = roll.opFieldOnLookupObject.getDescribe().getName();
      String lookupfield = roll.lookupFieldOnLookupObject.getDescribe().getName();
      if (this.lookupObjectToUniqueFieldNames.containsKey(roll.lookupObj)) {
        this.lookupObjectToUniqueFieldNames.get(roll.lookupObj).addAll(new List<String>{ rollupField, lookupField });
      } else {
        this.lookupObjectToUniqueFieldNames.put(roll.lookupObj, new Set<String>{ rollupField, lookupfield });
      }

      List<String> whereFields = String.isBlank(roll.metadata.CalcItemWhereClause__c)
        ? new List<String>()
        : RollupEvaluator.getWhereEval(roll.metadata.CalcItemWhereClause__c, roll.calcItemType).getQueryFields();
      whereFields.addAll(new List<String>{ roll.opFieldOnCalcItem.getDescribe().getName(), roll.lookupFieldOnCalcItem.getDescribe().getName() });
      if (String.isNotBlank(roll.metadata.OrderByFirstLast__c)) {
        whereFields.add(roll.metadata.OrderByFirstLast__c);
      }
      if (this.calcObjectToUniqueFieldNames.containsKey(roll.calcItemType)) {
        this.calcObjectToUniqueFieldNames.get(roll.calcItemType).addAll(whereFields);
      } else {
        this.calcObjectToUniqueFieldNames.put(roll.calcItemType, new Set<String>(whereFields));
      }
    }
  }

  private void winnowRollups(List<RollupAsyncProcessor> potentialRollups) {
    this.transformRollups(potentialRollups);
    for (Integer index = potentialRollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor processor = potentialRollups[index];
      if (processor.lookupObj != null) {
        Map<String, SObjectField> fieldMap = processor.lookupObj.getDescribe().fields.getMap();
        if (fieldMap.containsKey(processor.opFieldOnLookupObject.getDescribe().getName()) == false) {
          potentialRollups.remove(index);
        }
      }
    }
  }

  private Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    Map<String, CalcItemBag> lookupFieldToCalcItems = new Map<String, CalcItemBag>();
    if (this.calcItems == null) {
      return lookupFieldToCalcItems;
    }
    if (String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c) || rollup.metadata.RollupToUltimateParent__c) {
      if (rollup.traversal == null) {
        rollup.traversal = new RollupRelationshipFieldFinder(rollup.rollupControl, rollup.metadata, uniqueQueryFieldNames, rollup.lookupObj, this.oldCalcItems)
          .getParents(this.calcItems);
      } else if (rollup.traversal?.getIsFinished() == false) {
        rollup.traversal.recommence();
      }
      return rollup.traversal.getIsFinished() ? rollup.traversal.getParentLookupToRecords() : lookupFieldToCalcItems;
    }
    for (SObject calcItem : this.calcItems) {
      if (rollup.matchingCalcItemIds.contains(calcItem.Id) == false) {
        continue;
      }
      String key = (String) calcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new CalcItemBag(new List<SObject>{ calcItem }));
      } else {
        lookupFieldToCalcItems.get(key).originals.add(calcItem);
      }

      // if the lookup key differs from what it was on the old calc item,
      // include that value as well so that we can fix reparented records' rollup values
      SObject potentialOldCalcItem = this.oldCalcItems?.get(calcItem.Id);
      if (potentialOldCalcItem != null) {
        String oldKey = (String) potentialOldCalcItem.get(rollup.lookupFieldOnCalcItem);

        if (key == oldKey) {
          continue;
        }

        if (lookupFieldToCalcItems.containsKey(oldKey) == false) {
          lookupFieldToCalcItems.put(oldKey, new CalcItemBag(new List<SObject>{ potentialOldCalcItem }));
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
    if (lookupItem.get(rollup.opFieldOnLookupObject) == null || this.isValidFullRecalcReset(rollup, lookupItem)) {
      lookupItem.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
    }
  }

  private Boolean isValidFullRecalcReset(RollupAsyncProcessor rollup, SObject lookupItem) {
    Boolean isValid = false;
    if (rollup.isFullRecalc) {
      isValid = rollup.fullRecalcProcessor?.parentRollupFieldHasBeenReset(rollup, lookupItem) != true;
    }
    return isValid;
  }

  private void ingestRollupControlData() {
    RollupControl__mdt orgDefaults = this.rollupControl;
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = this.rollups[index];
      rollup.isFullRecalc = rollup.isFullRecalc || this.isFullRecalc;

      Boolean shouldRunSyncDeferred = this.getShouldRunSyncDeferred(rollup);
      Boolean couldRunSync =
        rollup.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous ||
        ((hasExceededCurrentRollupLimits(rollup.rollupControl) == false) &&
        isRunningAsync &&
        this.getIsRunningFromFlow() == false) ||
        System.isBatch() && Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs();

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
    if (apexOperations?.contains(TriggerOperation.AFTER_INSERT) == true && roll.op?.name().contains('UPDATE') == true) {
      return true;
    } else if (
      (apexOperations?.contains(TriggerOperation.AFTER_INSERT) == true || apexOperations?.contains(TriggerOperation.AFTER_UPDATE) == true) &&
      roll.op?.name().contains('DELETE') == true
    ) {
      return true;
    }

    return false;
  }

  private Integer getLookupRecordsCount(Boolean hasMoreThanOneTarget, List<RollupAsyncProcessor> processors) {
    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupControl__mdt and/or sensible defaults, we'll decide whether to queue up or batch (or fail - that's always an option)
    // if there's more than one SObjectType involved we bail on retrieving the actual count
    // because you can only return one list of SObjects from a batch job's QueryLocator
    SObjectType targetType;
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();

    Integer totalCountOfRecords = 0;
    for (RollupAsyncProcessor roll : processors) {
      if (targetType == null) {
        targetType = roll.lookupObj;
      } else if (roll.lookupObj != targetType) {
        hasMoreThanOneTarget = true;
      }

      if (roll.queryCount != null) {
        totalCountOfRecords += roll.queryCount;
        continue;
      }

      if (hasMoreThanOneTarget) {
        break;
      }

      if (String.isNotBlank(roll.metadata?.GrandparentRelationshipFieldPath__c)) {
        // getting the count for grandparent (or greater) relationships will be handled further
        // downstream; for our purposes, it isn't useful to try to get all of the records while
        // we're still in a sync context
        continue;
      } else if (roll.calcItems?.isEmpty() == true) {
        continue;
      }

      Set<String> uniqueIds = new Set<String>();

      List<SObject> items = roll.calcItems?.isEmpty() == false ? roll.calcItems : this.calcItems;
      for (SObject calcItem : items) {
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

  private List<SObject> getUpdatedLookupItemsByRollup(RollupAsyncProcessor rollup, Map<String, CalcItemBag> calcItemsByLookupField, List<SObject> lookupItems) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    Set<Id> unprocessedCalcItems = new Set<Id>();
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
        CalcItemBag bag = calcItemsByLookupField.get(key);
        // You might find yourself looking at this, wondering what the point of the bag is if we're just going to combine
        // the two lists here and move on with our lives. And, in truth, it serves little purpose at the moment - but it will
        // in the future! This is because the AVERAGE / CONCAT_DISTINCT / COUNT_DISTINCT / FIRST / LAST operations are ALWAYS full recalc operations -
        // they're just not labeled as such at the moment by the rollup.isFullRecalc property, a fact that has always bothered me.
        // those full recalc operations can be completely bulkified by completing the torch-passing of CalcItemBag downstream.
        List<SObject> localCalcItems = bag.originals;
        localCalcItems.addAll(bag.additional);

        if (hasExceededCurrentRollupLimits(this.rollupControl)) {
          unprocessedCalcItems = new Map<Id, SObject>(localCalcItems).keySet();
          lookupItems.remove(index);
          continue;
        }

        this.winnowCalcItemsAndCheckReparenting(rollup, localCalcItems, oldLookupItems);

        // Check for changed values
        Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
        Object newVal = this.calculateNewRollupVal(rollup, localCalcItems, lookupRecord, priorVal, key, rollup.lookupFieldOnCalcItem);
        this.conditionallyPerformUpdate(priorVal, newVal, lookupRecord, rollup, recordsToUpdate, updater, 'lookup');
      }
    }

    this.removeRolledUpValuesFromReparentedRecords(lookupItems, oldLookupItems, recordsToUpdate, rollup, updater);
    this.deferCalculationsWhenApproachingLimits(rollup, unprocessedCalcItems);

    return recordsToUpdate.values();
  }

  private void deferCalculationsWhenApproachingLimits(RollupAsyncProcessor roll, Set<Id> unprocessedCalcItems) {
    // remove the calc items that were successfully processed -
    // they're the ones that aren't in the unprocessed Set
    List<SObject> mutableItems = this.calcItems?.clone();
    if (mutableItems != null) {
      for (Integer index = mutableItems.size() - 1; index >= 0; index--) {
        SObject calcItem = mutableItems[index];
        if (unprocessedCalcItems.contains(calcItem.Id) == false) {
          mutableItems.remove(index);
        }
      }
    }
    // if all of the calc items have been processed, we're golden - no need to proceed
    // otherwise, the newly trimmed-down Rollup will get picked up downstream for
    // reprocessing!
    if (mutableItems?.isEmpty() == false) {
      roll.calcItems = mutableItems;
      this.deferredRollups.add(roll);
    } else if (roll instanceof FullRecalcProcessor) {
      for (RollupAsyncProcessor otherRollup : this.rollups) {
        if (roll.isProcessed == false && otherRollup != roll) {
          RollupLogger.Instance.log('adding full recalc rollup as inner rollup:', otherRollup, LoggingLevel.DEBUG);
          roll.rollups.add(otherRollup);
        }
      }
      roll.startAsyncWork();
    }
  }

  private void winnowCalcItemsAndCheckReparenting(RollupAsyncProcessor roll, List<SObject> localCalcItems, Map<String, List<SObject>> oldLookupItems) {
    for (Integer index = localCalcItems.size() - 1; index >= 0; index--) {
      SObject calcItem = localCalcItems[index];
      Boolean doesNotMatchCurrentItem = roll.eval.matches(calcItem) == false;
      if (
        roll.metadata?.IsFullRecordSet__c == true &&
        (doesNotMatchCurrentItem && (this.oldCalcItems.containsKey(calcItem.Id) == false || roll.eval.matches(this.oldCalcItems.get(calcItem.Id)) == false))
      ) {
        // technically it should only be possible for a calc item that doesn't match
        // to still exist if it is a Full Record Set operation; this gives people the chance
        // to reset rollup values if none of the records passed in match the eval criteria
        localCalcItems.remove(index);
        continue;
      }
      // Check for reparented records
      SObject oldCalcItem = this.oldCalcItems?.get(calcItem.Id);

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
    if (String.isBlank(lookupId) || this.oldCalcItems == null) {
      return oldCalcItem;
    }
    // truly terrible, but before we pass the old item through the reparenting code path, we need to validate that it's only
    // the lookup field that has changed; otherwise, if the opFieldOnCalcItem has changed too, substitute the item whose value
    // previously corresponded to the parent record
    for (SObject otherOldCalcItem : this.oldCalcItems.values()) {
      if (otherOldCalcItem.get(rollup.lookupFieldOnCalcItem) == lookupId) {
        if (otherOldCalcItem.get(rollup.opFieldOnCalcItem) != oldCalcItem.get(rollup.opFieldOnCalcItem)) {
          return otherOldCalcItem;
        }
        break; // break on the match, no matter what
      }
    }
    return oldCalcItem;
  }

  private Object calculateNewRollupVal(
    RollupAsyncProcessor roll,
    List<SObject> calcItems,
    SObject lookupRecord,
    Object priorVal,
    String lookupRecordKey,
    SObjectField lookupKeyField
  ) {
    RollupCalculator rollupCalc = RollupCalculator.Factory.getCalculator(
      priorVal,
      roll.op,
      roll.opFieldOnCalcItem,
      roll.opFieldOnLookupObject,
      roll.metadata,
      lookupRecordKey,
      lookupKeyField
    );
    rollupCalc.setFullRecalc(roll.isFullRecalc);
    rollupCalc.setEvaluator(roll.eval);
    rollupCalc.setCDCUpdate(this.isCDCUpdate);
    rollupCalc.setMultiCurrencyInfo(lookupRecord);
    rollupCalc.performRollup(calcItems, this.oldCalcItems);
    return rollupCalc.getReturnValue();
  }

  private void removeRolledUpValuesFromReparentedRecords(
    List<SObject> lookupItems,
    Map<String, List<SObject>> oldLookupItems,
    Map<String, SObject> recordsToUpdate,
    RollupAsyncProcessor roll,
    RollupSObjectUpdater updater
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

        // by default this returns a "batched" (set) of rollups; we
        // just want the first (and only) inner rollup to perform the pseudo-delete
        RollupAsyncProcessor oldLookupsRollup = getProcessor(
          new Set<Id>(),
          roll.opFieldOnCalcItem,
          roll.lookupFieldOnCalcItem,
          roll.lookupFieldOnLookupObject,
          roll.opFieldOnLookupObject,
          roll.lookupObj,
          roll.calcItemType,
          deleteOp,
          null,
          this.invokePoint,
          this.rollupControl,
          roll.metadata
        );

        RollupLogger.Instance.log('reparenting operation:', oldLookupsRollup, LoggingLevel.DEBUG);

        Object priorVal = lookupRecord.get(roll.opFieldOnLookupObject);
        Object newVal = this.calculateNewRollupVal(oldLookupsRollup, reparentedCalcItems, lookupRecord, priorVal, key, roll.lookupFieldOnCalcItem);

        this.conditionallyPerformUpdate(priorVal, newVal, lookupRecord, roll, recordsToUpdate, updater, 'reparented');
      }
    }
  }

  private void conditionallyPerformUpdate(
    Object priorVal,
    Object newVal,
    SObject lookupRecord,
    RollupAsyncProcessor roll,
    Map<String, SObject> recordsToUpdate,
    RollupSObjectUpdater updater,
    String logKey
  ) {
    RollupLogger.Instance.log(logKey + ' record prior to rolling up:', lookupRecord, LoggingLevel.DEBUG);
    if (priorVal != newVal || this.isFullRecalc || roll.isFullRecalc) {
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      RollupLogger.Instance.log('updating record ...', LoggingLevel.FINE);
      updater.updateField(lookupRecord, newVal);
      recordsToUpdate.put(key, lookupRecord);
      roll.fullRecalcProcessor?.storeParentResetField(roll, lookupRecord);
    }
    RollupLogger.Instance.log(logKey + ' record after rolling up:', lookupRecord, LoggingLevel.DEBUG);
  }
}
