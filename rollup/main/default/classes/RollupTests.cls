@isTest
private class RollupTests {
  // NB - tests that perform DML should wrap the DML by setting Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
  // and then Rollup.defaultRollupLimit = null after DML has been performed. This is to prevent side-effects caused by having implemented Rollup in your org
  @TestSetup
  static void setup() {
    // in the event that rollups are running in the org, we want to avoid triggering any operations while performing setup DML
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = 'RollupTests');
    insert acc;
    Contract con = new Contract(Name = 'Datetime tests', AccountId = acc.Id);
    Opportunity opp = new Opportunity(StageName = 'testsetup', Name = 'testsetup', CloseDate = System.today(), Amount = 500);
    insert new List<SObject>{ con, opp };
  }

  private class DMLMock extends Rollup.DMLHelper {
    public List<SObject> Records = new List<SObject>();
    public override void doUpdate(List<SObject> recordsToUpdate) {
      this.Records = recordsToUpdate;
    }
  }

  /** Trigger tests */

  @isTest
  static void shouldNotRunForInvalidTriggerContext() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 50) });
    Rollup.triggerContext = TriggerOperation.BEFORE_INSERT;

    Test.startTest();
    Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(true, mock.Records.isEmpty(), 'Records should not have been set or updated, this is a no-op');
  }

  @isTest
  static void shouldSumFromTriggerAfterInsert() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 25), new Opportunity(Amount = 25) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Rollup rollup = Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType);

    System.assertEquals(true, mock.Records.isEmpty());

    Test.startTest();
    rollup.runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(50, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original opportunity amount');
  }

  @isTest
  static void shouldSumFromTriggerAfterUpdate() {
    Opportunity opp = new Opportunity(Id = generateId(Opportunity.SObjectType), Amount = 50);
    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Amount = 25) };

    Test.startTest();
    Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(25, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @isTest
  static void shouldSumFromTriggerBeforeDelete() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100) });
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-100, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE should subtract the current amount from the pre-existing one');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    insert new Opportunity(Name = 'Test Count Distinct Insert', StageName = 'something', CloseDate = System.today(), AccountId = acc.Id);
    Rollup.defaultRollupLimit = null;

    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Name = 'Test Count Distinct Insert Two') });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should simply add unique values');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    insert new Opportunity(Name = 'Test Count Distinct Insert', StageName = 'something', CloseDate = System.today(), AccountId = acc.Id);
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(Name = 'Test Count Distinct Insert', Id = generateId(Opportunity.SObjectType));
    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    // the important part here is that the old value WAS distinct; the new one isn't
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Name = 'something different', Id = opp.Id) };

    Test.startTest();
    Rollup.countDistinctFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should ensure distinct values');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc; // we want to ensure that the AnnualRevenue is reset because there are no other matching values
    Rollup.defaultRollupLimit = null;

    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity() });
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.countDistinctFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT BEFORE_DELETE should simply decrement');
  }

  @isTest
  static void shouldCountFromTriggerAfterInsert() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated');
  }

  @isTest
  static void shouldDecrementCountFromTriggerAfterUpdateIfValueIsRemoved() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(Id = generateId(Opportunity.SObjectType));
    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, Amount = 1) };

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE should decrement when field is removed');
  }

  @isTest
  static void shouldKeepCountUnchangedFromTriggerAfterUpdateEvenIfValueChanges() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(Id = generateId(Opportunity.SObjectType), Amount = 50);
    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, Amount = 1) };

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated COUNT AFTER_UPDATE');
  }

  @isTest
  static void shouldNotCountNullValues() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity() });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated when empty COUNT AFTER_INSERT');
  }

  @isTest
  static void shouldRunSumFromTriggerBasedOnMetadata() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'SUM'
      )
    };
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original opportunity amount based on CMDT');
  }

  @isTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadata() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'SUM',
        FullRecalculationDefaultNumberValue__c = 100000
      )
    };

    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original opportunity amount to the default override based on CMDT');
  }

  @isTest
  static void shouldOverrideStringBasedDefaultBasedOnMetadata() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Name = 'A') });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupType__c = 'MAX',
        FullRecalculationDefaultStringValue__c = 'Z'
      )
    };

    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on override metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.Name, 'MAX AFTER_INSERT should add the default override based on CMDT if there is no greater value');
  }

  @isTest
  static void shouldRunMultipleOperationsWhenMoreMetadataIsPresent() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'COUNT'
      ),
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupType__c = 'COUNT_DISTINCT'
      )
    };
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should count when the field is present on the calc item based on CMDT');
    System.assertEquals(1, updatedAcc.NumberOfEmployees, 'COUNT_DISTINCT AFTER_INSERT should count regardless of not pointing to a field based on CMDT');
  }

  @isTest
  static void shouldBatchTwoOperations() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.batch(
      Rollup.countDistinctFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.NumberOfEmployees, Account.SObjectType),
      Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
    );
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated batch AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should count when the field is present on the calc item batched');
    System.assertEquals(
      1,
      updatedAcc.NumberOfEmployees,
      'COUNT_DISTINCT AFTER_INSERT should count regardless of not pointing to a field based on the batch operation'
    );
  }

  @isTest
  static void shouldBatchThreeOperations() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 100, Name = 'My test name') });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.batch(
      Rollup.countDistinctFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.NumberOfEmployees, Account.SObjectType),
      Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType),
      Rollup.concatFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType)
    );
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated batch AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should count when the field is present on the calc item batched');
    System.assertEquals(
      1,
      updatedAcc.NumberOfEmployees,
      'COUNT_DISTINCT AFTER_INSERT should count regardless of not pointing to a field based on the batch operation'
    );
    System.assertEquals('My test name', updatedAcc.AccountNumber, 'CONCAT AFTER_INSERT should append to the target field');
  }

  @isTest
  static void shouldThrowExceptionWhenBatchedOperationWithMultipleSObjectTypes() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 50, Name = 'Test') });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRunAsBatch = true;

    Exception ex;
    try {
      Rollup.batch(
        Rollup.sumFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType),
        Rollup.concatFromTrigger(Opportunity.Name, Opportunity.CreatedById, User.Id, User.Username, User.SObjectType)
      );
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterInsert() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(200, updatedAcc.AnnualRevenue, 'MAX AFTER_INSERT should take the maximum opportunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterUpdate() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opps[0].Id => new Opportunity(Id = opps[0].Id), opps[1].Id => new Opportunity(Id = opps[1].Id) };

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(200, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum opportunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMax() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    Opportunity opp = new Opportunity(Amount = acc.AnnualRevenue, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = 150;
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(new List<Opportunity>{ opp });
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(secondOpp.Amount, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum opportunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMax() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    Opportunity opp = new Opportunity(Amount = acc.AnnualRevenue, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = 150;
    Opportunity updatedSecondOpp = secondOpp.clone(true, true);
    updatedSecondOpp.Amount = secondOpp.Amount + 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp, updatedSecondOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(originalOpps);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondOpp.Amount, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum opportunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMaxAndNoOtherSObjectsExist() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(
      Amount = acc.AnnualRevenue,
      AccountId = acc.Id,
      Name = 'testOpp',
      StageName = 'something',
      CloseDate = System.today(),
      Id = generateId(Opportunity.SObjectType)
    );
    Opportunity secondOpp = new Opportunity(
      Amount = 175,
      AccountId = acc.Id,
      Name = 'testOppTwo',
      StageName = 'something',
      CloseDate = System.today(),
      Id = generateId(Opportunity.SObjectType)
    );
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = 150;
    Opportunity updatedSecondOpp = secondOpp.clone(true, true);
    updatedSecondOpp.Amount = secondOpp.Amount + 30; // the amount is really unimportant; that it doesn't match what's in memory is
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp, updatedSecondOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(originalOpps);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondOpp.Amount, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum opportunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    Opportunity opp = new Opportunity(Amount = 250, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Rollup.oldRecordsMap = new Map<Id, Opportunity>(originalOpps);
    DMLMock mock = getMock(originalOpps);
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'MAX BEFORE_DELETE should take the maximum opportunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterInsert() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'MIN AFTER_INSERT should take the minimum opportunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterUpdate() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opps[0].Id => new Opportunity(Id = opps[0].Id), opps[1].Id => new Opportunity(Id = opps[1].Id) };

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum opportunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMin() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    Opportunity opp = new Opportunity(Amount = 150, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = 200;
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(new List<Opportunity>{ opp });
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum opportunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMin() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    Opportunity opp = new Opportunity(Amount = acc.AnnualRevenue, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = secondOpp.Amount + 50; // the amount isn't important - that it's now more than the second Opp amount is
    Opportunity updatedSecondOpp = secondOpp.clone(true, true);
    updatedSecondOpp.Amount = secondOpp.Amount - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp, updatedSecondOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(originalOpps);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondOpp.Amount, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min opportunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMinAndNoOtherSObjectsExist() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(
      Amount = acc.AnnualRevenue,
      AccountId = acc.Id,
      Name = 'testOpp',
      StageName = 'something',
      CloseDate = System.today(),
      Id = generateId(Opportunity.SObjectType)
    );
    Opportunity secondOpp = new Opportunity(
      Amount = 175,
      AccountId = acc.Id,
      Name = 'testOppTwo',
      StageName = 'something',
      CloseDate = System.today(),
      Id = generateId(Opportunity.SObjectType)
    );
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };

    Opportunity updatedOpp = opp.clone(true, true);
    updatedOpp.Amount = secondOpp.Amount + 50; // the amount isn't important - that it's now more than the second Opp amount is
    Opportunity updatedSecondOpp = secondOpp.clone(true, true);
    updatedSecondOpp.Amount = secondOpp.Amount - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<Opportunity> opps = new List<Opportunity>{ updatedOpp, updatedSecondOpp };
    Rollup.records = opps;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(originalOpps);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondOpp.Amount, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min opportunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    Opportunity opp = new Opportunity(Amount = 150, AccountId = acc.Id, Name = 'testOpp', StageName = 'something', CloseDate = System.today());
    Opportunity secondOpp = new Opportunity(Amount = 175, AccountId = acc.Id, Name = 'testOppTwo', StageName = 'something', CloseDate = System.today());
    List<Opportunity> originalOpps = new List<Opportunity>{ opp, secondOpp };
    insert originalOpps;
    Rollup.defaultRollupLimit = null;

    Rollup.records = new List<Opportunity>{ opp };
    Rollup.oldRecordsMap = new Map<Id, SObject>(Rollup.records);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN BEFORE_DELETE should take the minimum opportunity amount');
  }

  @isTest
  static void shouldConcatOnUpdate() {
    // AFTER_INSERT test is handled in the "shouldBatchThreeOperations" method
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'second test string', Id = generateId(Opportunity.SObjectType));
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Name = acc.AccountNumber;

    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldOpp.Id => oldOpp };
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(opp.Name, updatedAcc.AccountNumber, 'CONCAT AFTER_UPDATE should replace the old string value with the new');
  }

  @isTest
  static void shouldConcatOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning test string something';
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'test string');
    DMLMock mock = getMock(new List<Opportunity>{ opp });
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.concatFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('beginning something', updatedAcc.AccountNumber, 'CONCAT BEFORE_DELETE should replace the outgoing string value with empty string');
  }

  @isTest
  static void shouldConcatDistinctOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning test string something';
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'test string');
    Opportunity secondOpp = new Opportunity(AccountId = acc.Id, Name = 'hello another string');
    Opportunity thirdOpp = opp.clone(true, true);
    DMLMock mock = getMock(new List<Opportunity>{ opp, secondOpp, thirdOpp });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      'beginning test string something, hello another string',
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_INSERT should only add unique values'
    );
  }

  @isTest
  static void shouldConcatDistinctOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;
    Rollup.defaultRollupLimit = null;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'second test string', Id = generateId(Opportunity.SObjectType));
    Opportunity secondOpp = new Opportunity(AccountId = acc.Id, Name = 'third test string', Id = generateId(Opportunity.SObjectType));
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Name = acc.AccountNumber;
    Opportunity secondOldOpp = secondOpp.clone(true, true);
    secondOldOpp.Name = acc.AccountNumber;

    DMLMock mock = getMock(new List<Opportunity>{ opp, secondOpp });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOldOpp.Id => secondOldOpp };
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatDistinctFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      'second test string, third test string',
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should be the distinct combo of the old and new strings'
    );
  }

  @isTest
  static void shouldMaxOnStringsOnInsert() {
    List<Opportunity> testOpps = new List<Opportunity>{ new Opportunity(Name = 'A'), new Opportunity(Name = 'Z') };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.AccountNumber, 'MAX AFTER_INSERT should take the maximum string');
  }

  @isTest
  static void shouldMinOnStringsOnInsert() {
    List<Opportunity> testOpps = new List<Opportunity>{ new Opportunity(Name = 'A'), new Opportunity(Name = 'Z') };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MIN AFTER_INSERT should take the minimum string');
  }

  @isTest
  static void shouldMinOnStringsOnUpdate() {
    List<Opportunity> testOpps = new List<Opportunity>{
      new Opportunity(Name = 'B', Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Name = 'A', Id = generateId(Opportunity.SObjectType))
    };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{
      testOpps[0].Id => new Opportunity(Id = testOpps[0].Id, Name = ''),
      testOpps[1].Id => new Opportunity(Id = testOpps[1].Id, Name = 'X')
    };

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MIN AFTER_UPDATE should take the minimum string');
  }

  @isTest
  static void shouldMaxOnStringsOnUpdate() {
    List<Opportunity> testOpps = new List<Opportunity>{
      new Opportunity(Name = '', Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Name = 'A', Id = generateId(Opportunity.SObjectType))
    };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(testOpps);

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MAX AFTER_UPDATE should take the maximum string');
  }

  @isTest
  static void shouldMinOnStringsBeforeDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;
    Rollup.defaultRollupLimit = null;

    List<Opportunity> testOpps = new List<Opportunity>{ new Opportunity(Name = 'A', Id = generateId(Opportunity.SObjectType)) };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ testOpps[0].Id => new Opportunity(Id = testOpps[0].Id, Name = 'A') };

    Test.startTest();
    Rollup.minFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('', updatedAcc.AccountNumber, 'MIN BEFORE_DELETE should take the minimum string');
  }

  @isTest
  static void shouldMaxOnStringsBeforeDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;

    Opportunity opp = new Opportunity(StageName = 'test max on delete', CloseDate = System.today(), Name = 'Z', AccountId = acc.Id);
    insert opp;
    Rollup.defaultRollupLimit = null;

    List<Opportunity> testOpps = new List<Opportunity>{ new Opportunity(Name = 'A', Id = generateId(Opportunity.SObjectType)) };

    DMLMock mock = getMock(testOpps);
    Rollup.TriggerContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>(testOpps);

    Test.startTest();
    Rollup.maxFromTrigger(Opportunity.Name, Opportunity.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(opp.Name, updatedAcc.AccountNumber, 'MAX BEFORE_DELETE should take the maximum string');
  }

  @isTest
  static void shouldMaxOnPicklistStringsOnInsert() {
    List<PicklistEntry> picklistVals = Lead.LeadSource.getDescribe().getPicklistValues();

    if (picklistVals.size() < 2) {
      return; // sorry
    }

    Account acc = [SELECT Id FROM Account];

    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Max Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Max Picklist on insert two')
    };
    insert leads; // not the best, either, but we need to be able to use SOQL below
    Rollup.defaultRollupLimit = null;

    DMLMock mock = loadMock(leads);
    Rollup.TriggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(Lead.LeadSource, Lead.Company, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    AggregateResult res = [SELECT Max(LeadSource) maxSource FROM Lead WHERE Id = :new Map<Id, Lead>(leads).keySet()][0];
    String maxLeadSource = (String) res.get('maxSource');

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_INSERT PICKLIST STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(maxLeadSource, updatedAcc.AccountNumber, 'MAX BEFORE_INSERT should take the maximum picklist string');
  }

  @isTest
  static void shouldMinPicklistStringsOnInsert() {
    List<PicklistEntry> picklistVals = Lead.LeadSource.getDescribe().getPicklistValues();

    if (picklistVals.size() < 2) {
      return; // sorry
    }

    Account acc = [SELECT Id FROM Account];

    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Min Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Min Picklist on insert two')
    };
    insert leads;
    Rollup.defaultRollupLimit = null;

    DMLMock mock = loadMock(leads);
    Rollup.TriggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Lead.LeadSource, Lead.Company, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    AggregateResult res = [SELECT MIN(LeadSource) maxSource FROM Lead WHERE Id = :new Map<Id, Lead>(leads).keySet()][0];
    String minLeadSource = (String) res.get('maxSource');

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_INSERT PICKLIST STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(minLeadSource, updatedAcc.AccountNumber, 'MIN BEFORE_INSERT should take the minimum picklist string');
  }

  @isTest
  static void shouldAverageOnInsert() {
    // average is a special case; even on insert, we have to also check for pre-existing records existing
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    Opportunity testOpp = new Opportunity(
      Amount = acc.AnnualRevenue,
      Name = 'Pre-existing',
      StageName = 'random',
      CloseDate = System.today(),
      AccountId = acc.Id
    );
    insert testOpp;
    Rollup.defaultRollupLimit = null;

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 200000, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200000, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.averageFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      (testOpp.Amount + opps[0].Amount + opps[1].Amount) / 3,
      updatedAcc.AnnualRevenue,
      'AVERAGE AFTER_INSERT should take into account all values'
    );
  }

  @isTest
  static void shouldAverageOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    Opportunity testOpp = new Opportunity(
      Amount = acc.AnnualRevenue,
      Name = 'Pre-existing',
      StageName = 'random',
      CloseDate = System.today(),
      AccountId = acc.Id
    );
    insert testOpp;
    Rollup.defaultRollupLimit = null;

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 200000, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 200000, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{
      opps[0].Id => new Opportunity(Amount = 100000, Id = opps[0].Id),
      opps[1].Id => new Opportunity(Amount = 100000, Id = opps[1].Id)
    };

    Test.startTest();
    Rollup.averageFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      (testOpp.Amount + opps[0].Amount + opps[1].Amount) / 3,
      updatedAcc.AnnualRevenue,
      'AVERAGE AFTER_UPDATE should take into account all values, including those from memory'
    );
  }

  @isTest
  static void shouldAverageOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 200;
    update acc;

    Opportunity testOppOne = new Opportunity(Amount = 100, Name = 'Pre-existing one', StageName = 'random', CloseDate = System.today(), AccountId = acc.Id);
    Opportunity testOppTwo = new Opportunity(Amount = 300, Name = 'Pre-existing one', StageName = 'random', CloseDate = System.today(), AccountId = acc.Id);
    insert new List<Opportunity>{ testOppOne, testOppTwo };
    Rollup.defaultRollupLimit = null;

    List<Opportunity> opps = new List<Opportunity>{ testOppTwo };

    DMLMock mock = getMock(opps);
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ testOppOne.Id => testOppOne };

    Test.startTest();
    Rollup.averageFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(testOppOne.Amount, updatedAcc.AnnualRevenue, 'AVERAGE BEFORE_DELETE should take into account only non-deleted values');
  }

  // Now we test different field types for success: time, datetime, date. Here be dragons.
  @isTest
  static void shouldMaxDateOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Opportunity opp = new Opportunity(StageName = 'something', CloseDate = System.today(), Name = 'Max date on insert test');
    insert opp;
    Rollup.defaultRollupLimit = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = opp.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = opp.Id);

    DMLMock mock = getTaskMock(new List<Task>{ taskOne, taskTwo }, opp.Id);
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(Task.ActivityDate, Task.WhatId, Opportunity.Id, Opportunity.CloseDate, Opportunity.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATE AFTER_INSERT');
    Opportunity updatedOpp = (Opportunity) mock.Records[0];
    System.assertEquals(taskTwo.ActivityDate, updatedOpp.CloseDate);
  }

  @isTest
  static void shouldMinDateOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Opportunity opp = new Opportunity(StageName = 'something', CloseDate = System.today(), Name = 'Min date on insert test');
    insert opp;
    Rollup.defaultRollupLimit = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    DMLMock mock = getTaskMock(new List<Task>{ taskOne, taskTwo }, opp.Id);
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Task.ActivityDate, Task.WhatId, Opportunity.Id, Opportunity.CloseDate, Opportunity.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Opportunity updatedOpp = (Opportunity) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedOpp.CloseDate);
  }

  @isTest
  static void shouldMinDateOnInsertWhereParentDateIsNull() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    //using campaign for this test because EndDate is not required when inserting a Campaign
    Campaign camp = new Campaign(Name = 'Test Date with no initialized value');
    insert camp;
    Rollup.defaultRollupLimit = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = camp.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = camp.Id);

    DMLMock mock = loadMock(new List<Task>{ taskOne, taskTwo });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Task.ActivityDate, Task.WhatId, Campaign.Id, Campaign.EndDate, Campaign.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Campaign updatedCamp = (Campaign) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCamp.EndDate);
  }

  @isTest
  static void shouldMinDateOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Opportunity opp = new Opportunity(StageName = 'something', CloseDate = System.today(), Name = 'Min date on insert test');
    insert opp;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = opp.Id);
    insert taskOne;
    Rollup.defaultRollupLimit = null;

    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = opp.CloseDate.addDays(5), Id = generateId(Task.SObjectType), WhatId = opp.Id);

    DMLMock mock = getTaskMock(new List<Task>{ taskTwo }, opp.Id);
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Task>(new List<Task>{ new Task(Id = taskTwo.Id, ActivityDate = opp.CloseDate) });

    Test.startTest();
    Rollup.minFromTrigger(Task.ActivityDate, Task.WhatId, Opportunity.Id, Opportunity.CloseDate, Opportunity.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Opportunity updatedOpp = (Opportunity) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedOpp.CloseDate);
  }

  @isTest
  static void shouldMaxDatetimeOnInsert() {
    Contract con = [SELECT Id FROM Contract];

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50), WhatId = con.Id);
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50), WhatId = con.Id);

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_INSERT');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMinDatetimeOnInsert() {
    Contract con = [SELECT Id FROM Contract];

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50), WhatId = con.Id);
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50), WhatId = con.Id);

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_INSERT');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventOne.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMinDatetimeOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;
    Rollup.defaultRollupLimit = null;

    // now the "new" version of eventOne is no longer the min
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = generateId(Event.SObjectType));

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing min
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.minFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_UPDATE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMaxDatetimeOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;
    Rollup.defaultRollupLimit = null;

    // now the "new" version of eventOne is no longer the max
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = generateId(Event.SObjectType));

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing max
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.maxFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_UPDATE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMaxDatetimeOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;
    Rollup.defaultRollupLimit = null;

    DMLMock mock = loadMock(new List<Event>{ eventOne });
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.maxFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME BEFORE_DELETE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMinDatetimeOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;
    Rollup.defaultRollupLimit = null;

    DMLMock mock = loadMock(new List<Event>{ eventOne });
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.minFromTrigger(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME BEFORE_DELETE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  /**
   * Time tests. Pretty slim pickings for standard objects with Time fields, but hopefully this helps
   * to highlight that you don't need your unique value to be in a lookup field; as long as it matches
   * a value on a related record, you're good to go!
   */

  @isTest
  static void shouldMinTimeOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;
    Rollup.defaultRollupLimit = null;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN TIME AFTER_INSERT');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp1.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldMaxTimeOnInsert() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;
    Rollup.defaultRollupLimit = null;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX TIME AFTER_INSERT');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldMaxTimeOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;
    Rollup.defaultRollupLimit = null;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });

    Rollup.oldRecordsMap = new Map<Id, SObject>{ cp1.Id => new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Id = cp1.Id) };
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX TIME AFTER_UPDATE');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldMinTimeOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;
    Rollup.defaultRollupLimit = null;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });

    Rollup.oldRecordsMap = new Map<Id, SObject>{ cp1.Id => new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Id = cp1.Id) };
    Rollup.triggerContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN TIME AFTER_UPDATE');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp1.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldMinTimeOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6), Name = cpe.EmailDomain);
    insert cp2;
    Rollup.defaultRollupLimit = null;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1 });

    Rollup.oldRecordsMap = new Map<Id, SObject>(addresses);
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN TIME BEFORE_DELETE');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldMaxTimeOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(4, 4, 4, 4), Name = cpe.EmailDomain);
    insert cp2;
    Rollup.defaultRollupLimit = null;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1 });

    Rollup.oldRecordsMap = new Map<Id, SObject>(addresses);
    Rollup.triggerContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromTrigger(
        ContactPointAddress.BestTimeToContactEndTime,
        ContactPointAddress.Name,
        ContactPointEmail.EmailDomain,
        ContactPointEmail.BestTimeToContactEndTime,
        ContactPointEmail.SObjectType
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN TIME BEFORE_DELETE');
    cpe = (ContactPointEmail) mock.Records[0];
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @isTest
  static void shouldThrowExceptionWhenTryingToOperateOnDisallowedFieldTypes() {
    Account acc = [SELECT Id FROM Account];
    DMLMock mock = loadMock(new List<Task>{ new Task(ActivityDate = System.today(), WhatId = acc.Id) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;

    Exception ex;
    try {
      Test.startTest();
      Rollup.maxFromTrigger(Task.ActivityDate, Task.WhatId, Account.Id, Account.BillingAddress, Account.SObjectType).runCalc();
      Test.stopTest();
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
    System.assertEquals('Field: BillingAddress of type: ADDRESS specified invalid for rollup operation', ex.getMessage());
  }

  /** CDC trigger tests - TODO: separate test suite to provide code coverage for the usage of custom fields as Field Definitions within Rollup__mdt */

  @isTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnCreate() {
    // CDC functions ** nearly ** the same as regular triggers, yet the SObjects supplied to ChangeEventTriggers
    // differ in two subtle ways: not all the fields are populated (just the changed ones), and the reference info
    // is supplied on a separate object, the ChangeEventHeader
    // Unfortunately, these two "tiny" differences means a lot of other code needs to be tested
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'test cdc', Amount = 500, Name = 'test cdc', AccountId = acc.Id);
    insert opp;
    Rollup.defaultRollupLimit = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'CREATE';
    header.changedFields = new List<String>{ 'Amount', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ opp.Id };
    header.entityName = 'Opportunity';

    OpportunityChangeEvent ev = new OpportunityChangeEvent();
    ev.ChangeEventHeader = header;
    ev.Amount = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'SUM'
      )
    };

    Test.startTest();
    Rollup.runFromCDCTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CDC AFTER_INSERT');
    acc = (Account) mock.Records[0];
    System.assertEquals(500, acc.AnnualRevenue);
  }

  @isTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnUpdate() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'test cdc update', Amount = 500, Name = 'test cdc update', AccountId = acc.Id);
    insert opp;
    Rollup.defaultRollupLimit = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'UPDATE';
    header.changedFields = new List<String>{ 'Amount', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ opp.Id };
    header.entityName = 'Opportunity';

    OpportunityChangeEvent ev = new OpportunityChangeEvent();
    ev.ChangeEventHeader = header;
    ev.Amount = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'SUM'
      )
    };

    Test.startTest();
    Rollup.runFromCDCTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CDC AFTER_UPDATE');
    acc = (Account) mock.Records[0];
    System.assertEquals(500, acc.AnnualRevenue);
  }

  @isTest
  static void shouldWorkForChangeDataCaptureTriggersOnDelete() {
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 10000;
    update acc;

    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'test cdc update', Amount = 500, Name = 'test cdc update', AccountId = acc.Id);
    insert opp;
    Rollup.defaultRollupLimit = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'DELETE';
    header.changedFields = new List<String>{ 'Amount', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ opp.Id };
    header.entityName = 'Opportunity';

    OpportunityChangeEvent ev = new OpportunityChangeEvent();
    ev.ChangeEventHeader = header;
    ev.Amount = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupType__c = 'SUM'
      )
    };

    Test.startTest();
    Rollup.runFromCDCTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CDC BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(acc.AnnualRevenue - ev.Amount, updatedAcc.AnnualRevenue);
  }

  /** Invocable tests */

  @isTest
  static void shouldBeInvokedSuccessfullyAfterInsertFromFlow() {
    List<Opportunity> opps = new List<Opportunity>{ new Opportunity(Amount = 1000) };
    DMLMock mock = getMock(opps);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(opps, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input Amount');
  }

  @isTest
  static void shouldBeInvokedSuccessfullyAfterSaveFromFlow() {
    List<Opportunity> opps = new List<Opportunity>{ new Opportunity(Amount = 1000, Id = generateId(Opportunity.SObjectType)) };
    DMLMock mock = getMock(opps);
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opps[0].Id => new Opportunity(Id = opps[0].Id, Amount = 250) };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(opps, 'UPDATE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(750, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for Amount');
  }

  @isTest
  static void shouldCorrectlyInitializeDefaultsWhenOldRecordsDontExistFromFlow() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 1000, Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 1000, Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);
    opps[1].AccountId = null;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(opps, 'UPDATE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for Amount');
  }

  @isTest
  static void shouldBeInvokedSuccessfullyBeforeDeleteFromFlow() {
    List<Opportunity> opps = new List<Opportunity>{ new Opportunity(Amount = 1000) };
    DMLMock mock = getMock(opps);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(opps, 'DELETE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM BEFORE_DELETE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1000, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE from flow should subtract Amount from Account');
  }

  @isTest
  static void shouldOnlyIncludeObjectChangedFieldsWhenSuppliedFromFlow() {
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 1000, Name = 'Acme opp', Id = generateId(Opportunity.SObjectType)),
      new Opportunity(Amount = 500, Name = 'Test name changed opp', Id = generateId(Opportunity.SObjectType))
    };
    DMLMock mock = getMock(opps);

    Rollup.oldRecordsMap = new Map<Id, Opportunity>{
      opps[0].Id => new Opportunity(Id = opps[0].Id, Amount = 250, Name = opps[0].Name),
      opps[1].Id => new Opportunity(Id = opps[1].Id, Name = 'Name that does not match', Amount = 200)
    };

    List<Rollup.FlowInput> flowInputs = prepareFlowTest(opps, 'UPDATE', 'SUM');
    flowInputs[0].calcItemChangedFields = 'Name, StageName';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      300,
      updatedAcc.AnnualRevenue,
      'SUM AFTER_UPDATE from flow with changed fields should match diff for Amount based off of the Opp with Name changes'
    );
  }

  @isTest
  static void shouldReportSuccessWhenFlowPassesNoRecords() {
    List<Opportunity> opps = new List<Opportunity>();
    Rollup.shouldRun = true;
    Rollup.records = opps;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(opps, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @isTest
  static void shouldReportFailureWhenExceptionIsThrown() {
    List<OpportunityHistory> history = new List<OpportunityHistory>{ new OpportunityHistory() };
    Rollup.shouldRun = true;
    Rollup.records = history;

    Test.startTest();
    // prepareFlowTest sets us up for a failure with a field that doesn't exist on OpportunityHistory
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(history, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals(false, flowOutputs[0].isSuccess);
  }

  @isTest
  static void shouldNotThrowErrorEvenIfNoRollupsPerformedDuringInvocable() {
    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(new List<SObject>(), 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size());
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @isTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadataForFlow() {
    List<Opportunity> opps = new List<Opportunity>{ new Opportunity(Amount = 1000) };
    DMLMock mock = getMock(opps);
    List<Rollup.FlowInput> flowInputs = prepareFlowTest(opps, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultNumberValue = -1001;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input Amount + number override');
  }

  @isTest
  static void shouldOverrideDateUsingNumberBasedDefaultForFlow() {
    Contract con = [SELECT Id FROM Contract];

    Datetime nowish = System.now();

    // it only matters that the amount below is LESS than the above value, and that "nowish" is assigned to the fullRecalculationDefaultNumberValue flow input value
    List<Event> events = new List<Event>{ new Event(ActivityDateTime = nowish.addDays(-2), WhatId = con.Id) };
    DMLMock mock = loadMock(events);
    Rollup.records = null;

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = events;
    flowInput.lookupFieldOnCalcItem = 'WhatId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = 'INSERT';
    flowInput.rollupFieldOnCalcItem = 'ActivityDateTime';
    flowInput.rollupFieldOnOpObject = 'ActivatedDate';
    flowInput.rollupSObjectName = 'Contract';
    flowInput.rollupOperation = 'MAX';
    flowInput.fullRecalculationDefaultNumberValue = nowish.getTime();

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput });
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'MAX AFTER_INSERT from flow with override date did not update accounts');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(nowish, updatedContract.ActivatedDate, 'MAX AFTER_INSERT from flow should match override date');
  }

  @isTest
  static void shouldOverrideStringBasedDefaultForFlow() {
    List<Opportunity> opps = new List<Opportunity>{ new Opportunity(Name = 'A') };
    DMLMock mock = getMock(opps);
    List<Rollup.FlowInput> flowInputs = prepareFlowTest(opps, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultStringValue = 'Z';
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.Name, 'SUM AFTER_INSERT from flow should match string override when it is greater than supplied calc values');
  }

  @isTest
  static void shouldNotWriteToNonUpdateableFieldsForOldFlowRecords() {
    Account acc = [SELECT Id FROM Account];

    Event ev = new Event(ActivityDateTime = System.now().addDays(-2), WhatId = acc.Id);

    // a useful hack for assigning values to unwriteable fields ...
    Map<String, Object> deserializedEvent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(ev));
    deserializedEvent.put('AccountId', null);
    ev = (Event) JSON.deserialize(JSON.serialize(deserializedEvent), Event.class);

    List<Event> events = new List<Event>{ ev };
    DMLMock mock = loadMock(events);
    Rollup.records = null;

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = events;
    flowInput.lookupFieldOnCalcItem = 'WhatId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = 'INSERT';
    flowInput.rollupFieldOnCalcItem = 'ActivityDateTime';
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupSObjectName = 'Account';
    flowInput.rollupOperation = 'COUNT';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput });
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT from flow should not fail when non-writeable fields are present');
  }

  /** Batch test */

  @isTest
  static void shouldRunSuccessfullyAsBatch() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRunAsBatch = true;

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated');
    // validate that job ran as batch
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  /** Rollup Limit metadata tests */

  @isTest
  static void shouldAbortWhenOrgDefaultsHaveDisabledRunning() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @isTest
  static void shouldAbortWhenSpecificRollupLimitDisablesRunning() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificRollupLimit = new RollupLimit__mdt(ShouldAbortRun__c = true);

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @isTest
  static void shouldRunAsBatchableWhenSpecificRollupIsBatchable() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificRollupLimit = new RollupLimit__mdt(ShouldRunAsBatchable__c = true);

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @isTest
  static void shouldNotRunAsBatchableWhenDefaultIsBatchableAndRecordsAreLessThanBatchableLimit() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultRollupLimit = new RollupLimit__mdt(ShouldRunAsBatchable__c = true, MaxLookupRowsBeforeBatching__c = 1000);

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @isTest
  static void shouldRunAsQueueableWhenSpecificLimitIsQueueableAndBatchableIsFalse() {
    DMLMock mock = getMock(new List<Opportunity>{ new Opportunity(Amount = 1) });
    Rollup.triggerContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificRollupLimit = new RollupLimit__mdt(ShouldRunAsBatchable__c = false, ShouldRunAsQueueable__c = true);

    Test.startTest();
    Rollup.countFromTrigger(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  /** Schedulable tests */
  @isTest
  static void shouldThrowExceptionForBadQuery() {
    // it's a date field - you tell ME why this query is invalid!
    String veryBadQuery = 'SELECT MAX(ActivityDate) FROM Task';

    Exception ex;
    try {
      Rollup.schedule('Test bad query', '0 0 0 0 0', veryBadQuery, new List<Id>(), null);
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @isTest
  static void shouldScheduleSuccessfullyForGoodQuery() {
    String goodQuery = 'SELECT Id, StageName FROM Opportunity WHERE CreatedDate > YESTERDAY';

    String jobId = Rollup.schedule('Test good query' + System.now(), '0 0 0 * * ?', goodQuery, new List<Id>(), null);

    System.assertNotEquals(null, jobId);
  }

  /** Integration tests */

  @isTest
  static void shouldEnqueueFullRecalculationWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<Opportunity> opps = new List<Opportunity> {
      new Opportunity(Name = 'one', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'two', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'three', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'four', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'five', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'six', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1)
    };
    insert opps;

    Test.startTest();
    Rollup.performFullRecalculation(
      'Amount',
      'AccountId',
      'Id',
      'AnnualRevenue',
      'Account',
      'Opportunity',
      'SUM'
    );
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
  }

  @isTest
  static void shouldBatchForFullRecalcWhenOverLimits() {
    Account acc = [SELECT Id FROM Account];

    List<Opportunity> opps = new List<Opportunity> {
      new Opportunity(Name = 'one', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'two', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'three', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'four', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'five', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'six', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1)
    };
    insert opps;

    Rollup.maxQueryRowOverride = 1;

    Test.startTest();
    Rollup.performFullRecalculation(
      'Amount',
      'AccountId',
      'Id',
      'AnnualRevenue',
      'Account',
      'Opportunity',
      'SUM'
    );
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
  }

  //** Helpers */

  private static DMLMock getMock(List<SObject> records) {
    Account acc = [SELECT Id FROM Account];
    for (SObject record : records) {
      record.put('AccountId', acc.Id);
    }

    return loadMock(records);
  }

  private static DMLMock getTaskMock(List<SObject> records, Id oppId) {
    for (SObject task : records) {
      task.put('WhatId', oppId);
    }
    return loadMock(records);
  }

  private static DMLMock loadMock(List<SObject> records) {
    Rollup.records = records;
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;

    return mock;
  }

  private static List<Rollup.FlowInput> prepareFlowTest(List<SObject> records, String rollupContext, String rollupOperation) {
    Rollup.records = null; // just to ensure this is coming from the correct place

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = records;
    flowInput.lookupFieldOnCalcItem = 'AccountId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = rollupContext;
    flowInput.rollupFieldOnCalcItem = 'Amount';
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupSObjectName = 'Account';
    flowInput.rollupOperation = rollupOperation;

    return new List<Rollup.FlowInput>{ flowInput };
  }

  // from https://salesforce.stackexchange.com/questions/21137/creating-unit-tests-without-interacting-with-the-database-creating-fake-ids
  private static Integer startingNumber = 1;
  private static String generateId(Schema.SObjectType sObjectType) {
    String result = String.valueOf(startingNumber++);
    return sObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - result.length()) + result;
  }
}
