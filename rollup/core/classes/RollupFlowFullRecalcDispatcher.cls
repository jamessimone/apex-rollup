@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RollupFlowFullRecalcDispatcher {
  global class FlowInput {
    @InvocableVariable(label='Comma-separated list of API Names you want to run' required=true)
    global String rollupDeveloperNames;

    @InvocableVariable(label='Optional parent Id')
    global String optionalParentId;
  }

  public interface FlowFullRecalcPreprocessor {
    Schema.SObjectField getTarget();
    String getExceptionMessage();
  }

  @InvocableMethod(category='Rollups' label='Full Recalc Comma-Separated Rollup DeveloperNames')
  global static List<Rollup.FlowOutput> performFullRecalcRollups(List<FlowInput> inputs) {
    return new RollupFlowFullRecalcDispatcher().process(inputs, new DeveloperNamePreprocessor());
  }

  public List<Rollup.FlowOutput> process(List<FlowInput> inputs, FlowFullRecalcPreprocessor preprocessor) {
    RollupLogger.Instance.log('Full recalc flow started with inputs', inputs, System.LoggingLevel.INFO);
    Set<String> targetNames = new Set<String>();
    Set<String> potentialParentIds = new Set<String>();
    for (FlowInput input : inputs) {
      if (String.isBlank(input.rollupDeveloperNames)) {
        throw new IllegalArgumentException(preprocessor.getExceptionMessage());
      }
      potentialParentIds.add(input.optionalParentId);
      List<String> splitListOfApiNames = input.rollupDeveloperNames.stripHtmlTags().split(',');
      for (String apiName : splitListOfApiNames) {
        targetNames.add(apiName.trim());
      }
    }
    potentialParentIds.remove(null);
    List<String> uniqueParentIds = new List<String>(potentialParentIds);

    List<Rollup__mdt> localRollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
    List<Rollup__mdt> selectedRollupMetadata = new List<Rollup__mdt>();
    for (Rollup__mdt rollup : localRollupMetadata) {
      if (targetNames.contains('' + rollup.get(preprocessor.getTarget().toString()))) {
        selectedRollupMetadata.add(rollup);
        if (uniqueParentIds.isEmpty() == false) {
          rollup.CalcItemWhereClause__c =
            (rollup.CalcItemWhereClause__c ?? '') +
            ' ||| ' +
            rollup.LookupFieldOnCalcItem__c +
            ' = \'' +
            uniqueParentIds.remove(0) +
            '\'';
        }
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
    while (flowOutputs.size() > inputs.size()) {
      flowOutputs.remove(0);
    }
    return flowOutputs;
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
