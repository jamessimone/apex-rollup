public class RollupNebulaLoggerAdapter extends RollupLogger {
  public override void save() {
    Logger.saveLog();
  }

  protected override void innerLog(String logString, Object logObject, LoggingLevel logLevel) {
    logString = logString + '\n' + this.getLogStringFromObject(logObject);
    Logger.newEntry(logLevel, this.getBaseLoggingMessage() + logString);
  }
}
