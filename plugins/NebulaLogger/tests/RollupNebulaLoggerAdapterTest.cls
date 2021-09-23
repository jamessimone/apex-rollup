@IsTest
private class RollupNebulaLoggerAdapterTest {
  @SuppressWarnings('apex-assist')
  @IsTest
  static void shouldLogToNebula() {
    LoggerSettings__c settings = new LoggerSettings__c(IsEnabled__c = true);
    upsert settings;

    RollupNebulaLoggerAdapter adapter = new RollupNebulaLoggerAdapter();
    adapter.log('Test string', new Account(), LoggingLevel.DEBUG);

    Test.startTest();
    adapter.save();
    Test.stopTest();

    // For Nebula Logger, we aren't opinionated (at present) about how the log
    // chooses to represent itself. Nebula Logger handles all of the formatting
    // of log entries and creation of Log__c records. If a log is created, we're golden
    System.assertEquals(1, [SELECT COUNT() FROM Log__c]);
  }
}
