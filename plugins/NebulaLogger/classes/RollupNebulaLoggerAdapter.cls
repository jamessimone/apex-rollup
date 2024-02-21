public class RollupNebulaLoggerAdapter extends RollupLogger {
  public RollupNebulaLoggerAdapter() {
    super();
    // prevents duplicating Apex Debug messages
    // between logger instances
    Logger.getUserSettings().IsApexSystemDebugLoggingEnabled__c = false;
    Logger.setScenario('Apex Rollup');
    Logger.ignoreOrigin(RollupNebulaLoggerAdapter.class);
    Logger.ignoreOrigin(RollupLogger.class);
  }

  public override void save() {
    Logger.saveLog();
  }

  protected override void innerLog(String logString, Object logObject, System.LoggingLevel logLevel) {
    logString = logString + '\n' + this.getLogStringFromObject(logObject);
    Logger.newEntry(logLevel, this.getBaseLoggingMessage() + logString);
  }
}
