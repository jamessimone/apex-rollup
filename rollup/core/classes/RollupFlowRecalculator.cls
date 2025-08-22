@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RollupFlowRecalculator {
  @InvocableMethod(category='Rollups' label='Full Recalc Comma-Separated Parent API Names')
  global static List<Rollup.FlowOutput> performFullRecalcRollups(List<RollupFlowFullRecalcDispatcher.FlowInput> inputs) {
    return new RollupFlowFullRecalcDispatcher().process(inputs, new ParentNamePreprocessor());
  }

  private class ParentNamePreprocessor implements RollupFlowFullRecalcDispatcher.FlowFullRecalcPreprocessor {
    public Schema.SObjectField getTarget() {
      return Schema.Rollup__mdt.LookupObject__c;
    }

    public String getExceptionMessage() {
      return 'Comma-separated list of parent API name(s) was not provided';
    }
  }
}
