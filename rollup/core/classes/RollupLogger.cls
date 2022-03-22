public without sharing virtual class RollupLogger extends Rollup implements ILogger {
  @TestVisible
  // this gets updated via the pipeline as the version number gets incremented
  private static final String CURRENT_VERSION_NUMBER = 'v1.4.7';
  private static final LoggingLevel FALLBACK_LOGGING_LEVEL = LoggingLevel.DEBUG;
  private static final RollupPlugin PLUGIN = new RollupPlugin();
  private static Boolean disabledMessageHasBeenLogged = false;

  private final LoggingLevel currentLoggingLevel;

  protected RollupLogger() {
    super(InvocationPoint.FROM_STATIC_LOGGER);
    this.currentLoggingLevel = this.getLogLevel();
  }

  private static final RollupLogger SELF {
    get {
      if (SELF == null) {
        SELF = new RollupLogger();
      }
      return SELF;
    }
    set;
  }

  public static final ILogger Instance {
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

  public void log(String logString, Object logObject, LoggingLevel logLevel) {
    if (this.rollupControl?.IsRollupLoggingEnabled__c == true && logLevel.ordinal() >= this.currentLoggingLevel.ordinal()) {
      this.innerLog(logString, logObject, logLevel);
    } else if (this.rollupControl?.IsRollupLoggingEnabled__c == false && disabledMessageHasBeenLogged == false) {
      disabledMessageHasBeenLogged = true;
      this.innerLog('logging isn\'t enabled, no further output', null, LoggingLevel.DEBUG);
    }
  }

  public virtual void save() {
    // this is a no-op by default; sub-classes can opt in if they need to perform DML
  }

  protected String getBaseLoggingMessage() {
    return 'Rollup ' + CURRENT_VERSION_NUMBER + ': ';
  }

  @SuppressWarnings('PMD.AvoidDebugStatements')
  protected virtual void innerLog(String logString, Object logObject, LoggingLevel logLevel) {
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
      (innerStacktraces.get(0).contains('Class.RollupLogger.log') || innerStacktraces.get(0).contains('Class.RollupLogger.CombinedLogger.log')) ||
      innerStacktraces.get(0).contains('Class.RollupLogger.innerLog')
    ) {
      innerStacktraces.remove(0);
    }
    messages.add(String.join(innerStacktraces, '\n'));
    System.debug(logLevel, this.getBaseLoggingMessage() + String.join(messages, '\n') + '\n');
  }

  protected RollupPluginParameter__mdt getLoggingLevelParameter() {
    return PLUGIN.getParameterInstance(this.getLoggingLevelDeveloperName());
  }

  protected virtual String getLoggingLevelDeveloperName() {
    return 'LoggingDebugLevel';
  }

  protected override String getTypeName() {
    return RollupLogger.class.getName();
  }

  protected LoggingLevel getLogLevel() {
    LoggingLevel toReturn = FALLBACK_LOGGING_LEVEL;
    RollupPluginParameter__mdt loggingLevelParamater = this.getLoggingLevelParameter();
    String logLevelNameToSearch = loggingLevelParamater != null ? loggingLevelParamater.Value__c : toReturn.name();
    try {
      toReturn = LoggingLevel.valueOf(logLevelNameToSearch);
    } catch (Exception ex) {
      toReturn = FALLBACK_LOGGING_LEVEL;
    }
    return toReturn;
  }

  protected String getLogStringFromObject(Object logObject) {
    String appended = '';
    if (logObject == null) {
      return appended;
    } else if (logObject instanceof String) {
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
    List<RollupPlugin__mdt> plugins = PLUGIN.getInstances();
    for (Integer index = plugins.size() - 1; index >= 0; index--) {
      RollupPlugin__mdt plugin = plugins[index];
      if ((plugin.RollupControl__c != null && plugin.RollupControl__c != SELF.rollupControl.Id) || plugin.DeveloperName?.contains('Logger') == false) {
        plugins.remove(index);
      }
    }
    SELF.log('retrieved the following logging plugins:', plugins, LoggingLevel.FINE);
    return combineLoggers(plugins);
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
    }
    return loggingPlugins.isEmpty() ? rollLogger : new CombinedLogger(rollLogger, combineLoggers(loggingPlugins));
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
