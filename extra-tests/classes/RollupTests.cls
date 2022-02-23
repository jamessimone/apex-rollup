@IsTest
private class RollupTests {
  static Object testPriorVal;
  static Rollup.Op testOp;
  static SObjectField testOpFieldOnCalcItem;
  static SObjectField testOpFieldOnLookupObject;
  static Rollup__mdt testMetadata;
  static String testLookupRecordKey;
  static SObjectField testLookupKeyField;
  static Rollup.Op rollupOp;
  static Boolean calcMockWasCalled = false;

  @SuppressWarnings('apex-assist')
  @TestSetup
  static void setup() {
    // in the event that rollups are running in the org, we want to avoid triggering any operations while performing setup DML
    Account acc = new Account(Name = 'RollupTests');
    insert acc;
    Contract con = new Contract(Name = 'Datetime tests', AccountId = acc.Id);
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'RollupTestsCpa');
    insert new List<SObject>{ con, cpa };
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

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

  public class RollupCalcMock extends RollupCalculator {
    // everything is a no-op
    public RollupCalcMock() {
      super(0, rollupOp, null, null, null, new Rollup__mdt(), null, null);
      calcMockWasCalled = true;
    }
  }

  /** Trigger tests */

  @IsTest
  static void shouldNotRunForInvalidApexContext() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.BEFORE_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(true, mock.Records.isEmpty(), 'Records should not have been set or updated, this is a no-op');
  }

  @IsTest
  static void shouldNotRunWhenDisabled() {
    RollupSettings__c existingSetting = [SELECT Id, IsEnabled__c FROM RollupSettings__c];
    existingSetting.IsEnabled__c = false;
    update existingSetting;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(true, mock.Records.isEmpty(), 'Records should not have been set or updated, custom setting was disabled');
  }

  @IsTest
  static void shouldRunSyncForSingleRecordWhenControlRecordFlagged() {
    RollupControl__mdt defaultControl = RollupControl__mdt.getInstance(Rollup.CONTROL_ORG_DEFAULTS).clone();
    defaultControl.ShouldRunSingleRecordsSynchronously__c = true;
    Rollup.defaultControl = defaultControl;
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    // specifically don't wrap in start/stopTest to prove it ran sync
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();

    System.assertNotEquals(true, mock.Records.isEmpty(), 'Account should have been updated sync');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(50, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldSumFromTriggerAfterInsert() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
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

  @IsTest
  static void shouldTakeDefaultForSumWhenGiven() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
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

  @IsTest
  static void shouldSumFromTriggerAfterUndelete() {
    // undelete should behave the same as an insert, for our purposes
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
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

  @IsTest
  static void shouldSumFromTriggerAfterUpdate() {
    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, PreferenceRank = 25, Id = cpa.Id) };

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(25, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @IsTest
  static void shouldSumFromTriggerBeforeDelete() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated SUM BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-100, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE should subtract the current amount from the pre-existing one');
  }

  @IsTest
  static void shouldCountDistinctFromTriggerOnInsert() {
    Account acc = [SELECT Id FROM Account];
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert', ParentId = acc.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Test Count Distinct Insert Two') }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should simply add unique values');
  }

  @IsTest
  static void shouldCountDistinctFromTriggerOnUpdate() {
    Account acc = [SELECT Id FROM Account];
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert One', ParentId = acc.Id);

    ContactPointAddress cpa = new ContactPointAddress(Name = 'Test Count Distinct Insert Two', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType));
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
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

  @IsTest
  static void shouldCountDistinctFromTriggerOnDelete() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc; // we want to ensure that the AnnualRevenue is reset because there are no other matching values

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress() });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT BEFORE_DELETE should simply decrement');
  }

  @IsTest
  static void shouldCountFromTriggerAfterInsert() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated');
  }

  @IsTest
  static void shouldDecrementCountFromTriggerAfterUpdateIfValueIsRemoved() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType));
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE should decrement when field is removed');
  }

  @IsTest
  static void shouldKeepCountUnchangedFromTriggerAfterUpdateEvenIfValueChanges() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated COUNT AFTER_UPDATE');
  }

  @IsTest
  static void shouldDecrementCountFromTriggerBeforeDeleteIfValueIsRemoved() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 9;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should not have been populated COUNT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(acc.AnnualRevenue - 1, updatedAcc.AnnualRevenue, 'COUNT BEFORE_DELETE should decrement when field is removed');
  }

  @IsTest
  static void shouldNotCountNullValues() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress() });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated when empty COUNT AFTER_INSERT');
  }

  @IsTest
  static void shouldRunSumFromTriggerBasedOnMetadata() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
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

  @IsTest
  static void shouldRunRegardlessOfMetadataCasing() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
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

  @IsTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadata() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
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

  @IsTest
  static void shouldOverrideStringBasedDefaultBasedOnMetadata() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') });
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
  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEquals() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'RollupZ'), new ContactPointAddress(Name = 'RollupZZ') }
    );
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

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEqualsNonDestructively() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{
        new ContactPointAddress(Name = 'RollupZ', PreferenceRank = 2),
        new ContactPointAddress(Name = 'RollupZZ', PreferenceRank = 1)
      }
    );

    Rollup__mdt firstMeta = new Rollup__mdt(
      RollupFieldOnCalcItem__c = 'Name',
      LookupObject__c = 'Account',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'Name',
      RollupOperation__c = 'MAX',
      CalcItemWhereClause__c = 'Name = \'RollupZ\'',
      CalcItem__c = 'ContactPointAddress'
    );

    Rollup__mdt secondMeta = new Rollup__mdt(
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupObject__c = 'Account',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      RollupOperation__c = 'SUM',
      CalcItem__c = 'ContactPointAddress'
    );

    Rollup.rollupMetadata = new List<Rollup__mdt>{ firstMeta, secondMeta };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on exclusion metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('RollupZ', updatedAcc.Name, 'MAX AFTER_INSERT should ignore excluded items');
    System.assertEquals(3, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void shouldResetRollupValueWhenNoItemsMatchAndToggleIsSupplied() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 50;
    update acc;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'RollupZ', ParentId = acc.Id, PreferenceRank = 50) }
    );

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
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'Full record set flag should force empty match set to still update lookup item');
  }

  @IsTest
  static void shouldRunMultipleOperationsWhenMoreMetadataIsPresent() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
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

  @IsTest
  static void shouldBatchTwoOperations() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100) });
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

  @IsTest
  static void shouldBatchThreeOperations() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 100, Name = 'My test name') }
    );
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

  @IsTest
  static void shouldMaxNumbersSuccessfullyAfterInsert() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(200, updatedAcc.AnnualRevenue, 'MAX AFTER_INSERT should take the maximum cpaortunity amount');
  }

  @IsTest
  static void shouldMaxNumbersSuccessfullyAfterUpdate() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
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

  @IsTest
  static void shouldMaxNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(new List<ContactPointAddress>{ cpa });
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(secondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa PreferenceRank');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank + 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMaxAndNoOtherSObjectsExist() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = acc.AnnualRevenue.intValue(),
      ParentId = acc.Id,
      Name = 'testCpa',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      PreferenceRank = 175,
      ParentId = acc.Id,
      Name = 'testCpaTwo',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
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
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpaortunity amount');
  }

  @IsTest
  static void shouldMaxNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 250, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(originalCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'MAX BEFORE_DELETE should take the maximum cpaortunity amount');
  }

  @IsTest
  static void shouldMinNumbersSuccessfullyAfterInsert() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'MIN AFTER_INSERT should take the minimum cpaortunity amount');
  }

  @IsTest
  static void shouldMinNumbersSuccessfullyAfterUpdate() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
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

  @IsTest
  static void shouldMinNumbersSuccessfullyAfterUpdateWhenUpdatedItemIsNoLongerMin() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 200;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(new List<ContactPointAddress>{ cpa });
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum cpaortunity amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMin() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = secondCpa.PreferenceRank + 50; // the amount isn't important - that it's now more than the second CPA PreferenceRank is
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa };
    Rollup.records = cpas;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMinAndNoOtherSObjectsExist() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = acc.AnnualRevenue.intValue(),
      ParentId = acc.Id,
      Name = 'testCpa',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      PreferenceRank = 175,
      ParentId = acc.Id,
      Name = 'testCpaTwo',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
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
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(updatedSecondCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @IsTest
  static void shouldMinNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>(Rollup.records);
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(175, updatedAcc.AnnualRevenue, 'MIN BEFORE_DELETE should take the minimum cpaortunity amount');
  }

  @IsTest
  static void shouldConcatOnUpdate() {
    // AFTER_INSERT test is handled in the "shouldBatchThreeOperations" method
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = 'second test string',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldCpa.Id => oldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpa.Name, updatedAcc.AccountNumber, 'CONCAT AFTER_UPDATE should replace the old string value with the new');
  }

  @IsTest
  static void shouldConcatOnDelete() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning test string something';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'test string');
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('beginning something', updatedAcc.AccountNumber, 'CONCAT BEFORE_DELETE should replace the outgoing string value with empty string');
  }

  @IsTest
  static void shouldSortConcatStringWithCustomOptions() {
    Account acc = [SELECT Id, Name FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'a', PreferenceRank = 1);
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = acc.Id, Name = 'b', PreferenceRank = 0);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, cpaTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType, null, null, new List<RollupOrderBy__mdt>{
      new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank', SortOrder__c = RollupMetaPicklists.SortOrder.Ascending, Ranking__c = 0)
    }).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('b, a', updatedAcc.AccountNumber, 'Should have been sorted according to rollup order bys');
  }

  @IsTest
  static void shouldConcatDistinctOnInsert() {
    ContactPointAddress cpa = new ContactPointAddress(Name = 'test string');
    ContactPointAddress secondCpa = new ContactPointAddress(Name = 'hello another string');
    ContactPointAddress thirdCpa = cpa.clone(true, true);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa, thirdCpa });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('hello another string, test string', updatedAcc.AccountNumber, 'CONCAT_DISTINCT AFTER_INSERT should only add unique values');
  }

  @IsTest
  static void shouldConcatDistinctOnUpdate() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = 'second test string',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = 'third test string',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;
    ContactPointAddress secondoldCpa = secondCpa.clone(true, true);
    secondoldCpa.Name = acc.AccountNumber;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa });
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

  @IsTest
  static void shouldConcatDistinctOnUpdateWhereOnlyNewItemIsAdded() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string again';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = acc.AccountNumber,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondCpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = 'third test string',
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress secondoldCpa = secondCpa.clone(true, true);
    secondoldCpa.Name = 'some other string';

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa });

    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => cpa, secondoldCpa.Id => secondoldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      'first test string again, third test string',
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should be the distinct combo of the old and new strings'
    );
  }

  @IsTest
  static void shouldProperlyShortCircuitOnConcatDistinctDeleteWhenDistinctValueStillPresentOnOtherItem() {
    Account acc = [SELECT Id, Name FROM Account];
    String originalAccountName = acc.Name;
    String somethingElse = 'Something else';
    acc.Name = acc.Name + ', ' + somethingElse;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Name = originalAccountName, ParentId = acc.Id, PreferenceRank = 0);
    ContactPointAddress toDelete = new ContactPointAddress(Name = originalAccountName, ParentId = acc.Id, PreferenceRank = 1);
    ContactPointAddress toDeleteTwo = new ContactPointAddress(Name = somethingElse, ParentId = acc.Id, PreferenceRank = 2);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa, toDelete, toDeleteTwo };
    insert cpas;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ toDelete, toDeleteTwo });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Name, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Account should be updated CONCAT_DISTINCT delete');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(originalAccountName, updatedAcc.Name);
  }

  @IsTest
  static void shouldMaxOnStringsOnInsert() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.AccountNumber, 'MAX AFTER_INSERT should take the maximum string');
  }

  @IsTest
  static void shouldMaxStringsWhenDefaultIsGiven() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType, 'ZZZ').runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('ZZZ', updatedAcc.AccountNumber, 'MAX AFTER_INSERT should take the maximum string including default');
  }

  @IsTest
  static void shouldMinOnStringsOnInsert() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A'), new ContactPointAddress(Name = 'Z') };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_INSERT STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MIN AFTER_INSERT should take the minimum string');
  }

  @IsTest
  static void shouldMinOnStringsOnUpdate() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'B', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(Name = 'A', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
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

  @IsTest
  static void shouldMaxOnStringsOnUpdate() {
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = '', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(Name = 'A', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(testCpas);

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('A', updatedAcc.AccountNumber, 'MAX AFTER_UPDATE should take the maximum string');
  }

  @IsTest
  static void shouldMinOnStringsBeforeDelete() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'A', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpas[0].Id => new ContactPointAddress(Id = testCpas[0].Id, Name = 'A') };

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE STRING');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('', updatedAcc.AccountNumber, 'MIN BEFORE_DELETE should take the minimum string');
  }

  @IsTest
  static void shouldMaxOnStringsBeforeDelete() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(Name = 'Z', ParentId = acc.Id);
    insert cpa;
    // ensure that if any automation has changed the name, we keep track of it
    cpa = [SELECT Name FROM ContactPointAddress WHERE Id = :cpa.Id];

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'A', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
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

  @IsTest
  static void shouldMaxOnPicklistStringsOnInsert() {
    List<PicklistEntry> picklistVals = Lead.LeadSource.getDescribe().getPicklistValues();

    if (picklistVals.size() < 2) {
      return; // sorry
    }

    Account acc = [SELECT Id FROM Account];

    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Max Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Max Picklist on insert two')
    };
    insert leads; // not the best, either, but we need to be able to use SOQL below

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(leads);
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

  @IsTest
  static void shouldMinPicklistStringsOnInsert() {
    List<PicklistEntry> picklistVals = Lead.LeadSource.getDescribe().getPicklistValues();

    if (picklistVals.size() < 2) {
      return; // sorry
    }

    Account acc = [SELECT Id FROM Account];

    List<Lead> leads = new List<Lead>{
      new Lead(Company = acc.Id, LeadSource = picklistVals[0].getValue(), LastName = 'Min Picklist on insert one'),
      new Lead(Company = acc.Id, LeadSource = picklistVals[1].getValue(), LastName = 'Min Picklist on insert two')
    };
    insert leads;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(leads);
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

  @IsTest
  static void shouldAverageOnInsert() {
    // average is a special case; even on insert, we have to also check for pre-existing records existing
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
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

  @IsTest
  static void shouldAverageOnUpdate() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 100;
    update acc;

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 200000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
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

  @IsTest
  static void shouldAverageOnDelete() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 200;
    update acc;

    ContactPointAddress testCpaOne = new ContactPointAddress(PreferenceRank = 100, Name = 'Pre-existing one', ParentId = acc.Id);
    ContactPointAddress testCpaTwo = new ContactPointAddress(PreferenceRank = 300, Name = 'Pre-existing two', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ testCpaOne, testCpaTwo };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ testCpaTwo };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpaOne.Id => testCpaOne };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(testCpaOne.PreferenceRank, updatedAcc.AnnualRevenue, 'AVERAGE BEFORE_DELETE should take into account only non-deleted values');
  }

  @IsTest
  static void shouldRollupForFirst() {
    rollupOp = Rollup.Op.FIRST;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today()) });
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

  @IsTest
  static void shouldRollupForLast() {
    rollupOp = Rollup.Op.LAST;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today()) });
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

  @IsTest
  static void shouldPassRecalcValueForAverage() {
    rollupOp = Rollup.Op.AVERAGE;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5)
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForCountDistinct() {
    rollupOp = Rollup.Op.COUNT_DISTINCT;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5)
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForConcatDistinct() {
    rollupOp = Rollup.Op.CONCAT_DISTINCT;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 'a')
      .runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForConcat() {
    rollupOp = Rollup.Op.CONCAT;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 'a')
      .runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForCount() {
    rollupOp = Rollup.Op.COUNT;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5).runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForFirst() {
    rollupOp = Rollup.Op.FIRST;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.firstFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType,
        5,
        'ParentId'
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForLast() {
    rollupOp = Rollup.Op.LAST;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.lastFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5, 'ParentId')
      .runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  @IsTest
  static void shouldPassRecalcValueForMin() {
    rollupOp = Rollup.Op.MIN;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType, 5).runCalc();
    Test.stopTest();

    System.assertEquals(5, testMetadata.FullRecalculationDefaultNumberValue__c);
  }

  // Now we test different field types for success: time, datetime, date. Here be dragons.
  @IsTest
  static void shouldMaxDateOnInsert() {
    ContactPointAddress cpa = new ContactPointAddress(Name = 'Max date on insert test');
    insert cpa;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = cpa.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = cpa.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.getTaskMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATE AFTER_INSERT');
    ContactPointAddress updatedCpa = (ContactPointAddress) mock.Records[0];
    System.assertEquals(taskTwo.ActivityDate, updatedCpa.ActiveFromDate);
  }

  @IsTest
  static void shouldMinDateOnInsert() {
    ContactPointAddress cpa = new ContactPointAddress(Name = 'Min date on insert test');
    insert cpa;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getTaskMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    ContactPointAddress updatedCpa = (ContactPointAddress) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCpa.ActiveFromDate);
  }

  @IsTest
  static void shouldMinDateOnInsertWhereParentDateIsNull() {
    //using campaign for this test because EndDate is not required when inserting a Campaign
    Campaign camp = new Campaign(Name = 'Test Date with no initialized value');
    insert camp;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50), WhatId = camp.Id);
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50), WhatId = camp.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Task>{ taskOne, taskTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, Campaign.Id, Campaign.EndDate, Campaign.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Campaign updatedCamp = (Campaign) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCamp.EndDate);
  }

  @IsTest
  static void shouldMinDateOnUpdate() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Contact con = new Contact(LastName = 'Min date on insert test', BirthDate = System.today());
    insert con;

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = con.BirthDate.addDays(-50), WhoId = con.Id);
    insert taskOne;
    Rollup.defaultControl = null;

    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = con.BirthDate.addDays(5), Id = RollupTestUtils.createId(Task.SObjectType), WhoId = con.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.getTaskMock(new List<Task>{ taskTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Task>(new List<Task>{ new Task(Id = taskTwo.Id, ActivityDate = con.BirthDate) });

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhoId, Contact.Id, Contact.BirthDate, Contact.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    Contact updatedCon = (Contact) mock.Records[0];
    System.assertEquals(taskOne.ActivityDate, updatedCon.BirthDate);
  }

  @IsTest
  static void shouldMaxDatetimeOnInsert() {
    Contract con = [SELECT Id FROM Contract];

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50), WhatId = con.Id);
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50), WhatId = con.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_INSERT');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnInsert() {
    Contract con = [SELECT Id FROM Contract];

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50), WhatId = con.Id);
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50), WhatId = con.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne, eventTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_INSERT');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventOne.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnUpdate() {
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    // now the "new" version of eventOne is no longer the min
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne, eventTwo });
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

  @IsTest
  static void shouldMaxDatetimeOnUpdate() {
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    // now the "new" version of eventOne is no longer the max
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne, eventTwo });
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

  @IsTest
  static void shouldMaxDatetimeOnDelete() {
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME BEFORE_DELETE');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(eventTwo.ActivityDateTime, updatedContract.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnDelete() {
    Contract con = [SELECT Id FROM Contract];
    con.ActivatedDate = System.now();
    update con;

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate, WhatId = con.Id, Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-50), WhatId = con.Id, DurationInMinutes = 50);
    insert eventTwo;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Event>{ eventOne });
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

  @IsTest
  static void shouldMinTimeOnInsert() {
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1, cp2 });
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

  @IsTest
  static void shouldMaxTimeOnInsert() {
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', EmailAddress = 'testrollup' + System.now().getTime() + '@email.com');
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(11, 11, 11, 11), Name = cpe.EmailDomain);
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = cpe.EmailDomain);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1, cp2 });
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

  @IsTest
  static void shouldMaxTimeOnUpdate() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6),
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1, cp2 });

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

  @IsTest
  static void shouldMinTimeOnUpdate() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6),
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1, cp2 });

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

  @IsTest
  static void shouldMinTimeOnDelete() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = cpe.BestTimeToContactEndTime,
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(6, 6, 6, 6), Name = cpe.EmailDomain);
    insert cp2;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1 });

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

  @IsTest
  static void shouldMaxTimeOnDelete() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      EmailDomain = 'Lookupfield',
      EmailAddress = 'testrollup' + System.now().getTime() + '@email.com'
    );
    insert cpe;

    ContactPointAddress cp1 = new ContactPointAddress(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      Name = cpe.EmailDomain,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    ContactPointAddress cp2 = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(4, 4, 4, 4), Name = cpe.EmailDomain);
    insert cp2;

    List<ContactPointAddress> addresses = new List<ContactPointAddress>{ cp1 };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cp1 });

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

  /** CDC trigger tests */

  @IsTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnCreate() {
    // CDC functions ** nearly ** the same as regular triggers, yet the SObjects supplied to ChangeEventTriggers
    // differ in two subtle ways: not all the fields are populated (just the changed ones), and the reference info
    // is supplied on a separate object, the ChangeEventHeader
    // Unfortunately, these two "tiny" differences means a lot of other code needs to be tested
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc', ParentId = acc.Id);
    insert cpa;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'CREATE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = 500;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.records = new List<ContactPointAddressChangeEvent>{ ev };
    Rollup.shouldRun = true;

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

  @IsTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnUpdate() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc update', ParentId = acc.Id);
    insert cpa;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'UPDATE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = 500;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.records = new List<ContactPointAddressChangeEvent>{ ev };
    Rollup.shouldRun = true;

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

  @IsTest
  static void shouldWorkForChangeDataCaptureTriggersOnDelete() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 10000;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc update', ParentId = acc.Id);
    insert cpa;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'DELETE';
    header.changedFields = new List<String>{ 'PreferenceRank', 'LastModifiedDate' };
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';

    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent();
    ev.ChangeEventHeader = header;
    ev.PreferenceRank = cpa.PreferenceRank;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.records = new List<ContactPointAddressChangeEvent>{ ev };
    Rollup.shouldRun = true;

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

  @IsTest
  static void shouldBeInvokedSuccessfullyAfterInsertFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank');
  }

  @IsTest
  static void shouldSplitConcatCalcItemsFromFlow() {
    Account acc = [SELECT Id FROM Account];
    acc.Name = 'CDC';
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'CDC, GDG', ParentId = acc.Id),
      new ContactPointAddress(Name = 'CDC, GDG', ParentId = acc.Id)
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'CONCAT_DISTINCT');
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';
    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'CONCAT_DISTINCT AFTER_INSERT from flow did not update account');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpas[0].Name, updatedAcc.Name, 'CONCAT_DISTINCT should have split on calc item values!');
  }

  @IsTest
  static void shouldBeInvokedRegardlessOfCasingFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'insert', 'sum'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'sum AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'sum AFTER_INSERT from flow should match input PreferenceRank');
  }

  @IsTest
  static void shouldBeInvokedSuccessfullyAfterSaveFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250)
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(750, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @IsTest
  static void shouldAllowForSuccessiveInvocablesToBeCalledInSameTransaction() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'distinct'),
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'again')
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Account reparentedAcc = new Account(Name = 'ReparentMultipleDMLInvocableRollup');
    insert reparentedAcc;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].deferProcessing = true;
    Rollup.performRollup(flowInputs);

    Rollup.FlowInput flowInput = flowInputs[0];
    flowInput.rollupFieldOnCalcItem = 'Name';
    flowInput.rollupFieldOnOpObject = 'Description';
    flowInput.rollupOperation = 'CONCAT_DISTINCT';
    Rollup.performRollup(flowInputs);

    // now that the inserts have been queued, let's do the updates
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>(cpas);
    cpas[0].ParentId = reparentedAcc.Id;
    flowInput.rollupContext = 'UPDATE';
    Rollup.performRollup(flowInputs);
    flowInput.rollupOperation = 'SUM';
    flowInput.rollupFieldOnCalcItem = 'PreferenceRank';
    flowInput.rollupFieldOnOpObject = 'Description';
    Rollup.performRollup(flowInputs);

    // simulate multiple DML situations
    Test.startTest();
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Enqueued rollups did not properly update old account and reparented Account');
    Account updatedReparentAcc = (Account) mock.Records[0];
    System.assertEquals(cpas[0].Name, updatedReparentAcc.Description);
    System.assertEquals(cpas[0].PreferenceRank, updatedReparentAcc.AnnualRevenue);

    Account updatedAcc = (Account) mock.Records[1];
    System.assertNotEquals(updatedAcc.Id, reparentedAcc.Id);
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
    System.assertEquals(cpas[1].Name, updatedAcc.Description, 'CONCAT_DISTINCT AFTER_UPDATE from flow should match diff for reparented Name');
  }

  @IsTest
  static void shouldThrowValidationErrorOnUpdateFromFlowIfNoOldCalcItems() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Prior records to rollup collection required for rollup context: UPDATE', ex.getMessage());
  }

  @IsTest
  static void shouldThrowValidationErrorOnUpsertFromFlowIfNoOldCalcItems() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPSERT', 'SUM');

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Prior records to rollup collection required for rollup context: UPSERT', ex.getMessage());
  }

  @IsTest
  static void shouldGracefullyExitIfCalcItemsAreNull() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(null, 'INSERT', 'CONCAT');

    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);

    System.assertEquals(1, flowOutputs.size());
    System.assertEquals('No records to rollup, returning early', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotCount() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 2;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'Count Non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 1, Name = 'Count match', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, matchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'COUNT');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE from flow should correctly perform full recalc');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotCountDistinct() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 3;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'Count Non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 1, Name = 'Count distinct match', ParentId = acc.Id);
    ContactPointAddress secondMatchingCpa = matchingCpa.clone();
    secondMatchingCpa.Name = 'Second Count Distinct Match';
    insert new List<ContactPointAddress>{ cpa, matchingCpa, secondMatchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'COUNT_DISTINCT');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT_DISTINCT AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE from flow should correctly perform full recalc');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotSum() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 18;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 2, Name = 'Sum non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 15, Name = 'sum match', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, matchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 3)
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(matchingCpa.PreferenceRank, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotFirst() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'First', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'FIRST');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'FIRST AFTER_UPDATE from flow should get nulled out if no other matching items');
  }

  @IsTest
  static void shouldUpdateToActualFirstIfCurrentItemShouldBeExcludedAndOldOneWouldNot() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress nullPrefRankCpa = new ContactPointAddress(PreferenceRank = null, Name = 'Null pref', ParentId = acc.Id);
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'First', ParentId = acc.Id);
    ContactPointAddress cpaTwo = new ContactPointAddress(PreferenceRank = 1, Name = 'Second', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, cpaTwo, nullPrefRankCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa }; // only pass cpa, which would be excluded normally (except for the PreferenceRank being set below to another val)
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'FIRST');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'Name descending nulls last, PreferenceRank';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpaTwo.PreferenceRank, updatedAcc.AnnualRevenue, 'FIRST AFTER_UPDATE from flow should correctly recalculate and exclude current item');
  }

  @IsTest
  static void shouldProperlyDeleteFirstIfCurrentItemIsOnlyItemAndItIsExcluded() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'First Delete', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank.format();
    flowInputs[0].orderByFirstLast = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST BEFORE_DELETE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'FIRST BEFORE_DELETE from flow should correctly null out');
  }

  @IsTest
  static void shouldProperlyDeleteForAverageIfCurrentItemIsOnlyItemAndItIsExcluded() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Average Delete', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'AVERAGE');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank.format();

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'AVERAGE AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'AVERAGE BEFORE_DELETE from flow should correctly null out');
  }

  @IsTest
  static void shouldBeInvokedSuccessfullyBeforeDeleteFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM BEFORE_DELETE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1000, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE from flow should subtract PreferenceRank from Account');
  }

  @IsTest
  static void shouldExcludeNonLinkedItemsAndUseCalcItemWhereClause() {
    Account acc = [SELECT Id FROM Account];
    Date today = System.today();
    // create a cpa not linked to the parent account with a higher PreferenceRank
    insert new ContactPointAddress(PreferenceRank = 1, ActiveFromDate = today.addDays(-1), Name = 'non-match on account');
    // inserting the both of these at the same time caused a gack, and I have no idea why ... so singular inserts it is!
    insert new ContactPointAddress(PreferenceRank = 0, ActiveFromDate = today.addDays(-1), ParentId = acc.Id, Name = 'Non match on where clause');

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = 5,
      ActiveFromDate = today,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'ActiveFromDate';

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Updated account should have been loaded FIRST AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpa.PreferenceRank, updatedAcc.AnnualRevenue, 'Only linked items should be used');
  }

  @IsTest
  static void shouldReportErrorWhenUltimateParentRollupAndNoLookupField() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].rollupToUltimateParent = true;

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Rollup To Ultimate Parent and Ultimate Parent Lookup must both be set for hierarchical rollups', ex?.getMessage());
  }

  @IsTest
  static void shouldReportErrorWhenConcatDelimiterSetAndNotConcat() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].concatDelimiter = ';';

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Concat delimiter should only be supplied for CONCAT-based rollups.', ex?.getMessage());
  }

  @IsTest
  static void shouldReportErrorWhenConcatOptionSetAndNotConcat() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Concat options should only be set for CONCAT_DISTINCT operations', ex?.getMessage());
  }

  @IsTest
  static void shouldReportErrorWhenBothOverridesSet() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].fullRecalculationDefaultNumberValue = 1;
    flowInputs[0].fullRecalculationDefaultStringValue = 'someValue';

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Only one override - the default string value or number value - can be supplied for each rollup', ex?.getMessage());
  }

  @IsTest
  static void shouldStillPerformRollupForFirstLastEvenIfCurrentCalcItemsDoNotMatch() {
    Account acc = [SELECT Id FROM Account];
    Date today = System.today();

    // the important part here is that this one SHOULDN'T be first if the passed in calc item is not winnowed properly
    insert new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = today.addDays(1), ParentId = acc.Id, Name = 'match on where clause');

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = 0,
      ActiveFromDate = today,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'ActiveFromDate';

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Updated account should have been loaded FIRST AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(5, updatedAcc.AnnualRevenue, 'Queried item should be found and used even if calc item where clause filters out current iterations');
  }

  // integration test for "ChangedFieldsOnCalcItem__c" being properly constructed
  @IsTest
  static void shouldOnlyIncludeObjectChangedFieldsWhenSuppliedFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Name = 'Acme cpa', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 500, Name = 'Test name changed cpa', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].calcItemChangedFields = 'Name, IsDefault';
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250, Name = cpas[0].Name),
      new ContactPointAddress(ParentId = cpas[1].ParentId, Id = cpas[1].Id, PreferenceRank = 200, Name = 'Name that does not match')
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
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

  @IsTest
  static void shouldReportSuccessWhenFlowPassesNoRecords() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>();
    Rollup.shouldRun = true;
    Rollup.records = cpas;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldReportFailureWhenExceptionIsThrown() {
    List<ContactPointAddressHistory> history = new List<ContactPointAddressHistory>{ new ContactPointAddressHistory() };
    Rollup.shouldRun = true;

    Exception ex;
    Test.startTest();
    // RollupTestUtils.prepareFlowTest sets us up for a failure with a field that doesn't exist on ContactPointAddressHistory
    try {
      Rollup.performRollup(RollupTestUtils.prepareFlowTest(history, 'INSERT', 'SUM'));
    } catch (Exception e) {
      ex = e;
    }
    Test.stopTest();

    System.assertEquals('Invalid field PreferenceRank for ContactPointAddressHistory', ex.getMessage(), ex.getMessage() + '\n' + ex.getStacktraceString());
  }

  @IsTest
  static void shouldNotThrowErrorEvenIfNoRollupsPerformedDuringInvocable() {
    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(new List<SObject>(), 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size());
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldCountOnNonIdField() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Test') };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'COUNT');
    flowInputs[0].rollupFieldOnCalcItem = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadataForFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultNumberValue = -1001;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank + number override');
  }

  @IsTest
  static void shouldOverrideDateUsingNumberBasedDefaultForFlow() {
    Contract con = [SELECT Id FROM Contract];

    Datetime nowish = System.now();

    // it only matters that the amount below is LESS than the above value, and that "nowish" is assigned to the fullRecalculationDefaultNumberValue flow input value
    List<Event> events = new List<Event>{ new Event(ActivityDateTime = nowish.addDays(-2), WhatId = con.Id) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(events);
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

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'MAX AFTER_INSERT from flow with override date did not update accounts');
    Contract updatedContract = (Contract) mock.Records[0];
    System.assertEquals(nowish, updatedContract.ActivatedDate, 'MAX AFTER_INSERT from flow should match override date');
  }

  @IsTest
  static void shouldOverrideStringBasedDefaultForFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultStringValue = 'Z';
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.Name, 'SUM AFTER_INSERT from flow should match string override when it is greater than supplied calc values');
  }

  @IsTest
  static void shouldNotWriteToNonUpdateableFieldsForOldFlowRecords() {
    Account acc = [SELECT Id FROM Account];

    Event ev = new Event(ActivityDateTime = System.now().addDays(-2), WhatId = acc.Id);

    // a useful hack for assigning values to unwriteable fields ...
    Map<String, Object> deserializedEvent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(ev));
    deserializedEvent.put('AccountId', null);
    ev = (Event) JSON.deserialize(JSON.serialize(deserializedEvent), Event.class);

    List<Event> events = new List<Event>{ ev };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(events);
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

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT from flow should not fail when non-writeable fields are present');
  }

  /** Batch test */

  @IsTest
  static void shouldRunSuccessfullyAsBatch() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    RollupAsyncProcessor.shouldRunAsBatch = true;

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

  @IsTest
  static void shouldAbortWhenOrgDefaultsHaveDisabledRunning() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @IsTest
  static void shouldAbortWhenspecificControlDisablesRunning() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldAbortRun__c = true);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Rollup run should have aborted');
  }

  @IsTest
  static void shouldRunAsBatchableWhenSpecificRollupIsBatchable() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Batchable,
      BatchChunkSize__c = 1,
      MaxLookupRowsBeforeBatching__c = 1
    );

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(1, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @IsTest
  static void shouldNotRunAsBatchableWhenDefaultIsBatchableAndRecordsAreLessThanBatchableLimit() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Batchable,
      MaxLookupRowsBeforeBatching__c = 1000,
      BatchChunkSize__c = 50
    );

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(1, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldRunAsQueueableWhenSpecificControlIsQueueable() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldCorrectlyReparentWhenBothParentsArePartOfRollup() {
    // Happy path - all items in memory
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(AnnualRevenue = 300, Name = 'AnotherRollupTest');
    insert oldAcc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    ContactPointAddress reparentedCpa = new ContactPointAddress(
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType),
      PreferenceRank = oldAcc.AnnualRevenue.intValue(),
      ParentId = acc.Id
    );
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa, reparentedCpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 25, Id = cpa.Id),
      reparentedCpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue(), Id = reparentedCpa.Id)
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

  @IsTest
  static void shouldCorrectlyReparentWhenOnlyNewParentIsPartOfRollup() {
    // Unhappy path - query for related rows
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(AnnualRevenue = 25, Name = 'AnotherRollupTest');
    insert oldAcc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue(), Id = cpa.Id)
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

  @IsTest
  static void shouldReparentSameObjectRollups() {
    Rollup.onlyUseMockmetadata = true;
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    Account clearedParent = new Account(AnnualRevenue = 25, Name = 'clear parent same object');
    insert clearedParent;

    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Account>{
      clearedParent.Id => new Account(ParentId = acc.Id, AnnualRevenue = 25, Id = clearedParent.Id)
    };
    Rollup.shouldRun = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Account'
      )
    };
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.records = new List<Account>{ clearedParent };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertNotEquals(0, mock.Records.size());
    Account updatedAcc = (Account) new Map<Id, SObject>(mock.Records).get(acc.Id);
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'Count should have been decremented');
  }

  @IsTest
  static void shouldCorrectlyReparentForStrings() {
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(Name = 'Something');
    insert oldAcc;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Y', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    ContactPointAddress firstCpa = testCpas[0].clone(true, true);
    ContactPointAddress secondCpa = testCpas[1].clone(true, true);
    secondCpa.ParentId = oldAcc.Id;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ firstCpa.Id => firstCpa, secondCpa.Id => secondCpa };

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Name, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE STRING');
    Account updatedAcc = (Account) mock.Records[1];
    System.assertEquals('Y', updatedAcc.Name, 'MAX AFTER_UPDATE should take the maximum string');
    Account updatedOldAcc = (Account) mock.Records[0];
    System.assertEquals('', updatedOldAcc.Name, 'MAX AFTER_UPDATE should be empty after reparenting');
  }

  @IsTest
  static void shouldCorrectlyReparentForStringsCountDistinct() {
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(AnnualRevenue = 1, Name = 'Something');
    insert oldAcc;

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Y', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(testCpas);
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
    for (Account updatedAcc : (List<Account>) mock.Records) {
      if (updatedAcc.Id == acc.Id) {
        System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should count only the distinct entries');
      } else if (updatedAcc.Id == oldAcc.Id) {
        System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should be empty after reparenting');
      }
    }
  }

  @IsTest
  static void shouldCorrectlyReparentForStringCount() {
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(AnnualRevenue = 1, Name = 'Something');
    insert oldAcc;

    // the first two items will be false positives; records whose values haven't changed over the course of the update
    // of interest to us will be the last record, whose ParentId we'll show as the oldAcc's in oldRecordsMap to trigger a
    // reparenting
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'X', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Y', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Z', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(testCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    ContactPointAddress firstCpa = testCpas[0].clone(true, true);
    ContactPointAddress secondCpa = testCpas[1].clone(true, true);
    ContactPointAddress thirdCpa = testCpas[2].clone(true, true);
    thirdCpa.ParentId = oldAcc.Id;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ firstCpa.Id => firstCpa, secondCpa.Id => secondCpa, thirdCpa.Id => thirdCpa };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Records should have been populated COUNT AFTER_UPDATE reparenting STRING: ' + mock.Records);
    for (Account updatedAcc : (List<Account>) mock.Records) {
      if (updatedAcc.Id == acc.Id) {
        System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE should only count updated entries reparented to it');
      } else if (updatedAcc.Id == oldAcc.Id) {
        System.assertEquals(0, updatedAcc.AnnualRevenue, 'Old account should have had its annual revenue decremented');
      }
    }
  }

  @IsTest
  static void shouldCorrectlyReparentForAverage() {
    Account acc = [SELECT Id FROM Account];

    Account oldAcc = new Account(AnnualRevenue = 50, Name = 'AnotherRollupTest');
    insert oldAcc;

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);
    ContactPointAddress reparentedCpa = new ContactPointAddress(
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType),
      PreferenceRank = oldAcc.AnnualRevenue.intValue(),
      ParentId = acc.Id
    );
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa, reparentedCpa });
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
    System.assertEquals(acc.Id, updatedAcc.Id);
    System.assertEquals(50, updatedAcc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
    Account updatedOldAcc = (Account) mock.Records[1];
    System.assertEquals(oldAcc.Id, updatedOldAcc.Id);
    System.assertEquals(null, updatedOldAcc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  /** Re-queueing */
  @IsTest
  static void shouldRequeueRollupsWhenQueryLimitsExceeded() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 1) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(MaxRollupRetries__c = 1, IsRollupLoggingEnabled__c = true, MaxNumberOfQueries__c = 3);
    Rollup.specificControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      MaxLookupRowsBeforeBatching__c = 1,
      BatchChunkSize__c = 1
    );

    Test.startTest();
    Rollup.batch(
      Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType),
      Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
    );
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status, [SELECT Status, JobType FROM AsyncApexJob]);
  }

  /** Grandparent rollups */
  @IsTest
  static void shouldAllowGrandparentRollups() {
    Account acc = [SELECT Id FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
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

  @IsTest
  static void shouldDeferGrandparentRollupSafelyTillAllParentRecordsAreRetrieved() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.defaultControl = new RollupControl__mdt(MaxNumberOfQueries__c = 2, BatchChunkSize__c = 1, MaxRollupRetries__c = 100);
    // start as synchronous rollup to allow for one deferral
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, MaxNumberOfQueries__c = 2);
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

  @IsTest
  static void shouldDeferGrandparentRollupSafelyTillAllParentRecordsAreRetrievedWithBatch() {
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.defaultControl = new RollupControl__mdt(MaxNumberOfQueries__c = 2, BatchChunkSize__c = 1, MaxRollupRetries__c = 100);
    // start as synchronous rollup to allow for one deferral
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, MaxNumberOfQueries__c = 2);
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

  @IsTest
  static void shouldRollupEntireHierarchyWhenEnabled() {
    Account acc = [SELECT Id, Name FROM Account];

    Account childAcc = new Account(ParentId = acc.Id, Name = 'Hierarchy Rollup');
    insert childAcc;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = new List<ContactPointAddress>{ new ContactPointAddress(ParentId = childAcc.Id, Name = 'One') };
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT',
        RollupToUltimateParent__c = true,
        UltimateParentLookup__c = 'ParentId'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Hierarchy record should have been found!');
    Account updatedAccount = (Account) mock.Records[0];
    System.assertEquals(acc.Id, updatedAccount.Id, 'Top-level parent should have been updated: ' + JSON.serialize(updatedAccount));
    // in alphabetical order ...
    System.assertEquals('One' + ', ' + acc.Name, updatedAccount.Name);
  }
}
