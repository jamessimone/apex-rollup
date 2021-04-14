@isTest
private class RollupTests {
  // NB - tests that perform DML should wrap the DML by setting Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
  // and then Rollup.defaultControl = null after DML has been performed. This is to prevent side-effects caused by having implemented Rollup in your org
  @TestSetup
  static void setup() {
    // in the event that rollups are running in the org, we want to avoid triggering any operations while performing setup DML
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = 'RollupTests');
    insert acc;
    Contract con = new Contract(Name = 'Datetime tests', AccountId = acc.Id);
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'RollupTestsCpa');
    insert new List<SObject>{ con, cpa };
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  private class DMLMock extends Rollup.DMLHelper {
    public List<SObject> Records = new List<SObject>();
    public override void doUpdate(List<SObject> recordsToUpdate) {
      this.Records = recordsToUpdate;
    }
  }

  static Object testPriorVal;
  static Rollup.Op testOp;
  static SObjectField testOpFieldOnCalcItem;
  static SObjectField testOpFieldOnLookupObject;
  static Rollup__mdt testMetadata;
  static String testLookupRecordKey;
  static SObjectField testLookupKeyField;
  private class FactoryMock extends RollupCalculator.Factory {
    public override RollupCalculator getCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      testPriorVal = priorVal;
      testOp = op;
      testOpFieldOnCalcItem = opFieldOnCalcItem;
      testOpFieldOnLookupObject = opFieldOnLookupObject;
      testMetadata = metadata;
      testLookupRecordKey = lookupRecordKey;
      testLookupKeyField = lookupKeyField;
      return new RollupCalcMock();
    }
  }

  static Boolean calcMockWasCalled = false;
  public class RollupCalcMock extends RollupCalculator {
    // everything is a no-op
    public RollupCalcMock() {
      super(0, Rollup.Op.First, null, null, null, null, null);
      calcMockWasCalled = true;
    }
  }

  /** Trigger tests */

  @isTest
  static void shouldNotRunForInvalidApexContext() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.BEFORE_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(true, mock.Records.isEmpty(), 'Records should not have been set or updated, this is a no-op');
  }

  @isTest
  static void shouldNotRunWhenDisabled() {
    RollupSettings__c existingSetting = [SELECT Id, IsEnabled__c FROM RollupSettings__c];
    existingSetting.IsEnabled__c = false;
    update existingSetting;

    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(true, mock.Records.isEmpty(), 'Records should not have been set or updated, custom setting was disabled');
  }

  @isTest
  static void shouldSumFromTriggerAfterInsert() {
    DMLMock mock = loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 25), new ContactPointAddress(PreferenceRank = 25) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Rollup rollup = Rollup.sumFromApex(
      ContactPointAddress.PreferenceRank,
      ContactPointAddress.ParentId,
      Account.Id,
      Account.AnnualRevenue,
      Account.SObjectType
    );

    System.assertEquals(true, mock.Records.isEmpty());

    Test.startTest();
    rollup.runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(50, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original cpaortunity amount');
  }

  @isTest
  static void shouldTakeDefaultForSumWhenGiven() {
    DMLMock mock = loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 25), new ContactPointAddress(PreferenceRank = 25) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Rollup rollup = Rollup.sumFromApex(
      ContactPointAddress.PreferenceRank,
      ContactPointAddress.ParentId,
      Account.Id,
      Account.AnnualRevenue,
      Account.SObjectType,
      5
    );

    System.assertEquals(true, mock.Records.isEmpty());

    Test.startTest();
    rollup.runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(55, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original cpaortunity amount to the default');
  }

  @isTest
  static void shouldSumFromTriggerAfterUndelete() {
    // undelete should behave the same as an insert, for our purposes
    DMLMock mock = loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 25), new ContactPointAddress(PreferenceRank = 25) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_UNDELETE;

    Rollup rollup = Rollup.sumFromApex(
      ContactPointAddress.PreferenceRank,
      ContactPointAddress.ParentId,
      Account.Id,
      Account.AnnualRevenue,
      Account.SObjectType
    );

    Test.startTest();
    rollup.runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_UNDELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(50, updatedAcc.AnnualRevenue, 'SUM AFTER_UNDELETE should add the original cpaortunity amount');
  }

  @isTest
  static void shouldSumFromTriggerAfterUpdate() {
    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, PreferenceRank = 25) };

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(25, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @isTest
  static void shouldSumFromTriggerBeforeDelete() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-100, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE should subtract the current amount from the pre-existing one');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnInsert() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert', ParentId = acc.Id);
    Rollup.defaultControl = null;

    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Test Count Distinct Insert Two') });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should simply add unique values');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert One', ParentId = acc.Id);
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Name = 'Test Count Distinct Insert Two', Id = generateId(ContactPointAddress.SObjectType));
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the important part here is that the old value differs
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Name = 'something different', Id = cpa.Id) };

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should ensure distinct values');
  }

  @isTest
  static void shouldCountDistinctFromTriggerOnDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc; // we want to ensure that the AnnualRevenue is reset because there are no other matching values
    Rollup.defaultControl = null;

    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress() });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT BEFORE_DELETE should simply decrement');
  }

  @isTest
  static void shouldCountFromTriggerAfterInsert() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated');
  }

  @isTest
  static void shouldDecrementCountFromTriggerAfterUpdateIfValueIsRemoved() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType));
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE should decrement when field is removed');
  }

  @isTest
  static void shouldKeepCountUnchangedFromTriggerAfterUpdateEvenIfValueChanges() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated COUNT AFTER_UPDATE');
  }

  @isTest
  static void shouldDecrementCountFromTriggerBeforeDeleteIfValueIsRemoved() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 9;
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should not have been populated COUNT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(acc.AnnualRevenue - 1, updatedAcc.AnnualRevenue, 'COUNT BEFORE_DELETE should decrement when field is removed');
  }

  @isTest
  static void shouldNotCountNullValues() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress() });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated when empty COUNT AFTER_INSERT');
  }

  @isTest
  static void shouldRunSumFromTriggerBasedOnMetadata() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original cpaortunity amount based on CMDT');
  }

  @isTest
  static void shouldRunRegardlessOfMetadataCasing() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'sum',
        CalcItem__c = 'ContactPointAddress'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'sum AFTER_INSERT should add the original cpaortunity amount based on CMDT');
  }

  @isTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadata() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress',
        FullRecalculationDefaultNumberValue__c = 100000
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original cpaortunity amount to the default override based on CMDT');
  }

  @isTest
  static void shouldOverrideStringBasedDefaultBasedOnMetadata() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'MAX',
        CalcItem__c = 'ContactPointAddress',
        FullRecalculationDefaultStringValue__c = 'Z'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on override metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.Name, 'MAX AFTER_INSERT should add the default override based on CMDT if there is no greater value');
  }

  // an integration test of sorts, to validate that CalcItemWhereClause__c is correctly handed off to the right evaluator
  // the other tests pertaining to this are in RollupEvaluatorTests
  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEquals() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'RollupZ'), new ContactPointAddress(Name = 'RollupZZ') });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'MAX',
        CalcItemWhereClause__c = 'Name = \'RollupZ\'',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on exclusion metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('RollupZ', updatedAcc.Name, 'MAX AFTER_INSERT should ignore excluded items');
  }

  @isTest
  static void shouldResetRollupValueWhenNoItemsMatchAndToggleIsSupplied() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 50;
    update acc;
    Rollup.defaultControl = null;

    DMLMock mock = loadMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'RollupZ', ParentId = acc.Id, PreferenceRank = 50) });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Name != \'RollupZ\'',
        IsFullRecordSet__c = true,
        CalcItem__c = 'ContactPointAddress',
        FullRecalculationDefaultNumberValue__c = 0
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'IsFullRecordSet__c should force account to reset its rollup value AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'Full record set flag should force empty match set to still update lookup item');
  }

  @isTest
  static void shouldRunMultipleOperationsWhenMoreMetadataIsPresent() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'ContactPointAddress'
      ),
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should count when the field is present on the calc item based on CMDT');
    System.assertEquals(1, updatedAcc.NumberOfEmployees, 'COUNT_DISTINCT AFTER_INSERT should count regardless of not pointing to a field based on CMDT');
  }

  @isTest
  static void shouldRunDirectlyFromApex() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 5),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 10)
    };

    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromApex(cpas, TriggerOperation.AFTER_INSERT);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(15, acc.AnnualRevenue);
  }

  /** Parent-initiated rollups */
  @isTest
  static void shouldAllowRollupToBeInitiatedFromTheParent() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Asset asset = new Asset(AccountId = acc.Id, Name = 'Rollup initiated from parent', Quantity = 500);
    insert asset;
    Rollup.defaultControl = null;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Quantity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Asset',
        IsRollupStartedFromParent__c = true
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.records = new List<Account>{ acc };
    Rollup.oldRecordsMap = new Map<Id, Account>{ acc.Id => new Account(Id = acc.Id, AnnualRevenue = 0) };
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been updated based on parent metadata AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertNotEquals(acc.AnnualRevenue, updatedAcc.AnnualRevenue, 'Account should have been updated with asset Quantity');
  }

  @isTest
  static void shouldAllowRollupFromParentByInvocable() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    ContactPointAddress cpa = [SELECT Id, PreferenceRank FROM ContactPointAddress];
    cpa.ParentId = acc.Id;
    update cpa;
    Rollup.defaultControl = null;

    List<Account> accs = new List<Account>{ acc };
    DMLMock mock = loadMock(accs);

    List<Rollup.FlowInput> flowInputs = prepareFlowTest(accs, 'INSERT', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpa.PreferenceRank, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank');
  }

  @isTest
  static void shouldBatchTwoOperations() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.batch(
      Rollup.countDistinctFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.NumberOfEmployees,
        Account.SObjectType
      ),
      Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
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
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100, Name = 'My test name') });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.batch(
      Rollup.countDistinctFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.NumberOfEmployees,
        Account.SObjectType
      ),
      Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType),
      Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType)
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
  static void shouldDeferUpdateWhenMaxParentRowsLessThanCurrentUpdateRows() {
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 50, Name = 'MaxParentRows');
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRunAsBatch = true;
    Rollup.defaultControl = new RollupControl__mdt(MaxParentRowsUpdatedAtOnce__c = 0, BatchChunkSize__c = 1);

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    Account acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(50, acc.AnnualRevenue, 'Account should have been updated since the mock is not used async');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterInsert() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(200, updatedAcc.AnnualRevenue, 'MAX AFTER_INSERT should take the maximum cpaortunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterUpdate() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(Id = cpas[0].Id),
      cpas[1].Id => new ContactPointAddress(Id = cpas[1].Id)
    };

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(200, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpaortunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMax() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(new List<ContactPointAddress>{ cpa });
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(secondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa PreferenceRank');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMax() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank + 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMaxAndNoOtherSObjectsExist() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = acc.AnnualRevenue.intValue(),
      ParentId = acc.Id,
      Name = 'testCpa',
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      PreferenceRank = 175,
      ParentId = acc.Id,
      Name = 'testCpaTwo',
      Id = generateId(ContactPointAddress.SObjectType)
    );
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank + 30; // the amount is really unimportant; that it doesn't match what's in memory is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpaortunity amount');
  }

  @isTest
  static void shouldMaxNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 250, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    DMLMock mock = loadAccountIdMock(originalCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'MAX BEFORE_DELETE should take the maximum cpaortunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterInsert() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'MIN AFTER_INSERT should take the minimum cpaortunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterUpdate() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(Id = cpas[0].Id),
      cpas[1].Id => new ContactPointAddress(Id = cpas[1].Id)
    };

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum cpaortunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMin() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 200;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(new List<ContactPointAddress>{ cpa });
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum cpaortunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMin() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = secondCpa.PreferenceRank + 50; // the amount isn't important - that it's now more than the second CPA PreferenceRank is
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @isTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMinAndNoOtherSObjectsExist() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = acc.AnnualRevenue.intValue(),
      ParentId = acc.Id,
      Name = 'testCpa',
      Id = generateId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      PreferenceRank = 175,
      ParentId = acc.Id,
      Name = 'testCpaTwo',
      Id = generateId(ContactPointAddress.SObjectType)
    );
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = secondCpa.PreferenceRank + 50; // the amount isn't important - that it's now more than the second CPA PreferenceRank is
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @isTest
  static void shouldMinNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;
    Rollup.defaultControl = null;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>(Rollup.records);
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN BEFORE_DELETE should take the minimum cpaortunity amount');
  }

  @isTest
  static void shouldConcatOnUpdate() {
    // AFTER_INSERT test is handled in the "shouldBatchThreeOperations" method
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'second test string', Id = generateId(ContactPointAddress.SObjectType));
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;

    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldCpa.Id => oldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpa.Name, updatedAcc.AccountNumber, 'CONCAT AFTER_UPDATE should replace the old string value with the new');
  }

  @isTest
  static void shouldConcatOnDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning test string something';
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'test string');
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('beginning something', updatedAcc.AccountNumber, 'CONCAT BEFORE_DELETE should replace the outgoing string value with empty string');
  }

  @isTest
  static void shouldConcatDistinctOnInsert() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning, test string, something';
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'test string');
    ContactPointAddress secondCpa = new ContactPointAddress(ParentId = acc.Id, Name = 'hello another string');
    ContactPointAddress thirdCpa = cpa.clone(true, true);
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa, thirdCpa });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      'beginning, hello another string, something, test string',
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_INSERT should only add unique values'
    );
  }

  @isTest
  static void shouldConcatDistinctOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'second test string', Id = generateId(ContactPointAddress.SObjectType));
    ContactPointAddress secondCpa = new ContactPointAddress(ParentId = acc.Id, Name = 'third test string', Id = generateId(ContactPointAddress.SObjectType));
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;
    ContactPointAddress secondoldCpa = secondCpa.clone(true, true);
    secondoldCpa.Name = acc.AccountNumber;

    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldCpa.Id => oldCpa, secondoldCpa.Id => secondoldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
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
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.AccountNumber, 'MAX AFTER_INSERT should take the maximum string');
  }

  @isTest
  static void shouldMaxStringsWhenDefaultIsGiven() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType, 'ZZZ').runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('ZZZ', updatedAcc.AccountNumber, 'MAX AFTER_INSERT should take the maximum string including default');
  }

  @isTest
  static void shouldMinOnStringsOnInsert() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MIN AFTER_INSERT should take the minimum string');
  }

  @isTest
  static void shouldMinOnStringsOnUpdate() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'B', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(Name = 'A', Id = generateId(ContactPointAddress.SObjectType))
    };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      testCpas[0].Id => new ContactPointAddress(Id = testCpas[0].Id, Name = ''),
      testCpas[1].Id => new ContactPointAddress(Id = testCpas[1].Id, Name = 'X')
    };

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MIN AFTER_UPDATE should take the minimum string');
  }

  @isTest
  static void shouldMaxOnStringsOnUpdate() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = '', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(Name = 'A', Id = generateId(ContactPointAddress.SObjectType))
    };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(testCpas);

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MAX AFTER_UPDATE should take the maximum string');
  }

  @isTest
  static void shouldMinOnStringsBeforeDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;
    Rollup.defaultControl = null;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A', Id = generateId(ContactPointAddress.SObjectType)) };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpas[0].Id => new ContactPointAddress(Id = testCpas[0].Id, Name = 'A') };

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('', updatedAcc.AccountNumber, 'MIN BEFORE_DELETE should take the minimum string');
  }

  @isTest
  static void shouldMaxOnStringsBeforeDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Name = 'Z', ParentId = acc.Id);
    insert cpa;
    Rollup.defaultControl = null;
    // ensure that if any automation has changed the name, we keep track of it
    cpa = [SELECT Name FROM ContactPointAddress WHERE Id = :cpa.Id];

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A', Id = generateId(ContactPointAddress.SObjectType)) };

    DMLMock mock = loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(testCpas);

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    Boolean originalCpaNameGreater = cpa.Name > testCpas[0].Name;
    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(originalCpaNameGreater ? cpa.Name : testCpas[0].Name, updatedAcc.AccountNumber, 'MAX BEFORE_DELETE should take the maximum string');
  }

  @isTest
  static void shouldMaxOnPicklistStringsOnInsert() {
    List<PicklistEntry> picklistVals = Lead.LeadSource.getDescribe().getPicklistValues();

    if (picklistVals.size() < 2) {
      return; // sorry
    }

    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Max Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Max Picklist on insert two')
    };
    insert leads; // not the best, either, but we need to be able to use SOQL below
    Rollup.defaultControl = null;

    DMLMock mock = loadMock(leads);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Lead.LeadSource, Lead.Company, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
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

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Min Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Min Picklist on insert two')
    };
    insert leads;
    Rollup.defaultControl = null;

    DMLMock mock = loadMock(leads);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Lead.LeadSource, Lead.Company, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    AggregateResult res = [SELECT MIN(LeadSource) minSource FROM Lead WHERE Id = :new Map<Id, Lead>(leads).keySet()][0];
    String minLeadSource = (String) res.get('minSource');

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_INSERT PICKLIST STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(minLeadSource, updatedAcc.AccountNumber, 'MIN BEFORE_INSERT should take the minimum picklist string');
  }

  @isTest
  static void shouldAverageOnInsert() {
    // average is a special case; even on insert, we have to also check for pre-existing records existing
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;
    Rollup.defaultControl = null;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200000, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      (testCpa.PreferenceRank + cpas[0].PreferenceRank + cpas[1].PreferenceRank) / 3.00,
      updatedAcc.AnnualRevenue,
      'AVERAGE AFTER_INSERT should take into account all values'
    );
  }

  @isTest
  static void shouldAverageOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;
    Rollup.defaultControl = null;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200000, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(PreferenceRank = 100000, Id = cpas[0].Id),
      cpas[1].Id => new ContactPointAddress(PreferenceRank = 100000, Id = cpas[1].Id)
    };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      (testCpa.PreferenceRank + cpas[0].PreferenceRank + cpas[1].PreferenceRank) / 3.00,
      updatedAcc.AnnualRevenue,
      'AVERAGE AFTER_UPDATE should take into account all values, including those from memory'
    );
  }

  @isTest
  static void shouldAverageOnDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 200;
    update acc;

    ContactPointAddress testCpaOne = new ContactPointAddress(PreferenceRank = 100, Name = 'Pre-existing one', ParentId = acc.Id);
    ContactPointAddress testCpaTwo = new ContactPointAddress(PreferenceRank = 300, Name = 'Pre-existing one', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ testCpaOne, testCpaTwo };
    Rollup.defaultControl = null;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ testCpaTwo };

    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpaOne.Id => testCpaOne };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(testCpaOne.PreferenceRank, updatedAcc.AnnualRevenue, 'AVERAGE BEFORE_DELETE should take into account only non-deleted values');
  }

  // TODO migrate tests specific to calculating to this format, and the actual testing of functionality to RollupCalculatorTests
  @isTest
  static void shouldRollupForFirst() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today()) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.firstFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType,
        'ActiveFromDate'
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(true, calcMockWasCalled);
  }

  @isTest
  static void shouldRollupForLast() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today()) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.lastFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType,
        'ActiveFromDate'
      )
      .runCalc();
    Test.stopTest();
    System.assertEquals(true, calcMockWasCalled);
  }

  @isTest
  static void shouldPassRecalcValueForAverage() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5)
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForCountDistinct() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5)
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForConcatDistinct() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 'a')
      .runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForConcat() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 'a')
      .runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForCount() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5).runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForFirst() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.firstFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5, 'orderby')
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForLast() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.lastFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5, 'orderby')
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @isTest
  static void shouldPassRecalcValueForMin() {
    RollupCalculator.Factory = new FactoryMock();
    loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5).runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  // Now we test different field types for success: time, datetime, date. Here be dragons.
  @isTest
  static void shouldMaxDateOnInsert() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointAddress cpa = new ContactPointAddress(Name = 'Max date on insert test');
    insert cpa;
    Rollup.defaultControl = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = cpa.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = cpa.Id);

    DMLMock mock = getTaskMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATE AFTER_INSERT');
    ContactPointAddress updatedCpa = (ContactPointAddress) mock.Records[0];
    System.assertEquals(taskTwo.ActivityDate, updatedCpa.ActiveFromDate);
  }

  @isTest
  static void shouldMinDateOnInsert() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointAddress cpa = new ContactPointAddress(Name = 'Min date on insert test');
    insert cpa;
    Rollup.defaultControl = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    DMLMock mock = getTaskMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    ContactPointAddress updatedCpa = (ContactPointAddress) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCpa.ActiveFromDate);
  }

  @isTest
  static void shouldMinDateOnInsertWhereParentDateIsNull() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    //using campaign for this test because EndDate is not required when inserting a Campaign
    Campaign camp = new Campaign(Name = 'Test Date with no initialized value');
    insert camp;
    Rollup.defaultControl = null;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = camp.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = camp.Id);

    DMLMock mock = loadMock(new List<Task>{ taskOne, taskTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, Campaign.Id, Campaign.EndDate, Campaign.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Campaign updatedCamp = (Campaign) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCamp.EndDate);
  }

  @isTest
  static void shouldMinDateOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contact con = new Contact(LastName = 'Min date on insert test', BirthDate = System.today());
    insert con;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = con.BirthDate.addDays(-50), WhoId = con.Id);
    insert taskOne;
    Rollup.defaultControl = null;

    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = con.BirthDate.addDays(5), Id = generateId(Task.SObjectType), WhoId = con.Id);

    DMLMock mock = getTaskMock(new List<Task>{ taskTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Task>(new List<Task>{ new Task(Id = taskTwo.Id, ActivityDate = con.BirthDate) });

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhoId, Contact.Id, Contact.BirthDate, Contact.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Contact updatedCon = (Contact) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCon.BirthDate);
  }

  @isTest
  static void shouldMaxDatetimeOnInsert() {
    Contract con = [SELECT Id FROM Contract];

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50), WhatId = con.Id);
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50), WhatId = con.Id);

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
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
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_INSERT');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventOne.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMinDatetimeOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;
    Rollup.defaultControl = null;

    // now the "new" version of eventOne is no longer the min
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = generateId(Event.SObjectType));

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing min
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_UPDATE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMaxDatetimeOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;
    Rollup.defaultControl = null;

    // now the "new" version of eventOne is no longer the max
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = generateId(Event.SObjectType));

    DMLMock mock = loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing max
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_UPDATE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMaxDatetimeOnDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;
    Rollup.defaultControl = null;

    DMLMock mock = loadMock(new List<Event>{ eventOne });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME BEFORE_DELETE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @isTest
  static void shouldMinDatetimeOnDelete() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = generateId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;
    Rollup.defaultControl = null;

    DMLMock mock = loadMock(new List<Event>{ eventOne });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;
    Rollup.defaultControl = null;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;
    Rollup.defaultControl = null;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1, cp2 });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;
    Rollup.defaultControl = null;

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
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;
    Rollup.defaultControl = null;

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
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
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
    Rollup.defaultControl = null;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1 });

    Rollup.oldRecordsMap = new Map<Id, SObject>(addresses);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromApex(
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
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
    Rollup.defaultControl = null;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cp1 });

    Rollup.oldRecordsMap = new Map<Id, SObject>(addresses);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromApex(
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
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Exception ex;
    try {
      Test.startTest();
      Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, Account.Id, Account.BillingAddress, Account.SObjectType).runCalc();
      Test.stopTest();
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
    System.assertEquals('Field: BillingAddress of type: ADDRESS specified invalid for rollup operation', ex.getMessage());
  }

  /** CDC trigger tests */

  @isTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnCreate() {
    // CDC functions ** nearly ** the same as regular triggers, yet the SObjects supplied to ChangeEventTriggers
    // differ in two subtle ways: not all the fields are populated (just the changed ones), and the reference info
    // is supplied on a separate object, the ChangeEventHeader
    // Unfortunately, these two "tiny" differences means a lot of other code needs to be tested
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc', ParentId = acc.Id);
    insert cpa;
    Rollup.defaultControl = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'CREATE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc update', ParentId = acc.Id);
    insert cpa;
    Rollup.defaultControl = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'UPDATE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
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
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 10000;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc update', ParentId = acc.Id);
    insert cpa;
    Rollup.defaultControl = null;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'DELETE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = 500;

    DMLMock mock = loadMock(new List<SObject>{ ev });

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromCDCTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CDC BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(acc.AnnualRevenue - ev.PreferenceRank, updatedAcc.AnnualRevenue);
  }

  /** Invocable tests */

  @isTest
  static void shouldBeInvokedSuccessfullyAfterInsertFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    DMLMock mock = loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank');
  }

  @isTest
  static void shouldBeInvokedRegardlessOfCasingFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    DMLMock mock = loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'insert', 'sum'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'sum AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'sum AFTER_INSERT from flow should match input PreferenceRank');
  }

  @isTest
  static void shouldBeInvokedSuccessfullyAfterSaveFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250)
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'UPDATE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(750, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @isTest
  static void shouldCorrectlyInitializeDefaultsWhenOldRecordsDontExistFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 1000, Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);
    cpas[1].ParentId = null;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'UPDATE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @isTest
  static void shouldBeInvokedSuccessfullyBeforeDeleteFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    DMLMock mock = loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'DELETE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM BEFORE_DELETE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1000, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE from flow should subtract PreferenceRank from Account');
  }

  // integration test for "ChangedFieldsOnCalcItem__c" being properly constructed
  @isTest
  static void shouldOnlyIncludeObjectChangedFieldsWhenSuppliedFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Name = 'Acme cpa', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 500, Name = 'Test name changed cpa', Id = generateId(ContactPointAddress.SObjectType))
    };
    DMLMock mock = loadAccountIdMock(cpas);

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250, Name = cpas[0].Name),
      cpas[1].Id => new ContactPointAddress(ParentId = cpas[1].ParentId, Id = cpas[1].Id, Name = 'Name that does not match', PreferenceRank = 200)
    };

    List<Rollup.FlowInput> flowInputs = prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].calcItemChangedFields = 'Name, IsDefault';

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
      'SUM AFTER_UPDATE from flow with changed fields should match diff for PreferenceRank based off of the CPA with Name changes'
    );
  }

  @isTest
  static void shouldReportSuccessWhenFlowPassesNoRecords() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>();
    Rollup.shouldRun = true;
    Rollup.records = cpas;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @isTest
  static void shouldReportFailureWhenExceptionIsThrown() {
    List<ContactPointAddressHistory> history = new List<ContactPointAddressHistory>{ new ContactPointAddressHistory() };
    Rollup.shouldRun = true;
    Rollup.records = history;

    Test.startTest();
    // prepareFlowTest sets us up for a failure with a field that doesn't exist on ContactPointAddressHistory
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
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    DMLMock mock = loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultNumberValue = -1001;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow ouputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank + number override');
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
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') };
    DMLMock mock = loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = prepareFlowTest(cpas, 'INSERT', 'SUM');
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
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRunAsBatch = true;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated');
    // validate that job ran as batch
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  /** Rollup Control metadata tests */

  @isTest
  static void shouldAbortWhenOrgDefaultsHaveDisabledRunning() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @isTest
  static void shouldAbortWhenspecificControlDisablesRunning() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldAbortRun__c = true);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @isTest
  static void shouldRunAsBatchableWhenSpecificRollupIsBatchable() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = 'Batchable', BatchChunkSize__c = 1, MaxLookupRowsBeforeBatching__c = 0);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @isTest
  static void shouldNotRunAsBatchableWhenDefaultIsBatchableAndRecordsAreLessThanBatchableLimit() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = 'Batchable', MaxLookupRowsBeforeBatching__c = 1000, BatchChunkSize__c = 50);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @isTest
  static void shouldRunAsQueueableWhenSpecificControlIsQueueable() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Queueable');

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
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
      Rollup.schedule('Test bad query', '0 0 0 0 0', veryBadQuery, 'Account', null);
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @isTest
  static void shouldScheduleSuccessfullyForGoodQuery() {
    String goodQuery = 'SELECT Id, Name FROM ContactPointAddress WHERE CreatedDate > YESTERDAY';

    String jobId = Rollup.schedule('Test good query' + System.now(), '0 0 0 * * ?', goodQuery, 'ContactPointAddress', null);

    System.assertNotEquals(null, jobId);
  }

  /** Integration tests */

  @isTest
  static void shouldNotFailForTruncatedTextFields() {
    Account acc = [SELECT Id FROM Account];
    Contact con = new Contact(
      AccountId = acc.Id,
      Description = '0'.repeat(256),
      LastName = 'Truncate',
      Email = 'rollup@gmail.com'
    );
    insert con;

    Test.startTest();
    Rollup.performFullRecalculation('Description', 'AccountId', 'Id', 'Name', 'Account', 'Contact', 'CONCAT', null, null);
    Test.stopTest();

    acc = [SELECT Name FROM Account];
    System.assertEquals(255, acc.Name.length(), acc.Name);
  }

  @isTest
  static void shouldEnqueueCMDTRecalcWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Name = 'oneCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'twoCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'threeCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'fourCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'fiveCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1),
      new Opportunity(Name = 'sixCMDT', StageName = 'fullRecalc', CloseDate = System.today(), AccountId = acc.Id, Amount = 1)
    };
    insert opps;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'StageName = \'' + opps[0].StageName + '\''
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    Test.startTest();
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('Opportunity'));
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @isTest
  static void shouldEnqueueFullRecalculationWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'one', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'two', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'three', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'four', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'five', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'six', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Test.startTest();
    Rollup.performFullRecalculation('PreferenceRank', 'ParentId', 'Id', 'AnnualRevenue', 'Account', 'ContactPointAddress', 'SUM', null, null);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @isTest
  static void shouldBatchForFullRecalcWhenOverLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixBatch', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(MaxQueryRows__c = 1, BatchChunkSize__c = 10);

    Test.startTest();
    Rollup.performFullRecalculation('PreferenceRank', 'ParentId', 'Id', 'AnnualRevenue', 'Account', 'ContactPointAddress', 'SUM', null, null);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @isTest
  static void shouldNotAddToExistingAmountForFullRecalc() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 60;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneExisting', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoExisting', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Test.startTest();
    Rollup.performFullRecalculation('PreferenceRank', 'ParentId', 'Id', 'AnnualRevenue', 'Account', 'ContactPointAddress', 'SUM', null, null);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  // also an integration test for querying relationship names
  // on CalcItemWhereClause__c Rollup__mdt field
  @isTest
  static void shouldSuccessfullyExcludeBasedOnWhereCriteriaDuringFullRecalc() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Test.startTest();
    Rollup.performFullRecalculation(
      'PreferenceRank',
      'ParentId',
      'Id',
      'AnnualRevenue',
      'Account',
      'ContactPointAddress',
      'SUM',
      'Parent.Name != \'' +
      acc.Name +
      '\'',
      null
    );
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(acc.AnnualRevenue, updatedAcc.AnnualRevenue, 'Account should not have been updated based on exclusion criteria');
  }

  @isTest
  static void shouldRunSyncWhenFlaggedOnRollupLimit() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1), new ContactPointAddress(PreferenceRank = 1) };

    DMLMock mock = loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup');

    //sepcifically do NOT wrap in Test.startTest() / Test.stopTest() - we need to ensure this happened synchronously
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated sync calc');
  }

  @isTest
  static void shouldCorrectlyReparentWhenBothParentsArePartOfRollup() {
    // Happy path - all items in memory
    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account oldAcc = new Account(AnnualRevenue = 300, Name = 'AnotherRollupTest');
    insert oldAcc;
    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    ContactPointAddress reparentedCpa = new ContactPointAddress(
      Id = generateId(ContactPointAddress.SObjectType),
      PreferenceRank = oldAcc.AnnualRevenue.intValue(),
      ParentId = acc.Id
    );
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cpa, reparentedCpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 25),
      reparentedCpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue())
    };

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE, ' + mock.Records);
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(325, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals(0, updatedOldAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @isTest
  static void shouldCorrectlyReparentWhenOnlyNewParentIsPartOfRollup() {
    // Unhappy path - query for related rows
    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account oldAcc = new Account(AnnualRevenue = 25, Name = 'AnotherRollupTest');
    insert oldAcc;

    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue())
    };

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE, ' + mock.Records);
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      cpa.PreferenceRank,
      updatedAcc.AnnualRevenue,
      'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one'
    );
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals(0, updatedOldAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @isTest
  static void shouldCorrectlyReparentForStrings() {
    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account oldAcc = new Account(Name = 'Something');
    insert oldAcc;
    Rollup.defaultControl = null;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Y', Id = generateId(ContactPointAddress.SObjectType))
    };

    DMLMock mock = loadMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    ContactPointAddress firstCpa = testCpas[0].clone(true, true);
    ContactPointAddress secondCpa = testCpas[1].clone(true, true);
    secondCpa.ParentId = oldAcc.Id;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ firstCpa.Id => firstCpa, secondCpa.Id => secondCpa };

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Name, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Y', updatedAcc.Name, 'MAX AFTER_UPDATE should take the maximum string');
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals('', updatedOldAcc.Name, 'MAX AFTER_UPDATE should be empty after reparenting');
  }

  @isTest
  static void shouldCorrectlyReparentForCountDistinct() {
    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account oldAcc = new Account(AnnualRevenue = 1, Name = 'Something');
    insert oldAcc;
    Rollup.defaultControl = null;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = generateId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Y', Id = generateId(ContactPointAddress.SObjectType))
    };

    DMLMock mock = loadMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    ContactPointAddress firstCpa = testCpas[0].clone(true, true);
    ContactPointAddress secondCpa = testCpas[1].clone(true, true);
    ContactPointAddress thirdCpa = testCpas[2].clone(true, true);
    thirdCpa.ParentId = oldAcc.Id;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ firstCpa.Id => firstCpa, secondCpa.Id => secondCpa, thirdCpa.Id => thirdCpa };

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated COUNT DISTINCT AFTER_UPDATE reparenting STRING: ' + mock.Records);
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should count only the distinct entries');
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals(0, updatedOldAcc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should be empty after reparenting');
  }

  @isTest
  static void shouldCorrectlyReparentForAverage() {
    Account acc = [SELECT Id FROM Account];

    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account oldAcc = new Account(AnnualRevenue = 50, Name = 'AnotherRollupTest');
    insert oldAcc;

    Rollup.defaultControl = null;

    ContactPointAddress cpa = new ContactPointAddress(Id = generateId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    ContactPointAddress reparentedCpa = new ContactPointAddress(
      Id = generateId(ContactPointAddress.SObjectType),
      PreferenceRank = oldAcc.AnnualRevenue.intValue(),
      ParentId = acc.Id
    );
    DMLMock mock = loadMock(new List<ContactPointAddress>{ cpa, reparentedCpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 0, Id = cpa.Id),
      reparentedCpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue(), Id = reparentedCpa.Id)
    };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE, ' + mock.Records);
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(50, updatedAcc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals(null, updatedOldAcc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  /** Queries */
  @isTest
  static void shouldQueryAllTasks() {
    String queryString = Rollup.getQueryString(Task.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
  }

  @isTest
  static void shouldQueryAllEvents() {
    String queryString = Rollup.getQueryString(Event.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
  }

  /** Re-queueing */
  @isTest
  static void shouldRequeueRollupsWhenQueryLimitsExceeded() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(MaxRollupRetries__c = 100);
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup', MaxQueryRows__c = -1, BatchChunkSize__c = 1);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status, [SELECT Status, JobType FROM AsyncApexJob]);
  }

  @isTest
  static void shouldThrowIfDeferralNotPossible() {
    DMLMock mock = loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(MaxRollupRetries__c = 0);
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup', MaxQueryRows__c = -1, BatchChunkSize__c = 0);

    try {
      Test.startTest();
      Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
      Test.stopTest();
      // a throw should occur within startTest()/stopTest() - the assertion below is uncatchable
      System.assert(false, 'shouldThrowIfDeferralNotPossible should not make it here');
    } catch (Exception ex) {
      System.assertEquals(true, ex.getMessage().contains('Rollup failed to re-queue for'));
      System.assertNotEquals(true, ex.getMessage().contains('shouldThrowIfDeferralNotPossible should not make it here'));
    }
  }

  /** Grandparent rollups */
  @isTest
  static void shouldAllowGrandparentRollups() {
    Account acc = [SELECT Id FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'Parent.Owner.AboutMe'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(cpas[0].Name + ', ' + cpas[1].Name, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  @isTest
  static void shouldAllowGrandparentRollupsFromParent() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60),
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    DMLMock mock = new DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = [SELECT Id, AboutMe FROM User WHERE Id = :acc.OwnerId];
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'What.Owner.AboutMe',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'What.Type = \'Account\''
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(events[0].Subject + ', ' + events[1].Subject, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  @isTest
  static void shouldDeferGrandparentRollupSafelyTillAllParentRecordsAreRetrieved() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(AccountId = acc.Id, Name = 'One', CloseDate = System.today(), StageName = 'grandParent'),
      new Opportunity(AccountId = acc.Id, Name = 'Two', CloseDate = System.today(), StageName = 'grandParent')
    };
    insert opps;

    DMLMock mock = new DMLMock();
    Rollup.defaultControl = new RollupControl__mdt(MaxQueryRows__c = 2, BatchChunkSize__c = 1, MaxRollupRetries__c = 100);
    // start as synchronous rollup to allow for one deferral
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup', MaxQueryRows__c = 2);
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = opps;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'Account.Owner.AboutMe'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(opps[0].Name + ', ' + opps[1].Name, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  //** Helpers */

  private static DMLMock loadAccountIdMock(List<SObject> records) {
    Account acc = [SELECT Id FROM Account];
    for (SObject record : records) {
      record.put('ParentId', acc.Id);
    }

    return loadMock(records);
  }

  private static DMLMock getTaskMock(List<SObject> records, Id cpaId) {
    for (SObject task : records) {
      task.put('WhatId', cpaId);
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
    flowInput.lookupFieldOnCalcItem = 'ParentId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = rollupContext;
    flowInput.rollupFieldOnCalcItem = 'PreferenceRank';
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
