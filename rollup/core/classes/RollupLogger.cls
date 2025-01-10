global without sharing virtual class RollupLogger implements ILogger {
  @TestVisible
  // this gets updated via the pipeline as the version number gets incremented
  private static final String CURRENT_VERSION_NUMBER = 'v1.7.4';
  private static final System.LoggingLevel FALLBACK_LOGGING_LEVEL = System.LoggingLevel.DEBUG;
  private static final RollupPlugin PLUGIN = new RollupPlugin();

  private final System.LoggingLevel currentLoggingLevel;

  protected RollupLogger() {
    this.currentLoggingLevel = this.getLogLevel();
  }

  public static void setLogger(ILogger logger) {
    Instance = logger;
  }

  public static ILogger Instance {
    get {
      Instance = Instance ?? getRollupLogger();
      return Instance;
    }
    private set;
  }

  global interface ToStringObject {
  }

  global interface ILogger {
    void log(String logString, System.LoggingLevel logLevel);
    void log(String logString, Object logObject, System.LoggingLevel logLevel);
    void save();
    ILogger updateRollupControl(RollupControl__mdt control);
  }

  public void log(String logString, System.LoggingLevel logLevel) {
    this.log(logString, null, logLevel);
  }

  global virtual void log(String logString, Object logObject, System.LoggingLevel logLevel) {
    if (logLevel.ordinal() >= this.currentLoggingLevel.ordinal()) {
      this.innerLog(logString, logObject, logLevel);
    }
  }

  global virtual void save() {
    // this is a no-op by default; sub-classes can opt in if they need to perform DML
  }

  public ILogger updateRollupControl(RollupControl__mdt control) {
    return this;
  }

  protected String getBaseLoggingMessage() {
    return 'Rollup ' + CURRENT_VERSION_NUMBER + ': ';
  }

  @SuppressWarnings('PMD.AvoidDebugStatements')
  protected virtual void innerLog(String logString, Object logObject, System.LoggingLevel logLevel) {
    String appended = this.getLogStringFromObject(logObject);
    List<String> messages = new List<String>{ logString };
    if (String.isNotBlank(appended)) {
      messages.add(appended);
    }
    // not all Rollup-generated exceptions come with stacktraces - this is a known issue, where using "new DMLException().getStackTraceString()"
    // works to re-create the stacktrace for all of the calling code. we'll prune away any mentions to this class to keep the log size down
    List<String> innerStacktraces = new DMLException().getStackTraceString().split('\n');
    while (innerStacktraces.isEmpty() == false && innerStacktraces.get(0).contains(RollupLogger.class.getName())) {
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

  protected System.LoggingLevel getLogLevel() {
    System.LoggingLevel toReturn = FALLBACK_LOGGING_LEVEL;
    RollupPluginParameter__mdt loggingLevelParamater = this.getLoggingLevelParameter();
    String logLevelNameToSearch = loggingLevelParamater != null ? loggingLevelParamater.Value__c : toReturn.name();
    try {
      toReturn = System.LoggingLevel.valueOf(logLevelNameToSearch);
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
    } else if (logObject instanceof ToStringObject || logObject instanceof List<ToStringObject>) {
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
      if (plugin.DeveloperName?.contains('Logger') == false) {
        plugins.remove(index);
      }
    }
    return combineLoggers(plugins);
  }

  private static ILogger combineLoggers(List<RollupPlugin__mdt> loggingPlugins) {
    List<ILogger> loggers = loggingPlugins.isEmpty() ? new List<ILogger>{ new RollupLogger() } : new List<ILogger>();
    Boolean hasUsedBaseLogger = false;
    List<String> potentialErrorMessages = new List<String>();

    for (RollupPlugin__mdt loggerPlugin : loggingPlugins) {
      ILogger rollLogger;
      if (loggerPlugin.DeveloperName == RollupLogger.class.getName() && hasUsedBaseLogger == false) {
        rollLogger = new RollupLogger();
        hasUsedBaseLogger = true;
      } else {
        try {
          rollLogger = (ILogger) Type.forName(loggerPlugin.DeveloperName).newInstance();
        } catch (Exception ex) {
          potentialErrorMessages.add('Cast to ILogger failed for: ' + loggerPlugin.DeveloperName);
          if (hasUsedBaseLogger == false) {
            rollLogger = new RollupLogger();
            hasUsedBaseLogger = true;
          }
        }
      }
      if (rollLogger != null) {
        loggers.add(rollLogger);
      }
    }

    ILogger combinedLogger = new CombinedLogger(loggers, Rollup.getDefaultControl());
    for (String potentialError : potentialErrorMessages) {
      combinedLogger.log(potentialError, System.LoggingLevel.WARN);
    }

    return combinedLogger;
  }

  private class CombinedLogger implements ILogger {
    private final List<ILogger> loggers;

    private RollupControl__mdt control;
    private Boolean hasDisabledMessageBeenLogged = false;

    public CombinedLogger(List<ILogger> loggers, RollupControl__mdt control) {
      this.loggers = loggers;
      this.control = control;
    }

    public void log(String logString, System.LoggingLevel logLevel) {
      this.log(logString, null, logLevel);
    }

    public void log(String logString, Object logObject, System.LoggingLevel logLevel) {
      if (this.control.IsRollupLoggingEnabled__c == false && this.hasDisabledMessageBeenLogged == false) {
        this.hasDisabledMessageBeenLogged = true;
        this.control.IsRollupLoggingEnabled__c = true;
        this.log('logging isn\'t enabled, no further output', System.LoggingLevel.WARN);
        this.control.IsRollupLoggingEnabled__c = false;
      } else if (this.control.IsRollupLoggingEnabled__c) {
        for (ILogger logger : this.loggers) {
          logger.log(logString, logObject, logLevel);
        }
      }
    }

    public void save() {
      if (this.control.IsRollupLoggingEnabled__c != false) {
        for (ILogger logger : this.loggers) {
          logger.save();
        }
      }
    }

    public CombinedLogger updateRollupControl(RollupControl__mdt control) {
      this.control = control;
      this.log('updating control record', control, System.LoggingLevel.INFO);
      return this;
    }
  }
}
