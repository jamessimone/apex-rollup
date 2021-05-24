@isTest
private class RollupFlowBulkProcessorTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

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

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'CONCAT',
        CalcItem__c = 'Contact',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'FirstName',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name'
      )
    };

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertNotEquals(true, outputs.isEmpty(), 'Should have passed back data from inputs');
    for (Rollup.FlowOutput output : outputs) {
      System.assertEquals(true, outputs[0].isSuccess, 'Should not error when adding deferred flow rollup');
    }
    System.assertNotEquals(true, Rollup.CACHED_ROLLUPS.isEmpty(), 'Deferred rollup should be kept in buffer');
  }

  @isTest
  static void shouldProcessDeferredFlowRollups() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = 'RollupFlowBulkProcessorTests');
    insert acc;
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5, AccountId = acc.Id) };
    input.rollupContext = 'INSERT';

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'SUM',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue'
      )
    };

    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    Test.startTest();
    RollupFlowBulkSaver.processDeferredRollups();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(5, acc.AnnualRevenue);
    System.assertEquals(0, Rollup.CACHED_ROLLUPS.size(), 'Flow rollup buffer should have been flushed!');
  }

  @isTest
  static void shouldNotReportSuccessForInnerFailure() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5) };
    input.rollupContext = 'INSERT';

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'SUM',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Kaffufle', // this obviously doesn't exist
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue'
      )
    };

    Exception ex;
    try {
      RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(true, ex.getMessage().contains('Invalid field Kaffufle for Opportunity'), ex.getMessage() + '\n' + ex.getStackTraceString());
  }
}
