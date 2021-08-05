@isTest
private class RollupLogBatchPurgerTests {
  static RollupLoggerPluginParameter__mdt daysRetained = RollupLoggerPluginParameter__mdt.getInstance('DaysRollupLogsRetained');

  @isTest
  static void shouldDeleteLogEntriesAndLogs() {
    RollupLog__c log = new RollupLog__c(TransactionId__c = 'something');
    insert log;

    RollupLogEntry__c entry = new RollupLogEntry__c(
      LoggingLevel__c = 'DEBUG',
      RollupLog__c = log.Id
    );
    insert entry;
    // UTC time can lead to some weird Datetime issues with adding simply a single day
    // Let's go with 2 to make things completely solid
    Test.setCreatedDate(entry.Id, System.now().addDays(-(Integer.valueOf(daysRetained.Value__c) + 2)));

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
