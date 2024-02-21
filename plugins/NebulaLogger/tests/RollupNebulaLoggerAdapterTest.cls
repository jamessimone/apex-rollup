@IsTest
private class RollupNebulaLoggerAdapterTest {
  @IsTest
  static void shouldLogToNebula() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    String testString = 'Test String';

    Test.startTest();
    RollupLogger.Instance.log(testString, new Account(), System.LoggingLevel.INFO);
    RollupLogger.Instance.save();
    Test.stopTest();

    // For Nebula Logger, we aren't opinionated (at present) about how the log
    // chooses to represent itself. Nebula Logger handles all of the formatting
    // of log entries and creation of Log__c records. We only check for adapter-specific
    // settings on Log__c and LogEntry__c
    List<Log__c> logs = [SELECT Id, Scenario__c, (SELECT Message__c, OriginLocation__c FROM LogEntries__r) FROM Log__c];
    System.assertEquals(1, logs.size(), 'Log should have been created');
    System.assertEquals('Apex Rollup', Logger.getScenario());
    System.assertEquals(1, logs[0].LogEntries__r.size(), 'Log entry should have been created');
    LogEntry__c logEntry = logs[0].LogEntries__r[0];
    System.assertEquals(true, logEntry.Message__c.contains(testString), 'Log message should contain test string');
    System.assertNotEquals(RollupNebulaLoggerAdapter.class.getName() + '.innerLog', logEntry.OriginLocation__c, logEntry.OriginLocation__c);
    System.assertNotEquals(RollupLogger.class.getName() + '.log', logEntry.OriginLocation__c, logEntry.OriginLocation__c);
    System.assertNotEquals(true, logEntry.OriginLocation__c.contains('CombinedLogger'), logEntry.OriginLocation__c);
  }
}
