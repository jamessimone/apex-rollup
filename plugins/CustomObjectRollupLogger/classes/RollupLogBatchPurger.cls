global without sharing class RollupLogBatchPurger implements Database.Batchable<SObject>, Database.Stateful {
  private Integer recordCount = 0;
  private Boolean hasDeletedOrphanedLogs = false;

  global static Id schedule(String jobName, String cronSchedule) {
    return System.schedule(jobName, cronSchedule, new RollupPurgerSchedulable());
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  public Database.QueryLocator start(Database.BatchableContext bc) {
    Date daysBeforeOffset = System.today().addDays(-RollupLogControl.Offset);
    return Database.getQueryLocator([SELECT Id, RollupLog__c FROM RollupLogEntry__c WHERE CreatedDate <= :daysBeforeOffset ORDER BY RollupLog__c]);
  }

  public void execute(Database.BatchableContext bc, List<RollupLogEntry__c> logEntries) {
    // Max batch size is 2000
    // even if EVERY log entry has a separate log parent
    // we should never exceed the max DML row limit of 10k
    this.recordCount += logEntries.size();
    Set<RollupLog__c> distinctRollupLogs = new Set<RollupLog__c>();

    for (RollupLogEntry__c logEntry : logEntries) {
      distinctRollupLogs.add(new RollupLog__c(Id = logEntry.RollupLog__c));
    }
    delete logEntries;

    // it's possible, even with ordering by RollupLog__c, that some log entries with the same parent log
    // will end up in different batches. Assume that this delete will succeed once all child RollupLogEntry__c
    // have been deleted in successive batches, but that the first (several) of these deletes might fail
    List<Database.DeleteResult> deleteResults = Database.delete(new List<RollupLog__c>(distinctRollupLogs), false);
    for (Database.DeleteResult dr : deleteResults) {
      if (dr.isSuccess()) {
        this.recordCount++;
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    RollupLogger.Instance.log('RollupLogBatchPurger finishing up after having deleted ' + this.recordCount + ' rollup logs', System.LoggingLevel.DEBUG);

    String orphanedLogsQuery = 'SELECT Count() FROM RollupLog__c WHERE NumberOfLogEntries__c = 0 AND IsDeleted = false';
    if (Database.countQuery(orphanedLogsQuery) > 0 && this.hasDeletedOrphanedLogs == false) {
      orphanedLogsQuery = orphanedLogsQuery.replace('Count()', 'Id');
      this.hasDeletedOrphanedLogs = true;
      RollupLogger.Instance.log('Deleting orphaned logs ...', System.LoggingLevel.DEBUG);
      delete Database.query(orphanedLogsQuery);
    }
    RollupLogger.Instance.save();
  }
}
