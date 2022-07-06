global without sharing class RollupFlowFullRecalcDispatcher {
  private RollupFlowFullRecalcDispatcher() {
    // Only used for invocable
  }

  global class FlowInput {
    @InvocableVariable(label='Comma-separated list of API Names of the Rollup__mdt Records you want to run')
    global String rollupDeveloperNames;
  }

  @InvocableMethod(category='Rollups' label='Full Recalc CMDT-driven Invocable' iconName='resource:rollup:icon')
  public static void performFullRecalcRollups(List<FlowInput> inputs) {
    List<Rollup__mdt> localRollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
    Set<String> rollupDeveloperNames = new Set<String>();
    for (FlowInput input : inputs) {
      if (String.isBlank(input.rollupDeveloperNames)) {
        throw new IllegalArgumentException('Comma-separated list of Rollup__mdt DeveloperName(s) was not provided');
      }
      List<String> splitListOfApiNames = input.rollupDeveloperNames.split(',');
      for (String apiName : splitListOfApiNames) {
        rollupDeveloperNames.add(apiName.trim());
      }
    }
    List<Rollup__mdt> selectedRollupMetadata = new List<Rollup__mdt>();
    for (Rollup__mdt rollup : localRollupMetadata) {
      if (rollupDeveloperNames.contains(rollup.DeveloperName)) {
        selectedRollupMetadata.add(rollup);
      }
    }
    if (selectedRollupMetadata.isEmpty() == false) {
      Rollup.performBulkFullRecalc(selectedRollupMetadata, Rollup.InvocationPoint.FROM_FULL_RECALC_FLOW.name());
    }
  }
}
