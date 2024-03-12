public without sharing class RollupLimits {
  @TestVisible
  private static Integer stubbedQueryRows;
  @TestVisible
  private static Integer currentAsyncJobsUsed;
  @TestVisible
  private static Integer stubAsyncTimeoutInterval;

  private static final Integer SYNC_TIMEOUT_INTERVAL_MS = 1500;
  private static final Integer LIMIT_HEAP_SIZE = Limits.getLimitHeapSize();
  private static final Integer LIMIT_QUERY_ROWS = 50000;

  private static final Integer ASYNC_TIMEOUT_INTERVAL_MS {
    get {
      if (ASYNC_TIMEOUT_INTERVAL_MS == null) {
        ASYNC_TIMEOUT_INTERVAL_MS = stubAsyncTimeoutInterval == null ? 13000 : stubAsyncTimeoutInterval;
      }
      return ASYNC_TIMEOUT_INTERVAL_MS;
    }
    set;
  }

  private static final Boolean HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT {
    get {
      Integer asyncJobLimit = 250000;
      // at the moment, packaging orgs run tests synchronously, which produces an error when fetching System.OrgLimits.getMap()
      // this is a workaround until it's safe to access OrgLimits from a synchronously running test
      if (HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT == null) {
        System.OrgLimit asyncOrgLimit = System.OrgLimits.getMap().get('DailyAsyncApexExecutions');
        asyncJobLimit = asyncOrgLimit.getLimit();
        Integer countOfJobsUsed = currentAsyncJobsUsed != null ? currentAsyncJobsUsed : asyncOrgLimit.getValue();
        HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT = countOfJobsUsed - asyncJobLimit > 0;
      }
      return HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT;
    }
    set;
  }

  public class Tester {
    private final transient RollupControl__mdt control;
    private final transient Boolean isRunningAsync;
    private final Boolean hasExceededOverallLimits;

    public final Boolean hasExceededQueryNumberLimit;
    public final Boolean hasExceededQueryRowLimit;
    public final Boolean hasExceededHeapSizeLimit;
    public final Boolean hasExceededDMLRowLimit;
    public final Boolean hasExceededCPUTimeLimit;

    public Tester(RollupControl__mdt control, Boolean isRunningAsync) {
      this.control = control;
      this.isRunningAsync = isRunningAsync;
      this.hasExceededQueryNumberLimit = this.control?.MaxNumberOfQueries__c < Limits.getQueries();
      this.hasExceededQueryRowLimit = this.getRemainingQueryRows() < 0;
      this.hasExceededHeapSizeLimit = (LIMIT_HEAP_SIZE - 2000000) < Limits.getHeapSize();
      this.hasExceededDMLRowLimit = this.control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();

      Integer intervalTillTimeout = this.isRunningAsync ? ASYNC_TIMEOUT_INTERVAL_MS : SYNC_TIMEOUT_INTERVAL_MS;
      this.hasExceededCPUTimeLimit = (Limits.getCpuTime() + intervalTillTimeout) >= Limits.getLimitCpuTime();
      this.hasExceededOverallLimits =
        this.hasExceededQueryNumberLimit ||
        this.hasExceededQueryRowLimit ||
        this.hasExceededHeapSizeLimit ||
        this.hasExceededDMLRowLimit ||
        this.hasExceededCPUTimeLimit;
    }

    public Boolean hasExceededLimits() {
      return this.hasExceededOverallLimits;
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
