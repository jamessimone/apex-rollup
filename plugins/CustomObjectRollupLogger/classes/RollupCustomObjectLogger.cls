public class RollupCustomObjectLogger extends RollupLogger {
  private final List<RollupLogEvent__e> rollupLogEvents = new List<RollupLogEvent__e>();

  public override void log(String logString, LoggingLevel logLevel) {
    this.rollupLogEvents.add(new RollupLogEvent__e(
      LoggingLevel__c = logLevel.name(),
      LoggedBy__c = UserInfo.getUserId(),
      Message__c = logString,
      TransactionId__c = Request.getCurrent().getRequestId()
    ));
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