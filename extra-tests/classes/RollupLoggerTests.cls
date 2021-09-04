@IsTest
public class RollupLoggerTests {
  // Type.forName requires public visibility
  @IsTest
  static void shouldLogUsingCustomLoggerWhenSupplied() {
    setup();

    RollupLogger.Instance.log('hi', LoggingLevel.DEBUG);

    System.assertEquals('hi', locallogString);
    System.assertEquals(LoggingLevel.DEBUG, localLogLevel);
  }

  @IsTest
  static void shouldLogCustomObjectWhenSupplied() {
    setup();

    Account acc = new Account();

    RollupLogger.Instance.log('hello', acc, LoggingLevel.FINE);

    System.assertEquals('hello', locallogString);
    System.assertEquals(acc, localLogObject);
    System.assertEquals(LoggingLevel.FINE, localLogLevel);
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
    RollupLogger.pluginMocks.add(new RollupPlugin__mdt(DeveloperName = 'Nonsense'));

    RollupLogger.Instance.save();

    System.assert(true, 'Should make it here');
  }

  private static void setup() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    RollupLogger.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
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
