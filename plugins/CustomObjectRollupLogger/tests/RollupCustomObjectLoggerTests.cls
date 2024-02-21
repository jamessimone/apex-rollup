@IsTest
private class RollupCustomObjectLoggerTests {
  @IsTest
  static void shouldSaveToRollupLog() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    rollupCustomLogger.log('Test log', System.LoggingLevel.DEBUG);
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
    System.assertEquals(System.LoggingLevel.DEBUG.name(), firstEntry.RollupLogEntry__r[0].LoggingLevel__c);
    System.assertEquals('Rollup ' + RollupLogger.CURRENT_VERSION_NUMBER + ': Test log', firstEntry.RollupLogEntry__r[0].Message__c);

    System.assertEquals(System.LoggingLevel.ERROR.name(), firstEntry.RollupLogEntry__r[1].LoggingLevel__c);
    System.assertEquals(true, firstEntry.RollupLogEntry__r[1].Message__c.contains('Second test log with record' + '\n' + JSON.serializePretty(new Account())));
  }

  @IsTest
  static void shouldTruncateTooLongLogMessage() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    // if the message is too long for the platform event to fire - it simply won't fire!
    // this test is to ensure a RollupLogEntry__c is created
    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    Integer maximumLength = RollupLogEvent__e.Message__c.getDescribe().getLength();
    rollupCustomLogger.log('1'.repeat(maximumLength + 1), System.LoggingLevel.ERROR);

    Test.startTest();
    rollupCustomLogger.save();
    Test.stopTest();

    List<RollupLogEntry__c> logEntries = [SELECT Message__c FROM RollupLogEntry__c];
    System.assertEquals(1, logEntries.size(), 'Message should have been created successfully!');
    System.assertEquals(maximumLength, logEntries[0].Message__c.length());
  }

  @IsTest
  static void shouldNotLogBelowSpecifiedLoggingLevel() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    // override whatever's included in the CMDT to ensure we arrive at this value deterministically
    RollupPlugin.parameterMock = new RollupPluginParameter__mdt(Value__c = System.LoggingLevel.DEBUG.name());

    RollupCustomObjectLogger rollupCustomLogger = new RollupCustomObjectLogger();
    rollupCustomLogger.log('Test message', System.LoggingLevel.FINE);

    Test.startTest();
    rollupCustomLogger.save();
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM RollupLog__c], 'Log should not have been created because FINE is below DEBUG in LoggingLevel');
  }

  @IsTest
  static void shouldNotPublishLogsWhenDisabled() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    RollupPlugin.pluginMocks.add(new RollupPlugin__mdt(DeveloperName = RollupCustomObjectLogger.class.getName()));
    // load a valid message into the buffer prior to disabling logging again
    RollupLogger.Instance.log('Test message', System.LoggingLevel.ERROR);
    RollupLogger.Instance.updateRollupControl(new RollupControl__mdt(IsRollupLoggingEnabled__c = false));

    Test.startTest();
    RollupLogger.Instance.save();
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM RollupLog__c]);
  }
}
