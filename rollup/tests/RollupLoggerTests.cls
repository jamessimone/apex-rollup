@isTest
public class RollupLoggerTests {
  // Type.forName requires public visibility
  @isTest
  static void shouldLogUsingCustomLoggerWhenSupplied() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, RollupLoggerName__c = ExampleLogger.class.getName());

    RollupLogger.Instance.log('hi', LoggingLevel.DEBUG);

    System.assertEquals('hi', locallogString);
    System.assertEquals(LoggingLevel.DEBUG, localLogLevel);
  }

  @isTest
  static void shouldLogCustomObjectWhenSupplied() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, RollupLoggerName__c = ExampleLogger.class.getName());

    Account acc = new Account();

    RollupLogger.Instance.log('hello', acc, LoggingLevel.FINE);

    System.assertEquals('hello', locallogString);
    System.assertEquals(acc, localLogObject);
    System.assertEquals(LoggingLevel.FINE, localLogLevel);
  }

  @isTest
  static void shouldSaveProperly() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, RollupLoggerName__c = ExampleLogger.class.getName());

    RollupLogger.Instance.save();

    System.assertEquals(true, wasSaved);
  }

  @isTest
  static void shouldGracefullRecoverFromErrors() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, RollupLoggerName__c = 'made up');

    RollupLogger.Instance.save();

    System.assert(true, 'Should make it here');
  }

  static Boolean wasSaved = false;
  static Object localLogObject;
  static String locallogString;
  static LoggingLevel localLogLevel;

  public class ExampleLogger implements RollupLogger.ILogger {
    public void log(String logString, LoggingLevel logLevel) {
      locallogString = logString;
      localLogLevel = logLevel;
    }
    public void log(String logString, Object logObject, LoggingLevel logLevel) {
      locallogString = logString;
      localLogObject = logObject;
      localLogLevel = logLevel;
    }
    public void save() {
      wasSaved = true;
    }
  }
}
