public without sharing class RollupLimits {
  @TestVisible
  private static Integer stubbedQueryRows;
  @TestVisible
  private static Integer orgAsyncJobsUsed;

  private static final Integer SYNC_TIMEOUT_INTERVAL_MS = 3000;
  private static final Integer ASYNC_TIMEOUT_INTERVAL_MS = 13000;

  private static final Integer LIMIT_HEAP_SIZE = Limits.getLimitHeapSize();
  private static final Integer LIMIT_QUERY_ROWS = 50000;

  private static final Boolean HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT {
    get {
      Integer countOfJobsUsed = 0;
      Integer asyncJobLimit = 250000;
      // at the moment, packaging orgs run tests synchronously, which produces an error when fetching System.OrgLimits.getMap()
      // this is a workaround until it's safe to access OrgLimits from a synchronously running test
      if (HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT == null && orgAsyncJobsUsed == null) {
        System.OrgLimit asyncLimit = System.OrgLimits.getMap().get('DailyAsyncApexExecutions');
        asyncJobLimit = asyncLimit.getLimit();
        countOfJobsUsed = asyncLimit.getValue();
      } else if (HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT == null) {
        countOfJobsUsed = orgAsyncJobsUsed;
      }
      HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT = countOfJobsUsed - asyncJobLimit > 0;
      return HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT;
    }
    set;
  }

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
        return (LIMIT_HEAP_SIZE - 2000) < Limits.getHeapSize();
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
        return LIMIT_QUERY_ROWS - queryRowsUsed;
      }
      Integer remainingQueryRows = this.control.MaxQueryRows__c?.intValue() - queryRowsUsed;
      return remainingQueryRows > 0 ? remainingQueryRows : 0;
    }

    public Boolean hasExceededOrgAsyncLimit() {
      return HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT;
    }
  }
}
