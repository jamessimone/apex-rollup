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
      SELECT Id, NumberOfLogEntries__c, TransactionId__c, ErrorWouldHaveBeenThrown__c, (SELECT Message__c, LoggingLevel__c FROM RollupLogEntry__r)
      FROM RollupLog__c
    ];
    System.assertEquals(1, rollupLogs.size(), 'Parent-level rollup log should have been created');
    RollupLog__c firstEntry = rollupLogs[0];
    System.assertNotEquals(null, firstEntry.TransactionId__c, 'Transaction Id should have been assigned');
    System.assertEquals(true, firstEntry.ErrorWouldHaveBeenThrown__c, 'ERROR level log message was created, this field should be flagged');

    // Rollup Log Entries
    System.assertEquals(2, firstEntry.RollupLogEntry__r.size());
    System.assertEquals(LoggingLevel.DEBUG.name(), firstEntry.RollupLogEntry__r[0].LoggingLevel__c);
    System.assertEquals('Test log', firstEntry.RollupLogEntry__r[0].Message__c);

    System.assertEquals(LoggingLevel.ERROR.name(), firstEntry.RollupLogEntry__r[1].LoggingLevel__c);
    System.assertEquals('Second test log with record' + '\n' + JSON.serializePretty(new Account()), firstEntry.RollupLogEntry__r[1].Message__c);
  }

  @isTest
  static void shouldTruncateTooLongLogMessage() {
    // if the message is too long for the platform event to fire - it simply won't fire!
    // this test is to ensure a RollupLogEntry__c is created
    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    Integer maximumLength = RollupLogEvent__e.Message__c.getDescribe().getLength();
    rollupCustomLogger.log('1'.repeat(maximumLength + 1), LoggingLevel.ERROR);

    Test.startTest();
    rollupCustomLogger.save();
    Test.stopTest();

    List<RollupLogEntry__c> logEntries = [SELECT Message__c FROM RollupLogEntry__c];
    System.assertEquals(1, logEntries.size(), 'Message should have been created successfully!');
    System.assertEquals(maximumLength, logEntries[0].Message__c.length());
  }

  @isTest
  static void shouldNotLogBelowSpecifiedLoggingLevel() {
    // override whatever's included in the CMDT to ensure we arrive at this value deterministically
    RollupLogger.loggingLevelMock = new RollupLoggerPluginParameter__mdt(Value__c = LoggingLevel.DEBUG.name());

    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    rollupCustomLogger.log('Test message', LoggingLevel.FINE);

    Test.startTest();
    rollupCustomLogger.save();
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM RollupLog__c], 'Log should not have been created because FINE is below DEBUG in LoggingLevel');
  }
}
