public class RollupLogControl {
  private static final Integer FALLBACK_DATE_OFFSET = 5;
  private static final Integer FALLBACK_BATCH_CHUNK_SIZE = 2000;
  private static final RollupControl__mdt ORG_DEFAULT = RollupControl__mdt.getInstance('Org_Default');
  private static final RollupPlugin PLUGIN = new RollupPlugin();
  private static final RollupPluginParameter__mdt DATE_OFFSET = PLUGIN.getParameterInstance('DaysRollupLogsRetained');

  public static Integer Offset {
    get {
      Offset = Offset ??
        (DATE_OFFSET != null &&
          PLUGIN.getInstance('CustomObjectRollupLogger')?.Id == DATE_OFFSET?.RollupPlugin__c
          ? Integer.valueOf(DATE_OFFSET.Value__c)
          : FALLBACK_DATE_OFFSET);
      return Offset;
    }
    private set;
  }

  public static Integer BatchSize {
    get {
      BatchSize = BatchSize ?? ORG_DEFAULT?.BatchChunkSize__c?.intValue() ?? FALLBACK_BATCH_CHUNK_SIZE;
      return BatchSize;
    }
    private set;
  }
}
