global virtual without sharing class RollupAsyncProcessor extends Rollup implements Database.Batchable<SObject>, Database.RaisesPlatformEvents, System.Comparable {
  private final Evaluator eval;
  private final Op op;
  private final SObjectField lookupFieldOnCalcItem;
  private final SObjectField lookupFieldOnLookupObject;
  private final SObjectField opFieldOnCalcItem;
  private final SObjectType lookupObj;
  private final SObjectField opFieldOnLookupObject;

  private Integer stackDepth = 0;
  private List<SObject> lookupItems;
  private Map<SObjectType, Set<String>> calcObjectToUniqueFieldNames;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private RollupRelationshipFieldFinder.Traversal traversal;
  private Boolean wasConvertedToFullRecalculation = false;

  protected Boolean isTimingOut = false;
  protected Boolean isProcessed = false;
  protected Boolean overridesRunCalc = false;
  protected Boolean shouldSortToFront = false;
  protected RollupFullRecalcProcessor fullRecalcProcessor;
  protected final SObjectType calcItemType;
  protected final Set<String> recordIds;

  private static Set<String> hashedRollups = new Set<String>();
  @TestVisible
  private static List<SObject> stubParentRecords;
  @TestVisible
  private static Boolean shouldRunAsBatch = false;
  @TestVisible
  private static Integer additionalCalcItemCount;
  private static Boolean hasAlreadyAsyncEnqueued = false;

  private enum CollectionType {
    DICTIONARY,
    ITERABLE
  }

  private enum ParentUpdateType {
    LOOKUP,
    REPARENTED
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

  private final Map<Schema.SObjectType, RollupFullRecalcProcessor> childToUnexpectedFullRecalc {
    get {
      if (childToUnexpectedFullRecalc == null) {
        childToUnexpectedFullRecalc = new Map<Schema.SObjectType, RollupFullRecalcProcessor>();
      }
      return childToUnexpectedFullRecalc;
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

  private static Map<Integer, Map<String, CalcItemBag>> CACHED_CALC_ITEM_LOOKUPS {
    get {
      if (CACHED_CALC_ITEM_LOOKUPS == null) {
        CACHED_CALC_ITEM_LOOKUPS = new Map<Integer, Map<String, CalcItemBag>>();
      }
      return CACHED_CALC_ITEM_LOOKUPS;
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
    this.lookupItems = innerRollup.lookupItems;
    this.previouslyResetParents.addAll(innerRollup.getPreviouslyResetParents());
    this.calcObjectToUniqueFieldNames = innerRollup.calcObjectToUniqueFieldNames;
    this.lookupObjectToUniqueFieldNames = innerRollup.lookupObjectToUniqueFieldNames;
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

  public Database.QueryLocator start(Database.BatchableContext context) {
    /**
     * for batch, we know 100% for sure there's only 1 SObjectType / Set<String> in the map.
     * NB: we have to call "populateObjectFields" in both the "start" and "execute" methods because
     * trying to use Database.Stateful on the top-level class ** in addition to Batchable ** results in the dreaded:
     * "System.AsyncException: Queueable cannot be implemented with other system interfaces" exception
     */
    RollupRepository repo = this.preStart();
    this.logger.save();
    return repo.getLocator();
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> scope) {
    this.logger.log('starting batch chunk', this, LoggingLevel.INFO);

    if (this.getTypeName() == RollupAsyncProcessor.class.getName()) {
      this.lookupItems = scope;
      for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
        RollupAsyncProcessor roll = this.rollups[index];
        if (scope.getSObjectType() != roll.lookupObj) {
          this.rollups.remove(index);
          this.deferredRollups.add(roll);
        }
      }
    } else {
      this.calcItems = scope;
    }

    this.performWork();
    this.logger.log('batch chunk end', LoggingLevel.INFO);
    this.logger.save();
  }

  public virtual void finish(Database.BatchableContext context) {
    if (this.isTimingOut == false) {
      this.fullRecalcProcessor?.finish();
    }
    if (context == null) {
      context = new AdditionalContext(this.getNoProcessId());
    }
    this.logger.log(this.getTypeName() + ' finished successfully', context, LoggingLevel.INFO);
    this.logger.save();
  }

  public virtual void storeParentResetField(RollupAsyncProcessor processor, SObject parent) {
    this.addToPreviouslyResetParents(processor, parent);
    this.fullRecalcProcessor?.storeParentResetField(processor, parent);
  }

  public virtual override String runCalc() {
    // side effect in the below method - rollups can be removed from this.rollups if a control record ShouldAbortRun__c == true
    // they also can be added to syncRollups if we're already async
    List<RollupAsyncProcessor> syncRollups = new List<RollupAsyncProcessor>();
    Boolean shouldRunWithoutCustomSetting = this.ingestRollupControlData(syncRollups);

    Boolean isBasicNoOp = this.rollups.isEmpty() && syncRollups.isEmpty() && this.isFullRecalc == false;
    if (this.isNoOp) {
      this.isNoOp = isBasicNoOp && this.calcItems?.isEmpty() == true;
    } else {
      this.isNoOp = isBasicNoOp;
    }

    String rollupProcessId = this.getNoProcessId();
    String logMessage;
    System.LoggingLevel logLevel = System.LoggingLevel.INFO;
    if (this.isNoOp) {
      logMessage = 'no-op, exiting early to avoid burning async job';
    } else if (this.rollupControl.ShouldAbortRun__c) {
      logMessage = String.valueOf(RollupControl__mdt.SObjectType) + '.' + String.valueOf(RollupControl__mdt.ShouldAbortRun__c) + ' set to true, exiting early';
    } else if (RollupSettings__c.getInstance().IsEnabled__c == false && shouldRunWithoutCustomSetting == false) {
      logMessage = String.valueOf(RollupSettings__c.SObjectType) + '.' + String.valueOf(RollupSettings__c.IsEnabled__c) + ' is false, exiting early';
    } else if (syncRollups.isEmpty() == false) {
      this.logger.log(this.getTypeName() + ': about to process sync rollups', logLevel);
      this.process(syncRollups);
      logMessage = 'finished running sync rollups';
      if (this.rollups.isEmpty()) {
        rollupProcessId = logMessage;
      }
    } else {
      Integer totalCountOfRecords = this.getLookupRecordsCount(this.rollups);
      shouldRunAsBatch =
        shouldRunAsBatch ||
        (this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Batchable &&
        totalCountOfRecords >= this.rollupControl.MaxLookupRowsBeforeBatching__c);
      rollupProcessId = this.getAsyncRollup()?.beginAsyncRollup();
    }
    if (logMessage != null) {
      this.logger.log(this.getTypeName() + ': ' + logMessage, logLevel);
      rollupProcessId = logMessage;
    }
    this.logger.save();
    return rollupProcessId;
  }

  protected virtual RollupRepository preStart() {
    this.winnowRollups(this.rollups);
    this.populateObjectFields(this.rollups);
    String query = 'SELECT Id FROM Organization WHERE Name != \'' + UserInfo.getOrganizationName() + '\'';
    RollupRepository repo = new RollupRepository(this.accessLevel);
    if (this.rollups.isEmpty() == false) {
      RollupAsyncProcessor firstRollup = this.rollups.get(0);
      SObjectType sObjectType = firstRollup.lookupObj;
      String lookupFieldForLookupObject = firstRollup.lookupFieldOnLookupObject.getDescribe().getName();
      Set<String> uniqueLookupObjectFields = this.lookupObjectToUniqueFieldNames.get(sObjectType);
      repo.setArg(this.getCalcItemsByLookupField(firstRollup, uniqueLookupObjectFields).keySet());
      query = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(uniqueLookupObjectFields), lookupFieldForLookupObject, '=');
    }
    return repo.setQuery(query);
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

  protected virtual void performWork() {
    this.process(this.rollups);
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    // swap off on which async process is running to achieve infinite scaling
    Boolean canEnqueue = this.getCanEnqueue();
    RollupAsyncProcessor roll;
    if (this.rollups.size() == 1 && this.rollups[0] instanceof RollupFullRecalcProcessor && (System.isBatch() == false || this.rollups[0].isBatch() == false)) {
      roll = this.rollups[0];
    } else if (this instanceof RollupFullRecalcProcessor && this.isBatch() == false) {
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
    } else if (canEnqueue && (System.isQueueable() == false || hasAlreadyAsyncEnqueued == false)) {
      roll = new QueueableProcessor(this);
    } else if (canEnqueue) {
      roll = this.rollupControl.IsDevEdOrTrialOrg__c && this.stackDepth >= 4 ? new RollupAsyncProcessor(this) : this;
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

    protected virtual override Boolean isBatch() {
      return false;
    }

    protected virtual override String startAsyncWork() {
      if (System.isQueueable()) {
        hasAlreadyAsyncEnqueued = true;
      }
      return System.enqueueJob(this);
    }

    public void execute(System.QueueableContext qc) {
      AdditionalContext context = new AdditionalContext(qc);
      this.setCurrentJobId(context.getJobId());
      System.attachFinalizer(new RollupFinalizer());
      this.performWork();
      if (this.fullRecalcProcessor?.isBatch() != true) {
        this.finish(context);
      }
    }
  }

  private class AdditionalContext implements Database.BatchableContext {
    private final String jobId;

    public AdditionalContext(String noProcessId) {
      this.jobId = noProcessId;
    }

    public AdditionalContext(System.QueueableContext qc) {
      this.jobId = qc?.getJobId();
    }

    public String getJobId() {
      return this.jobId;
    }

    public Id getChildJobId() {
      return null;
    }
  }

  protected String beginAsyncRollup() {
    this.isTimingOut = false;
    this.logger.log('about to start for ' + this.getTypeName(), this, LoggingLevel.INFO);
    return this.startAsyncWork();
  }

  protected virtual String startAsyncWork() {
    return this.startBatchProcessor();
  }

  protected String startBatchProcessor() {
    return Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
  }

  protected List<SObject> getExistingLookupItems(Set<String> lookupKeys, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
    if (lookupKeys.isEmpty()) {
      this.lookupItems = new List<SObject>();
    } else if (stubParentRecords != null) {
      this.lookupItems = stubParentRecords;
    }
    // for Rollups that are Batchable, the lookup items are retrieved en masse in the "start" method and cached in the "execute" method
    if (this.lookupItems != null) {
      return this.lookupItems;
    }
    List<SObject> localLookupItems;
    if (rollup.traversal != null) {
      localLookupItems = rollup.traversal.getAllParents();
    } else {
      localLookupItems = new RollupRepository(rollup.accessLevel)
        .setQuery(
          RollupQueryBuilder.Current.getQuery(
            rollup.lookupObj,
            new List<String>(uniqueQueryFieldNames),
            String.valueOf(rollup.lookupFieldOnLookupObject),
            '='
          ) + (this.isSingleRecordSyncUpdate(rollup) ? '\nFOR UPDATE' : '')
        )
        .setArg(lookupKeys)
        .get();
    }
    List<SObject> recordsToReset = new List<SObject>();
    for (SObject lookupItem : localLookupItems) {
      if (this.parentRollupFieldHasBeenReset(rollup, lookupItem) == false) {
        recordsToReset.add(lookupItem);
      }
    }
    this.lookupItems = localLookupItems;
    this.fullRecalcProcessor?.processParentFieldsToReset(this.lookupItems);
    return this.lookupItems;
  }

  protected void retrieveAdditionalCalcItems(Map<String, CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    if (
      this.isValidAdditionalCalcItemRetrieval(rollup) == false ||
      rollup.metadata?.RollupToUltimateParent__c == true ||
      rollup.lookupFieldOnCalcItem == null
    ) {
      return;
    }

    Set<String> lookupKeys = new Set<String>();
    for (CalcItemBag bag : lookupToCalcItems.values()) {
      if (bag.hasQueriedForAdditionalItems == false) {
        bag.hasQueriedForAdditionalItems = true;
        lookupKeys.addAll(bag.getAllIds());
      }
      // calling clear in a loop here might look interesting - and it would be a massive problem if not for the
      // bag only responding to the very first clear() invocation. everything after that is a no-op (so, any rollup with more
      // than one rollup operation going at a time)
      if (rollup.triggerContext == System.TriggerOperation.BEFORE_DELETE) {
        bag.clear();
      }
    }

    if (lookupKeys.isEmpty()) {
      return;
    }

    Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null &&
      rollup.calcObjectToUniqueFieldNames != null
      ? rollup.calcObjectToUniqueFieldNames
      : this.calcObjectToUniqueFieldNames;

    String recordBindVar = 'recordIds';
    String whereClause = '' + rollup.lookupFieldOnCalcItem + ' = :' + recordBindVar;
    String query = RollupQueryBuilder.Current.getQuery(
      rollup.calcItemType,
      new List<String>(localCalcToUniqueFieldNames.get(rollup.calcItemType)),
      'Id',
      '!=',
      whereClause
    );
    String cachedQueryKey = query;

    Boolean hasAlreadyBeenQueried = this.cachedQueryToAdditionalCalcItems.containsKey(query);
    Boolean shouldLimitCalcItemQuery = false;
    Integer remainingQueryRowsLeft = 0;
    Integer outstandingItemCount = 0;
    List<SObject> additionalCalcItems = new List<SObject>();

    /**
     * Below follows one of the most complicated pieces of logic in the entire codebase
     * with respect to limits, we need to retrieve any missing children for all parents
     * and defer our calculation(s) till such a time as all other adjacent children have been fetched
     */

    if (hasAlreadyBeenQueried) {
      additionalCalcItems = this.cachedQueryToAdditionalCalcItems.get(query);
    } else {
      Set<String> recordIds = lookupToCalcItems.keySet();
      RollupRepository repo = new RollupRepository(rollup.accessLevel).setQuery(query).setArg(lookupKeys).setArg(recordBindVar, recordIds);
      if (additionalCalcItemCount != null) {
        outstandingItemCount = additionalCalcItemCount;
        additionalCalcItemCount = null;
      } else {
        outstandingItemCount = repo.getCount();
      }
      remainingQueryRowsLeft = new RollupLimits.Tester(rollup.rollupControl, this.getIsRunningAsync()).getRemainingQueryRows();
      shouldLimitCalcItemQuery = outstandingItemCount >= remainingQueryRowsLeft;

      if (shouldLimitCalcItemQuery) {
        query = RollupQueryBuilder.Current.getAllRowSafeQuery(rollup.calcItemType, query += '\nLIMIT ' + remainingQueryRowsLeft);
        // this might look weird - and it is - but we want limited versions of the query to build up the full number of records
        // by adding to the existing cache, which isn't possible if there are any numbers after the limit clause
        cachedQueryKey = query.substringBeforeLast('LIMIT') + 'LIMIT';
        hasAlreadyBeenQueried = this.cachedQueryToAdditionalCalcItems.containsKey(cachedQueryKey);
      }

      if (shouldLimitCalcItemQuery && remainingQueryRowsLeft < outstandingItemCount) {
        rollup.wasConvertedToFullRecalculation = true;
        rollup.metadata.RollupOperation__c = getBaseOperationName(rollup.metadata.RollupOperation__c);
        for (String lookupKey : recordIds) {
          this.storeParentResetField(rollup, rollup.lookupObj.newSObject(Id.valueOf(lookupKey)));
        }
        if (this.childToUnexpectedFullRecalc.containsKey(rollup.calcItemType)) {
          this.childToUnexpectedFullRecalc.get(rollup.calcItemType).addMetadata(rollup.metadata);
        } else {
          this.logger.log(this.getTypeName() + ': Populating unexpected full recalc for ' + outstandingItemCount + ' items', LoggingLevel.INFO);
          RollupFullRecalcProcessor fullBatchProcessor = new RollupFullBatchRecalculator(
            query.substringBeforeLast('\nLIMIT'),
            this.invokePoint,
            new List<Rollup__mdt>{ rollup.metadata },
            rollup.calcItemType,
            recordIds,
            null
          );
          fullBatchProcessor.queryCount = outstandingItemCount;
          this.childToUnexpectedFullRecalc.put(rollup.calcItemType, fullBatchProcessor);
        }
        return;
      }
      if (outstandingItemCount > 0) {
        additionalCalcItems = repo.setQuery(query).get();

        if (hasAlreadyBeenQueried) {
          this.cachedQueryToAdditionalCalcItems.get(cachedQueryKey).addAll(additionalCalcItems);
        } else {
          this.cachedQueryToAdditionalCalcItems.put(cachedQueryKey, additionalCalcItems);
        }
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
    this.isProcessed = true;
    this.handleMultipleDMLRollupsEnqueuedInTheSameTransaction(rollups);
    this.preProcessRollups(rollups);
    this.populateObjectFields(rollups);

    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<String, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<String, RollupRelationshipFieldFinder.Traversal>();
    for (RollupAsyncProcessor roll : rollups) {
      roll.isProcessed = true;
      this.setupCalcItemData(roll);
      // for each iteration, ensure we're not operating beyond the bounds of our governor limits
      if (this.getIsTimingOut(roll.rollupControl, roll)) {
        this.deferredRollups.add(roll);
        continue;
      }

      String grandparentKey = '' + roll.lookupObj + roll.calcItemType;
      if (String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c) && grandparentRollups.containsKey(grandparentKey)) {
        roll.traversal = grandparentRollups.get(grandparentKey);
      }

      Set<String> uniqueParentObjectFields = this.lookupObjectToUniqueFieldNames.get(roll.lookupObj);
      Map<String, CalcItemBag> calcItemsByLookupField = this.getCalcItemsByLookupField(roll, uniqueParentObjectFields);
      // some rollups may not finish retrieving all parent rows the first time around - and that's ok! we can keep
      // trying until all necessary records have been retrieved
      if (roll.traversal?.getIsFinished() == false) {
        this.addProcessorToDeferredRollups(roll);
        continue;
      } else if (roll.traversal != null) {
        // cache the traversal for any future callers - because we queried for ALL unique grand(or greater)parent fields
        // we don't need to re-traverse the whole object chain again if there are other grandparent rollups in the list
        grandparentRollups.put(grandparentKey, roll.traversal);
      }

      List<SObject> localLookupItems = this.getLookupItems(calcItemsByLookupField, updatedLookupRecords, roll);
      this.logger.log(this.getTypeName() + ' starting rollup for:', roll, LoggingLevel.INFO);
      updatedLookupRecords.putAll(this.getUpdatedLookupItemsByRollup(roll, calcItemsByLookupField, localLookupItems));
    }

    if (this.isTimingOut) {
      this.getDML().forceSyncUpdate();
    }
    this.cleanup();
    this.getDML().doUpdate(updatedLookupRecords.values());
    this.populateOtherDeferredRollups();
    this.processDeferredRollups();
  }

  protected virtual List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return new List<RollupAsyncProcessor>();
  }

  protected virtual override String getHashedContents() {
    // the only thing that necessarily makes a rollup unique is the metadata behind it
    return String.valueOf(this.metadata);
  }

  protected virtual Boolean isBatch() {
    return true;
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
    return this.hasParentRollupFieldBeenReset(meta.RollupFieldOnLookupObject__c, parent);
  }

  protected Boolean parentRollupFieldHasBeenReset(RollupAsyncProcessor processor, SObject parent) {
    return this.hasParentRollupFieldBeenReset(String.valueOf(processor.opFieldOnLookupObject), parent);
  }

  protected virtual Set<String> getPreviouslyResetParents() {
    return this.previouslyResetParents;
  }

  protected void addToPreviouslyResetParents(RollupAsyncProcessor processor, SObject parent) {
    this.getPreviouslyResetParents().add(this.getParentResetKey(String.valueOf(processor.opFieldOnLookupObject), parent));
  }

  protected virtual Boolean getCanRollupWithoutCustomSetting() {
    return this.metadata?.ShouldRunWithoutCustomSettingEnabled__c == true;
  }

  private void clearPreviouslyResetParents(RollupAsyncProcessor processor, SObject parent) {
    String key = this.getParentResetKey(String.valueOf(processor.opFieldOnLookupObject), parent);
    this.getPreviouslyResetParents().remove(key);
  }

  private Boolean hasParentRollupFieldBeenReset(String rollupFieldName, SObject parent) {
    String resetKey = this.getParentResetKey(rollupFieldName, parent);
    return this.getPreviouslyResetParents().contains(resetKey);
  }

  protected Boolean getCanEnqueue() {
    return Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
  }

  private void addProcessorToDeferredRollups(RollupAsyncProcessor processor) {
    processor.isProcessed = false;
    this.deferredRollups.add(processor);
  }

  private String getParentResetKey(String fieldKey, SObject parent) {
    return fieldKey + parent.Id;
  }

  private Boolean isValidAdditionalCalcItemRetrieval(RollupAsyncProcessor roll) {
    if (roll.fullRecalcProcessor != null) {
      // if we aren't batching, safe to assume a full recalc has already pulled the rest of the records back
      return roll.fullRecalcProcessor.isBatch() != true;
    } else {
      return roll.isFullRecalc || roll.metadata.IsFullRecordSet__c == true;
    }
  }

  private Boolean getIsTimingOut(RollupControl__mdt control, RollupAsyncProcessor processor) {
    if (this.isTimingOut == false && hasExceededCurrentRollupLimits(control)) {
      this.logger.log(this.getTypeName() + ': starting to time out ...', LoggingLevel.WARN);
      this.isTimingOut = true;
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

  private Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor roll, Set<String> uniqueLookupObjectFields) {
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

    Integer cacheKey = roll.calcItems.hashCode();
    switch on this.invokePoint {
      when FROM_FULL_RECALC_LWC, FROM_SINGULAR_PARENT_RECALC_LWC, FROM_FULL_RECALC_FLOW {
        Map<String, CalcItemBag> possiblyCachedItems = CACHED_CALC_ITEM_LOOKUPS.get(cacheKey);
        if (possiblyCachedItems != null) {
          return possiblyCachedItems;
        }
      }
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
    CACHED_CALC_ITEM_LOOKUPS.put(cacheKey, lookupFieldToCalcItems);
    return lookupFieldToCalcItems;
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

  private void populateOtherDeferredRollups() {
    this.deferredRollups.addAll(this.childToUnexpectedFullRecalc.values());
    if (this.getCachedRollups().isEmpty() == false) {
      for (Rollup outerRollup : this.getCachedRollups()) {
        this.deferredRollups.addAll(outerRollup.rollups);
      }
      this.getCachedRollups().clear();
    }
  }

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty()) {
      return;
    }
    Boolean isAllowedToContinue = this.rollupControl.MaxRollupRetries__c >= stackDepth;
    this.logger.log(
      this.getTypeName() +
      ': number of deferred rollups: ' +
      this.deferredRollups.size() +
      ', still allowed to re-queue?: ' +
      isAllowedToContinue +
      ' with stackDepth: ' +
      this.stackDepth,
      LoggingLevel.INFO
    );

    Boolean isDeferralAllowed = this.getIsDeferralAllowed() && isAllowedToContinue;
    this.stackDepth++;
    this.setIsDeferralAllowed(this.rollupControl.MaxRollupRetries__c > stackDepth);
    this.rollups.clear();
    this.rollups.addAll(this.deferredRollups);
    this.deferredRollups.clear();
    this.isTimingOut = false;

    if (isDeferralAllowed) {
      this.logger.log(this.getTypeName() + ': deferred rollups remaining:', this.rollups, LoggingLevel.INFO);
      this.getAsyncRollup()?.beginAsyncRollup();
    } else if (this.rollups.isEmpty() == false) {
      this.logger.log(this.getTypeName() + ': deferral was explicitly disallowed for rollups:', this.rollups, LoggingLevel.ERROR);
    }
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
      if (this.fullRecalcProcessor != null) {
        this.fullRecalcProcessor.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames;
        this.fullRecalcProcessor.lookupObjectToUniqueFieldNames = this.lookupObjectToUniqueFieldNames;
      }
    }

    if (this.calcItems != null && this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, this.calcItems) == false) {
      Integer oldHashCode = this.calcItems?.hashCode();
      this.calcItems = this.calcItemReplacer.replace(this.calcItems, combinedMeta);
      this.replaceCalcItems(oldHashCode, this.calcItems, rollups, CollectionType.ITERABLE);
    }
    if (this.oldCalcItems != null && this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, this.oldCalcItems.values()) == false) {
      Integer oldHashCode = this.oldCalcItems?.hashCode();
      Map<Id, SObject> oldCalcItemsWithUpdatedFields = new Map<Id, SObject>();
      for (SObject oldCalcItem : this.calcItemReplacer.replace(this.oldCalcItems.values(), combinedMeta)) {
        oldCalcItemsWithUpdatedFields.put(oldCalcItem.Id, oldCalcItem);
      }
      this.oldCalcItems = oldCalcItemsWithUpdatedFields;
      this.replaceCalcItems(oldHashCode, this.oldCalcItems, rollups, CollectionType.DICTIONARY);
    }
  }

  private void replaceCalcItems(Integer oldHashCode, Object updatedRecords, List<Rollup> innerRollups, CollectionType type) {
    // this unfortunate statement wouldn't be nearly so bad if the collections were passed by reference - but they're not,
    // they're passed by value, which means the reassignments below would not cascade back up to the innerRollup's
    // calcItems / oldCalcItems properties without explicitly being re-set.
    for (Rollup innerRollup : innerRollups) {
      Boolean isMatch = (type == CollectionType.ITERABLE ? innerRollup.calcItems?.hashCode() : innerRollup.oldCalcItems?.hashCode()) == oldHashCode;
      if (isMatch) {
        switch on type {
          when ITERABLE {
            innerRollup.calcItems = (List<SObject>) updatedRecords;
          }
          when DICTIONARY {
            innerRollup.oldCalcItems = (Map<Id, SObject>) updatedRecords;
          }
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
      when ALL, MOST, NONE, SOME {
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
      String hashedRollupKey = rollup.getHashedContents() + rollup.calcItems?.hashCode() + rollup.oldCalcItems?.hashCode();
      if (hashedRollups.contains(hashedRollupKey)) {
        this.rollups.remove(index);
      } else if (rollup.rollupControl.ShouldAbortRun__c || this.rollupControl.ShouldAbortRun__c) {
        this.rollups.remove(index);
      } else if (couldRunSync && shouldRunSyncDeferred == false) {
        this.calcItemReplacer?.resetShouldRunAs(RollupMetaPicklists.ShouldRunAs.Synchronous);
        this.rollups.remove(index);
        syncRollups.add(rollup);
      } else if (couldRunSync && shouldRunSyncDeferred) {
        this.rollups.remove(index);
        this.getCachedRollups().add(rollup);
      }
      hashedRollups.add(hashedRollupKey);

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
    Map<String, Set<String>> queryCountsToLookupIds = new Map<String, Set<String>>();

    Integer totalCountOfRecords = 0;
    System.AccessLevel localAccessLevel = this.accessLevel;
    for (RollupAsyncProcessor roll : processors) {
      localAccessLevel = roll.accessLevel;
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
          String lookupKey = (String) calcItem.get(roll.lookupFieldOnCalcItem.getDescribe().getName());
          if (String.isNotBlank(lookupKey)) {
            uniqueIds.add(lookupKey);
          }
        }
      }

      String countQuery = RollupQueryBuilder.Current.getQuery(roll.lookupObj, new List<String>(), String.valueOf(roll.lookupFieldOnLookupObject), '=');
      if (queryCountsToLookupIds.containsKey(countQuery)) {
        queryCountsToLookupIds.get(countQuery).addAll(uniqueIds);
      } else {
        queryCountsToLookupIds.put(countQuery, uniqueIds);
      }
    }

    RollupRepository repo = new RollupRepository(localAccessLevel);
    for (String countQuery : queryCountsToLookupIds.keySet()) {
      Integer countForSObject = repo.setQuery(countQuery).setArg(queryCountsToLookupIds.get(countQuery)).getCount();
      if (countForSObject == RollupRepository.SENTINEL_COUNT_VALUE) {
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
    this.retrieveAdditionalCalcItems(calcItemsByLookupField, roll);
    if (roll.wasConvertedToFullRecalculation) {
      return recordsToUpdate.values();
    }

    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    Map<String, SObject> unprocessedCalcItems = new Map<String, SObject>();
    RollupSObjectUpdater updater = new RollupSObjectUpdater(roll.opFieldOnLookupObject);
    RollupCalculator calc;
    String priorKey;
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
          this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, updater, ParentUpdateType.LOOKUP, localCalcItems);
        }
        if (priorKey != null && key != priorKey) {
          // once we've fully processed a parent (in separate batches)
          // it's safe to clear the stateful map
          this.clearPreviouslyResetParents(roll, lookupRecord);
          priorKey = key;
        } else if (priorKey == null) {
          priorKey = key;
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
      roll.calcItems = unprocessedCalcItems;
      this.addProcessorToDeferredRollups(roll);
    }
  }

  private void populateReparentedItems(RollupAsyncProcessor roll, List<SObject> localCalcItems, Map<String, List<SObject>> oldLookupItems) {
    if (roll.oldCalcItems?.isEmpty() == true || this.isEmptyReparentingSet(roll.op)) {
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
      rollupCalc.setEvaluator(roll.eval);
      rollupCalc.setCDCUpdate(this.isCDCUpdate);
      rollupCalc.setFullRecalc(roll.isFullRecalc);
    }
    rollupCalc.setDefaultValues(lookupRecordKey, priorVal);
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
        this.logger.log(this.getTypeName() + ': reparenting operation', oldLookupsRollup, LoggingLevel.DEBUG);
        calc = this.getCalculator(calc, oldLookupsRollup, reparentedCalcItems, lookupRecord, priorVal, key, roll.lookupFieldOnCalcItem);
        this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, updater, ParentUpdateType.REPARENTED, reparentedCalcItems);
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
    ParentUpdateType parentUpdateType,
    List<SObject> localCalcItems
  ) {
    String logKey = parentUpdateType.name().toLowerCase();
    this.logger.log(this.getTypeName() + ': ' + logKey + ' record prior to rolling up:', lookupRecord, LoggingLevel.DEBUG);
    Object newVal = calc.getReturnValue();
    if (this.rollupControl.ShouldSkipResettingParentFields__c == true && ((localCalcItems.isEmpty() == false && newVal == null) || localCalcItems.isEmpty())) {
      newVal = priorVal;
    }
    if (priorVal != newVal) {
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      this.logger.log(this.getTypeName() + ': updating record ...', LoggingLevel.FINE);
      updater.updateField(lookupRecord, newVal);
      recordsToUpdate.put(key, lookupRecord);
    }
    this.storeParentResetField(roll, lookupRecord);
    this.logger.log(this.getTypeName() + ': ' + logKey + ' record after rolling up:', lookupRecord, LoggingLevel.DEBUG);
  }

  private void cleanup() {
    RollupEvaluator.clearConditionCache();
    CACHED_CALC_ITEM_LOOKUPS = null;
  }
}
