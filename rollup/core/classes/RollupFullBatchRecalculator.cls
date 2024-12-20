public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor {
  private final RollupState state = new RollupState();
  private Database.Cursor cursor;
  private Integer currentPosition = 0;

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
    this.cursor = this.cursor ?? this.preStart().getCursor();

    Integer countOfRecordsToReturn = this.rollupControl.BatchChunkSize__c.intValue();
    if (countOfRecordsToReturn + this.currentPosition > this.cursor.getNumRecords()) {
      countOfRecordsToReturn = this.cursor.getNumRecords() - this.currentPosition;
    }
    this.calcItems = this.cursor.fetch(this.currentPosition, countOfRecordsToReturn);
    this.currentPosition += countOfRecordsToReturn;
    return super.startAsyncWork();
  }

  protected override RollupFinalizer getFinalizer() {
    return new FullRecalcFinalizer(this);
  }

  private class FullRecalcFinalizer extends RollupFinalizer {
    private final RollupFullBatchRecalculator conductor;
    public FullRecalcFinalizer(RollupFullBatchRecalculator conductor) {
      this.conductor = conductor;
    }

    public override void handleSuccess() {
      if (this.conductor.currentPosition < this.conductor.cursor.getNumRecords()) {
        this.conductor.startAsyncWork();
      } else {
        this.conductor.finish();
      }
    }
  }
}
