public class RollupLogControl {
  private static final Integer FALLBACK_DATE_OFFSET = 5;
  private static final Integer FALLBACK_BATCH_CHUNK_SIZE = 2000;
  private static final RollupControl__mdt ORG_DEFAULT = RollupControl__mdt.getInstance('Org_Default');
  private static final RollupLoggerPluginParameter__mdt DATE_OFFSET = RollupLoggerPluginParameter__mdt.getInstance('DaysRollupLogsRetained');

  public static Integer Offset {
    get {
      if (Offset == null) {
        Offset = DATE_OFFSET != null &&
          RollupLoggerPlugin__mdt.getInstance('CustomObjectRollupLogger')?.Id == DATE_OFFSET.RollupLoggerPlugin__c
          ? Integer.valueOf(DATE_OFFSET.Value__c)
          : FALLBACK_DATE_OFFSET;
      }
      return Offset;
    }
    private set;
  }

  public static Integer BatchSize {
    get {
      if (BatchSize == null) {
        BatchSize = ORG_DEFAULT != null ? ORG_DEFAULT.BatchChunkSize__c.intValue() : FALLBACK_BATCH_CHUNK_SIZE;
      }
      return BatchSize;
    }
    private set;
  }
}
