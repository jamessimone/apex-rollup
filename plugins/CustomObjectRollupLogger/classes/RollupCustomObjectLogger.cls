public class RollupCustomObjectLogger extends RollupLogger {
  private final List<RollupLogEvent__e> rollupLogEvents = new List<RollupLogEvent__e>();
  private static final Integer MAX_LENGTH = RollupLogEvent__e.Message__c.getDescribe().getLength();

  public RollupCustomObjectLogger() {
    super();
  }

  public override void save() {
    EventBus.publish(this.rollupLogEvents);
    this.rollupLogEvents.clear();
  }

  protected override void innerLog(String logString, Object logObject, System.LoggingLevel logLevel) {
    logString = this.getBaseLoggingMessage() + logString + '\n' + this.getLogStringFromObject(logObject);
    if (logString.length() >= MAX_LENGTH) {
      // normally we could do this with the AllowFieldTruncation property on Database.DMLOptions
      // but even though you can add DMLOptions to platform event objects, they don't seem to do anything -
      // and if any of the field's text lengths is exceeded, the platform event silently fails to fire - neat!
      logString = logString.substring(0, MAX_LENGTH - 4) + ' ...';
    }
    RollupLogEvent__e logEvent = new RollupLogEvent__e(
      LoggingLevel__c = logLevel.name(),
      LoggedBy__c = UserInfo.getUserId(),
      Message__c = logString,
      TransactionId__c = Request.getCurrent().getRequestId()
    );
    this.rollupLogEvents.add(logEvent);
  }

  protected override String getLoggingLevelDeveloperName() {
    return 'CustomLoggingDebugLevel';
  }
}
