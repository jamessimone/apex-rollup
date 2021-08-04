public class RollupCustomObjectLogger extends RollupLogger {
  private final List<RollupLogEvent__e> rollupLogEvents = new List<RollupLogEvent__e>();
  private static final Integer MAX_LENGTH = RollupLogEvent__e.Message__c.getDescribe().getLength();

  public RollupCustomObjectLogger() {
    super();
  }

  public override void log(String logString, LoggingLevel logLevel) {
    if (this.getLogLevel().ordinal() > logLevel.ordinal()) {
      return; // it's a no-op
    }
    else if (logString.length() >= MAX_LENGTH) {
      // normally we could do this with the AllowFieldTruncation property on Database.DMLOptions
      // but even though you can add DMLOptions to platform event objects, they don't seem to do anything -
      // and if any of the field's text lengths is exceeded, the platform event just silently fails to trigger - neat!
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

  public override void log(String logString, Object logObject, LoggingLevel logLevel) {
    String fullLogString = logString + '\n' + this.getLogStringFromObject(logObject);
    this.log(fullLogString, logLevel);
  }

  public override void save() {
    EventBus.publish(this.rollupLogEvents);
    this.rollupLogEvents.clear();
  }

  protected override RollupLoggerPluginParameter__mdt getLoggingLevelParameter() {
    return RollupLoggerPluginParameter__mdt.getInstance('CustomLoggingDebugLevel');
  }
}