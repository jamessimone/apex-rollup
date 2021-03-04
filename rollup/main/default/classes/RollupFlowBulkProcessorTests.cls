@isTest
private class RollupFlowBulkProcessorTests {
  @isTest
  static void shouldNotProcessIfNoRecords() {
    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ new RollupFlowBulkProcessor.FlowInput() });

    System.assertEquals('No records', outputs[0].message);
  }

  @isTest
  static void shouldAddToRollupsIfCMDTPresent() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Contact() };
    input.rollupContext = 'INSERT';

    RollupFlowBulkProcessor.testMetadata = new Rollup__mdt(RollupOperation__c = 'SUM', CalcItem__c = 'Contact', LookupObject__c = 'Account');

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertEquals(true, outputs[0].message.contains('SUM'));
    System.assertEquals(true, outputs[0].isSuccess, 'Should not error when adding deferred flow rollup');
    System.assertEquals(1, Rollup.FLOW_ROLLUPS.size(), 'Deferred rollup should be kept in buffer');
  }

  @isTest
  static void shouldProcessDeferredFlowRollups() {
    Account acc = new Account(Name = 'RollupFlowBulkProcessorTests');
    insert acc;

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5, AccountId = acc.Id) };
    input.rollupContext = 'INSERT';

    RollupFlowBulkProcessor.testMetadata = new Rollup__mdt(
      RollupOperation__c = 'SUM',
      CalcItem__c = 'Opportunity',
      LookupObject__c = 'Account',
      RollupFieldOnCalcItem__c = 'Opportunity.Amount',
      LookupFieldOnCalcItem__c = 'Opportunity.AccountId',
      LookupFieldOnLookupObject__c = 'Account.Id',
      RollupFieldOnLookupObject__c = 'Account.AnnualRevenue'
    );

    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    Test.startTest();
    RollupFlowBulkSaver.processDeferredRollups();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(5, acc.AnnualRevenue);
    System.assertEquals(0, Rollup.FLOW_ROLLUPS.size(), 'Flow rollup buffer should have been flushed!');
  }

  @isTest
  static void shouldNotReportSuccessForInnerFailure() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5) };
    input.rollupContext = 'INSERT';

    RollupFlowBulkProcessor.testMetadata = new Rollup__mdt(
      RollupOperation__c = 'SUM',
      CalcItem__c = 'Opportunity',
      LookupObject__c = 'Account',
      RollupFieldOnCalcItem__c = 'Opportunity.Kaffufle', // this obviously doesn't exist
      LookupFieldOnCalcItem__c = 'Opportunity.AccountId',
      LookupFieldOnLookupObject__c = 'Account.Id',
      RollupFieldOnLookupObject__c = 'Account.AnnualRevenue'
    );

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertEquals(false, outputs[0].isSuccess);
  }
}
