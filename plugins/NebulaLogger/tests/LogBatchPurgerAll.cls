public without sharing class LogBatchPurgerAll implements Database.Batchable<SObject>, Database.Stateful {
  private final List<Schema.SObjectType> typesToProcess = new List<Schema.SObjectType>{ Schema.LogEntry__c.SObjectType, Schema.LogEntry__c.SObjectType };

  public void kickoff() {
    Database.executeBatch(this, 2000);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator('SELECT Id FROM ' + typesToProcess.remove(0));
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    delete scope;
    Database.emptyRecycleBin(scope);
  }

  public void finish(Database.BatchableContext bc) {
    if (this.typesToProcess.isEmpty() == false) {
      this.kickoff();
    }
  }
}
