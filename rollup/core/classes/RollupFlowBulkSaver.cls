@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RollupFlowBulkSaver {
  @InvocableMethod(
    category='Rollups'
    label='Process Deferred Rollups'
    description='You must include this action when using the "Perform Rollup On Records" action when the Is Deferred flag is set to true, or the "Perform Rollup CMDT-based rollup" action'
  )
  global static void processDeferredRollups() {
    Rollup.processStoredFlowRollups();
  }
}
