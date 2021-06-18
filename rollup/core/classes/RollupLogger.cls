public class RollupLogger extends Rollup {
  private RollupLogger() {
    super(InvocationPoint.FROM_STATIC_LOGGER);
  }

  public static final RollupLogger Instance = new RollupLogger();

  public void log(String logString) {
    this.log(logString, null);
  }

  public void log(String logString, Object logObject) {
    if (this.rollupControl?.IsRollupLoggingEnabled__c == true) {
      String appended = this.getLogStringFromObject(logObject);
      List<String> messages = new List<String>{ logString };
      if (String.isNotBlank(appended)) {
        messages.add(appended);
      }
      // not all Rollup-generated exceptions come with stacktraces - this is a known issue, where using "new DMLException().getStackTraceString()"
      // works to re-create the stacktrace for all of the calling code
      messages.add(new DMLException().getStackTraceString());
      System.debug('Rollup: ' + String.join(messages, '\n') + '\n');
    }
  }

  private String getLogStringFromObject(Object logObject) {
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
      Rollup roll = (Rollup) logObject;
      if (roll.isBatched && roll.rollups.isEmpty() == false) {
        appended = this.getLogStringFromObject(roll.rollups);
      } else {
        appended = roll.toString();
      }
    } else if (logObject instanceof Exception) {
      Exception ex = (Exception) logObject;
      appended = ex.getMessage() + '\nInner stacktrace: ' + ex.getStackTraceString();
    } else if (logObject != null) {
      // not all objects implement toString, unfortunately,
      // and we don't want this to throw. Blob.toString throws,
      // for example - let's just serializePretty and move on
      appended = JSON.serializePretty(logObject);
    }
    return appended;
  }
}
