public without sharing class RollupFinalizer implements Finalizer {
  private static Boolean isRecursive = false;
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
    if (isRecursive == false) {
      // a finalizer can be re-queued up to five times, but we view this as a one-time "get out of jail free card" -
      // if re-running doesn't work once, it's unlikely to work again
      isRecursive = true;
      RollupLogger.Instance.log('beginning re-run via finalizer after failure from:', fc?.getException(), LoggingLevel.DEBUG);
      try {
        // the finalizer runs in the same transaction as the parent Queueable, so we DON'T want the conductor to think we're already
        // in a safe, async space; we're not - we're in the equivalent of a Batch class's "finish" method. Even though the transaction
        // is the same, here we're allowed to fire off a batch start/queued job (even if we hadn't been able to in the parent queueable)
        this.rollupConductor.resetFlags();
        this.rollupConductor.runCalc();
      } catch (Exception ex) {
        RollupLogger.Instance.log('exception while trying to recover from finalizer:', ex, LoggingLevel.ERROR);
      }
      RollupLogger.Instance.save();
    }
  }
}
