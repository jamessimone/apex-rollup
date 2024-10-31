public without sharing virtual class RollupFinalizer implements Finalizer {
  @TestVisible
  private static Boolean wasCalled = false;
  @TestVisible
  private static ParentJobResult testResult;
  protected final List<RollupAsyncProcessor> cabooses = new List<RollupAsyncProcessor>();

  public virtual void execute(FinalizerContext fc) {
    RollupLogger.Instance.log('Beginning finalizer with cabooses: ' + this.cabooses.size(), fc, System.LoggingLevel.INFO);
    ParentJobResult res = this.getParentJobResult(fc);
    switch on res {
      when UNHANDLED_EXCEPTION {
        this.logUnhandledException(fc);
      }
      when else {
        this.handleSuccess();
        this.recurseThroughConductors();
      }
    }
    wasCalled = true;
  }

  public void addCaboose(RollupAsyncProcessor caboose) {
    this.cabooses.add(caboose);
  }

  protected virtual void handleSuccess() {
  }

  protected void logUnhandledException(FinalizerContext fc) {
    if (wasCalled == false) {
      // a finalizer can be re-queued up to five times, but we view this as a one-time "get out of jail free" logger
      RollupLogger.Instance.log('finalizer logging failure from:', fc?.getException(), System.LoggingLevel.ERROR);
      RollupLogger.Instance.save();
    }
  }

  private ParentJobResult getParentJobResult(FinalizerContext fc) {
    ParentJobResult res = testResult ?? fc?.getResult();
    testResult = null;
    return res;
  }

  private void recurseThroughConductors() {
    if (this.cabooses.isEmpty() == false) {
      RollupAsyncProcessor conductor = this.cabooses.remove(0);
      RollupLogger.Instance.log('Starting up new conductor', conductor, System.LoggingLevel.INFO);
      String potentialProcessId = conductor.runCalc();
      if (potentialProcessId == conductor.getNoProcessId() && this.cabooses.isEmpty() == false) {
        this.recurseThroughConductors();
      }
    }
  }
}
