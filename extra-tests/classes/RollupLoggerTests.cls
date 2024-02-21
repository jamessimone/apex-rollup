@IsTest
private class RollupLoggerTests {
  static Boolean wasSaved = false;
  static Object localLogObject;
  static String locallogString;
  static LoggingLevel localLogLevel;

  @IsTest
  static void shouldLogUsingCustomLoggerWhenSupplied() {
    setup();

    RollupLogger.Instance.log('hi', System.LoggingLevel.DEBUG);

    System.assertEquals('hi', locallogString);
    System.assertEquals(System.LoggingLevel.DEBUG, localLogLevel);
  }

  @IsTest
  static void shouldLogCustomObjectWhenSupplied() {
    setup();
    Account acc = new Account();

    RollupLogger.Instance.log('hello', acc, System.LoggingLevel.FINE);

    System.assertEquals('hello', locallogString);
    System.assertEquals(acc, localLogObject);
    System.assertEquals(System.LoggingLevel.FINE, localLogLevel);
  }

  @IsTest
  static void shouldSaveProperly() {
    setup();

    RollupLogger.Instance.save();

    System.assertEquals(true, wasSaved);
  }

  @IsTest
  static void shouldGracefullyRecoverFromErrors() {
    setup();
    RollupPlugin.pluginMocks.add(new RollupPlugin__mdt(DeveloperName = 'Nonsense'));

    RollupLogger.Instance.save();

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void skipsSaveWhenDisabled() {
    setup();
    Rollup.defaultControl.IsRollupLoggingEnabled__c = false;

    RollupLogger.Instance.save();

    System.assertEquals(false, wasSaved);
  }

  @IsTest
  static void updatesRollupControlForLoggers() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = false);
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ControlUpdatingLogger.class.getName()) };

    RollupLogger.Instance.log('Should not be logged', System.LoggingLevel.DEBUG);
    System.assertEquals('logging isn\'t enabled, no further output', localLogString);

    RollupLogger.Instance.updateRollupControl(new RollupControl__mdt(IsRollupLoggingEnabled__c = true));
    String expectedLogMessage = 'hi';
    RollupLogger.Instance.log(expectedLogMessage, System.LoggingLevel.INFO);

    System.assertEquals(expectedLogMessage, localLogString);
    System.assertEquals(System.LoggingLevel.INFO, localLogLevel);
  }

  private static void setup() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
  }

  // Type.forName requires public visibility
  public class ExampleLogger implements RollupLogger.ILogger {
    public void log(String logString, System.LoggingLevel logLevel) {
      locallogString = logString;
      localLogLevel = logLevel;
    }
    public void log(String logString, Object logObject, System.LoggingLevel logLevel) {
      locallogString = logString;
      localLogObject = logObject;
      localLogLevel = logLevel;
    }
    public void save() {
      wasSaved = true;
    }
    public ExampleLogger updateRollupControl(RollupControl__mdt control) {
      return this;
    }
  }

  public class ControlUpdatingLogger extends RollupLogger {
    public override void log(String logString, Object logObject, System.LoggingLevel logLevel) {
      locallogString = logString;
      localLogLevel = logLevel;
    }
  }
}
