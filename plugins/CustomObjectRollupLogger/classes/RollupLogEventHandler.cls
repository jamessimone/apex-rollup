public without sharing class RollupLogEventHandler {
  @SuppressWarnings('PMD.ApexCrudViolation')
  public void handle(List<RollupLogEvent__e> logEvents) {
    Map<String, RollupLog__c> transactionIdToLogs = new Map<String, RollupLog__c>();

    for (RollupLogEvent__e logEvent : logEvents) {
      RollupLog__c rollupLog = new RollupLog__c(
        ErrorWouldHaveBeenThrown__c = logEvent.LoggingLevel__c == System.LoggingLevel.ERROR.name(),
        LoggedBy__c = Id.valueOf(logEvent.LoggedBy__c),
        TransactionId__c = logEvent.TransactionId__c
      );
      transactionIdToLogs.put(logEvent.TransactionId__c, rollupLog);
    }

    upsert transactionIdToLogs.values() RollupLog__c.TransactionId__c;

    List<RollupLogEntry__c> logEntries = new List<RollupLogEntry__c>();
    for (RollupLogEvent__e logEvent : logEvents) {
      RollupLogEntry__c rollupLogEntry = new RollupLogEntry__c(
        LoggingLevel__c = logEvent.LoggingLevel__c,
        Message__c = logEvent.Message__c,
        RollupLog__c = transactionIdToLogs.get(logEvent.TransactionId__c).Id
      );
      logEntries.add(rollupLogEntry);
    }
    insert logEntries;
  }
}
