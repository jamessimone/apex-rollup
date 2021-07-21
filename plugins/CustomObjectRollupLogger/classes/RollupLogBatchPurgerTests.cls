@isTest
private class RollupLogBatchPurgerTests {
  static RollupControl__mdt logControl = RollupControl__mdt.getInstance('CustomObjectRollupLogger');

  @isTest
  static void shouldDeleteLogEntriesAndLogs() {
    RollupLog__c log = new RollupLog__c(TransactionId__c = 'something');
    insert log;

    RollupLogEntry__c entry = new RollupLogEntry__c(
      LoggingLevel__c = 'DEBUG',
      RollupLog__c = log.Id,
      LogRetentionDate__c = System.today().addDays(-(logControl.DaysRollupLogsRetained__c.intValue() + 1))
    );
    insert entry;

    Test.startTest();
    Database.executeBatch(new RollupLogBatchPurger());
    Test.stopTest();

    List<RollupLogEntry__c> existingEntries = [SELECT Id FROM RollupLogEntry__c WHERE Id = :entry.Id];
    System.assertEquals(0, existingEntries.size(), 'Entry should have been deleted');
    List<RollupLog__c> existingLogs = [SELECT Id FROM RollupLog__c WHERE Id = :log.Id];
    System.assertEquals(0, existingLogs.size(), 'Log should have been deleted');
  }

  @isTest
  static void shouldScheduleSuccessfully() {
    Id scheduleId = RollupLogBatchPurger.schedule('Test purge log schedule ' + System.now().getTime() , '0 0 0 * * ?');

    CronTrigger scheduledJob = [SELECT Id FROM CronTrigger WHERE Id =: scheduleId];
    System.assertNotEquals(null, scheduledJob);
  }
}
