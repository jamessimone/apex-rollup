public without sharing class RollupLimits {
  @TestVisible
  private static Integer stubbedQueryRows;
  @TestVisible
  private static Integer currentAsyncJobsUsed;
  @TestVisible
  private static Integer stubAsyncTimeoutInterval;

  private static final Integer SYNC_TIMEOUT_INTERVAL_MS = 1500;
  private static final Integer LIMIT_QUERY_ROWS = 50000;

  private static final Integer ASYNC_TIMEOUT_INTERVAL_MS {
    get {
      ASYNC_TIMEOUT_INTERVAL_MS = ASYNC_TIMEOUT_INTERVAL_MS ?? stubAsyncTimeoutInterval ?? 13000;
      return ASYNC_TIMEOUT_INTERVAL_MS;
    }
    set;
  }

  private static final Boolean HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT {
    get {
      Integer asyncJobLimit = 250000;
      if (HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT == null) {
        System.OrgLimit asyncOrgLimit = System.OrgLimits.getMap().get('DailyAsyncApexExecutions');
        asyncJobLimit = asyncOrgLimit.getLimit();
        Integer countOfJobsUsed = currentAsyncJobsUsed ?? asyncOrgLimit.getValue();
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
    public final Boolean hasExceededDMLRowLimit;
    public final Boolean hasExceededCPUTimeLimit;

    public Tester(RollupControl__mdt control, Boolean isRunningAsync) {
      this.control = control;
      this.isRunningAsync = isRunningAsync;
      this.hasExceededQueryNumberLimit = this.control?.MaxNumberOfQueries__c < Limits.getQueries();
      this.hasExceededQueryRowLimit = this.getRemainingQueryRows() < 0;
      this.hasExceededDMLRowLimit = this.control?.MaxParentRowsUpdatedAtOnce__c < Limits.getDmlRows();

      Integer intervalTillTimeout = this.isRunningAsync ? ASYNC_TIMEOUT_INTERVAL_MS : SYNC_TIMEOUT_INTERVAL_MS;
      this.hasExceededCPUTimeLimit = (Limits.getCpuTime() + intervalTillTimeout) >= Limits.getLimitCpuTime();
      this.hasExceededOverallLimits =
        this.hasExceededQueryNumberLimit ||
        this.hasExceededQueryRowLimit ||
        this.hasExceededDMLRowLimit ||
        this.hasExceededCPUTimeLimit;
    }

    public Boolean hasExceededLimits() {
      return this.hasExceededOverallLimits;
    }

    public Decimal getRemainingQueryRows() {
      Integer queryRowsUsed = stubbedQueryRows ?? Limits.getQueryRows();
      Decimal maxQueryRows = this.control.MaxQueryRows__c != null && this.control.MaxQueryRows__c <= LIMIT_QUERY_ROWS ? this.control.MaxQueryRows__c : LIMIT_QUERY_ROWS;
      return maxQueryRows - queryRowsUsed;
    }

    public Boolean hasExceededOrgAsyncLimit() {
      return HAS_EXCEEDED_ORG_ASYNC_JOB_LIMIT;
    }
  }
}
