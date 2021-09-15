public without sharing class RollupFinalizer implements Finalizer {
  @TestVisible
  private static ParentJobResult testResult;
  private final Rollup rollupConductor;

  public RollupFinalizer(Rollup rollupConductor) {
    this.rollupConductor = rollupConductor;
  }

  public void execute(FinalizerContext fc) {
    ParentJobResult res = this.getParentJobResult(fc);
    switch on res {
      when UNHANDLED_EXCEPTION {
        this.logAndRerun(fc);
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

  private void logAndRerun(FinalizerContext fc) {
    RollupLogger.Instance.log('beginning re-run via finalizer after failure from:', fc?.getException(), LoggingLevel.DEBUG);
    try {
      this.rollupConductor.runCalc();
    } catch(Exception ex) {
      RollupLogger.Instance.log('exception while trying to recover from finalizer:', ex, LoggingLevel.ERROR);
    }
    RollupLogger.Instance.save();
  }
}
