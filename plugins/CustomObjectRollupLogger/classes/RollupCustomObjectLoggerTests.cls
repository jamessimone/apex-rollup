@isTest
private class RollupCustomObjectLoggerTests {
  @isTest
  static void shouldSaveToRollupLog() {
    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    rollupCustomLogger.log('Test log', LoggingLevel.DEBUG);
    rollupCustomLogger.log('Second test log with record', new Account(), LoggingLevel.ERROR);

    Test.startTest();
    rollupCustomLogger.save();
    Test.stopTest();

    List<RollupLog__c> rollupLogs = [
      SELECT Id, NumberOfLogEntries__c, TransactionId__c, (SELECT Message__c, LoggingLevel__c, LogRetentionDate__c FROM RollupLogEntry__r)
      FROM RollupLog__c
    ];
    System.assertEquals(1, rollupLogs.size(), 'Parent-level rollup log should have been created');
    RollupLog__c firstEntry = rollupLogs[0];
    System.assertNotEquals(null, firstEntry.TransactionId__c, 'Transaction Id should have been assigned');

    // Rollup Log Entries
    System.assertEquals(2, firstEntry.RollupLogEntry__r.size());
    System.assertEquals(LoggingLevel.DEBUG.name(), firstEntry.RollupLogEntry__r[0].LoggingLevel__c);
    System.assertEquals('Test log', firstEntry.RollupLogEntry__r[0].Message__c);

    System.assertEquals(LoggingLevel.ERROR.name(), firstEntry.RollupLogEntry__r[1].LoggingLevel__c);
    System.assertEquals('Second test log with record' + '\n' + JSON.serializePretty(new Account()), firstEntry.RollupLogEntry__r[1].Message__c);
    System.assertNotEquals(null, firstEntry.RollupLogEntry__r[1].LogRetentionDate__c, 'Retention date should have been filled out');
  }
}
