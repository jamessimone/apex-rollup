global virtual without sharing class RollupAsyncProcessor extends Rollup implements Database.Batchable<SObject>, System.Comparable {
  private final SObjectField opFieldOnCalcItem;
  private final SObjectField lookupFieldOnCalcItem;
  private final SObjectField lookupFieldOnLookupObject;
  private final SObjectField opFieldOnLookupObject;
  private final SObjectType lookupObj;
  private final Evaluator eval;
  private final Op op;

  protected final SObjectType calcItemType;
  protected Boolean isProcessed = false;
  protected Boolean overridesRunCalc = false;
  protected FullRecalcProcessor fullRecalcProcessor;
  protected Boolean shouldSortToFront = false;

  private RollupRelationshipFieldFinder.Traversal traversal;
  private Map<SObjectType, Set<String>> lookupObjectToUniqueFieldNames;
  private Map<SObjectType, Set<String>> calcObjectToUniqueFieldNames;
  private List<SObject> lookupItems;
  private Integer stackDepth = 0;

  @TestVisible
  private static Boolean shouldRunAsBatch = false;
  @TestVisible
  private static Boolean shouldFlattenAsyncProcesses;

  private enum CollectionType {
    DICTIONARY,
    ITERABLE
  }

  private final Map<String, List<SObject>> cachedFullRecalcs {
    get {
      if (cachedFullRecalcs == null) {
        cachedFullRecalcs = new Map<String, List<SObject>>();
      }
      return cachedFullRecalcs;
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

  @SuppressWarnings('PMD.UnusedLocalVariable')
  public abstract without sharing class FullRecalcProcessor extends QueueableProcessor {
    protected final String queryString;
    protected final List<Rollup__mdt> rollupInfo;
    protected final Set<Id> recordIds;
    protected final Set<Id> objIds = new Set<Id>(); // necessary; there's a bind variable in the query string
    private final Set<String> previouslyResetParents = new Set<String>();

    public FullRecalcProcessor(String queryString, InvocationPoint invokePoint, List<Rollup__mdt> rollupInfo, SObjectType calcItemType, Set<Id> recordIds) {
      super(invokePoint);
      this.isFullRecalc = true;
      this.isNoOp = true; // consumers should either opt out of this or have it be set properly downstream
      this.calcItemType = calcItemType;
      this.queryString = queryString;
      this.rollupInfo = rollupInfo;
      this.recordIds = recordIds;
      this.overrideRollupControl();
    }

    protected override Map<String, String> customizeToStringEntries(Map<String, String> props) {
      props = super.customizeToStringEntries(props);
      this.addToMap(props, 'Rollup Metadata', this.rollupInfo);
      this.addToMap(props, 'Query String', this.queryString);
      return props;
    }

    protected override String getHashedContents() {
      return String.valueOf(this.rollupInfo);
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

    private void overrideRollupControl() {
      for (Rollup__mdt meta : this.rollupInfo) {
        if (meta.RollupControl__c != null) {
          RollupControl__mdt specificControl = this.getSpecificControl(meta.RollupControl__c);
          this.overrideParentRollupControlValues(specificControl);
        }
      }
    }
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
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor roll = this.rollups[index];
      if (lookupItems.getSObjectType() != roll.lookupObj) {
        this.rollups.remove(index);
        this.deferredRollups.add(roll);
      } else {
        this.initializeRollupFieldDefaults(lookupItems, roll);
      }
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
    // they also can be added to syncRollups if we're already async
    List<RollupAsyncProcessor> syncRollups = new List<RollupAsyncProcessor>();
    this.ingestRollupControlData(syncRollups);

    if (this.isNoOp) {
      this.isNoOp = this.rollups.isEmpty() && syncRollups.isEmpty() && (this.isFullRecalc == false && this.calcItems?.isEmpty() == true);
    }

    String rollupProcessId = this.getNoProcessId();
    if (this.isNoOp || this.rollupControl.ShouldAbortRun__c || RollupSettings__c.getInstance().IsEnabled__c == false) {
      RollupLogger.Instance.log('no-op, exiting early to avoid burning async job', LoggingLevel.FINE);
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
    return props;
  }

  protected String getNoProcessId() {
    return 'No process Id';
  }

  protected RollupAsyncProcessor getAsyncRollup() {
    // swap off on which async process is running to achieve infinite scaling
    Boolean canEnqueue = Limits.getLimitQueueableJobs() > Limits.getQueueableJobs();
    RollupAsyncProcessor roll;
    if (this.rollups.size() == 1 && this.rollups[0] instanceof FullRecalcProcessor) {
      roll = this.rollups[0];
    } else if (this instanceof FullRecalcProcessor) {
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
    } else {
      this.attemptToStaticallyDeferRollup();
    }

    return roll;
  }

  private without sharing virtual class QueueableProcessor extends RollupAsyncProcessor implements System.Queueable {
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

    @SuppressWarnings('PMD.ApexSOQLInjection')
    protected override List<SObject> getExistingLookupItems(Set<String> objIds, RollupAsyncProcessor rollup, Set<String> uniqueQueryFieldNames) {
      if (objIds.isEmpty()) {
        return new List<SObject>();
      }
      List<SObject> localLookupItems;
      if (String.isNotBlank(rollup.metadata.GrandparentRelationshipFieldPath__c) || rollup.metadata.RollupToUltimateParent__c) {
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
      this.initializeRollupFieldDefaults(localLookupItems, rollup);
      for (Integer index = localLookupItems.size() - 1; index >= 0; index--) {
        if (rollup.fullRecalcProcessor?.parentRollupFieldHasBeenReset(rollup, localLookupItems[index]) == true) {
          localLookupItems.remove(index);
        }
      }
      return localLookupItems;
    }

    public void execute(System.QueueableContext qc) {
      System.attachFinalizer(new RollupFinalizer());
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
    RollupAsyncProcessor processor = this.getAsyncRollup(rollupInfo, this.calcItemType, calcItems, new Map<Id, SObject>(), null, this.invokePoint);
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
    if (this.isValidAdditionalCalcItemRetrieval(rollup) == false) {
      return;
    }
    // if, at any point, we're requerying for all other possible calc items
    // the rollup _becomes_ a full recalc
    rollup.isFullRecalc = true;

    String key = rollup.calcItemType.getDescribe().getName();
    List<SObject> additionalCalcItems;
    Boolean shouldLimitCalcItemQuery = false;
    if (this.cachedFullRecalcs.containsKey(key)) {
      additionalCalcItems = this.cachedFullRecalcs.get(key);
      for (String lookupKey : lookupToCalcItems.keySet()) {
        CalcItemBag bag = lookupToCalcItems.get(lookupKey);
        bag.hasQueriedForAdditionalItems = true;
      }
    } else {
      Set<String> objIds = new Set<String>();
      for (String lookupKey : lookupToCalcItems.keySet()) {
        CalcItemBag bag = lookupToCalcItems.get(lookupKey);
        if (bag.hasQueriedForAdditionalItems == false) {
          bag.hasQueriedForAdditionalItems = true;
          for (SObject calcItem : bag.getAll()) {
            objIds.add(calcItem.Id);
          }
        }
      }

      if (objIds.isEmpty()) {
        additionalCalcItems = new List<SObject>();
      } else {
        Set<String> lookupKeys = lookupToCalcItems.keySet();
        String whereClause = '' + rollup.lookupFieldOnCalcItem + ' = :lookupKeys';
        Map<Schema.SObjectType, Set<String>> localCalcToUniqueFieldNames = rollup.fullRecalcProcessor != null &&
          rollup.calcObjectToUniqueFieldNames != null
          ? rollup.calcObjectToUniqueFieldNames
          : this.calcObjectToUniqueFieldNames;

        String countQuery = RollupQueryBuilder.Current.getQuery(rollup.calcItemType, new List<String>{ 'Count()' }, 'Id', '!=', whereClause);

        // a dark hack, possibly even evil - but there are tests that rely on only a single record being batched at a time
        // and we can't both consume the one query allowed AND do the countQuery call here. This is because actually deferring rollups
        // isn't allowed in tests - we can't rebatch or requeue
        Integer outstandingItemCount = Test.isRunningTest() ? 0 : Database.countQuery(countQuery);
        Integer remainingQueryRowsLeft = Limits.getLimitQueryRows() - (Limits.getQueryRows() + 1);
        shouldLimitCalcItemQuery = outstandingItemCount >= remainingQueryRowsLeft;

        String query = RollupQueryBuilder.Current.getQuery(
          rollup.calcItemType,
          new List<String>(localCalcToUniqueFieldNames.get(rollup.calcItemType)),
          'Id',
          '!=',
          whereClause
        );
        if (shouldLimitCalcItemQuery) {
          query += '\nLIMIT ' + remainingQueryRowsLeft;
        }
        RollupLogger.Instance.log('gathering additional calc items with query:', query, LoggingLevel.FINE);
        additionalCalcItems = Database.query(query);
      }
      if (shouldLimitCalcItemQuery == false) {
        this.cachedFullRecalcs.put(key, additionalCalcItems);
      }
    }

    for (SObject additionalCalcItem : additionalCalcItems) {
      String lookupKey = (String) additionalCalcItem.get(rollup.lookupFieldOnCalcItem);
      if (lookupToCalcItems.containsKey(lookupKey)) {
        CalcItemBag bag = lookupToCalcItems.get(lookupKey);
        bag.hasQueriedForAdditionalItems = shouldLimitCalcItemQuery == false;
        bag.add(additionalCalcItem);
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

  protected virtual List<RollupAsyncProcessor> transformFullRecalcRollups() {
    return new List<RollupAsyncProcessor>();
  }

  protected virtual override String getHashedContents() {
    // the only thing that necessarily makes a rollup unique is the sum total of the metadata behind it
    // as well as the calc items driving that calculation.
    // you could have multiple rollups with different Calc Item Where Clauses all rolling up to the same field
    return String.valueOf(this.metadata);
  }

  private Boolean isValidAdditionalCalcItemRetrieval(RollupAsyncProcessor roll) {
    if ((roll.isFullRecalc == false && roll.metadata.IsFullRecordSet__c == false) || String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c)) {
      return false;
    } else if (roll.op?.name().contains('DELETE') == true) {
      // full recalc rollups won't have an op, hence the safe navigation above
      return false;
    }
    return roll.isFullRecalc || roll.metadata.IsFullRecordSet__c == true;
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
        this.stackDepth++;
        RollupLogger.Instance.log(
          'processing deferred rollups with stack depth: ' +
          this.stackDepth +
          ', rollup control:',
          this.rollupControl,
          LoggingLevel.DEBUG
        );
        this.setIsDeferralAllowed(this.rollupControl.MaxRollupRetries__c > stackDepth);

        this.rollups.clear();
        this.rollups.addAll(this.deferredRollups);
        this.deferredRollups.clear();

        RollupLogger.Instance.log('deferred rollups remaining:', this.rollups, LoggingLevel.DEBUG);

        this.getAsyncRollup()?.beginAsyncRollup();
      } else if (this.deferredRollups.isEmpty() == false) {
        this.setIsDeferralAllowed(false);
        this.attemptToStaticallyDeferRollup();
      }
    }
  }

  private void attemptToStaticallyDeferRollup() {
    // if there's no possible avenue for starting an async rollup, it's possible that we've already called getAsyncRollup
    // upstream, and we can try to process by piggybacking off of that procedure
    this.getCachedRollups().add(this);
    RollupLogger.Instance.log('attempting to statically defer rollup:', this, LoggingLevel.WARN);
    RollupLogger.Instance.save();
  }

  private void setupCalcItemData(Rollup roll) {
    if (roll.calcItems == null || roll.calcItems.isEmpty()) {
      roll.calcItems = this.calcItems;
      roll.oldCalcItems = this.oldCalcItems;
    }
  }

  private void getFieldNamesForRollups(List<RollupAsyncProcessor> rollups) {
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
      if (this.lookupObjectToUniqueFieldNames.containsKey(roll.lookupObj)) {
        this.lookupObjectToUniqueFieldNames.get(roll.lookupObj).addAll(new List<String>{ rollupField, lookupField });
      } else {
        this.lookupObjectToUniqueFieldNames.put(roll.lookupObj, new Set<String>{ rollupField, lookupfield });
      }

      List<String> whereFields = String.isBlank(roll.metadata.CalcItemWhereClause__c)
        ? new List<String>()
        : RollupEvaluator.getWhereEval(roll.metadata.CalcItemWhereClause__c, roll.calcItemType).getQueryFields();
      whereFields.addAll(new List<String>{ roll.opFieldOnCalcItem.getDescribe().getName(), roll.lookupFieldOnCalcItem.getDescribe().getName() });
      for (RollupOrderBy__mdt orderBy : roll.metadata.RollupOrderBys__r) {
        whereFields.add(orderBy.FieldName__c);
      }
      if (this.calcObjectToUniqueFieldNames.containsKey(roll.calcItemType)) {
        this.calcObjectToUniqueFieldNames.get(roll.calcItemType).addAll(whereFields);
      } else {
        this.calcObjectToUniqueFieldNames.put(roll.calcItemType, new Set<String>(whereFields));
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
    this.transformRollups(potentialRollups);
    for (Integer index = potentialRollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor processor = potentialRollups[index];
      Map<String, SObjectField> fieldMap = processor.lookupObj?.getDescribe().fields.getMap();
      if (fieldMap?.containsKey(processor.opFieldOnLookupObject.getDescribe().getName()) == false) {
        potentialRollups.remove(index);
      }
    }
  }

  private Map<String, CalcItemBag> getCalcItemsByLookupField(RollupAsyncProcessor roll, Set<String> uniqueQueryFieldNames) {
    Map<String, CalcItemBag> lookupFieldToCalcItems = new Map<String, CalcItemBag>();
    if (roll.calcItems == null) {
      return lookupFieldToCalcItems;
    }
    if (String.isNotBlank(roll.metadata.GrandparentRelationshipFieldPath__c) || roll.metadata.RollupToUltimateParent__c) {
      if (roll.traversal == null) {
        roll.traversal = new RollupRelationshipFieldFinder(roll.rollupControl, roll.metadata, uniqueQueryFieldNames, roll.lookupObj, roll.oldCalcItems)
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
      if (String.isBlank(key) && roll.oldCalcItems?.containsKey(calcItem.Id) == true) {
        key = (String) roll.oldCalcItems.get(calcItem.Id).get(roll.lookupFieldOnCalcItem);
      }
      if (lookupFieldToCalcItems.containsKey(key) == false) {
        lookupFieldToCalcItems.put(key, new CalcItemBag(new List<SObject>{ calcItem }));
      } else {
        lookupFieldToCalcItems.get(key).add(calcItem);
      }

      // if the lookup key differs from what it was on the old calc item,
      // include that value as well so that we can fix reparented records' rollup values
      SObject potentialOldCalcItem = roll.oldCalcItems?.get(calcItem.Id);
      if (potentialOldCalcItem != null) {
        String oldKey = (String) potentialOldCalcItem.get(roll.lookupFieldOnCalcItem);
        if (key == oldKey || String.isBlank(key)) {
          continue;
        }

        if (lookupFieldToCalcItems.containsKey(oldKey) == false) {
          lookupFieldToCalcItems.put(oldKey, new CalcItemBag(new List<SObject>{ potentialOldCalcItem }));
        } else {
          lookupFieldToCalcItems.get(oldKey).add(potentialOldCalcItem);
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
    if (lookupItem.getSObjectType() == rollup.lookupObj) {
      if (lookupItem.get(rollup.opFieldOnLookupObject) == null || this.isValidFullRecalcReset(rollup, lookupItem)) {
        lookupItem.put(rollup.opFieldOnLookupObject, RollupFieldInitializer.Current.getDefaultValue(rollup.opFieldOnLookupObject));
      }
    }
  }

  private Boolean isValidFullRecalcReset(RollupAsyncProcessor rollup, SObject lookupItem) {
    Boolean isValid = false;
    if (rollup.isFullRecalc) {
      isValid = rollup.fullRecalcProcessor?.parentRollupFieldHasBeenReset(rollup, lookupItem) != true;
    }
    return isValid;
  }

  private void ingestRollupControlData(List<RollupAsyncProcessor> syncRollups) {
    Boolean isRunningAsnyc = this.getIsRunningAsync();
    for (Integer index = this.rollups.size() - 1; index >= 0; index--) {
      RollupAsyncProcessor rollup = this.rollups[index];
      rollup.isFullRecalc = rollup.isFullRecalc || this.isFullRecalc;

      Boolean shouldRunSyncDeferred = this.getShouldRunSyncDeferred(rollup);
      Boolean couldRunSync =
        rollup.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous ||
        (isRunningAsnyc && hasExceededCurrentRollupLimits(rollup.rollupControl) == false) ||
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
  }

  private Boolean isSingleRecordSyncUpdate(RollupAsyncProcessor roll) {
    return roll.calcItems?.size() == 1 &&
      (this.rollupControl.ShouldRunSingleRecordsSynchronously__c || roll.rollupControl.ShouldRunSingleRecordsSynchronously__c);
  }

  private void overrideParentRollupControlValues(RollupControl__mdt specificControl) {
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

  private List<SObject> getUpdatedLookupItemsByRollup(RollupAsyncProcessor rollup, Map<String, CalcItemBag> calcItemsByLookupField, List<SObject> lookupItems) {
    Map<String, SObject> recordsToUpdate = new Map<String, SObject>();
    Map<String, List<SObject>> oldLookupItems = new Map<String, List<SObject>>();
    Set<Id> unprocessedCalcItems = new Set<Id>();
    RollupSObjectUpdater updater = new RollupSObjectUpdater(rollup.opFieldOnLookupObject);
    if (rollup.fullRecalcProcessor != null) {
      rollup.calcObjectToUniqueFieldNames = this.calcObjectToUniqueFieldNames;
      rollup.fullRecalcProcessor.retrieveAdditionalCalcItems(calcItemsByLookupField, rollup);
    } else {
      this.retrieveAdditionalCalcItems(calcItemsByLookupField, rollup);
    }

    RollupCalculator calc;
    for (Integer index = lookupItems.size() - 1; index >= 0; index--) {
      SObject lookupRecord = lookupItems[index];
      if (lookupRecord.getSObjectType() != rollup.lookupObj) {
        continue;
      }
      String key = (String) lookupRecord.get(rollup.lookupFieldOnLookupObject);
      if (calcItemsByLookupField.containsKey(key)) {
        CalcItemBag bag = calcItemsByLookupField.get(key);
        List<SObject> localCalcItems = bag.getAll();

        if (
          hasExceededCurrentRollupLimits(this.rollupControl) || this.isValidAdditionalCalcItemRetrieval(rollup) && bag.hasQueriedForAdditionalItems == false
        ) {
          unprocessedCalcItems.addAll(new Map<Id, SObject>(localCalcItems).keySet());
          lookupItems.remove(index);
          continue;
        }

        this.winnowCalcItemsAndCheckReparenting(rollup, localCalcItems, oldLookupItems);

        // local calculations and reparenting can step on one another (due to full recalculations happening)
        // this guard clause prevents a full recalculation from taking place unnecessarily if a reparenting operation
        // has already been setup to adjust the lookup item's rollup field
        if (localCalcItems.isEmpty() == false || localCalcItems.isEmpty() && oldLookupItems.isEmpty()) {
          Object priorVal = lookupRecord.get(rollup.opFieldOnLookupObject);
          calc = this.getCalculator(calc, rollup, localCalcItems, lookupRecord, priorVal, key, rollup.lookupFieldOnCalcItem);
          this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, rollup, recordsToUpdate, updater, 'lookup');
        }
      }
    }

    this.removeRolledUpValuesFromReparentedRecords(lookupItems, oldLookupItems, recordsToUpdate, rollup, updater);
    this.deferCalculationsWhenApproachingLimits(rollup, unprocessedCalcItems);

    return recordsToUpdate.values();
  }

  private void deferCalculationsWhenApproachingLimits(RollupAsyncProcessor roll, Set<Id> unprocessedCalcItems) {
    // remove the calc items that were successfully processed -
    // they're the ones that aren't in the unprocessed Set
    List<SObject> mutableItems;
    if (unprocessedCalcItems.isEmpty() == false) {
      mutableItems = roll.calcItems?.clone();
      if (mutableItems != null) {
        for (Integer index = mutableItems.size() - 1; index >= 0; index--) {
          SObject calcItem = mutableItems[index];
          if (unprocessedCalcItems.contains(calcItem.Id) == false) {
            mutableItems.remove(index);
          }
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
        (doesNotMatchCurrentItem && (roll.oldCalcItems.containsKey(calcItem.Id) == false || roll.eval.matches(roll.oldCalcItems.get(calcItem.Id)) == false))
      ) {
        // technically it should only be possible for a calc item that doesn't match
        // to still exist if it is a Full Record Set operation; this gives people the chance
        // to reset rollup values if none of the records passed in match the eval criteria
        localCalcItems.remove(index);
        continue;
      }
      // Check for reparented records
      SObject oldCalcItem = roll.oldCalcItems?.get(calcItem.Id);
      if (oldCalcItem == null) {
        continue;
      }

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

      // once the reparenting logic has been done, if the lookup field isn't set on the current calc item, remove it
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

  private RollupCalculator getCalculator(
    RollupCalculator rollupCalc,
    RollupAsyncProcessor roll,
    List<SObject> calcItems,
    SObject lookupRecord,
    Object priorVal,
    String lookupRecordKey,
    SObjectField lookupKeyField
  ) {
    if (rollupCalc == null) {
      rollupCalc = RollupCalculator.Factory.getCalculator(
        priorVal,
        roll.op,
        roll.opFieldOnCalcItem,
        roll.opFieldOnLookupObject,
        roll.metadata,
        lookupRecordKey,
        lookupKeyField
      );
    } else {
      rollupCalc.setDefaultValues(lookupRecordKey, priorVal);
    }
    rollupCalc.setFullRecalc(roll.isFullRecalc);
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
    if (oldLookupItems.isEmpty()) {
      return;
    }
    RollupCalculator calc;
    Op deleteOp = Rollup.Op.valueOf('DELETE_' + getBaseOperationName(roll.op.name()));
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
        this.conditionallyPerformUpdate(priorVal, calc, lookupRecord, roll, recordsToUpdate, updater, 'reparented');
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
    String logKey
  ) {
    RollupLogger.Instance.log(logKey + ' record prior to rolling up:', lookupRecord, LoggingLevel.DEBUG);
    Object newVal = calc.getReturnValue();
    if (priorVal != newVal || this.isFullRecalc || roll.isFullRecalc) {
      String key = (String) lookupRecord.get(roll.lookupFieldOnLookupObject);
      RollupLogger.Instance.log('updating record ...', LoggingLevel.FINE);
      updater.updateField(lookupRecord, newVal);
      recordsToUpdate.put(key, lookupRecord);
      roll.fullRecalcProcessor?.storeParentResetField(roll, lookupRecord);
    }
    RollupLogger.Instance.log(logKey + ' record after rolling up:', lookupRecord, LoggingLevel.DEBUG);
  }

  private Boolean getIsRunningAsync() {
    return System.isBatch() || System.isQueueable() || System.isScheduled() || shouldFlattenAsyncProcesses == true;
  }
}
