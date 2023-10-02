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

  private class CachedRollup extends Rollup {
    public List<Rollup> getCurrentlyCachedRollups() {
      return this.getCachedRollups();
    }
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
    System.assertNotEquals(true, new CachedRollup().getCurrentlyCachedRollups().isEmpty(), 'Deferred rollup should be kept in buffer');
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
    System.assertEquals(0, new CachedRollup().getCurrentlyCachedRollups().size(), 'Flow rollup buffer should have been flushed!');
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
  static void shouldSkipRunWhenContextPartOfListedExclusions() {
    Account acc = [SELECT Id FROM Account];
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, OnlyRunInFlowContexts__c = 'UPDATE, UPSERT, REFRESH');

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
    System.assertEquals(null, acc.AnnualRevenue);
  }

  @IsTest
  static void syncUpdatesWithReparentingRunProperly() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 5;
    update acc;

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    Opportunity opp = new Opportunity(Amount = acc.AnnualRevenue.intValue(), AccountId = null, Id = RollupTestUtils.createId(Opportunity.SObjectType));
    Opportunity oldOpp = opp.clone(true, true, true);
    oldOpp.AccountId = acc.Id;

    input.recordsToRollup = new List<SObject>{ opp };
    input.oldRecordsToRollup = new List<SObject>{ oldOpp };
    input.rollupContext = 'UPDATE';
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
    // reparenting should purely subtract from account ...
    System.assertEquals(null, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldPassOrderBysThroughSuccessfully() {
    Account acc = [SELECT Id FROM Account];
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{
      new Opportunity(Amount = 7, CloseDate = System.today(), AccountId = acc.Id, Id = RollupTestUtils.createId(Opportunity.SObjectType)),
      new Opportunity(Amount = 3, AccountId = acc.Id, Id = RollupTestUtils.createId(Opportunity.SObjectType)),
      new Opportunity(Amount = 4, CloseDate = System.today().addDays(-1), AccountId = acc.Id, Id = RollupTestUtils.createId(Opportunity.SObjectType))
    };
    input.rollupContext = 'INSERT';
    input.orderByFirstLast = 'CloseDate ascending nulls last';

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'FIRST',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue'
      )
    };

    Test.startTest();
    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    RollupFlowBulkSaver.processDeferredRollups();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(4, acc.AnnualRevenue);
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
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(CalcItem__c = 'Opportunity', LookupFieldOnLookupObject__c = 'Id', LookupObject__c = 'User', RollupOperation__c = 'CONCAT')
    };
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Amount = 5, Id = RollupTestUtils.createId(Opportunity.SObjectType)) };
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
  static void correctlyInvokesGrandparentRollup() {
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupOperation__c = 'CONCAT',
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'User',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        GrandparentRelationshipFieldPath__c = 'Account.Owner.AboutMe'
      )
    };
    Account acc = [SELECT Id, OwnerId FROM Account];
    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ new Opportunity(Name = 'Hi', AccountId = acc.Id, Id = RollupTestUtils.createId(Opportunity.SObjectType)) };
    input.rollupContext = 'INSERT';
    input.deferProcessing = false;

    Test.startTest();
    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    Test.stopTest();

    User updatedUser = [SELECT AboutMe FROM User WHERE Id = :acc.OwnerId];
    Assert.areEqual('Hi', updatedUser.AboutMe);
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
    List<Rollup.FlowOutput> flowOutputs = RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(10, acc.AnnualRevenue, 'Account annual revenue should have summed properly');
    System.assertEquals(2, acc.NumberOfEmployees, 'Account number of employees should have counted properly');
    System.assertEquals(1, flowOutputs.size(), 'Output size should be the same as input size');
  }

  @IsTest
  static void handlesRollupsStartedFromParent() {
    // prior to the introduction of RollupAsyncProcessor.hashedRollups
    // this test was throwing a silent error that has now been fixed
    Rollup.onlyUseMockMetadata = true;
    List<Account> accs = [SELECT Id, AnnualRevenue FROM Account];
    insert new List<SObject>{
      new Opportunity(Amount = 5, AccountId = accs[0].Id, StageName = 'A', CloseDate = System.today(), Name = 'Amount 1'),
      new Opportunity(Amount = 5, AccountId = accs[0].Id, StageName = 'A', CloseDate = System.today(), Name = 'Amount 2')
    };

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = accs;
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
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'Amount > 0' // validate where clause only runs for children
      )
    };

    Exception ex;
    Test.startTest();
    try {
      RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    } catch (Exception e) {
      ex = e;
    }
    Test.stopTest();

    System.assertEquals(null, ex, 'Exception should not be thrown when child object info can be inferred from CMDT');
    Account acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(10, acc.AnnualRevenue, 'Account annual revenue should have summed properly');
  }

  @IsTest
  static void rollupOrderBysAreHandledProperlyForParentRollups() {
    Rollup.onlyUseMockMetadata = true;
    List<Account> accs = [SELECT Id, AnnualRevenue FROM Account];
    insert new List<SObject>{
      new Opportunity(Amount = 5, AccountId = accs[0].Id, StageName = 'A', CloseDate = System.today().addDays(5), Name = 'Amount 1'),
      new Opportunity(Amount = 10, AccountId = accs[0].Id, StageName = 'A', CloseDate = System.today(), Name = 'Amount 2')
    };

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = accs;
    input.rollupContext = 'UPSERT';
    input.oldRecordsToRollup = new List<SObject>{ null, null };
    input.deferProcessing = false;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      Rollup.appendOrderByMetadata(
        new Rollup__mdt(
          RollupOperation__c = 'FIRST',
          CalcItem__c = 'Opportunity',
          LookupObject__c = 'Account',
          RollupFieldOnCalcItem__c = 'Amount',
          LookupFieldOnCalcItem__c = 'AccountId',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          IsRollupStartedFromParent__c = true
        ),
        new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'CloseDate', Ranking__c = 0) }
      )
    };

    Exception ex;
    Test.startTest();
    try {
      RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    } catch (Exception e) {
      ex = e;
    }
    Test.stopTest();

    System.assertEquals(null, ex, 'Exception should not be thrown when child object info can be inferred from CMDT');
    Account acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(10, acc.AnnualRevenue, 'Account annual revenue should have ordered properly');
  }

  @IsTest
  static void supportsOneToManyUpdates() {
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Account',
        LookupObject__c = 'Individual',
        LookupFieldOnCalcItem__c = 'Id',
        RollupOperation__c = 'MIN',
        RollupFieldOnLookupObject__c = 'ConsumerCreditScore',
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupFieldOnLookupObject__c = 'Id',
        GrandparentRelationshipFieldPath__c = 'Contacts.Individual.ConsumerCreditScore',
        OneToManyGrandparentFields__c = 'Contact.AccountId'
      )
    };
    Rollup.onlyUseMockMetadata = true;
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue, Account.MasterRecordId });
    acc.AnnualRevenue = 67;
    update acc;
    Account secondChild = new Account(Name = 'new actual min', AnnualRevenue = 43);
    Individual indy = new Individual(LastName = 'Indy');

    insert new List<SObject>{ secondChild, indy };
    insert new List<Contact>{
      new Contact(LastName = 'One To Many Child', AccountId = acc.Id, IndividualId = indy.Id),
      new Contact(LastName = 'Second one to many', AccountId = secondChild.Id, IndividualId = indy.Id)
    };

    RollupFlowBulkProcessor.FlowInput input = new RollupFlowBulkProcessor.FlowInput();
    input.recordsToRollup = new List<SObject>{ acc };
    input.rollupContext = 'UPSERT';
    input.oldRecordsToRollup = new List<SObject>{ new Account(Id = acc.Id, AnnualRevenue = secondChild.AnnualRevenue - 1) };
    input.deferProcessing = false;

    Test.startTest();
    RollupFlowBulkProcessor.addRollup(new List<RollupFlowBulkProcessor.FlowInput>{ input });
    Test.stopTest();

    Individual updatedIndy = [SELECT Id, ConsumerCreditScore FROM Individual WHERE Id = :indy.Id];
    System.assertEquals(secondChild.AnnualRevenue, updatedIndy.ConsumerCreditScore);
  }
}
