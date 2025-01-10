@SuppressWarnings('PMD.NcssTypeCount')
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
  private Boolean isFromBatchExecute = false;
  private Map<String, CalcItemBag> groupedLookupToCalcItems;

  protected Id jobId;
  protected Boolean isTimingOut = false;
  protected Boolean isProcessed = false;
  protected Boolean overridesRunCalc = false;
  protected Boolean shouldSortToFront = false;
  protected RollupFullRecalcProcessor fullRecalcProcessor;
  protected final SObjectType calcItemType;
  protected final Set<String> recordIds;
  protected RollupFinalizer finalizer;

  private static Set<String> hashedRollups = new Set<String>();
  @TestVisible
  private static List<SObject> stubParentRecords;
  @TestVisible
  private static Integer additionalCalcItemCount;
  private static Boolean hasAlreadyAsyncEnqueued = false;

  private enum CollectionType {
    DICTIONARY,
    ITERABLE
  }

  private enum ParentUpdateType {
    LOOKUP,
    GROUPING,
    REPARENTED
  }

  private enum TimeoutCheckLevel {
    AT_ROLLUP,
    AT_PARENT
  }

  private Map<Schema.SObjectType, RollupFullRecalcProcessor> childToUnexpectedFullRecalc {
    get {
      this.childToUnexpectedFullRecalc = this.childToUnexpectedFullRecalc ?? new Map<Schema.SObjectType, RollupFullRecalcProcessor>();
      return this.childToUnexpectedFullRecalc;
    }
    set;
  }

  private final Map<String, List<SObject>> cachedQueryToAdditionalCalcItems {
    get {
      this.cachedQueryToAdditionalCalcItems = this.cachedQueryToAdditionalCalcItems ?? new Map<String, List<SObject>>();
      return this.cachedQueryToAdditionalCalcItems;
    }
    set;
  }

  private final List<RollupAsyncProcessor> deferredRollups {
    get {
      this.deferredRollups = this.deferredRollups ?? new List<RollupAsyncProcessor>();
      return this.deferredRollups;
    }
    set;
  }

  private final Set<String> uniqueParentFields {
    get {
      this.uniqueParentFields = this.uniqueParentFields ?? new Set<String>();
      return uniqueParentFields;
    }
    set;
  }

  private static Map<String, Map<String, CalcItemBag>> CACHED_CALC_ITEM_BAGS {
    get {
      CACHED_CALC_ITEM_BAGS = CACHED_CALC_ITEM_BAGS ?? new Map<String, Map<String, CalcItemBag>>();
      return CACHED_CALC_ITEM_BAGS;
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

  /**
   * Conductor constructors - "outer" rollups that orchestrate the proceedings for inner rollups.
   * These rollups tend to be the ones using the lazy-loaded properties above
   */
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
    if ((otherRollup instanceof RollupAsyncProcessor) == false) {
      return numberToReturn;
    }

    RollupAsyncProcessor that = (RollupAsyncProcessor) otherRollup;
    if (this.shouldSortToFront == false && that.shouldSortToFront) {
      numberToReturn = 1;
    } else if (that.shouldSortToFront == false && this.shouldSortToFront) {
      numberToReturn = -1;
    } else if (this.op != null && that.op != null && this.op != that.op) {
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

  /**
   * Batches can either be started to fetch all lookup items, or all calc items.
   * - NB: we have to call `populateObjectFields` in both the "start" and "execute" methods because
   * trying to use `Database.Stateful` on the top-level class _in addition to `Database.Batchable`_ results in the dreaded:
   * `System.AsyncException: Queueable cannot be implemented with other system interfaces` exception
   */
  public Database.QueryLocator start(Database.BatchableContext context) {
    this.jobId = this.jobId ?? context?.getJobId();
    RollupRepository repo = this.preStart();
    this.logger.save();
    return repo.getLocator();
  }

  public virtual void execute(Database.BatchableContext context, List<SObject> scope) {
    this.logger.log('starting batch chunk', this, System.LoggingLevel.INFO);

    this.isFromBatchExecute = true;
    this.innerBatchExecute(scope);
    this.isFromBatchExecute = false;

    this.executeFinish();
  }

  public virtual void finish(Database.BatchableContext context) {
    if (this.isTimingOut == false) {
      this.fullRecalcProcessor?.finish();
    }
    context = context ?? new AdditionalContext(this.getNoProcessId());
    this.logger.log('finished successfully', context, System.LoggingLevel.INFO);
    this.logger.save();
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

    String rollupProcessId = 'no-op';
    String logMessage;
    if (this.isNoOp) {
      logMessage = 'no-op, exiting early to avoid burning async job';
    } else if (this.rollupControl.ShouldAbortRun__c) {
      logMessage = RollupControl__mdt.SObjectType.toString() + '.' + RollupControl__mdt.ShouldAbortRun__c + ' set to true, exiting early';
    } else if (RollupSettings__c.getInstance().IsEnabled__c == false && shouldRunWithoutCustomSetting == false) {
      logMessage = RollupSettings__c.SObjectType.toString() + '.' + RollupSettings__c.IsEnabled__c + ' is false, exiting early';
    } else {
      if (syncRollups.isEmpty() == false) {
        rollupProcessId = this.getNoProcessId();
        this.logger.log('about to process sync rollups', System.LoggingLevel.INFO);
        this.process(syncRollups);
        this.logger.log('finished sync rollups', System.LoggingLevel.INFO);
      }
      if (this.rollups.isEmpty() == false || this instanceof RollupFullRecalcProcessor) {
        rollupProcessId = this.getAsyncRollup()?.beginAsyncRollup();
      }
    }
    if (logMessage != null) {
      this.logger.log(logMessage, System.LoggingLevel.INFO);
      rollupProcessId = logMessage;
    }
    this.logger.save();
    return rollupProcessId;
  }

  protected virtual RollupRepository preStart() {
    this.winnowRollups(this.rollups);
    String equality = '!=';
    if (this.childToUnexpectedFullRecalc.isEmpty() == false) {
      equality = '=';
    }
    this.populateObjectFields(this.rollups, false);
    String query = 'SELECT Id FROM Organization WHERE Name ' + equality + ' \'' + UserInfo.getOrganizationName() + '\'';
    RollupRepository repo = new RollupRepository(this.runAsMode);
    if (this.rollups.isEmpty() == false) {
      RollupAsyncProcessor firstRollup = this.rollups.get(0);
      repo.setArg(this.getCalcItemsByLookupField(firstRollup, null).keySet());
      query = RollupQueryBuilder.Current.getQuery(
        firstRollup.lookupObj,
        new List<String>(this.lookupObjectToUniqueFieldNames.get(firstRollup.lookupObj)),
        firstRollup.lookupFieldOnLookupObject.toString(),
        '='
      );
    }
    return repo.setQuery(query);
  }

  protected virtual override String getTypeName() {
    return RollupAsyncProcessor.class.getName();
  }

  protected virtual override Map<String, String> customizeToStringEntries(Map<String, String> props) {
    super.customizeToStringEntries(props);
    this.addToMap(props, 'Full Recalc Processor', this.fullRecalcProcessor?.getTypeName());
    this.addToMap(props, 'Stack depth', this.stackDepth > 0 ? this.stackDepth : null);
    this.addToMap(props, 'Is Processed?', this.isProcessed);
    return props;
  }

  public String getNoProcessId() {
    return 'No process Id';
  }

  protected virtual void innerBatchExecute(List<SObject> scope) {
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
  }

  protected virtual void performWork() {
    this.process(this.rollups);
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    Integer totalCountOfRecords = this.getLookupRecordsCount(this.rollups);
    Boolean shouldRunAsBatch =
      this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Batchable ||
      totalCountOfRecords >= this.rollupControl.MaxLookupRowsBeforeBatching__c;
    // swap off on which async process is running to achieve infinite scaling
    Boolean canEnqueue = this.getCanEnqueue();
    RollupAsyncProcessor roll;
    if (this instanceof RollupFullRecalcProcessor) {
      roll = this;
    } else if (this.rollups.size() == 1 && this.rollups[0] instanceof RollupFullRecalcProcessor) {
      roll = this.rollups[0];
    } else if (System.isBatch() == false && (shouldRunAsBatch || canEnqueue == false)) {
      // safe to batch because the QueryLocator will only return one type of SObject
      // we have to re-initialize the rollup because it's the Queueable inner class
      // at this point, and without re-initialization we get "System.UnexpectedException: Error processing messages"
      if (this instanceof QueueableProcessor) {
        roll = new RollupAsyncProcessor(this);
      } else {
        roll = this;
      }
    } else if (canEnqueue && (System.isQueueable() == false || hasAlreadyAsyncEnqueued == false) && (this instanceof QueueableProcessor) == false) {
      roll = new QueueableProcessor(this);
    } else if (canEnqueue) {
      roll = this.rollupControl.IsDevEdOrTrialOrg__c && this.stackDepth >= 4 ? new RollupAsyncProcessor(this) : this;
    }

    if (roll?.isNoOp != false && (roll instanceof RollupFullRecalcProcessor) == false) {
      roll = new NoOpProcessor(this.invokePoint);
    }

    return roll;
  }

  public without sharing class NoOpProcessor extends RollupAsyncProcessor {
    public NoOpProcessor(InvocationPoint invokePoint) {
      super(invokePoint);
    }

    protected override String beginAsyncRollup() {
      return new Rollup(this.invokePoint).runCalc();
    }

    protected override String getTypeName() {
      return NoOpProcessor.class.getName();
    }
  }

  public without sharing virtual class QueueableProcessor extends RollupAsyncProcessor implements System.Queueable {
    protected QueueableProcessor(InvocationPoint rollupInvokePoint) {
      super(rollupInvokePoint);
    }

    protected QueueableProcessor(InvocationPoint invokePoint, List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
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
      if (this.finalizer != null && System.isQueueable() && (System.Limits.getQueueableJobs() == 1 || hasAlreadyAsyncEnqueued)) {
        this.finalizer.addCaboose(this);
        return this.getNoProcessId();
      }
      hasAlreadyAsyncEnqueued = hasAlreadyAsyncEnqueued || System.isBatch() || System.isQueueable() || System.isFuture();
      return System.enqueueJob(this);
    }

    public void execute(System.QueueableContext qc) {
      this.logger.log('Starting ' + this.getTypeName() + ' queueable', this, System.LoggingLevel.INFO);
      AdditionalContext context = new AdditionalContext(qc);
      this.setCurrentJobId(context.getJobId());
      this.jobId = this.jobId ?? context.getJobId();
      this.finalizer = this.finalizer ?? this.getFinalizer();
      System.attachFinalizer(this.finalizer);

      this.performWork();

      if (this.fullRecalcProcessor?.isBatch() != true) {
        this.finish(context);
      } else {
        this.executeFinish();
      }
    }
  }

  protected virtual RollupFinalizer getFinalizer() {
    return new RollupFinalizer();
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

  protected virtual String beginAsyncRollup() {
    this.isTimingOut = false;
    this.logger.log('about to start for ' + this.getTypeName(), this, System.LoggingLevel.INFO);
    return this.startAsyncWork();
  }

  protected virtual String startAsyncWork() {
    return this.startBatchProcessor();
  }

  protected String startBatchProcessor() {
    String processId;
    if (this.isFromBatchExecute) {
      processId = new QueueableProcessor(this).startAsyncWork();
    } else {
      try {
        processId = Database.executeBatch(this, this.rollupControl.BatchChunkSize__c.intValue());
      } catch (Exception ex) {
        this.logger.log('Could not start batch, trying again as Queueable', ex, System.LoggingLevel.WARN);
        processId = new QueueableProcessor(this).startAsyncWork();
      }
    }
    return processId;
  }

  protected List<SObject> getExistingLookupItems(Set<String> lookupKeys, RollupAsyncProcessor roll, Set<String> uniqueQueryFieldNames) {
    List<SObject> lookupItemsToAssign;
    if (lookupKeys.isEmpty()) {
      lookupItemsToAssign = new List<SObject>();
    } else if (stubParentRecords != null && lookupItemsToAssign == null) {
      lookupItemsToAssign = stubParentRecords;
    } else if (this.lookupItems != null) {
      // lookup items are retrieved en masse in the "start" method for standard (not full recalc) Batch rollups, and are cached in the "execute" method
      lookupItemsToAssign = this.lookupItems;
    } else {
      lookupItemsToAssign = roll.traversal?.getAllParents() ??
        new RollupRepository(roll.runAsMode)
          .setQuery(
            RollupQueryBuilder.Current.getQuery(roll.lookupObj, new List<String>(uniqueQueryFieldNames), String.valueOf(roll.lookupFieldOnLookupObject), '=') +
            (this.isSingleRecordSyncUpdate(roll) ? '\nFOR UPDATE' : '')
          )
          .setArg(lookupKeys)
          .get();

      List<SObject> recordsToReset = new List<SObject>();
      for (SObject lookupItem : lookupItemsToAssign) {
        if (this.parentRollupFieldHasBeenReset('' + roll.lookupObj, '' + roll.opFieldOnLookupObject) == false) {
          recordsToReset.add(lookupItem);
        }
      }
      this.fullRecalcProcessor?.processParentFieldsToReset(recordsToReset);
      Map<Id, SObject> idToLookupItem = new Map<Id, SObject>(lookupItemsToAssign);
      for (SObject recordToReset : recordsToReset) {
        if (idToLookupItem.containsKey(recordToReset.Id) == false && roll.lookupObj == recordToReset.getSObjectType()) {
          lookupItemsToAssign.add(recordToReset);
        }
      }
    }
    return lookupItemsToAssign;
  }

  protected void retrieveAdditionalCalcItems(Map<String, CalcItemBag> lookupToCalcItems, RollupAsyncProcessor rollup) {
    Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null &&
      rollup.calcObjectToUniqueFieldNames != null
      ? rollup.calcObjectToUniqueFieldNames
      : this.calcObjectToUniqueFieldNames;
    if (
      this.isValidAdditionalCalcItemRetrieval(rollup) == false ||
      rollup.metadata?.RollupToUltimateParent__c == true ||
      rollup.lookupFieldOnCalcItem == null
    ) {
      return;
    } else if (rollup.isGrouped()) {
      this.handleGroupedCalcItemRetrieval(lookupToCalcItems, rollup, localCalcToUniqueFieldNames);
      return;
    }

    Set<String> childrenIds = new Set<String>();
    for (CalcItemBag bag : lookupToCalcItems.values()) {
      if (bag.hasQueriedForAdditionalItems == false) {
        bag.hasQueriedForAdditionalItems = true;
        childrenIds.addAll(bag.getAllIds());
      }
      // calling clear in a loop here might look interesting - and it would be a massive problem if not for the
      // bag only responding to the very first clear() invocation. everything after that is a no-op (so, any rollup with more
      // than one rollup operation going at a time)
      if (rollup.isDelete() && rollup.traversal?.getIsFinished() != true) {
        bag.clear();
      }
    }
    childrenIds.remove(null);

    if (childrenIds.isEmpty()) {
      return;
    }

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
    Decimal remainingQueryRowsLeft = 0;
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
      RollupRepository repo = new RollupRepository(rollup.runAsMode).setQuery(query).setArg(childrenIds).setArg(recordBindVar, recordIds);
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
        if (this.childToUnexpectedFullRecalc.containsKey(rollup.calcItemType)) {
          this.childToUnexpectedFullRecalc.get(rollup.calcItemType).addMetadata(rollup.metadata);
        } else {
          this.logger.log(this.getTypeName() + ': Populating unexpected full recalc for ' + outstandingItemCount + ' items', System.LoggingLevel.INFO);
          RollupFullRecalcProcessor fullBatchProcessor = new RollupFullBatchRecalculator(
            query.substringBeforeLast('\nLIMIT'),
            InvocationPoint.FROM_FULL_RECALC_APEX,
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
      } else {
        this.cachedQueryToAdditionalCalcItems.put(cachedQueryKey, new List<SObject>());
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
    this.populateObjectFields(rollups, false);

    Map<String, SObject> updatedLookupRecords = new Map<String, SObject>();
    Map<String, RollupRelationshipFieldFinder.Traversal> grandparentRollups = new Map<String, RollupRelationshipFieldFinder.Traversal>();
    for (RollupAsyncProcessor roll : rollups) {
      roll.isProcessed = true;
      this.setupCalcItemData(roll);
      // for each iteration, ensure we're not operating beyond the bounds of our governor limits
      if (this.getIsTimingOut(roll.rollupControl, TimeoutCheckLevel.AT_ROLLUP)) {
        this.addProcessorToDeferredRollups(roll);
        continue;
      }

      String grandparentKey = '' + roll.lookupObj + roll.calcItemType + (roll.metadata.CalcItemWhereClause__c?.trim() ?? '');
      if (String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c) && grandparentRollups.containsKey(grandparentKey) && roll.traversal == null) {
        roll.traversal = grandparentRollups.get(grandparentKey);
      }

      Map<String, CalcItemBag> calcItemsByLookupField = this.getCalcItemsByLookupField(roll, grandparentKey);
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
      this.logger.log('starting rollup for:', roll, System.LoggingLevel.INFO);
      updatedLookupRecords.putAll(this.getUpdatedLookupItemsByRollup(roll, calcItemsByLookupField, localLookupItems));
    }

    if (this.isTimingOut) {
      this.getDML().forceSyncUpdate();
    }
    this.cleanup();
    this.getDML().setFinalizer(this.finalizer).updateRecords();
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
    this.rollupControl.BatchChunkSize__c = this.rollupControl.BatchChunkSize__c ?? 2000;
    if (specificControl.BatchChunkSize__c < this.rollupControl.BatchChunkSize__c) {
      this.rollupControl.BatchChunkSize__c = specificControl.BatchChunkSize__c;
    }
    if (specificControl.MaxLookupRowsBeforeBatching__c > this.rollupControl.MaxLookupRowsBeforeBatching__c) {
      this.rollupControl.MaxLookupRowsBeforeBatching__c = specificControl.MaxLookupRowsBeforeBatching__c;
    }
    if (specificControl.ShouldRunAs__c != this.rollupControl.ShouldRunAs__c) {
      this.rollupControl.ShouldRunAs__c = specificControl.ShouldRunAs__c;
    }
    specificControl.MaxParentRowsUpdatedAtOnce__c = specificControl.MaxParentRowsUpdatedAtOnce__c ?? this.rollupControl.MaxParentRowsUpdatedAtOnce__c;
    if (specificControl.ShouldDuplicateRulesBeIgnored__c == true) {
      this.rollupControl.ShouldDuplicateRulesBeIgnored__c = true;
    }
  }

  protected Boolean parentRollupFieldHasBeenReset(String parentTypeName, String parentRollupField) {
    return this.uniqueParentFields.contains(parentTypeName + parentRollupField);
  }

  protected void storeUniqueParentFields(Rollup__mdt meta) {
    if (meta != null) {
      this.uniqueParentFields.add(meta.LookupObject__c + meta.RollupFieldOnLookupObject__c);
    }
  }

  protected virtual Boolean getCanRollupWithoutCustomSetting() {
    return this.metadata?.ShouldRunWithoutCustomSettingEnabled__c == true;
  }

  protected Boolean getCanEnqueue() {
    return Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
  }

  protected Object getDefaultValue(Rollup__mdt meta) {
    return (Object) meta.FullRecalculationDefaultNumberValue__c ?? (Object) meta.FullRecalculationDefaultStringValue__c;
  }

  private void storeParentResetField(String resetKey, SObject parent) {
    if (resetKey != null) {
      this.fullRecalcProcessor?.trackParentRecord(parent);
    }
  }

  private void addProcessorToDeferredRollups(RollupAsyncProcessor processor) {
    processor.isProcessed = false;
    this.deferredRollups.add(processor);
  }

  private Boolean isValidAdditionalCalcItemRetrieval(RollupAsyncProcessor roll) {
    Set<InvocationPoint> alwaysFalseForRetrieval = new Set<InvocationPoint>{
      InvocationPoint.FROM_FULL_RECALC_APEX,
      InvocationPoint.FROM_FULL_RECALC_LWC,
      InvocationPoint.FROM_FULL_RECALC_FLOW,
      InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC
    };
    if (roll.fullRecalcProcessor != null && alwaysFalseForRetrieval.contains(roll.invokePoint)) {
      return false;
    } else {
      return roll.isFullRecalc || roll.metadata.IsFullRecordSet__c == true || roll.metadata.IsDistinct__c == true || roll.isGrouped();
    }
  }

  private Boolean isGrouped() {
    return this.metadata.RollupGrouping__r.Id != null && this.rollups.isEmpty() == false;
  }

  private Boolean isDelete() {
    return this.triggerContext == System.TriggerOperation.BEFORE_DELETE || this.op.name().contains('DELETE');
  }

  private void handleGroupedCalcItemRetrieval(
    Map<String, CalcItemBag> lookupToCalcItems,
    RollupAsyncProcessor rollup,
    Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames
  ) {
    rollup.isFullRecalc = true;
    for (RollupAsyncProcessor groupedRollup : rollup.rollups) {
      groupedRollup.isFullRecalc = true;
      groupedRollup.metadata.IsFullRecordSet__c = true;
      groupedRollup.groupedLookupToCalcItems = new Map<String, CalcItemBag>();
      this.retrieveAdditionalCalcItems(lookupToCalcItems, groupedRollup);
      for (CalcItemBag bag : lookupToCalcItems.values()) {
        for (SObject child : bag.getAll()) {
          if (child.getSObjectType() != groupedRollup.calcItemType) {
            continue;
          }
          String lookupKey = (String) child.get(groupedRollup.lookupFieldOnCalcItem);
          CalcItemBag possibleGroupedBag = groupedRollup.groupedLookupToCalcItems.get(lookupKey);
          if (possibleGroupedBag == null) {
            possibleGroupedBag = new CalcItemBag(new List<SObject>());
            possibleGroupedBag.hasQueriedForAdditionalItems = true;
            groupedRollup.groupedLookupToCalcItems.put(lookupKey, possibleGroupedBag);
          }
          possibleGroupedBag.add(child);
          bag.removeKey(child.Id);
        }
      }
    }
  }

  private Boolean getIsTimingOut(RollupControl__mdt control, TimeoutCheckLevel timeCheckLevel) {
    if (timeCheckLevel == TimeoutCheckLevel.AT_PARENT && this.fullRecalcProcessor != null) {
      return false;
    }
    if (this.isTimingOut == false && hasExceededCurrentRollupLimits(control)) {
      this.logger.log(this.getTypeName() + ': starting to time out ...', System.LoggingLevel.WARN);
      this.isTimingOut = true;
    }
    return this.isTimingOut;
  }

  private void preProcessRollups(List<RollupAsyncProcessor> rollupsToProcess) {
    Map<Id, List<RollupAsyncProcessor>> groupingToRollups = new Map<Id, List<RollupAsyncProcessor>>();
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
        if (System.isQueueable() == false || hasAlreadyAsyncEnqueued == false || this.finalizer == null) {
          rollup.runCalc();
        } else {
          this.finalizer.addCaboose(rollup);
        }
      } else if (rollup.getTypeName() == RollupFullBatchRecalculator.class.getName()) {
        rollupsToProcess.remove(index);
        RollupFullBatchRecalculator fullRecalc = (RollupFullBatchRecalculator) rollup;
        RollupFullRecalcProcessor existingFullRecalc = this.childToUnexpectedFullRecalc.get(fullRecalc.getCalcItemType());
        if (existingFullRecalc == null) {
          this.childToUnexpectedFullRecalc.put(fullRecalc.getCalcItemType(), fullRecalc);
        } else {
          existingFullRecalc.addCaboose(fullRecalc);
        }
      } else if (
        rollup.metadata?.RollupGrouping__r.Id != null &&
        rollup.calcItems.isEmpty() == false &&
        rollup.calcItems[0].getSObjectType().toString() != rollup.metadata.CalcItem__c
      ) {
        List<RollupAsyncProcessor> groupedProcessors = groupingToRollups.get(rollup.metadata?.RollupGrouping__r.Id) ?? new List<RollupAsyncProcessor>();
        groupedProcessors.add(rollup);
        rollupsToProcess.remove(index);
        groupingToRollups.put(rollup.metadata?.RollupGrouping__r.Id, groupedProcessors);
      }
    }
    rollupsToProcess.addAll(this.transformFullRecalcRollups());
    for (RollupAsyncProcessor processor : rollupsToProcess) {
      List<RollupAsyncProcessor> groupedProcessors = groupingToRollups.get(processor.metadata?.RollupGrouping__r.Id);
      if (groupedProcessors != null) {
        processor.rollups.addAll(groupedProcessors);
      }
    }
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

  private Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor roll, String cacheKey) {
    Map<String, CalcItemBag> lookupFieldToCalcItems = new Map<String, CalcItemBag>();
    if (roll.calcItems == null) {
      return lookupFieldToCalcItems;
    }

    switch on this.invokePoint {
      when FROM_FULL_RECALC_LWC, FROM_SINGULAR_PARENT_RECALC_LWC, FROM_FULL_RECALC_FLOW {
        Map<String, CalcItemBag> possiblyCachedItems = CACHED_CALC_ITEM_BAGS.get(cacheKey);
        if (possiblyCachedItems != null) {
          return possiblyCachedItems;
        }
      }
    }

    if (String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c) || roll.metadata.RollupToUltimateParent__c) {
      roll.traversal = roll.traversal ??
        new RollupRelationshipFieldFinder(
            roll.rollupControl,
            roll.metadata,
            this.calcObjectToUniqueFieldNames.get(roll.calcItemType),
            this.lookupObjectToUniqueFieldNames.get(roll.lookupObj),
            roll.lookupObj,
            roll.oldCalcItems
          )
          .setIsFullRecalc(this.isFullRecalc)
          .setOldIntermediateGrandparents(this.fullRecalcProcessor?.getOldIntermediateGrandparents())
          .getParents(roll.calcItems);

      if (roll.traversal.getIsFinished()) {
        lookupFieldToCalcItems = roll.traversal.getParentLookupToRecords();
      } else {
        roll.traversal.recommence();
      }
    } else {
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
        CalcItemBag bag = lookupFieldToCalcItems.get(key);
        if (bag == null) {
          bag = new CalcItemBag(new List<SObject>());
          if (this.fullRecalcProcessor != null && this.isValidAdditionalCalcItemRetrieval(roll) == false) {
            bag.hasQueriedForAdditionalItems = true;
          }
          lookupFieldToCalcItems.put(key, bag);
        }
        bag.add(calcItem);

        // if the lookup key differs from what it was on the old child object,
        // include that value as well so that we can fix reparented records' rollup values
        if (potentialOldCalcItem != null) {
          String oldKey = (String) potentialOldCalcItem.get(roll.lookupFieldOnCalcItem);
          if (key == oldKey || String.isBlank(key)) {
            continue;
          }

          CalcItemBag oldBag = lookupFieldToCalcItems.get(oldKey);
          if (oldBag == null) {
            oldBag = new CalcItemBag(new List<SObject>());
            lookupFieldToCalcItems.put(oldKey, oldBag);
          }
          if (this.isEmptyReparentingOp(roll.op) == false) {
            oldBag.add(potentialOldCalcItem);
          }
        }
      }
    }
    CACHED_CALC_ITEM_BAGS.put(cacheKey, lookupFieldToCalcItems);
    return lookupFieldToCalcItems;
  }

  private List<SObject> getLookupItems(Map<String, CalcItemBag> calcItemsByLookupField, Map<String, SObject> updatedLookupRecords, RollupAsyncProcessor roll) {
    List<SObject> localLookupItems = new List<SObject>();
    Set<String> lookupItemKeys = new Set<String>(calcItemsByLookupField.keySet());
    if (this.fullRecalcProcessor != null) {
      this.fullRecalcProcessor.getState()?.loadState(this.jobId, lookupItemKeys);
      lookupItemKeys.addAll(this.fullRecalcProcessor.getRecordIdentifiers());
    }
    for (String lookupId : calcItemsByLookupField.keySet()) {
      if (updatedLookupRecords.containsKey(lookupId)) {
        lookupItemKeys.remove(lookupId);
        // this way, the updated values are persisted for each field
        SObject updatedLookupObject = updatedLookupRecords.get(lookupId);
        localLookupItems.add(updatedLookupObject);
      }
    }
    localLookupItems.addAll(this.getExistingLookupItems(lookupItemKeys, roll, this.lookupObjectToUniqueFieldNames.get(roll.lookupObj)));
    return localLookupItems;
  }

  private void populateOtherDeferredRollups() {
    RollupFullRecalcProcessor firstFullRecalc = this.loadCabooses();
    if (firstFullRecalc != null) {
      this.deferredRollups.add(firstFullRecalc);
    }
    this.childToUnexpectedFullRecalc = null;
    if (this.getCachedRollups().isEmpty() == false) {
      for (Rollup outerRollup : this.getCachedRollups()) {
        this.deferredRollups.addAll(outerRollup.rollups);
      }
      this.getCachedRollups().clear();
    }
  }

  private RollupFullRecalcProcessor loadCabooses() {
    RollupFullRecalcProcessor firstFullRecalc;
    for (RollupFullRecalcProcessor fullRecalc : this.childToUnexpectedFullRecalc.values()) {
      if (firstFullRecalc == null) {
        firstFullRecalc = fullRecalc;
      } else {
        firstFullRecalc.addCaboose(fullRecalc);
      }
    }
    return firstFullRecalc;
  }

  private void processDeferredRollups() {
    if (this.deferredRollups.isEmpty()) {
      return;
    }
    Boolean isAllowedToContinue = this.rollupControl.MaxRollupRetries__c >= stackDepth;
    this.logger.log(
      'number of deferred rollups: ' +
        this.deferredRollups.size() +
        ', still allowed to re-queue?: ' +
        isAllowedToContinue +
        ' with stackDepth: ' +
        this.stackDepth,
      System.LoggingLevel.WARN
    );

    Boolean isDeferralAllowed = this.getIsDeferralAllowed() && isAllowedToContinue;
    this.stackDepth++;
    this.setIsDeferralAllowed(this.rollupControl.MaxRollupRetries__c > stackDepth);
    this.isTimingOut = false;
    this.lookupObjectToUniqueFieldNames = null;
    this.calcObjectToUniqueFieldNames = null;

    if (isDeferralAllowed) {
      this.rollups.clear();
      this.rollups.addAll(this.deferredRollups);
      this.deferredRollups.clear();
      this.logger.log('deferred rollups remaining:', this.rollups, System.LoggingLevel.WARN);
      RollupAsyncProcessor conductor = this.rollups.size() == 1 && this.rollups[0] instanceof RollupFullRecalcProcessor
        ? this.rollups[0]
        : this.getAsyncRollup();
      if (conductor != null && this.finalizer != null) {
        this.finalizer.addCaboose(conductor);
      } else if (conductor != null) {
        conductor.startAsyncWork();
      }
      // for synchronous runs with a timeout, we need to ensure this.rollups is re-cleared here
      // to prevent re-running through the same logic in runCalc()
      this.rollups.clear();
    } else if (this.rollups.isEmpty() == false) {
      this.logger.log('deferral was explicitly disallowed for rollups:', this.rollups, System.LoggingLevel.ERROR);
      this.deferredRollups.clear();
    }
  }

  private void setupCalcItemData(Rollup roll) {
    if (roll.calcItems == null || roll.calcItems.isEmpty()) {
      roll.calcItems = this.calcItems;
      roll.oldCalcItems = this.oldCalcItems;
    }
  }

  private void populateObjectFields(List<RollupAsyncProcessor> rollups, Boolean isRecursivePopulation) {
    this.lookupObjectToUniqueFieldNames = this.lookupObjectToUniqueFieldNames ?? new Map<SObjectType, Set<String>>();
    this.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames ?? new Map<SObjectType, Set<String>>();
    List<Rollup__mdt> combinedMeta = new List<Rollup__mdt>();
    for (RollupAsyncProcessor roll : rollups) {
      if (roll.lookupObj == null) {
        continue;
      }
      combinedMeta.add(roll.metadata);
      this.mapFields(
        this.lookupObjectToUniqueFieldNames,
        roll.lookupObj,
        new Set<String>{ roll.opFieldOnLookupObject.toString(), roll.lookupFieldOnLookupObject.toString() }
      );

      Set<String> childFieldsToAdd = new Set<String>{ roll.opFieldOnCalcItem.toString(), roll.lookupFieldOnCalcItem.toString() };
      if (String.isNotBlank(roll.metadata.CalcItemWhereClause__c)) {
        childFieldsToAdd.addAll(RollupEvaluator.getWhereEval(roll.metadata.CalcItemWhereClause__c, roll.calcItemType).getQueryFields());
      }
      for (RollupOrderBy__mdt orderBy : roll.metadata.RollupOrderBys__r) {
        childFieldsToAdd.add(orderBy.FieldName__c);
      }
      this.mapFields(this.calcObjectToUniqueFieldNames, roll.calcItemType, childFieldsToAdd);
      if (roll.isGrouped()) {
        this.populateObjectFields(roll.rollups, true);
      }
    }

    if (isRecursivePopulation) {
      return;
    }

    if (this.calcItems != null && this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, this.calcItems) == false) {
      Integer oldHashCode = this.calcItems.hashCode();
      this.calcItems = this.calcItemReplacer.replace(this.calcItems, combinedMeta);
      this.replaceCalcItems(oldHashCode, this.calcItems, rollups, CollectionType.ITERABLE);
    }
    if (this.oldCalcItems != null && this.calcItemReplacer?.hasProcessedMetadata(combinedMeta, this.oldCalcItems.values()) == false) {
      Integer oldHashCode = this.oldCalcItems.hashCode();
      this.oldCalcItems = RollupFieldInitializer.Current.createSafeMap(this.calcItemReplacer.replace(this.oldCalcItems.values(), combinedMeta));
      this.replaceCalcItems(oldHashCode, this.oldCalcItems, rollups, CollectionType.DICTIONARY);
    }
  }

  private void mapFields(Map<Schema.SObjectType, Set<String>> typeToFields, Schema.SObjectType targetType, Set<String> fieldsToAdd) {
    Set<String> existingFields = typeToFields.get(targetType);
    if (existingFields == null) {
      typeToFields.put(targetType, fieldsToAdd);
    } else {
      existingFields.addAll(fieldsToAdd);
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
      if (fieldMap?.containsKey(processor.opFieldOnLookupObject.toString()) == false) {
        potentialRollups.remove(index);
      }
    }
  }

  private Boolean ingestRollupControlData(List<RollupAsyncProcessor> syncRollups) {
    Boolean isRunningAsync = this.getIsRunningAsync();
    Boolean shouldRollupsRunWithoutCustomSetting = false;
    RollupLimits.Tester limitTester = new RollupLimits.Tester(this.rollupControl, isRunningAsync);
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = this.rollups[index];
      shouldRollupsRunWithoutCustomSetting = rollup.getCanRollupWithoutCustomSetting();
      this.flagFullRecalcRollups(rollup);

      Boolean shouldRunSyncDeferred = this.getShouldRunSyncDeferred(rollup);
      Boolean couldRunSync =
        rollup.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous ||
        (isRunningAsync && this.getIsTimingOut(rollup.rollupControl, TimeoutCheckLevel.AT_ROLLUP) == false) ||
        this.isSingleRecordSyncUpdate(rollup);

      if (limitTester.hasExceededOrgAsyncLimit()) {
        couldRunSync = true;
        shouldRunSyncDeferred = false;
      }

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
    RollupRepository.RunAsMode localRunAsMode = this.runAsMode;
    for (RollupAsyncProcessor roll : processors) {
      runAsMode = roll.runAsMode;
      Integer possibleCountOfRecords = roll.queryCount ?? stubParentRecords?.size();
      if (possibleCountOfRecords != null) {
        totalCountOfRecords += possibleCountOfRecords;
        continue;
      }

      if (String.isNotBlank(roll.metadata?.GrandparentRelationshipFieldPath__c)) {
        // getting the count for grandparent (or greater) relationships will be handled further
        // downstream; for our purposes, it isn't useful to try to get all of the records while
        // we're still in a sync context
        continue;
      } else if (roll.calcItems?.isEmpty() != false) {
        continue;
      }

      String countQuery = RollupQueryBuilder.Current.getQuery(roll.lookupObj, new List<String>(), String.valueOf(roll.lookupFieldOnLookupObject), '=');
      Set<String> uniqueIds = queryCountsToLookupIds.get(countQuery);
      if (uniqueIds == null) {
        uniqueIds = new Set<String>();
        queryCountsToLookupIds.put(countQuery, uniqueIds);
      }
      for (SObject calcItem : roll.calcItems) {
        if (calcItem.getSObjectType() == roll.calcItemType) {
          String lookupKey = (String) calcItem.get(roll.lookupFieldOnCalcItem.toString());
          if (String.isNotBlank(lookupKey)) {
            uniqueIds.add(lookupKey);
          }
        }
      }
    }

    RollupRepository repo = new RollupRepository(localRunAsMode);
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
      for (SObject lookupItem : lookupItems) {
        if (lookupItem.getSObjectType() == roll.lookupObj) {
          String resetKey = String.valueOf(lookupItem.get(roll.lookupFieldOnLookupObject));
          recordsToUpdate.put(resetKey, lookupItem);
          this.storeParentResetField(resetKey, lookupItem);
        }
      }
      return recordsToUpdate.values();
    }

    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    RollupCalculator calc;
    Op rollupOp = roll.op;
    if (roll.isFullRecalc && roll.op.name().contains('DELETE')) {
      rollupOp = this.getOpMap().get(roll.op.name().substringAfter('_'));
    }
    Object defaultVal = this.getDefaultValue(roll.metadata);
    Boolean hasNotAlreadyBeenReset = this.parentRollupFieldHasBeenReset('' + roll.lookupObj, '' + roll.opFieldOnLookupObject) == false;
    for (Integer index = lookupItems.size() - 1; index >= 0; index--) {
      SObject lookupRecord = lookupItems[index];
      if (lookupRecord.getSObjectType() != roll.lookupObj) {
        continue;
      }
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      Object priorVal = lookupRecord.get(roll.opFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        CalcItemBag bag = calcItemsByLookupField.get(key);
        List<SObject> localCalcItems = bag.getAll();

        if (
          this.getIsTimingOut(this.rollupControl, TimeoutCheckLevel.AT_PARENT) ||
          (this.isValidAdditionalCalcItemRetrieval(roll) && bag.hasQueriedForAdditionalItems == false)
        ) {
          this.addProcessorToDeferredRollups(roll);
          lookupItems.remove(index);
          continue;
        }

        this.populateReparentedItems(roll, localCalcItems, oldLookupItems);

        // local calculations and reparenting can step on one another (due to full recalculations happening)
        // this guard clause prevents a full recalculation from taking place unnecessarily if a reparenting operation
        // has already been setup to adjust the lookup item's rollup field
        if (localCalcItems.isEmpty() == false || (localCalcItems.isEmpty() && oldLookupItems.isEmpty())) {
          Object priorValToUse = roll.isFullRecalc && hasNotAlreadyBeenReset ? defaultVal : priorVal;
          calc = this.getCalculator(rollupOp, calc, roll, bag, lookupRecord, priorValToUse, key, roll.lookupFieldOnCalcItem);
          this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, ParentUpdateType.LOOKUP, localCalcItems);
        }
      } else {
        this.logger.log('About to reset parent field for', lookupRecord, System.LoggingLevel.DEBUG);
        this.getDML().updateField(roll.opFieldOnLookupObject, lookupRecord, defaultVal);
      }
      roll.performGroupedRollup(calc, rollupOp, lookupRecord, key, recordsToUpdate, defaultVal);
    }

    this.removeRolledUpValuesFromReparentedRecords(lookupItems, oldLookupItems, recordsToUpdate, roll);
    this.handleFullRecalculators(roll);

    return recordsToUpdate.values();
  }

  private void populateReparentedItems(RollupAsyncProcessor roll, List<SObject> localCalcItems, Map<String, List<SObject>> oldLookupItems) {
    if (roll.oldCalcItems == null || roll.oldCalcItems.isEmpty() || this.isEmptyReparentingOp(roll.op)) {
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
      } else if (roll.traversal?.isUltimatelyReparented(calcItem, roll.lookupFieldOnCalcItem.toString()) == true) {
        Id oldLookupId = roll.traversal.getOldLookupId(calcItem, roll.lookupFieldOnCalcItem.toString());
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
    } else {
      this.storeUniqueParentFields(roll.metadata);
    }
  }

  private RollupCalculator getCalculator(
    Op operation,
    RollupCalculator rollupCalc,
    RollupAsyncProcessor roll,
    CalcItemBag bag,
    SObject lookupRecord,
    Object priorVal,
    String lookupRecordKey,
    SObjectField lookupKeyField
  ) {
    if (rollupCalc == null) {
      rollupCalc = RollupCalculator.Factory.getCalculator(operation, roll.opFieldOnCalcItem, roll.opFieldOnLookupObject, roll.metadata, lookupKeyField);
      rollupCalc.setEvaluator(roll.eval);
      rollupCalc.setCDCUpdate(this.isCDCUpdate);
      rollupCalc.setFullRecalc(roll.isFullRecalc);
      rollupCalc.setState(this.fullRecalcProcessor?.getState());
    }
    rollupCalc.setDefaultValues(lookupRecordKey, priorVal);
    rollupCalc.setMultiCurrencyInfo(lookupRecord);
    rollupCalc.performRollup(bag.getAll(), roll.oldCalcItems);
    return rollupCalc;
  }

  private void removeRolledUpValuesFromReparentedRecords(
    List<SObject> lookupItems,
    Map<String, List<SObject>> oldLookupItems,
    Map<String, SObject> recordsToUpdate,
    RollupAsyncProcessor roll
  ) {
    if (oldLookupItems.isEmpty() || this.isEmptyReparentingOp(roll.op)) {
      return;
    }
    RollupCalculator calc;
    Op deleteOp = this.getOpMap().get('DELETE_' + Rollup.getBaseOperationName(roll.op.name()));
    FilterResults results = new FilterResults();
    results.eval = roll.eval;
    Rollup__mdt clonedMeta = roll.metadata.clone();
    clonedMeta.RollupOperation__c = deleteOp.name();
    RollupAsyncProcessor oldLookupsRollup = getProcessor(
      results,
      roll.opFieldOnCalcItem,
      roll.lookupFieldOnCalcItem,
      roll.lookupFieldOnLookupObject,
      roll.opFieldOnLookupObject,
      roll.lookupObj,
      roll.calcItemType,
      deleteOp,
      this.invokePoint,
      this.rollupControl,
      clonedMeta
    );
    oldLookupsRollup.oldCalcItems = roll.oldCalcItems;
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
        this.logger.log('reparenting operation', oldLookupsRollup, System.LoggingLevel.DEBUG);
        CalcItemBag bag = new CalcItemBag(reparentedCalcItems);
        bag.hasQueriedForAdditionalItems = true;
        calc = this.getCalculator(deleteOp, calc, oldLookupsRollup, bag, lookupRecord, priorVal, key, roll.lookupFieldOnCalcItem);
        this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, ParentUpdateType.REPARENTED, reparentedCalcItems);
      }
    }
  }

  private void conditionallyPerformUpdate(
    Object priorVal,
    RollupCalculator calc,
    SObject lookupRecord,
    RollupAsyncProcessor roll,
    Map<String, SObject> recordsToUpdate,
    ParentUpdateType parentUpdateType,
    List<SObject> localCalcItems
  ) {
    String logKey = parentUpdateType.name().toLowerCase();
    this.logger.log(logKey + ' record prior to rolling up:', lookupRecord, System.LoggingLevel.DEBUG);
    Object newVal = calc.getReturnValue();
    if (
      this.rollupControl.ShouldSkipResettingParentFields__c == true &&
      ((localCalcItems?.isEmpty() == false && newVal == null) || localCalcItems?.isEmpty() == true)
    ) {
      newVal = priorVal;
    }
    String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
    if (priorVal != newVal) {
      this.getDML().updateField(roll.opFieldOnLookupObject, lookupRecord, newVal);
    }
    this.storeParentResetField(key, lookupRecord);
    recordsToUpdate.put(key, lookupRecord);
    this.logger.log(logKey + ' record after rolling up:', lookupRecord, System.LoggingLevel.DEBUG);
  }

  private void performGroupedRollup(RollupCalculator calc, Op op, SObject lookupRecord, String key, Map<String, SObject> recordsToUpdate, Object defaultVal) {
    if (this.isGrouped() == false) {
      return;
    }

    Object priorCalcValue = calc.getReturnValue();
    List<Object> values = new List<Object>{ priorCalcValue };
    Op groupedOp = op;
    for (RollupAsyncProcessor groupedRollup : this.rollups) {
      groupedOp = this.getOpMap().get(groupedRollup.metadata.RollupGrouping__r.RollupOperation__c) ?? op;
      this.logger.log('starting grouped rollup for:', groupedRollup.metadata, System.LoggingLevel.DEBUG);
      groupedRollup.isProcessed = true;
      CalcItemBag bag = groupedRollup.groupedLookupToCalcItems.get(key);
      if (bag != null) {
        RollupCalculator groupedCalc = this.getCalculator(op, null, groupedRollup, bag, lookupRecord, null, key, groupedRollup.lookupFieldOnCalcItem);
        values.add(groupedCalc.getReturnValue());
      }
    }

    calc.setDefaultValues(key, defaultVal);
    calc.setMultiCurrencyInfo(lookupRecord);

    this.conditionallyPerformUpdate(
      priorCalcValue,
      new RollupCalculator.ValueRollupCalculator(calc, values).setOperation(groupedOp),
      lookupRecord,
      this,
      recordsToUpdate,
      ParentUpdateType.GROUPING,
      null
    );
  }

  private void cleanup() {
    RollupEvaluator.clearCache();
    CACHED_CALC_ITEM_BAGS = null;
    this.uniqueParentFields.clear();
    this.cleanupStaticVars();
    this.getCachedApexOperations().clear();
  }

  private void executeFinish() {
    if (this.jobId != null) {
      this.fullRecalcProcessor?.getState()?.commitState(this.jobId);
    }
    this.logger.log(this.getTypeName() + ' execute end', System.LoggingLevel.INFO);
    this.logger.save();
  }
}
