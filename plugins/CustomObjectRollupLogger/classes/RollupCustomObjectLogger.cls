public class RollupCustomObjectLogger extends RollupLogger {
  private final List<RollupLogEvent__e> rollupLogEvents = new List<RollupLogEvent__e>();
  private final Database.DMLOptions truncatedAllowedOptions;

  public RollupCustomObjectLogger() {
    super();
    this.truncatedAllowedOptions = new Database.DMLOptions();
    this.truncatedAllowedOptions.AllowFieldTruncation = true;
  }

  public override void log(String logString, LoggingLevel logLevel) {
    RollupLogEvent__e logEvent = new RollupLogEvent__e(
      LoggingLevel__c = logLevel.name(),
      LoggedBy__c = UserInfo.getUserId(),
      Message__c = logString,
      TransactionId__c = Request.getCurrent().getRequestId()
    );
    logEvent.setOptions(this.truncatedAllowedOptions);
    this.rollupLogEvents.add(logEvent);
  }

  public override void log(String logString, Object logObject, LoggingLevel logLevel) {
    String fullLogString = logString + '\n' + this.getLogStringFromObject(logObject);
    this.log(fullLogString, logLevel);
  }

  public override void save() {
    EventBus.publish(this.rollupLogEvents);
    this.rollupLogEvents.clear();
  }
}