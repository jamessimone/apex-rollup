public without sharing class RollupFinalizer implements Finalizer {
  @TestVisible
  private static ParentJobResult testResult;
  private final Rollup rollupConductor;

  public RollupFinalizer(Rollup rollupConductor) {
    this.rollupConductor = rollupConductor;
  }

  public void execute(FinalizerContext fc) {
    ParentJobResult res = testResult != null ? testResult : fc.getResult();
    switch on res {
      when UNHANDLED_EXCEPTION {
        this.logAndRerun();
      }
    }
  }

  private void logAndRerun() {
    RollupLogger.Instance.log('beginning re-run via finalizer ...', LoggingLevel.DEBUG);
    try {
      this.rollupConductor.runCalc();
    } catch(Exception ex) {
      RollupLogger.Instance.log('exception while trying to recover from finalizer:', ex, LoggingLevel.ERROR);
    }
    RollupLogger.Instance.save();
  }
}
