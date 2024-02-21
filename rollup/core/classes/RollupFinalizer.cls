public without sharing class RollupFinalizer implements Finalizer {
  @TestVisible
  private static Boolean wasCalled = false;
  @TestVisible
  private static ParentJobResult testResult;

  public void execute(FinalizerContext fc) {
    ParentJobResult res = this.getParentJobResult(fc);
    switch on res {
      when UNHANDLED_EXCEPTION {
        this.logUnhandledException(fc);
      }
    }
  }

  private ParentJobResult getParentJobResult(FinalizerContext fc) {
    ParentJobResult res = fc?.getResult();
    if (testResult != null) {
      res = testResult;
      testResult = null;
    }
    return res;
  }

  private void logUnhandledException(FinalizerContext fc) {
    if (wasCalled == false) {
      // a finalizer can be re-queued up to five times, but we view this as a one-time "get out of jail free" logger
      wasCalled = true;
      RollupLogger.Instance.log('finalizer logging failure from:', fc?.getException(), System.LoggingLevel.ERROR);
      RollupLogger.Instance.save();
    }
  }
}
