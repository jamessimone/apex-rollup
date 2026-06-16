@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RollupFlowFullRecalcDispatcher {
  global class FlowInput {
    @InvocableVariable(
      label='Comma-separated list of API Names you want to run'
      description='The API names for the Rollup CMDT records you want to run'
      required=true
    )
    global String rollupDeveloperNames;

    @InvocableVariable(
      label='Optional parent Id'
      description='Supports a comma-separated list of Ids for specific parent records to re-run all calculations for'
    )
    global String optionalParentId;
    @InvocableVariable(
      label='Optional parent Id collection'
      description='Use either this or "Optional Parent Id" to provide specific parents to re-run all calculations for'
    )
    global List<String> optionalParentIds;
  }

  public interface FlowFullRecalcPreprocessor {
    Schema.SObjectField getTarget();
    String getExceptionMessage();
  }

  @InvocableMethod(
    category='Rollups'
    label='Full Recalc Comma-Separated Rollup DeveloperNames'
    description='Perform a full recalculation for all matching rollups using the API names for their Rollup records'
  )
  global static List<Rollup.FlowOutput> performFullRecalcRollups(List<FlowInput> inputs) {
    return new RollupFlowFullRecalcDispatcher().process(inputs, new DeveloperNamePreprocessor());
  }

  public List<Rollup.FlowOutput> process(List<FlowInput> inputs, FlowFullRecalcPreprocessor preprocessor) {
    RollupLogger.Instance.log('Full recalc flow started with inputs', inputs, System.LoggingLevel.INFO);
    Set<String> targetNames = new Set<String>();
    Set<String> optionalParentIds = new Set<String>();
    for (FlowInput input : inputs) {
      if (String.isBlank(input.rollupDeveloperNames)) {
        throw new IllegalArgumentException(preprocessor.getExceptionMessage());
      }
      populateParentIds(optionalParentIds, input.optionalParentId);
      if (input.optionalParentIds != null) {
        optionalParentIds.addAll(input.optionalParentIds);
      }
      List<String> splitListOfApiNames = input.rollupDeveloperNames.stripHtmlTags().split(',');
      for (String apiName : splitListOfApiNames) {
        targetNames.add(apiName.trim());
      }
    }
    optionalParentIds.remove(null);
    optionalParentIds.remove('');

    List<Rollup__mdt> localRollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
    List<Rollup__mdt> selectedRollupMetadata = new List<Rollup__mdt>();
    for (Rollup__mdt rollup : localRollupMetadata) {
      if (targetNames.contains('' + rollup.get(preprocessor.getTarget().toString()))) {
        selectedRollupMetadata.add(rollup);
      }
    }

    List<Rollup.FlowOutput> flowOutputs = new List<Rollup.FlowOutput>();
    Rollup.FlowOutput flowOutput = new Rollup.FlowOutput();
    flowOutput.message = 'No matching metadata, did not start bulk full recalc';
    flowOutputs.add(flowOutput);
    if (selectedRollupMetadata.isEmpty() == false) {
      String enqueuedJobId = Rollup.performBulkFullRecalcWithParentIds(
        JSON.serialize(selectedRollupMetadata),
        Rollup.InvocationPoint.FROM_FULL_RECALC_FLOW.name(),
        new List<String>(optionalParentIds)
      );
      flowOutput.message = 'Job enqueued with Id: ' + enqueuedJobId;
    }
    while (flowOutputs.size() > inputs.size()) {
      flowOutputs.remove(0);
    }
    return flowOutputs;
  }

  private static void populateParentIds(Set<String> potentialParentIds, String possibleParentIds) {
    List<String> splitIds = possibleParentIds?.split(',') ?? new List<String>();
    for (String splitId : splitIds) {
      potentialParentIds.add(splitId.trim());
    }
  }

  private class DeveloperNamePreprocessor implements FlowFullRecalcPreprocessor {
    public Schema.SObjectField getTarget() {
      return Rollup__mdt.DeveloperName;
    }

    public String getExceptionMessage() {
      return 'Comma-separated list of Rollup__mdt DeveloperName(s) was not provided';
    }
  }
}
