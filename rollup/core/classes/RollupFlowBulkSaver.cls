global without sharing class RollupFlowBulkSaver {
  private RollupFlowBulkSaver() {
    // only used for static invocable
  }

  @InvocableMethod(category='Rollups' label='Process Deferred Rollups')
  global static void processDeferredRollups() {
    Rollup.processStoredFlowRollups();
  }
}
