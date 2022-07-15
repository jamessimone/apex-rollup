@IsTest
private class RollupNebulaLoggerAdapterTest {
  @IsTest
  static void shouldLogToNebula() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    LoggerSettings__c settings = new LoggerSettings__c(IsEnabled__c = true);
    upsert settings;

    String testString = 'Test String';
    RollupNebulaLoggerAdapter adapter = new RollupNebulaLoggerAdapter();
    adapter.log(testString, new Account(), LoggingLevel.DEBUG);

    Test.startTest();
    adapter.save();
    Test.stopTest();

    // For Nebula Logger, we aren't opinionated (at present) about how the log
    // chooses to represent itself. Nebula Logger handles all of the formatting
    // of log entries and creation of Log__c records. If a log is created, we're golden
    List<Log__c> logs = [SELECT Id, (SELECT Message__c FROM LogEntries__r) FROM Log__c];
    System.assertEquals(1, logs.size(), 'Log should have been created');
    System.assertEquals(1, logs[0].LogEntries__r.size(), 'Log entry should have been created');
    System.assertEquals(true, logs[0].LogEntries__r[0].Message__c.contains(testString), 'Log message should contain test string');
  }
}
