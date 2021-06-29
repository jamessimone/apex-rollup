public class RollupLogger extends Rollup implements ILogger {
  private RollupLogger() {
    super(InvocationPoint.FROM_STATIC_LOGGER);
  }

  private static RollupLogger SELF {
    get {
      if (SELF == null) {
        SELF = new RollupLogger();
      }
      return SELF;
    }
    set;
  }

  public static ILogger Instance {
    get {
      if (Instance == null) {
        Instance = getRollupLogger();
      }
      return Instance;
    }
    private set;
  }

  public void log(String logString, LoggingLevel logLevel) {
    this.log(logString, null, logLevel);
  }

  public interface ILogger {
    void log(String logString, LoggingLevel logLevel);
    void log(String logString, Object logObject, LoggingLevel logLevel);
    void save();
  }

  public void log(String logString, Object logObject, LoggingLevel logLevel) {
    if (this.rollupControl?.IsRollupLoggingEnabled__c == true) {
      String appended = this.getLogStringFromObject(logObject);
      List<String> messages = new List<String>{ logString };
      if (String.isNotBlank(appended)) {
        messages.add(appended);
      }
      // not all Rollup-generated exceptions come with stacktraces - this is a known issue, where using "new DMLException().getStackTraceString()"
      // works to re-create the stacktrace for all of the calling code
      messages.add(new DMLException().getStackTraceString());
      System.debug(logLevel, 'Rollup: ' + String.join(messages, '\n') + '\n');
    }
  }

  public void save() {
    // this is a no-op by default; sub-classes can opt in if they need to perform DML
  }

  private String getLogStringFromObject(Object logObject) {
    String appended = '';
    if (logObject instanceof String) {
      appended = (String) logObject;
    } else if (logObject instanceof List<Rollup>) {
      List<Rollup> rolls = (List<Rollup>) logObject;
      for (Rollup roll : rolls) {
        appended += this.getLogStringFromObject(roll) + '\n';
      }
      appended = appended.removeEnd('\n');
    } else if (logObject instanceof Rollup) {
      Rollup roll = (Rollup) logObject;
      if (roll.isBatched && roll.rollups.isEmpty() == false) {
        appended = this.getLogStringFromObject(roll.rollups);
      } else {
        appended = roll.toString();
      }
    } else if (logObject instanceof Exception) {
      Exception ex = (Exception) logObject;
      appended = ex.getMessage() + '\nInner stacktrace: ' + ex.getStackTraceString();
    } else if (logObject != null) {
      // not all objects implement toString, unfortunately,
      // and we don't want this to throw. Blob.toString throws,
      // for example - let's just serializePretty and move on
      appended = JSON.serializePretty(logObject);
    }
    return appended;
  }

  private static ILogger getRollupLogger() {
    ILogger loggerInstance;
    if (String.isNotBlank(SELF.rollupControl.RollupLoggerName__c)) {
      try {
        loggerInstance = (ILogger) Type.forName(SELF.rollupControl.RollupLoggerName__c).newInstance();
      } catch (Exception ex) {
        loggerInstance = SELF;
      }
    } else {
      loggerInstance = SELF;
    }
    return loggerInstance;
  }
}
