global without sharing class RollupLogBatchPurger implements Database.Batchable<SObject>, Database.Stateful {
  private Integer recordCount = 0;

  global static Id schedule(String jobName, String cronSchedule) {
    return System.schedule(jobName, cronSchedule, new PurgerSchedulable(RollupLogControl.BatchSize));
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Date daysBeforeOffset = System.today().addDays(-RollupLogControl.Offset);
    return Database.getQueryLocator([SELECT Id, RollupLog__c FROM RollupLogEntry__c WHERE CreatedDate <= :daysBeforeOffset ORDER BY RollupLog__c]);
  }

  public void execute(Database.BatchableContext bc, List<RollupLogEntry__c> logEntries) {
    // Max batch size is 2000
    // even if EVERY log entry has a separate log parent
    // we should never exceed the max DML row limit of 10k
    this.recordCount += logEntries.size();
    Set<Id> rollupLogIds = new Set<Id>();

    for (RollupLogEntry__c logEntry : logEntries) {
      rollupLogIds.add(logEntry.RollupLog__c);
    }
    delete logEntries;

    List<RollupLog__c> parentLogs = [SELECT Id FROM RollupLog__c WHERE Id = :rollupLogIds];
    // it's possible, even with ordering by RollupLog__c, that some log entries with the same parent log
    // will end up in different batches. Assume that this delete will succeed once all child RollupLogEntry__c
    // have been deleted in successive batches, but that the first (several) of these deletes might fail
    List<Database.DeleteResult> deleteResults = Database.delete(parentLogs, false);
    for (Database.DeleteResult dr : deleteResults) {
      if (dr.isSuccess()) {
        this.recordCount++;
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    RollupLogger.Instance.log('RollupLogBatchPurger finished after having deleted ' + this.recordCount + ' rollup logs', LoggingLevel.DEBUG);
    RollupLogger.Instance.save();
  }

  private without sharing class PurgerSchedulable implements Schedulable {
    private final Integer batchSize;

    public PurgerSchedulable(Integer batchSize) {
      this.batchSize = batchSize;
    }

    public void execute(SchedulableContext sc) {
      Database.executeBatch(new RollupLogBatchPurger(), this.batchSize);
    }
  }
}