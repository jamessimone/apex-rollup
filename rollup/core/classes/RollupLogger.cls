public without sharing virtual class RollupLogger extends Rollup implements ILogger {
  @TestVisible
  private static List<RollupPlugin__mdt> pluginMocks;
  @TestVisible
  private static RollupPluginParameter__mdt loggingLevelMock;
  private static final LoggingLevel FALLBACK_LOGGING_LEVEL = LoggingLevel.DEBUG;

  private final LoggingLevel currentLoggingLevel;

  protected RollupLogger() {
    super(InvocationPoint.FROM_STATIC_LOGGER);
    this.currentLoggingLevel = this.getLogLevel();
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

  public interface ILogger {
    void log(String logString, LoggingLevel logLevel);
    void log(String logString, Object logObject, LoggingLevel logLevel);
    void save();
  }

  public virtual void log(String logString, LoggingLevel logLevel) {
    this.log(logString, null, logLevel);
  }

  @SuppressWarnings('PMD.AvoidDebugStatements')
  public virtual void log(String logString, Object logObject, LoggingLevel logLevel) {
    if (this.rollupControl?.IsRollupLoggingEnabled__c == true && logLevel.ordinal() >= this.currentLoggingLevel.ordinal()) {
      String appended = this.getLogStringFromObject(logObject);
      List<String> messages = new List<String>{ logString };
      if (String.isNotBlank(appended)) {
        messages.add(appended);
      }
      // not all Rollup-generated exceptions come with stacktraces - this is a known issue, where using "new DMLException().getStackTraceString()"
      // works to re-create the stacktrace for all of the calling code. we'll prune away any mentions to this class to keep the log size down
      List<String> innerStacktraces = new DMLException().getStackTraceString().split('\n');
      while (
        innerStacktraces.isEmpty() == false &&
        (innerStacktraces.get(0).contains('Class.RollupLogger.log') || innerStacktraces.get(0).contains('Class.RollupLogger.CombinedLogger.log'))
      ) {
        innerStacktraces.remove(0);
      }
      messages.add(String.join(innerStacktraces, '\n'));
      System.debug(logLevel, 'Rollup: ' + String.join(messages, '\n') + '\n');
    }
  }

  public virtual void save() {
    // this is a no-op by default; sub-classes can opt in if they need to perform DML
  }

  private RollupPluginParameter__mdt loggingLevelPluginParameter {
    get {
      if (loggingLevelPluginParameter == null) {
        loggingLevelPluginParameter = loggingLevelMock != null ? loggingLevelMock : this.getLoggingLevelParameter();
      }
      return loggingLevelPluginParameter;
    }
    set;
  }

  protected virtual RollupPluginParameter__mdt getLoggingLevelParameter() {
    return RollupPluginParameter__mdt.getInstance('LoggingDebugLevel');
  }

  protected override String getTypeName() {
    return RollupLogger.class.getName();
  }

  protected LoggingLevel getLogLevel() {
    LoggingLevel toReturn = FALLBACK_LOGGING_LEVEL;
    String logLevelNameToSearch = this.loggingLevelPluginParameter != null ? this.loggingLevelPluginParameter.Value__c : toReturn.name();
    for (LoggingLevel logLevel : System.LoggingLevel.values()) {
      if (logLevel.name().equalsIgnoreCase(logLevelNameToSearch)) {
        toReturn = logLevel;
        break;
      }
    }
    return toReturn;
  }

  protected String getLogStringFromObject(Object logObject) {
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
      appended = logObject.toString();
    } else if (logObject instanceof Exception) {
      Exception ex = (Exception) logObject;
      appended = ex.getMessage() + '\nInner stacktrace: ' + ex.getStackTraceString();
    } else if (logObject != null) {
      // not all objects implement toString, unfortunately,
      // and we don't want this to throw. Blob.toString throws,
      // for example - let's just serializePretty and move on
      appended = JSON.serializePretty(logObject, true);
    }
    return appended;
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private static ILogger getRollupLogger() {
    List<RollupPlugin__mdt> loggingPlugins = [
      SELECT DeveloperName
      FROM RollupPlugin__mdt
      WHERE RollupControl__c = :SELF.rollupControl.Id AND DeveloperName LIKE '%Logger%'
    ];
    SELF.log('retrieved the following logging plugins:', loggingPlugins, LoggingLevel.FINE);
    if (pluginMocks != null) {
      loggingPlugins.addAll(pluginMocks);
    }
    return combineLoggers(loggingPlugins);
  }

  private static ILogger combineLoggers(List<RollupPlugin__mdt> loggingPlugins) {
    ILogger rollLogger;
    if (loggingPlugins.isEmpty()) {
      return SELF;
    }
    RollupPlugin__mdt firstLogger = loggingPlugins.remove(0);
    if (firstLogger.DeveloperName == SELF.getTypeName()) {
      rollLogger = SELF;
    } else {
      try {
        rollLogger = (ILogger) Type.forName(firstLogger.DeveloperName).newInstance();
      } catch (Exception ex) {
        SELF.log(
          'cast to ILogger for:' +
          firstLogger.DeveloperName +
          ' failed with message: ' +
          ex.getMessage() +
          ', falling back to default logger',
          SELF,
          LoggingLevel.WARN
        );
        rollLogger = SELF;
      }
      if (loggingPlugins.isEmpty() == false) {
        rollLogger = new CombinedLogger(rollLogger, combineLoggers(loggingPlugins));
      }
    }

    return rollLogger;
  }

  private class CombinedLogger implements ILogger {
    private final ILogger first;
    private final ILogger second;

    public CombinedLogger(ILogger first, ILogger second) {
      this.first = first;
      this.second = second;
    }

    public void log(String logString, LoggingLevel logLevel) {
      this.first.log(logString, logLevel);
      this.second.log(logString, logLevel);
    }

    public void log(String logString, Object logObject, LoggingLevel logLevel) {
      this.first.log(logString, logObject, logLevel);
      this.second.log(logString, logObject, logLevel);
    }

    public void save() {
      this.first.save();
      this.second.save();
    }
  }
}
