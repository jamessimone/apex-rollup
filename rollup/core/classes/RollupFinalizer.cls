public without sharing virtual class RollupFinalizer implements Finalizer {
  @TestVisible
  private static Boolean wasCalled = false;
  @TestVisible
  private static ParentJobResult testResult;

  public virtual void execute(FinalizerContext fc) {
    ParentJobResult res = this.getParentJobResult(fc);
    switch on res {
      when UNHANDLED_EXCEPTION {
        this.logUnhandledException(fc);
      }
    }
  }

  protected void logUnhandledException(FinalizerContext fc) {
    if (wasCalled == false) {
      // a finalizer can be re-queued up to five times, but we view this as a one-time "get out of jail free" logger
      wasCalled = true;
      RollupLogger.Instance.log('finalizer logging failure from:', fc?.getException(), System.LoggingLevel.ERROR);
      RollupLogger.Instance.save();
    }
  }

  private ParentJobResult getParentJobResult(FinalizerContext fc) {
    ParentJobResult res = testResult ?? fc?.getResult();
    testResult = null;
    return res;
  }
}
