global without sharing class RollupFlowFullRecalcDispatcher {
  private RollupFlowFullRecalcDispatcher() {
    // Only used for invocable
  }

  global class FlowInput {
    @InvocableVariable(label='Comma-separated list of API Names of the Rollup__mdt Records you want to run')
    global String rollupDeveloperNames;
  }

  @InvocableMethod(category='Rollups' label='Full Recalc CMDT-driven Invocable')
  public static List<Rollup.FlowOutput> performFullRecalcRollups(List<FlowInput> inputs) {
    Set<String> rollupDeveloperNames = new Set<String>();
    for (FlowInput input : inputs) {
      if (String.isBlank(input.rollupDeveloperNames)) {
        throw new IllegalArgumentException('Comma-separated list of Rollup__mdt DeveloperName(s) was not provided');
      }
      List<String> splitListOfApiNames = input.rollupDeveloperNames.stripHtmlTags().split(',');
      for (String apiName : splitListOfApiNames) {
        rollupDeveloperNames.add(apiName.trim());
      }
    }
    List<Rollup__mdt> localRollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
    List<Rollup__mdt> selectedRollupMetadata = new List<Rollup__mdt>();
    for (Rollup__mdt rollup : localRollupMetadata) {
      if (rollupDeveloperNames.contains(rollup.DeveloperName)) {
        selectedRollupMetadata.add(rollup);
      }
    }
    List<Rollup.FlowOutput> flowOutputs = new List<Rollup.FlowOutput>();
    Rollup.FlowOutput flowOutput = new Rollup.FlowOutput();
    flowOutput.message = 'No matching metadata, did not start bulk full recalc';
    flowOutputs.add(flowOutput);
    if (selectedRollupMetadata.isEmpty() == false) {
      String enqueuedJobId = Rollup.performBulkFullRecalc(selectedRollupMetadata, Rollup.InvocationPoint.FROM_FULL_RECALC_FLOW.name());
      flowOutput.message = 'Job enqueued with Id: ' + enqueuedJobId;
    }
    return flowOutputs;
  }
}
