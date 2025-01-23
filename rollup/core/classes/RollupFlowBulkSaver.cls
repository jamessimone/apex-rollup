@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RollupFlowBulkSaver {
  @InvocableMethod(category='Rollups' label='Process Deferred Rollups')
  global static void processDeferredRollups() {
    Rollup.processStoredFlowRollups();
  }
}
