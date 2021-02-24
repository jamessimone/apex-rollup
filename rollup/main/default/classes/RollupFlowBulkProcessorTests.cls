@isTest
private class RollupFlowBulkProcessorTests {
  @isTest
  static void shouldNotProcessIfNoRecords() {
    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ new RollupFlowBulkProcessor.FlowInput() });

    System.assertNotEquals('No records', outputs[0].message);
  }

  @isTest
  static void shouldAddToRollupsIfCMDTPresent() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Contact() };
    input.rollupContext = 'INSERT';

    RollupFlowBulkProcessor.testMetadata = new Rollup__mdt(RollupOperation__c = 'SUM', CalcItem__c = 'Contact', LookupObject__c = 'Account');

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertEquals(true, outputs[0].message.contains('SUM'));
  }
}
