public class RollupLogControl {
  private static final Integer FALLBACK_DATE_OFFSET = 5;
  private static final Integer FALLBACK_BATCH_CHUNK_SIZE = 2000;
  private static final RollupControl__mdt LOG_CONTROL = RollupControl__mdt.getInstance('CustomObjectRollupLogger');

  public static Integer Offset {
    get {
      if (Offset == null) {
        Offset = LOG_CONTROL != null ? LOG_CONTROL.DaysRollupLogsRetained__c.intValue() : FALLBACK_DATE_OFFSET;
      }
      return Offset;
    }
    private set;
  }

  public static Integer BatchSize {
    get {
      if (BatchSize == null) {
        BatchSize = LOG_CONTROL != null ? LOG_CONTROL.BatchChunkSize__c.intValue() : FALLBACK_BATCH_CHUNK_SIZE;
      }
      return BatchSize;
    }
    private set;
  }
}