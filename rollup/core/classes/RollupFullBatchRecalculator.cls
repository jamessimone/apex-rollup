public without sharing virtual class RollupFullBatchRecalculator extends RollupFullRecalcProcessor {
  private final RollupState state = new RollupState();
  private Database.Cursor cursor;
  private Integer currentPosition = 0;

  public RollupFullBatchRecalculator(
    String queryString,
    InvocationPoint invokePoint,
    List<Rollup__mdt> rollupMetas,
    SObjectType calcItemType,
    Set<String> recordIds,
    RollupFullRecalcProcessor postProcessor
  ) {
    super(RollupQueryBuilder.Current.getAllRowSafeQuery(calcItemType, queryString), invokePoint, rollupMetas, calcItemType, recordIds, postProcessor);
  }

  public override RollupState getState() {
    return this.state;
  }

  public override void finish(Database.BatchableContext bc) {
    // TODO
    // if (this.currentPosition < this.cursor.getNumRecords()) {
    //   this.startAsyncWork();
    // } else {
    //   // super.finish(bc);
    // }
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
    this.cursor = this.cursor ?? this.preStart().getCursor();

    Integer countOfRecordsToReturn = this.rollupControl.BatchChunkSize__c.intValue();
    this.calcItems = this.cursor.fetch(this.currentPosition, countOfRecordsToReturn);
    this.currentPosition += countOfRecordsToReturn;
    return super.startAsyncWork();
  }

  protected override System.Finalizer getFinalizer() {
    return new MyAWESOMEFinalizer(this);
  }

  private class MyAWESOMEFinalizer implements System.Finalizer {
    private final RollupFullBatchRecalculator conductor;
    public MyAWESOMEFinalizer(RollupFullBatchRecalculator conductor) {
      this.conductor = conductor;
    }

    public void execute(System.FinalizerContext fc) {
      switch on fc.getResult() {
        when SUCCESS {
          if (this.conductor.currentPosition < this.conductor.cursor.getNumRecords()) {
            this.conductor.startAsyncWork();
          }
        }
      }
    }
  }
}
