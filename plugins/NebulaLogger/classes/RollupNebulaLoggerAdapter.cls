@SuppressWarnings('apex-assist')
public class RollupNebulaLoggerAdapter extends RollupLogger {
  public override void log(String logString, LoggingLevel logLevel) {
    Logger.newEntry(logLevel, logString);
  }

  public override void log(String logString, Object logObject, LoggingLevel logLevel) {
    String formattedLogObject = this.getLogStringFromObject(logObject);
    this.log(logString + '\n' + formattedLogObject, logLevel);
  }

  public override void save() {
    Logger.saveLog();
  }
}
