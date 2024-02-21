@IsTest
private class RollupLogBatchPurgerTests {
  static RollupPluginParameter__mdt daysRetained = RollupPluginParameter__mdt.getInstance('DaysRollupLogsRetained');

  @IsTest
  static void shouldDeleteLogEntriesAndLogs() {
    RollupLog__c log = new RollupLog__c(TransactionId__c = 'something');
    RollupLog__c logWithoutChildren = new RollupLog__c(TransactionId__c = 'something-else');
    List<RollupLog__c> logs = new List<RollupLog__c>{ log, logWithoutChildren };
    insert logs;

    RollupLogEntry__c entry = new RollupLogEntry__c(LoggingLevel__c = System.LoggingLevel.DEBUG.name(), RollupLog__c = log.Id);
    insert entry;
    // UTC time can lead to some weird Datetime issues with adding simply a single day
    // Let's go with 2 to make things completely solid
    Test.setCreatedDate(entry.Id, System.now().addDays(-(Integer.valueOf(daysRetained.Value__c) + 2)));

    Test.startTest();
    Database.executeBatch(new RollupLogBatchPurger());
    Test.stopTest();

    List<RollupLogEntry__c> existingEntries = [SELECT Id FROM RollupLogEntry__c WHERE Id = :entry.Id];
    System.assertEquals(0, existingEntries.size(), 'Entry should have been deleted');
    List<RollupLog__c> existingLogs = [SELECT Id, TransactionId__c FROM RollupLog__c WHERE Id = :logs];
    System.assertEquals(0, existingLogs.size(), 'Logs should have been deleted: ' + existingLogs);
  }

  @IsTest
  static void shouldScheduleSuccessfully() {
    Id scheduleId = RollupLogBatchPurger.schedule('Test purge log schedule ' + System.now().getTime(), '0 0 0 * * ?');

    CronTrigger scheduledJob = [SELECT Id FROM CronTrigger WHERE Id = :scheduleId];
    System.assertNotEquals(null, scheduledJob);
  }
}
