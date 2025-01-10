public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor {
  private final RollupState state = new RollupState();
  private CalcItemRetriever retriever;

  private static final Integer DEFAULT_CHUNK_SIZE = 500;

  public class NonResettingBulkFullRecalc extends RollupFullBatchRecalculator {
    public NonResettingBulkFullRecalc(String queryString, InvocationPoint invokePoint, List<Rollup__mdt> rollupMetas, SObjectType calcItemType) {
      super(queryString, invokePoint, rollupMetas, calcItemType, new Set<String>(), null);
    }

    public override Boolean getShouldResetParentRecordsDuringRecalculation() {
      return false;
    }
  }

  public RollupFullBatchRecalculator(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupMetas,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(RollupQueryBuilder.Current.getAllRowSafeQuery(calcItemType, queryString), invokePoint, rollupMetas, calcItemType, recordIds, postProcessor);
    this.rollupControl.BatchChunkSize__c = this.rollupControl.BatchChunkSize__c ?? DEFAULT_CHUNK_SIZE;
  }

  public override RollupState getState() {
    return this.state;
  }

  protected override void performWork() {
    this.process(this.getDelegatedFullRecalcRollups(this.calcItems));
  }

  protected override Boolean isBatch() {
    return true;
  }

  protected override List<RollupAsyncProcessor> transformFullRecalcRollups() {
    if (this.isProcessed == false && this.rollupControl.ShouldRunAs__c == RollupMetaPicklists.ShouldRunAs.Synchronous && System.isBatch() == false) {
      this.startAsyncWork();
    }
    return new List<RollupAsyncProcessor>();
  }

  protected virtual override String getTypeName() {
    return RollupFullBatchRecalculator.class.getName();
  }

  protected virtual override String startAsyncWork() {
    if (this.finalizer != null) {
      while (this.cabooses.isEmpty() == false) {
        this.finalizer.addCaboose(this.cabooses.remove(0));
      }
    }
    if (this.retriever == null) {
      try {
        this.retriever = new CursorBasedRetriever(this.preStart(), this.rollupControl);
      } catch (Exception ex) {
        this.logger.log('cursor use disallowed', ex, System.LoggingLevel.WARN);
        return System.enqueueJob(new FullBatchQueueableFailsafe(this));
      }
    }

    this.calcItems = this.retriever.fetch();
    return super.startAsyncWork();
  }

  private String runBatch() {
    return this.startBatchProcessor();
  }

  protected override RollupFinalizer getFinalizer() {
    return new FullRecalcFinalizer(this);
  }

  private interface CalcItemRetriever {
    List<SObject> fetch();
    Boolean shouldContinue();
  }

  private class CursorBasedRetriever implements CalcItemRetriever {
    private final Database.Cursor cursor;
    private Integer countOfRecordsToReturn;
    private Integer currentPosition = 0;

    public CursorBasedRetriever(RollupRepository repo, RollupControl__mdt control) {
      this.cursor = repo.getCursor();
      this.countOfRecordsToReturn = control.BatchChunkSize__c.intValue();
    }

    public List<SObject> fetch() {
      if (this.countOfRecordsToReturn + this.currentPosition > this.cursor.getNumRecords()) {
        this.countOfRecordsToReturn = this.cursor.getNumRecords() - this.currentPosition;
      }
      List<SObject> fetchedRecords = this.cursor.fetch(this.currentPosition, this.countOfRecordsToReturn);
      this.currentPosition += this.countOfRecordsToReturn;
      return fetchedRecords;
    }

    public Boolean shouldContinue() {
      return this.currentPosition < this.cursor.getNumRecords();
    }
  }

  private class FullBatchQueueableFailsafe implements System.Queueable {
    private final RollupFullBatchRecalculator roll;

    public FullBatchQueueableFailsafe(RollupFullBatchRecalculator roll) {
      this.roll = roll;
    }

    public void execute(QueueableContext qc) {
      this.roll.runBatch();
    }
  }

  private class FullRecalcFinalizer extends RollupFinalizer {
    private final RollupFullBatchRecalculator conductor;
    public FullRecalcFinalizer(RollupFullBatchRecalculator conductor) {
      this.conductor = conductor;
    }

    public override void handleSuccess() {
      if (this.conductor.retriever?.shouldContinue() ?? false) {
        this.conductor.startAsyncWork();
      } else {
        this.conductor.finish();
      }
    }
  }
}
