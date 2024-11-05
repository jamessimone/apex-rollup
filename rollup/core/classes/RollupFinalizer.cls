public without sharing virtual class RollupFinalizer implements Finalizer {
  @TestVisible
  private static Boolean wasExceptionLogged = false;
  protected final List<RollupAsyncProcessor> cabooses = new List<RollupAsyncProcessor>();

  // Avoids issues with serializing Exceptions in Apex by flattening the finalizer context data structure
  private class FinalizerContextLoggable implements RollupLogger.ToStringObject {
    public final String exceptionMessage;
    public final String exceptionStacktrace;
    public final String exceptionType;
    public final String jobId;
    public final String requestId;
    public final String resultName;

    public FinalizerContextLoggable(System.FinalizerContext fc) {
      this.jobId = fc.getAsyncApexJobId();
      this.requestId = fc.getRequestId();
      this.resultName = fc.getResult().name();
      this.exceptionMessage = fc.getException()?.getMessage();
      this.exceptionStacktrace = fc.getException()?.getStackTraceString();
      this.exceptionType = fc.getException()?.getTypeName();
    }

    public override String toString() {
      return 'FinalizerContext:[ ' + JSON.serializePretty(this, true).removeStart('{').removeEnd('}') + ']';
    }
  }

  public virtual void execute(FinalizerContext fc) {
    RollupLogger.Instance.log('Beginning finalizer with cabooses: ' + this.cabooses.size(), System.LoggingLevel.INFO);
    switch on fc?.getResult() {
      when UNHANDLED_EXCEPTION {
        this.logUnhandledException(fc);
      }
      when else {
        this.handleSuccess();
        this.recurseThroughConductors();
      }
    }
  }

  public void addCaboose(RollupAsyncProcessor caboose) {
    this.cabooses.add(caboose);
  }

  protected virtual void handleSuccess() {
  }

  protected void logUnhandledException(FinalizerContext fc) {
    if (wasExceptionLogged == false) {
      wasExceptionLogged = true;
      // a finalizer can be re-queued up to five times, but we view this as a one-time "get out of jail free" logger
      RollupLogger.Instance.log('Unhandled exception, stopping execution:', new FinalizerContextLoggable(fc), System.LoggingLevel.ERROR);
      RollupLogger.Instance.save();
    }
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
