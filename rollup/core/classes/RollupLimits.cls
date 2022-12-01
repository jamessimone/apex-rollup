public without sharing class RollupLimits {
  @TestVisible
  private static Integer stubbedQueryRows;

  private static final Integer SYNC_TIMEOUT_INTERVAL_MS = 3000;
  private static final Integer ASYNC_TIMEOUT_INTERVAL_MS = 13000;

  public class Tester {
    private final transient RollupControl__mdt control;
    private final transient Boolean isRunningAsync;
    public Tester(RollupControl__mdt control, Boolean isRunningAsync) {
      this.control = control;
      this.isRunningAsync = isRunningAsync;
    }

    public Boolean hasExceededQueryNumberLimit {
      get {
        return this.control?.MaxNumberOfQueries__c < Limits.getQueries();
      }
    }
    public Boolean hasExceededQueryRowLimit {
      get {
        return this.getRemainingQueryRows() < 0;
      }
    }
    public Boolean hasExceededHeapSizeLimit {
      get {
        return (Limits.getLimitHeapSize() - 2000) < Limits.getHeapSize();
      }
    }
    public Boolean hasExceededDMLRowLimit {
      get {
        return this.control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();
      }
    }
    public Boolean hasExceededCPUTimeLimit {
      get {
        Integer intervalTillTimeout = this.isRunningAsync ? ASYNC_TIMEOUT_INTERVAL_MS : SYNC_TIMEOUT_INTERVAL_MS;
        return (Limits.getCpuTime() + intervalTillTimeout) >= Limits.getLimitCpuTime();
      }
    }

    public transient Boolean hasExceededLimits {
      get {
        return this.hasExceededQueryNumberLimit ||
          this.hasExceededQueryRowLimit ||
          this.hasExceededHeapSizeLimit ||
          this.hasExceededDMLRowLimit ||
          this.hasExceededCPUTimeLimit;
      }
    }

    public Integer getRemainingQueryRows() {
      Integer queryRowsUsed = stubbedQueryRows != null ? stubbedQueryRows : Limits.getQueryRows();
      if (this.control?.MaxQueryRows__c == null) {
        return Limits.getLimitQueryRows() - queryRowsUsed;
      }
      Integer remainingQueryRows = this.control.MaxQueryRows__c?.intValue() - queryRowsUsed;
      return remainingQueryRows > 0 ? remainingQueryRows : 0;
    }
  }
}
