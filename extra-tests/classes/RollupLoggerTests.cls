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
    System.assertEquals('logging isn\'t enabled, further log messages paused unless otherwise re-activated', localLogString);

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
    public void logDiagnostic(String logString, System.LoggingLevel logLevel) {
      locallogString = logString;
      localLogLevel = logLevel;
    }
    public void logDiagnostic(String logString, Object logObject, System.LoggingLevel logLevel) {
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

  @IsTest
  static void diagnosticLevelLogsWhenSetToDiagnostic() {
    Rollup.defaultControl = new RollupControl__mdt(RollupLoggingLevel__c = 'Diagnostic');
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
    locallogString = null;
    String diagnosticMessage = 'diagnostic test message';

    Test.startTest();
    RollupLogger.Instance.logDiagnostic(diagnosticMessage, System.LoggingLevel.INFO);
    Test.stopTest();

    Assert.areEqual(diagnosticMessage, locallogString, 'Diagnostic messages should log when level is Diagnostic');
  }

  @IsTest
  static void debugLevelDoesNotLogWhenSetToDiagnostic() {
    Rollup.defaultControl = new RollupControl__mdt(RollupLoggingLevel__c = 'Diagnostic');
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
    locallogString = null;

    Test.startTest();
    RollupLogger.Instance.log('debug message', System.LoggingLevel.DEBUG);
    Test.stopTest();

    Assert.isNull(locallogString, 'Debug messages should not log when level is Diagnostic');
  }

  @IsTest
  static void bothLevelsLogWhenSetToDebug() {
    Rollup.defaultControl = new RollupControl__mdt(RollupLoggingLevel__c = 'Debug');
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
    locallogString = null;

    Test.startTest();
    RollupLogger.Instance.log('debug message', System.LoggingLevel.DEBUG);
    Assert.areEqual('debug message', locallogString, 'Debug messages should log when level is Debug');

    RollupLogger.Instance.logDiagnostic('diagnostic message', System.LoggingLevel.INFO);
    Test.stopTest();

    Assert.areEqual('diagnostic message', locallogString, 'Diagnostic messages should also log when level is Debug');
  }

  @IsTest
  static void nothingLogsWhenSetToNone() {
    Rollup.defaultControl = new RollupControl__mdt(RollupLoggingLevel__c = 'None');
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
    locallogString = null;

    Test.startTest();
    RollupLogger.Instance.log('debug message', System.LoggingLevel.DEBUG);
    RollupLogger.Instance.logDiagnostic('diagnostic message', System.LoggingLevel.INFO);
    Test.stopTest();

    Assert.areEqual('logging isn\'t enabled, further log messages paused unless otherwise re-activated', locallogString, 'Only disabled message should appear when level is None');
  }

  @IsTest
  static void backwardCompatibilityWithIsRollupLoggingEnabled() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, RollupLoggingLevel__c = null);
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = ExampleLogger.class.getName()) };
    locallogString = null;

    Test.startTest();
    RollupLogger.Instance.log('test message', System.LoggingLevel.DEBUG);
    Test.stopTest();

    Assert.areEqual('test message', locallogString, 'Legacy IsRollupLoggingEnabled__c = true should enable debug-level logging');
  }
}
