@IsTest
private class RollupFlowBulkProcessorTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    Account acc = new Account(Name = RollupFlowBulkProcessorTests.class.getName());
    insert acc;
  }

  @IsTest
  static void shouldNotProcessIfNoRecords() {
    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ new RollupFlowBulkProcessor.FlowInput() });

    System.assertEquals('No records', outputs[0].message);
  }

  @IsTest
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

  @IsTest
  static void shouldProcessDeferredFlowRollups() {
    Account acc = [SELECT Id FROM Account];

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

  @IsTest
  static void shouldSyncRunFlowWhenToggled() {
    Account acc = [SELECT Id FROM Account];
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5, AccountId = acc.Id) };
    input.rollupContext = 'INSERT';
    input.shouldRunSync = true;
    input.deferProcessing = false;

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

    // since it should run sync, we don't wrap in start/stopTest
    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(5, acc.AnnualRevenue);
  }

  @IsTest
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

  @IsTest
  static void shouldMapBulkFlowInputToRegularOne() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5) };
    input.rollupContext = 'INSERT';
    input.calcItemChangedFields = 'Amount';
    input.calcItemTypeWhenRollupStartedFromParent = 'Opportunity';
    input.calcItemWhereClause = 'Amount = 5';
    input.concatDelimiter = ';';
    input.deferProcessing = true;
    input.fullRecalculationDefaultNumberValue = 0;
    input.grandparentRelationshipFieldPath = 'Account.Owner.Name';
    input.isFullRecordSet = true;
    input.isRollupStartedFromParent = true;
    input.rollupToUltimateParent = true;
    input.ultimateParentLookup = 'AccountId';

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertEquals(1, outputs.size());
    System.assertEquals(true, outputs[0].isSuccess);
  }

  @IsTest
  static void shouldNotThrowValidationErrorForHierarchyRollups() {
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5) };
    input.rollupContext = 'REFRESH';

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'SUM',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        UltimateParentLookup__c = 'ParentId',
        RollupToUltimateParent__c = true
      )
    };

    List<Rollup.FlowOutput> outputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });

    System.assertEquals(1, outputs.size());
    System.assertEquals(true, outputs[0].isSuccess, outputs);
  }

  @IsTest
  static void shouldNotThrowValidationErrorsForUpdatesWithMultipleCmdtRecords() {
    Account acc = [SELECT Id FROM Account];

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{
      new Opportunity(Amount = 5, Id = RollupTestUtils.createId(Opportunity.SObjectType), AccountId = acc.Id),
      new Opportunity(Amount = 5, Id = RollupTestUtils.createId(Opportunity.SObjectType), AccountId = acc.Id)
    };
    input.rollupContext = 'UPSERT';
    input.oldRecordsToRollup = new List<SObject>{ null, null };
    input.deferProcessing = false;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'SUM',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue'
      ),
      new Rollup__mdt(
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees'
      )
    };

    Test.startTest();
    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(10, acc.AnnualRevenue, 'Account annual revenue should have summed properly');
    System.assertEquals(2, acc.NumberOfEmployees, 'Account number of employees should have counted properly');
  }
}
