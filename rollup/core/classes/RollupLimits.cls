public without sharing class RollupLimits {
  @TestVisible
  private static Integer stubbedQueryRows;

  public class Tester {
    private final transient RollupControl__mdt control;
    public Tester(RollupControl__mdt control) {
      this.control = control;
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
        return (Limits.getLimitHeapSize() / 2) < Limits.getHeapSize();
      }
    }
    public Boolean hasExceededDMLRowLimit {
      get {
        return this.control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();
      }
    }
    public Boolean hasExceededCPUTimeLimit {
      get {
        Integer intervalTillTimeout = ((System.isBatch() || System.isQueueable()) && Test.isRunningTest() == false) ? 14000 : 3000;
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
        return queryRowsUsed;
      }
      Integer remainingQueryRows = this.control.MaxQueryRows__c?.intValue() - queryRowsUsed;
      return remainingQueryRows > 0 ? remainingQueryRows : 0;
    }
  }
}
