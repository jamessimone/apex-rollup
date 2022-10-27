global virtual without sharing class RollupAsyncProcessor extends Rollup implements Database.Batchable<SObject>, System.Comparable {
  private final Evaluator eval;
  private final Op op;
  private final SObjectField lookupFieldOnCalcItem;
  private final SObjectField lookupFieldOnLookupObject;
  private final SObjectField opFieldOnCalcItem;
  private final SObjectType lookupObj;

  private Integer stackDepth = 0;
  private List<SObject> lookupItems;
  private Map<SObjectType, Set<String>> calcObjectToUniqueFieldNames;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private RollupRelationshipFieldFinder.Traversal traversal;

  protected Boolean isTimingOut = false;
  protected Boolean isProcessed = false;
  protected Boolean overridesRunCalc = false;
  protected Boolean shouldSortToFront = false;
  protected final SObjectField opFieldOnLookupObject;
  protected final SObjectType calcItemType;
  protected RollupFullRecalcProcessor fullRecalcProcessor;

  @TestVisible
  private static Boolean shouldRunAsBatch = false;
  @TestVisible
  private static Integer additionalCalcItemCount;

  private enum CollectionType {
    DICTIONARY,
    ITERABLE
  }

  private final Set<String> previouslyResetParents {
    get {
      if (previouslyResetParents == null) {
        previouslyResetParents = new Set<String>();
      }
      return previouslyResetParents;
    }
    set;
  }

  private final Map<String, List<SObject>> cachedQueryToAdditionalCalcItems {
    get {
      if (cachedQueryToAdditionalCalcItems == null) {
        cachedQueryToAdditionalCalcItems = new Map<String, List<SObject>>();
      }
      return cachedQueryToAdditionalCalcItems;
    }
    set;
  }

  private final List<RollupAsyncProcessor> deferredRollups {
    get {
      if (deferredRollups == null) {
        deferredRollups = new List<RollupAsyncProcessor>();
      }
      return deferredRollups;
    }
    set;
  }

  public static RollupAsyncProcessor getConductor(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    return new QueueableProcessor(invokePoint, calcItems, oldCalcItems);
  }

  public static RollupAsyncProcessor getProcessor(
    FilterResults filterResults,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItem,
    Op operation,
    InvocationPoint rollupInvokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt metadata
  ) {
    return new QueueableProcessor(
      filterResults,
      opFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnLookupObject,
      opFieldOnLookupObject,
      lookupObj,
      calcItem,
      operation,
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
    this.stackDepth = innerRollup.stackDepth;
    this.calcItemReplacer = innerRollup.calcItemReplacer;
    this.previouslyResetParents.addAll(innerRollup.previouslyResetParents);
  }

  // Inner rollup constructor - a rollup solely concerned with calculations
  public RollupAsyncProcessor(
    FilterResults filterResults,
    SObjectField opFieldOnCalcItem,
    SObjectField lookupFieldOnCalcItem,
    SObjectField lookupFieldOnLookupObject,
    SObjectField opFieldOnLookupObject,
    SObjectType lookupObj,
    SObjectType calcItemType,
    Op op,
    InvocationPoint invokePoint,
    RollupControl__mdt rollupControl,
    Rollup__mdt rollupMetadata
  ) {
    super();
    this.matchingCalcItemIds.addAll(filterResults.matchingItemIds);
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

    if (filterResults.eval != null) {
      this.eval = filterResults.eval;
    }

    this.isNoOp = this.matchingCalcItemIds?.isEmpty() == true && this.metadata?.IsFullRecordSet__c == false;
  }

  public Integer compareTo(Object otherRollup) {
    Integer numberToReturn = 0;
    if (otherRollup instanceof RollupAsyncProcessor) {
      RollupAsyncProcessor that = (RollupAsyncProcessor) otherRollup;
      if (this.shouldSortToFront == false && that.shouldSortToFront) {
        numberToReturn = 1;
      } else if (that.shouldSortToFront == false && this.shouldSortToFront) {
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
     * NB: we have to call "populateObjectFields" in both the "start" and "execute" methods because
     * trying to use Database.Stateful on the top-level class ** in addition to Batchable ** results in the dreaded:
     * "System.AsyncException: Queueable cannot be implemented with other system interfaces" exception
     */
    this.winnowRollups(this.rollups);
    this.populateObjectFields(this.rollups);
    String query = 'SELECT Id FROM Organization WHERE Name != \'' + UserInfo.getOrganizationName() + '\'';
    Set<String> objIds = new Set<String>(); // bind variable
    if (this.rollups.isEmpty()) {
      RollupLogger.Instance.log('No matching rollups remaining, exiting early', LoggingLevel.WARN);
    } else {
      RollupAsyncProcessor firstRollup = this.rollups.get(0);
      SObjectType sObjectType = firstRollup.lookupObj;
      String lookupFieldForLookupObject = firstRollup.lookupFieldOnLookupObject.getDescribe().getName();
      Set<String> uniqueLookupObjectFields = this.lookupObjectToUniqueFieldNames.get(sObjectType);
      objIds = this.getCalcItemsByLookupField(firstRollup, uniqueLookupObjectFields).keySet();
      query = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(uniqueLookupObjectFields), lookupFieldForLookupObject, '=');
      RollupLogger.Instance.log('starting batch with query:', query, LoggingLevel.DEBUG);
    }
    RollupLogger.Instance.save();
    return Database.getQueryLocator(query);
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> lookupItems) {
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor roll = this.rollups[index];
      if (lookupItems.getSObjectType() != roll.lookupObj) {
        this.rollups.remove(index);
        this.deferredRollups.add(roll);
      }
    }

    this.lookupItems = lookupItems;
    this.process(this.rollups);
    RollupLogger.Instance.save();
  }

  public virtual void finish(Database.BatchableContext context) {
    if (this.isTimingOut == false) {
      this.fullRecalcProcessor?.finish();
    }
    this.logFinish();
  }

  public virtual void storeParentResetField(RollupAsyncProcessor processor, SObject parent) {
    this.previouslyResetParents.add(this.getParentResetKey(String.valueOf(processor.opFieldOnLookupObject), parent));
    this.fullRecalcProcessor?.storeParentResetField(processor, parent);
  }

  public virtual override String runCalc() {
    // side effect in the below method - rollups can be removed from this.rollups if a control record ShouldAbortRun__c == true
    // they also can be added to syncRollups if we're already async
    List<RollupAsyncProcessor> syncRollups = new List<RollupAsyncProcessor>();
    Boolean shouldRunWithoutCustomSetting = this.ingestRollupControlData(syncRollups);

    if (this.isNoOp) {
      this.isNoOp = this.rollups.isEmpty() && syncRollups.isEmpty() && (this.isFullRecalc == false && this.calcItems?.isEmpty() == true);
    }

    String rollupProcessId = this.getNoProcessId();
    String logMessage;
    if (this.isNoOp) {
      logMessage = 'no-op, exiting early to avoid burning async job';
    } else if (this.rollupControl.ShouldAbortRun__c) {
      logMessage = 'RollupControl__mdt.ShouldAbortRun__c set to true, exiting early';
    } else if (RollupSettings__c.getInstance().IsEnabled__c == false && shouldRunWithoutCustomSetting == false) {
      logMessage = 'RollupSettings__c.IsEnabled__c is false, exiting early';
    } else if (syncRollups.isEmpty() == false) {
      RollupLogger.Instance.log('about to process sync rollups', LoggingLevel.DEBUG);
      this.process(syncRollups);
      RollupLogger.Instance.log('finished running sync rollups', LoggingLevel.DEBUG);
    } else {
      Integer totalCountOfRecords = this.getLookupRecordsCount(this.rollups);
      shouldRunAsBatch =
        shouldRunAsBatch ||
        (this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Batchable &&
        totalCountOfRecords >= this.rollupControl.MaxLookupRowsBeforeBatching__c);
      rollupProcessId = this.getAsyncRollup()?.beginAsyncRollup();
    }
    if (logMessage != null) {
      RollupLogger.Instance.log(logMessage, LoggingLevel.DEBUG);
      rollupProcessId = logMessage;
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
    this.addToMap(props, 'Stack depth', this.stackDepth > 0 ? this.stackDepth : null);
    this.addToMap(props, 'Is Processed?', this.isProcessed);
    return props;
  }

  protected String getNoProcessId() {
    return 'No process Id';
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    // swap off on which async process is running to achieve infinite scaling
    Boolean canEnqueue = this.getCanEnqueue();
    RollupAsyncProcessor roll;
    if (this.rollups.size() == 1 && this.rollups[0] instanceof RollupFullRecalcProcessor) {
      roll = this.rollups[0];
    } else if (this instanceof RollupFullRecalcProcessor) {
      roll = this;
    } else if (System.isBatch() == false && (shouldRunAsBatch || canEnqueue == false)) {
      // safe to batch because the QueryLocator will only return one type of SObject
      // we have to re-initialize the rollup because it's the Queueable inner class
      // at this point, and without re-initialization we get "System.UnexpectedException: Error processing messages"
      if (this instanceof QueueableProcessor) {
        roll = new RollupAsyncProcessor(this);
      } else {
        roll = this;
      }
    } else if (canEnqueue && System.isQueueable() == false && (this instanceof QueueableProcessor) == false) {
      roll = new QueueableProcessor(this);
    } else if (canEnqueue) {
      roll = this;
    }

    return roll;
  }

  public without sharing virtual class QueueableProcessor extends RollupAsyncProcessor implements System.Queueable {
    protected QueueableProcessor(InvocationPoint rollupInvokePoint) {
      super(rollupInvokePoint);
    }

    private QueueableProcessor(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      super(invokePoint, calcItems, oldCalcItems);
    }

    private QueueableProcessor(
      FilterResults filterResults,
      SObjectField opFieldOnCalcItem,
      SObjectField lookupFieldOnCalcItem,
      SObjectField lookupFieldOnLookupObject,
      SObjectField opFieldOnLookupObject,
      SObjectType lookupObj,
      SObjectType calcItem,
      Op operation,
      InvocationPoint rollupInvokePoint,
      RollupControl__mdt rollupControl,
      Rollup__mdt metadata
    ) {
      super(
        filterResults,
        opFieldOnCalcItem,
        lookupFieldOnCalcItem,
        lookupFieldOnLookupObject,
        opFieldOnLookupObject,
        lookupObj,
        calcItem,
        operation,
        rollupInvokePoint,
        rollupControl,
        metadata
      );
    }

    private QueueableProcessor(RollupAsyncProcessor roll) {
      super(roll);
    }

    protected virtual override String getTypeName() {
      return QueueableProcessor.class.getName();
    }

    protected virtual override String startAsyncWork() {
      return this.enqueue();
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    protected override List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
      if (objIds.isEmpty()) {
        return new List<SObject>();
      }
      List<SObject> localLookupItems;
      if (rollup.traversal != null) {
        localLookupItems = rollup.traversal.getAllParents();
      } else {
        String queryString =
          RollupQueryBuilder.Current.getQuery(
            rollup.lookupObj,
            new List<String>(uniqueQueryFieldNames),
            String.valueOf(rollup.lookupFieldOnLookupObject),
            '='
          ) + (this.isSingleRecordSyncUpdate(rollup) ? '\nFOR UPDATE' : '');
        // non-obvious coupling between "objIds" and the computed "queryString", which uses dynamic variable binding
        localLookupItems = Database.query(queryString);
      }
      for (Integer index = localLookupItems.size() - 1; index >= 0; index--) {
        if (this.parentRollupFieldHasBeenReset(rollup, localLookupItems[index]) == true) {
          localLookupItems.remove(index);
        }
      }
      this.fullRecalcProcessor?.processParentFieldsToReset(localLookupItems);
      return localLookupItems;
    }

    public void execute(System.QueueableContext qc) {
      System.attachFinalizer(new RollupFinalizer());
      this.process(this.rollups);
      this.finish(null);
    }
  }

  protected void logFinish() {
    RollupLogger.Instance.log(this.getTypeName() + ' finished successfully', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
  }

  protected String beginAsyncRollup() {
    this.isTimingOut = false;
    RollupLogger.Instance.log('about to start for ' + this.getTypeName(), this, LoggingLevel.DEBUG);
    return this.startAsyncWork();
  }

  protected virtual String startAsyncWork() {
    return this.startBatchProcessor();
  }

  protected String enqueue() {
    return System.enqueueJob(this);
  }

  protected String startBatchProcessor() {
    return Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
  }

  protected virtual List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute" method
    this.fullRecalcProcessor?.processParentFieldsToReset(this.lookupItems);
    return this.lookupItems;
  }

  protected RollupAsyncProcessor getDelegatedFullRecalcRollup(
    List<Rollup__mdt> rollupMetas,
    List<SObject> calcItems,
    RollupFullRecalcProcessor fullRecalcProcessor
  ) {
    RollupAsyncProcessor processor = this.getAsyncRollup(rollupMetas, this.calcItemType, calcItems, new Map<Id, SObject>(), null, this.invokePoint);
    processor.isFullRecalc = true;
    processor.fullRecalcProcessor = fullRecalcProcessor;
    for (RollupAsyncProcessor innerRoll : processor.rollups) {
      innerRoll.fullRecalcProcessor = fullRecalcProcessor;
      innerRoll.isFullRecalc = true;
      innerRoll.calcItems = calcItems;
    }
    this.fullRecalcProcessor = fullRecalcProcessor;
    return processor;
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  protected virtual void retrieveAdditionalCalcItems(Map<String, CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    if (this.isValidAdditionalCalcItemRetrieval(rollup) == false || rollup.metadata?.RollupToUltimateParent__c == true) {
      return;
    }

    Set<String> objIds = new Set<String>();
    for (CalcItemBag bag : lookupToCalcItems.values()) {
      if (bag.hasQueriedForAdditionalItems == false) {
        bag.hasQueriedForAdditionalItems = true;
        objIds.addAll(bag.getAllIds());
      }
      // calling clear in a loop here might look interesting - and it would be a massive problem if not for the
      // bag only responding to the very first clear() invocation. everything after that is a no-op (so, any rollup with more
      // than one rollup operation going at a time)
      if (rollup.op.name().contains('DELETE')) {
        bag.clear();
      }
    }

    if (objIds.isEmpty()) {
      return;
    }

    Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null &&
      rollup.calcObjectToUniqueFieldNames != null
      ? rollup.calcObjectToUniqueFieldNames
      : this.calcObjectToUniqueFieldNames;

    String whereClause = '' + rollup.lookupFieldOnCalcItem + ' = :lookupKeys';
    String query = RollupQueryBuilder.Current.getQuery(
      rollup.calcItemType,
      new List<String>(localCalcToUniqueFieldNames.get(rollup.calcItemType)),
      'Id',
      '!=',
      whereClause
    );

    Boolean hasAlreadyBeenQueried = this.cachedQueryToAdditionalCalcItems.containsKey(query);
    Boolean shouldLimitCalcItemQuery = false;
    Integer remainingQueryRowsLeft = 0;
    Integer outstandingItemCount = 0;

    List<SObject> additionalCalcItems;
    if (hasAlreadyBeenQueried) {
      additionalCalcItems = this.cachedQueryToAdditionalCalcItems.get(query);
    } else {
      Set<String> lookupKeys = lookupToCalcItems.keySet();
      String countQuery = RollupQueryBuilder.Current.getQuery(rollup.calcItemType, new List<String>{ 'Count()' }, 'Id', '!=', whereClause);
      if (additionalCalcItemCount != null) {
        outstandingItemCount = additionalCalcItemCount;
        additionalCalcItemCount = null;
      } else {
        outstandingItemCount = Database.countQuery(countQuery);
      }
      remainingQueryRowsLeft = new RollupLimits.Tester(rollup.rollupControl, this.getIsRunningAsync()).getRemainingQueryRows();
      shouldLimitCalcItemQuery = outstandingItemCount >= remainingQueryRowsLeft;

      if (shouldLimitCalcItemQuery) {
        query = RollupQueryBuilder.Current.getAllRowSafeQuery(rollup.calcItemType, query += '\nLIMIT ' + remainingQueryRowsLeft);
        hasAlreadyBeenQueried = false;
      }

      if (hasAlreadyBeenQueried && shouldLimitCalcItemQuery && outstandingItemCount != remainingQueryRowsLeft) {
        this.isTimingOut = true;
        return;
      } else if (outstandingItemCount > 0) {
        RollupLogger.Instance.log('gathering additional calc items with query:', query, LoggingLevel.DEBUG);
        additionalCalcItems = Database.query(query);
        if (hasAlreadyBeenQueried) {
          this.cachedQueryToAdditionalCalcItems.get(query).addAll(additionalCalcItems);
        } else if (shouldLimitCalcItemQuery == false || remainingQueryRowsLeft >= outstandingItemCount) {
          this.cachedQueryToAdditionalCalcItems.put(query, additionalCalcItems);
        }
      } else {
        additionalCalcItems = new List<SObject>();
        this.cachedQueryToAdditionalCalcItems.put(query, additionalCalcItems);
      }
    }

    for (SObject additionalCalcItem : additionalCalcItems) {
      String lookupKey = (String) additionalCalcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupToCalcItems.containsKey(lookupKey)) {
        CalcItemBag bag = lookupToCalcItems.get(lookupKey);
        bag.hasQueriedForAdditionalItems = shouldLimitCalcItemQuery == false || remainingQueryRowsLeft >= outstandingItemCount;
        bag.add(additionalCalcItem);
      }
    }
  }

  protected void process(List<RollupAsyncProcessor> rollups) {
    this.handleMultipleDMLRollupsEnqueuedInTheSameTransaction(rollups);
    this.preProcessRollups(rollups);
    this.populateObjectFields(rollups);

    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<SObjectType, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<SObjectType, RollupRelationshipFieldFinder.Traversal>();
    for (RollupAsyncProcessor roll : rollups) {
      roll.isProcessed = true;
      this.setupCalcItemData(roll);
      // for each iteration, ensure we're not operating beyond the bounds of our query limits
      if (this.getIsTimingOut(roll.rollupControl, roll)) {
        this.deferredRollups.add(roll);
        continue;
      }

      if (grandparentRollups.containsKey(roll.lookupObj) && roll.traversal == null) {
        roll.traversal = grandparentRollups.get(roll.lookupObj);
      }

      Set<String> uniqueParentObjectFields = this.lookupObjectToUniqueFieldNames.get(roll.lookupObj);
      Map<String, CalcItemBag> calcItemsByLookupField = this.fullRecalcProcessor != null
        ? this.fullRecalcProcessor.getCalcItemsByLookupField(roll, uniqueParentObjectFields)
        : this.getCalcItemsByLookupField(roll, uniqueParentObjectFields);
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
      RollupLogger.Instance.log('starting rollup for:', roll, LoggingLevel.DEBUG);
      updatedLookupRecords.putAll(this.getUpdatedLookupItemsByRollup(roll, calcItemsByLookupField, localLookupItems));
    }

    // TODO - possibility here (or in "conditionallyPerformUpdate") to early-indicate to batch full recalcs that certain parent items have been
    // fully calculated. there were some idiosyncracies when testing this approach - particularly within tests,
    // where stacked async contexts (like a deferred rollup AND a batch job can both be running at once) are much harder to manage
    // due to the platform attempting to auto-collapse them for you, which in this specific bit was leading to the
    // RollupFullBatchRecalculator.statefulLookupToCalcItems map having lookup keys cleared from it too soon
    // on the upside, figuring this out massively reduces the amount of time it takes for batch full recalcs to run,
    // so this should be a "next version" priority

    if (this.isTimingOut) {
      this.getDML().forceSyncUpdate();
    }
    this.getDML().doUpdate(updatedLookupRecords.values());
    if (this.getCachedRollups().isEmpty() == false) {
      for (Rollup outerRollup : this.getCachedRollups()) {
        this.deferredRollups.addAll(outerRollup.rollups);
      }
      this.getCachedRollups().clear();
    }
    this.processDeferredRollups();
  }

  protected virtual Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor roll, Set<String> uniqueLookupObjectFields) {
    Map<String, CalcItemBag> lookupFieldToCalcItems = new Map<String, CalcItemBag>();
    if (roll.calcItems == null) {
      return lookupFieldToCalcItems;
    }
    if (String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c) || roll.metadata.RollupToUltimateParent__c) {
      if (roll.traversal == null) {
        roll.traversal = new RollupRelationshipFieldFinder(
            roll.rollupControl,
            roll.metadata,
            this.calcObjectToUniqueFieldNames.get(roll.calcItemType),
            uniqueLookupObjectFields,
            roll.lookupObj,
            roll.oldCalcItems
          )
          .getParents(roll.calcItems);
      } else if (roll.traversal?.getIsFinished() == false) {
        roll.traversal.recommence();
      }
      return roll.traversal.getIsFinished() ? roll.traversal.getParentLookupToRecords() : lookupFieldToCalcItems;
    }
    for (SObject calcItem : roll.calcItems) {
      if (roll.matchingCalcItemIds.contains(calcItem.Id) == false) {
        continue;
      }
      String key = (String) calcItem.get(roll.lookupFieldOnCalcItem);
      SObject potentialOldCalcItem = roll.oldCalcItems?.get(calcItem.Id);
      Boolean hasBlankKey = String.isBlank(key);
      if (hasBlankKey && potentialOldCalcItem != null) {
        key = (String) potentialOldCalcItem.get(roll.lookupFieldOnCalcItem);
      }
      if (hasBlankKey && potentialOldCalcItem == null) {
        continue;
      }
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new CalcItemBag(new List<SObject>{ calcItem }));
      } else {
        lookupFieldToCalcItems.get(key).add(calcItem);
      }

      // if the lookup key differs from what it was on the old child object,
      // include that value as well so that we can fix reparented records' rollup values
      if (potentialOldCalcItem != null) {
        String oldKey = (String) potentialOldCalcItem.get(roll.lookupFieldOnCalcItem);
        if (key == oldKey || String.isBlank(key)) {
          continue;
        }

        if (lookupFieldToCalcItems.containsKey(oldKey) == false) {
          List<SObject> oldItems = this.isEmptyReparentingSet(roll.op) ? new List<SObject>() : new List<SObject>{ potentialOldCalcItem };
          lookupFieldToCalcItems.put(oldKey, new CalcItemBag(oldItems));
        } else if (this.isEmptyReparentingSet(roll.op) == false) {
          lookupFieldToCalcItems.get(oldKey).add(potentialOldCalcItem);
        }
      }
    }
    return lookupFieldToCalcItems;
  }

  protected virtual List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return new List<RollupAsyncProcessor>();
  }

  protected virtual override String getHashedContents() {
    // the only thing that necessarily makes a rollup unique is the metadata behind it
    return String.valueOf(this.metadata);
  }

  protected void overrideParentRollupControlValues(RollupControl__mdt specificControl) {
    // override section - most updates go from a rollup specific control -> this.rollupControl
    if (specificControl.BatchChunkSize__c < this.rollupControl.BatchChunkSize__c) {
      this.rollupControl.BatchChunkSize__c = specificControl.BatchChunkSize__c;
    }
    if (specificControl.MaxLookupRowsBeforeBatching__c > this.rollupControl.MaxLookupRowsBeforeBatching__c) {
      this.rollupControl.MaxLookupRowsBeforeBatching__c = specificControl.MaxLookupRowsBeforeBatching__c;
    }
    if (specificControl.ShouldRunAs__c != this.rollupControl.ShouldRunAs__c) {
      this.rollupControl.ShouldRunAs__c = specificControl.ShouldRunAs__c;
    }
    if (specificControl.MaxParentRowsUpdatedAtOnce__c == null) {
      specificControl.MaxParentRowsUpdatedAtOnce__c = this.rollupControl.MaxParentRowsUpdatedAtOnce__c;
    }
    if (specificControl.ShouldDuplicateRulesBeIgnored__c == true) {
      this.rollupControl.ShouldDuplicateRulesBeIgnored__c = true;
    }
  }

  protected Boolean parentRollupFieldHasBeenReset(Rollup__mdt meta, SObject parent) {
    return this.previouslyResetParents.contains(this.getParentResetKey(meta.RollupFieldOnLookupObject__c, parent));
  }

  protected Boolean parentRollupFieldHasBeenReset(RollupAsyncProcessor processor, SObject parent) {
    return this.previouslyResetParents.contains(this.getParentResetKey(String.valueOf(processor.opFieldOnLookupObject), parent));
  }

  protected virtual Boolean getCanRollupWithoutCustomSetting() {
    return this.metadata?.ShouldRunWithoutCustomSettingEnabled__c == true;
  }

  private Boolean getCanEnqueue() {
    return Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
  }

  private String getParentResetKey(String fieldKey, SObject parent) {
    return fieldKey + parent.Id;
  }

  private Boolean isValidAdditionalCalcItemRetrieval(RollupAsyncProcessor roll) {
    switch on roll.invokePoint {
      when FROM_FULL_RECALC_LWC, FROM_SINGULAR_PARENT_RECALC_LWC, FROM_FULL_RECALC_FLOW {
        // if we aren't batching, safe to assume a full recalc has already pulled the rest of the records back
        return System.isBatch();
      }
      when else {
        return roll.isFullRecalc || roll.metadata.IsFullRecordSet__c == true;
      }
    }
  }

  private Boolean getIsTimingOut(RollupControl__mdt control, RollupAsyncProcessor processor) {
    if (this.isTimingOut == false && hasExceededCurrentRollupLimits(control)) {
      RollupLogger.Instance.log('Starting to time out ...', LoggingLevel.WARN);
      this.isTimingOut = true;
    }
    if (this.isTimingOut) {
      processor.isProcessed = false;
    }
    return this.isTimingOut;
  }

  private void preProcessRollups(List<RollupAsyncProcessor> rollupsToProcess) {
    for (Integer index = rollupsToProcess.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = rollupsToProcess[index];
      List<RollupAsyncProcessor> additionalRollups = rollup.transformFullRecalcRollups();
      // this can be a conductor containing full recalc rollups
      if (rollup.rollups.isEmpty() == false) {
        this.preProcessRollups(rollup.rollups);
        additionalRollups.addAll(rollup.rollups);
      }

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
        // this way, the updated values are persisted for each field
        SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
        localLookupItems.add(updatedLookupObject);
      }
    }
    localLookupItems.addAll(roll.getExistingLookupItems(lookupItemKeys, roll, this.lookupObjectToUniqueFieldNames.get(roll.lookupObj)));
    return localLookupItems;
  }

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty()) {
      return;
    }
    Boolean isAllowedToContinue = this.rollupControl.MaxRollupRetries__c >= stackDepth;
    RollupLogger.Instance.log(
      'Number of deferred rollups: ' +
      this.deferredRollups.size() +
      ', still allowed to re-queue?: ' +
      isAllowedToContinue +
      ' with stackDepth: ' +
      this.stackDepth,
      LoggingLevel.DEBUG
    );

    Boolean isDeferralAllowed = this.getIsDeferralAllowed() && isAllowedToContinue;
    this.stackDepth++;
    this.setIsDeferralAllowed(this.rollupControl.MaxRollupRetries__c > stackDepth);
    this.rollups.clear();
    this.rollups.addAll(this.deferredRollups);
    this.deferredRollups.clear();

    if (isDeferralAllowed) {
      RollupLogger.Instance.log('deferred rollups remaining:', this.rollups, LoggingLevel.DEBUG);
      this.getAsyncRollup()?.beginAsyncRollup();
    } else if (this.rollups.isEmpty() == false) {
      RollupLogger.Instance.log('deferral was explicitly disallowed for rollups:', this.rollups, LoggingLevel.ERROR);
    }
    RollupLogger.Instance.save();
  }

  private void setupCalcItemData(Rollup roll) {
    if (roll.calcItems == null || roll.calcItems.isEmpty()) {
      roll.calcItems = this.calcItems;
      roll.oldCalcItems = this.oldCalcItems;
    }
  }

  private void populateObjectFields(List<RollupAsyncProcessor> rollups) {
    if (this.lookupObjectToUniqueFieldNames != null) {
      return;
    }
    this.lookupObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    this.calcObjectToUniqueFieldNames = new Map<SObjectType, Set<String>>();
    List<Rollup__mdt> combinedMeta = new List<Rollup__mdt>();
    for (RollupAsyncProcessor roll : rollups) {
      if (roll.lookupObj == null) {
        continue;
      }
      combinedMeta.add(roll.metadata);
      String rollupField = roll.opFieldOnLookupObject.getDescribe().getName();
      String lookupfield = roll.lookupFieldOnLookupObject.getDescribe().getName();
      Set<String> rollupFieldNames = new Set<String>{ rollupField, lookupfield };
      if (this.lookupObjectToUniqueFieldNames.containsKey(roll.lookupObj)) {
        this.lookupObjectToUniqueFieldNames.get(roll.lookupObj).addAll(rollupFieldNames);
      } else {
        this.lookupObjectToUniqueFieldNames.put(roll.lookupObj, rollupFieldNames);
      }

      Set<String> whereFields = new Set<String>{ roll.opFieldOnCalcItem.getDescribe().getName(), roll.lookupFieldOnCalcItem.getDescribe().getName() };
      if (String.isNotBlank(roll.metadata.CalcItemWhereClause__c)) {
        whereFields.addAll(RollupEvaluator.getWhereEval(roll.metadata.CalcItemWhereClause__c, roll.calcItemType).getQueryFields());
      }
      for (RollupOrderBy__mdt orderBy : roll.metadata.RollupOrderBys__r) {
        whereFields.add(orderBy.FieldName__c);
      }
      if (this.calcObjectToUniqueFieldNames.containsKey(roll.calcItemType)) {
        this.calcObjectToUniqueFieldNames.get(roll.calcItemType).addAll(whereFields);
      } else {
        this.calcObjectToUniqueFieldNames.put(roll.calcItemType, whereFields);
      }
      if (this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, roll.calcItems) == false) {
        Integer oldHashCode = roll.calcItems?.hashCode();
        roll.calcItems = this.calcItemReplacer.replace(roll.calcItems, combinedMeta);
        this.replaceCalcItems(oldHashCode, roll.calcItems, roll, CollectionType.ITERABLE);
      }
      if (this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, roll.oldCalcItems?.values()) == false) {
        Integer oldHashCode = roll.oldCalcItems?.hashCode();
        Map<Id, SObject> oldCalcItemsWithUpdatedFields = new Map<Id, SObject>();
        for (SObject oldCalcItem : this.calcItemReplacer.replace(roll.oldCalcItems?.values(), combinedMeta)) {
          oldCalcItemsWithUpdatedFields.put(oldCalcItem.Id, oldCalcItem);
        }
        roll.oldCalcItems = oldCalcItemsWithUpdatedFields;
        this.replaceCalcItems(oldHashCode, roll.oldCalcItems, roll, CollectionType.DICTIONARY);
      }
      if (this.fullRecalcProcessor != null) {
        this.fullRecalcProcessor.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames;
        this.fullRecalcProcessor.lookupObjectToUniqueFieldNames = this.lookupObjectToUniqueFieldNames;
      }
    }
  }

  private void replaceCalcItems(Integer oldHashCode, Object updatedRecords, Rollup innerRollup, CollectionType collectionType) {
    // this unfortunate statement wouldn't be nearly so bad if the collections were passed by reference - but they're not,
    // they're passed by value, which means the reassignments below would not cascade back up to the innerRollup's
    // calcItems / oldCalcItems properties without explicitly being re-set.
    if (innerRollup.calcItems?.hashCode() == oldHashCode) {
      switch on collectionType {
        when ITERABLE {
          innerRollup.calcItems = (List<SObject>) updatedRecords;
        }
        when DICTIONARY {
          innerRollup.oldCalcItems = (Map<Id, SObject>) updatedRecords;
        }
      }
    }
  }

  private void winnowRollups(List<RollupAsyncProcessor> potentialRollups) {
    this.preProcessRollups(potentialRollups);
    for (Integer index = potentialRollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor processor = potentialRollups[index];
      Map<String, SObjectField> fieldMap = processor.lookupObj?.getDescribe().fields.getMap();
      if (fieldMap?.containsKey(processor.opFieldOnLookupObject.getDescribe().getName()) == false) {
        potentialRollups.remove(index);
      }
    }
  }

  private Boolean isEmptyReparentingSet(Op operation) {
    switch on operation {
      // reparenting is handled already for these operations
      when ALL, DELETE_ALL, DELETE_MOST, DELETE_NONE, DELETE_SOME, MOST, NONE, SOME, UPDATE_ALL, UPDATE_MOST, UPDATE_NONE, UPDATE_SOME {
        return true;
      }
      when else {
        return false;
      }
    }
  }

  private Boolean ingestRollupControlData(List<RollupAsyncProcessor> syncRollups) {
    Boolean isRunningAsnyc = this.getIsRunningAsync();
    Boolean shouldRollupsRunWithoutCustomSetting = false;
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = this.rollups[index];
      shouldRollupsRunWithoutCustomSetting = rollup.getCanRollupWithoutCustomSetting();
      this.flagFullRecalcRollups(rollup);

      Boolean shouldRunSyncDeferred = this.getShouldRunSyncDeferred(rollup);
      Boolean couldRunSync =
        rollup.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous ||
        (isRunningAsnyc && this.getIsTimingOut(rollup.rollupControl, rollup) == false) ||
        this.isSingleRecordSyncUpdate(rollup);

      if (rollup.rollupControl.ShouldAbortRun__c || this.rollupControl.ShouldAbortRun__c) {
        this.rollups.remove(index);
      } else if (couldRunSync && shouldRunSyncDeferred == false) {
        this.calcItemReplacer?.resetShouldRunAs(RollupMetaPicklists.ShouldRunAs.Synchronous);
        this.rollups.remove(index);
        syncRollups.add(rollup);
      } else if (couldRunSync && shouldRunSyncDeferred) {
        this.rollups.remove(index);
        this.getCachedRollups().add(rollup);
      }

      this.overrideParentRollupControlValues(rollup.rollupControl);
    }
    return shouldRollupsRunWithoutCustomSetting;
  }

  private void flagFullRecalcRollups(RollupAsyncProcessor rollup) {
    if (this.isValidAdditionalCalcItemRetrieval(rollup) && rollup.isFullRecalc == false) {
      rollup.isFullRecalc = true;
    } else {
      rollup.isFullRecalc = rollup.isFullRecalc || this.isFullRecalc;
    }
  }

  private Boolean isSingleRecordSyncUpdate(RollupAsyncProcessor roll) {
    return roll.calcItems?.size() == 1 &&
      (this.rollupControl.ShouldRunSingleRecordsSynchronously__c || roll.rollupControl.ShouldRunSingleRecordsSynchronously__c);
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

  private Integer getLookupRecordsCount(List<RollupAsyncProcessor> processors) {
    // we need to burn a few SOQL calls to consider how many records are going to be queried/updated
    // then, using RollupControl__mdt and/or sensible defaults, we'll decide whether to queue up or batch
    // (or fail - that's always an option)
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();

    Integer totalCountOfRecords = 0;
    for (RollupAsyncProcessor roll : processors) {
      if (roll.queryCount != null) {
        totalCountOfRecords += roll.queryCount;
        continue;
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
      for (SObject calcItem : roll.calcItems) {
        if (calcItem.getSObjectType() == roll.calcItemType) {
          String lookupKey = (String) calcItem.get(roll.lookupFieldOnCalcItem);
          if (String.isNotBlank(lookupKey)) {
            uniqueIds.add(lookupKey);
          }
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

    for (String countQuery : queryCountsToLookupIds.keySet()) {
      Set<String> objIds = queryCountsToLookupIds.get(countQuery);
      Integer countForSObject = getCountFromDb(countQuery, objIds);
      if (countForSObject == RollupQueryBuilder.SENTINEL_COUNT_VALUE) {
        totalCountOfRecords = this.rollupControl.MaxLookupRowsBeforeBatching__c.intValue() - 1;
        break;
      } else {
        totalCountOfRecords += countForSObject;
      }
    }
    return totalCountOfRecords;
  }

  private List<SObject> getUpdatedLookupItemsByRollup(RollupAsyncProcessor roll, Map<String, CalcItemBag> calcItemsByLookupField, List<SObject> lookupItems) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    Map<String, SObject> unprocessedCalcItems = new Map<String, SObject>();
    RollupSObjectUpdater updater = new RollupSObjectUpdater(roll.opFieldOnLookupObject);
    if (roll.fullRecalcProcessor != null) {
      roll.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames;
      roll.fullRecalcProcessor.retrieveAdditionalCalcItems(calcItemsByLookupField, roll);
    } else {
      this.retrieveAdditionalCalcItems(calcItemsByLookupField, roll);
    }

    RollupCalculator calc;
    for (Integer index = lookupItems.size() - 1; index >= 0; index--) {
      SObject lookupRecord = lookupItems[index];
      if (lookupRecord.getSObjectType() != roll.lookupObj) {
        continue;
      }
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        CalcItemBag bag = calcItemsByLookupField.get(key);
        List<SObject> localCalcItems = bag.getAll();

        if (this.getIsTimingOut(this.rollupControl, roll) || (this.isValidAdditionalCalcItemRetrieval(roll) && bag.hasQueriedForAdditionalItems == false)) {
          // this loop only gets entered into for one rollup because there's another early return checking isTimingOut in the outer method
          SObject replacementLookupRecord = lookupRecord.getSObjectType().newSObject();
          for (String fieldName : lookupRecord.getPopulatedFieldsAsMap().keySet()) {
            if (fieldName != roll.opFieldOnLookupObject.getDescribe().getName()) {
              replacementLookupRecord.put(fieldName, lookupRecord.getPopulatedFieldsAsMap().get(fieldName));
            }
          }
          recordsToUpdate.put(lookupRecord.Id, replacementLookupRecord);
          unprocessedCalcItems.putAll(localCalcItems);
          lookupItems.remove(index);
          continue;
        }

        this.populateReparentedItems(roll, localCalcItems, oldLookupItems);

        // local calculations and reparenting can step on one another (due to full recalculations happening)
        // this guard clause prevents a full recalculation from taking place unnecessarily if a reparenting operation
        // has already been setup to adjust the lookup item's rollup field
        if (localCalcItems.isEmpty() == false || (localCalcItems.isEmpty() && oldLookupItems.isEmpty())) {
          Object priorVal = lookupRecord.get(roll.opFieldOnLookupObject);
          Object priorValToUse = roll.isFullRecalc && this.parentRollupFieldHasBeenReset(roll, lookupRecord) == false ? null : priorVal;
          calc = this.getCalculator(calc, roll, localCalcItems, lookupRecord, priorValToUse, key, roll.lookupFieldOnCalcItem);
          this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, updater, 'lookup', localCalcItems);
        }
      }
    }

    this.removeRolledUpValuesFromReparentedRecords(lookupItems, oldLookupItems, recordsToUpdate, roll, updater);
    this.deferCalculationsWhenApproachingLimits(roll, unprocessedCalcItems.values());
    this.handleFullRecalculators(roll);

    return recordsToUpdate.values();
  }

  private void deferCalculationsWhenApproachingLimits(RollupAsyncProcessor roll, List<SObject> unprocessedCalcItems) {
    if (unprocessedCalcItems.isEmpty() == false) {
      this.deferredRollups.add(roll);
    }
  }

  private void populateReparentedItems(RollupAsyncProcessor roll, List<SObject> localCalcItems, Map<String, List<SObject>> oldLookupItems) {
    if (this.isEmptyReparentingSet(roll.op)) {
      return;
    }
    for (Integer index = localCalcItems.size() - 1; index >= 0; index--) {
      SObject calcItem = localCalcItems[index];
      if (roll.oldCalcItems?.containsKey(calcItem.Id) != true) {
        continue;
      }
      SObject oldCalcItem = roll.oldCalcItems.get(calcItem.Id);
      String priorLookup = (String) oldCalcItem.get(roll.lookupFieldOnCalcItem);
      // if the lookup wasn't previously populated, there's nothing to update
      if (String.isBlank(priorLookup)) {
        continue;
      }

      if (priorLookup != calcItem.get(roll.lookupFieldOnCalcItem) && roll.traversal == null) {
        this.populateOldLookupItems(priorLookup, oldCalcItem, oldLookupItems);
      } else if (roll.traversal?.isUltimatelyReparented(calcItem, roll.lookupFieldOnCalcItem.getDescribe().getName()) == true) {
        Id oldLookupId = roll.traversal.getOldLookupId(calcItem, roll.lookupFieldOnCalcItem.getDescribe().getName());
        if (oldLookupId != null) {
          this.populateOldLookupItems(oldLookupId, oldCalcItem, oldLookupItems);
        }
      }

      // once the reparenting logic has been done, if the lookup field isn't set on the current child object, remove it
      if (String.isBlank((String) calcItem.get(roll.lookupFieldOnCalcItem))) {
        localCalcItems.remove(index);
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

  private void handleFullRecalculators(RollupAsyncProcessor roll) {
    if (roll instanceof RollupFullRecalcProcessor && roll.isProcessed == false) {
      this.deferredRollups.add(roll);
    }
  }

  private RollupCalculator getCalculator(
    RollupCalculator rollupCalc,
    RollupAsyncProcessor roll,
    List<SObject> calcItems,
    SObject lookupRecord,
    Object priorVal,
    String lookupRecordKey,
    SObjectField lookupKeyField
  ) {
    Rollup.Op rollupOp = roll.op;
    if (roll.isFullRecalc && roll.op.name().contains('DELETE')) {
      rollupOp = this.getOpMap().get(roll.op.name().substringAfter('_'));
    }
    if (rollupCalc == null) {
      rollupCalc = RollupCalculator.Factory.getCalculator(rollupOp, roll.opFieldOnCalcItem, roll.opFieldOnLookupObject, roll.metadata, lookupKeyField);
    }
    rollupCalc.setFullRecalc(roll.isFullRecalc);
    rollupCalc.setDefaultValues(lookupRecordKey, priorVal);
    rollupCalc.setEvaluator(roll.eval);
    rollupCalc.setCDCUpdate(this.isCDCUpdate);
    rollupCalc.setMultiCurrencyInfo(lookupRecord);
    rollupCalc.performRollup(calcItems, roll.oldCalcItems);
    return rollupCalc;
  }

  private void removeRolledUpValuesFromReparentedRecords(
    List<SObject> lookupItems,
    Map<String, List<SObject>> oldLookupItems,
    Map<String, SObject> recordsToUpdate,
    RollupAsyncProcessor roll,
    RollupSObjectUpdater updater
  ) {
    if (oldLookupItems.isEmpty() || this.isEmptyReparentingSet(roll.op)) {
      return;
    }
    RollupCalculator calc;
    Op deleteOp = this.getOpMap().get('DELETE_' + getBaseOperationName(roll.op.name()));
    RollupAsyncProcessor oldLookupsRollup = getProcessor(
      new FilterResults(),
      roll.opFieldOnCalcItem,
      roll.lookupFieldOnCalcItem,
      roll.lookupFieldOnLookupObject,
      roll.opFieldOnLookupObject,
      roll.lookupObj,
      roll.calcItemType,
      deleteOp,
      this.invokePoint,
      this.rollupControl,
      roll.metadata
    );
    for (SObject lookupRecord : lookupItems) {
      if (lookupRecord.getSObjectType() != roll.lookupObj) {
        continue;
      }
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      if (oldLookupItems.containsKey(key)) {
        // Yes, old parent record has already had a new rollup established in memory
        List<SObject> reparentedCalcItems = oldLookupItems.get(key);
        Object priorVal = lookupRecord.get(roll.opFieldOnLookupObject);

        if (reparentedCalcItems.isEmpty() || priorVal == null) {
          continue;
        }

        oldLookupsRollup.calcItems = reparentedCalcItems;
        RollupLogger.Instance.log('reparenting operation:', oldLookupsRollup, LoggingLevel.DEBUG);
        calc = this.getCalculator(calc, oldLookupsRollup, reparentedCalcItems, lookupRecord, priorVal, key, roll.lookupFieldOnCalcItem);
        this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, updater, 'reparented', reparentedCalcItems);
      }
    }
  }

  private void conditionallyPerformUpdate(
    Object priorVal,
    RollupCalculator calc,
    SObject lookupRecord,
    RollupAsyncProcessor roll,
    Map<String, SObject> recordsToUpdate,
    RollupSObjectUpdater updater,
    String logKey,
    List<SObject> localCalcItems
  ) {
    RollupLogger.Instance.log(logKey + ' record prior to rolling up:', lookupRecord, LoggingLevel.DEBUG);
    Object newVal = calc.getReturnValue();
    if (this.rollupControl.ShouldSkipResettingParentFields__c == true && ((localCalcItems.isEmpty() == false && newVal == null) || localCalcItems.isEmpty())) {
      newVal = priorVal;
    }
    if (priorVal != newVal) {
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      RollupLogger.Instance.log('updating record ...', LoggingLevel.FINE);
      updater.updateField(lookupRecord, newVal);
      recordsToUpdate.put(key, lookupRecord);
    }
    this.storeParentResetField(roll, lookupRecord);
    RollupLogger.Instance.log(logKey + ' record after rolling up:', lookupRecord, LoggingLevel.DEBUG);
  }
}
