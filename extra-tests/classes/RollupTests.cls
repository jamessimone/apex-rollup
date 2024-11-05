@SuppressWarnings('PMD.NcssTypeCount')
@IsTest
private class RollupTests {
  static Rollup.Op testOp;
  static SObjectField testOpFieldOnCalcItem;
  static SObjectField testOpFieldOnLookupObject;
  static Rollup__mdt testMetadata;
  static SObjectField testLookupKeyField;
  static Rollup.Op rollupOp;
  static Boolean calcMockWasCalled = false;

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
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      testOp = op;
      testOpFieldOnCalcItem = opFieldOnCalcItem;
      testOpFieldOnLookupObject = opFieldOnLookupObject;
      testMetadata = metadata;
      testLookupKeyField = lookupKeyField;
      return new RollupCalcMock();
    }
  }

  private class RollupCalcMock extends RollupCalculator {
    // everything is a no-op
    public RollupCalcMock() {
      super(rollupOp, testOpFieldOnCalcItem, Account.AnnualRevenue, new Rollup__mdt(), testLookupKeyField);
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
  static void shouldNotRunWhenCustomSettingDisabled() {
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
  static void ignoresCustomSettingWhenSpecificallyFlagged() {
    RollupSettings__c existingSetting = [SELECT Id, IsEnabled__c FROM RollupSettings__c];
    existingSetting.IsEnabled__c = false;
    update existingSetting;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 50) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress',
        ShouldRunWithoutCustomSettingEnabled__c = true
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertNotEquals(true, mock.Records.isEmpty(), 'Account should have been updated');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(50, acc.AnnualRevenue);
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
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 50);
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
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert', ParentId = acc.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Test Count Distinct Insert Two', ParentId = acc.Id) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_INSERT');
    System.assertEquals(2, acc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should simply add unique values');
  }

  @IsTest
  static void shouldCountDistinctFromTriggerOnUpdate() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
    insert new ContactPointAddress(Name = 'Test Count Distinct Insert One', ParentId = acc.Id);

    ContactPointAddress cpa = new ContactPointAddress(Name = 'Test Count Distinct Insert Two', ParentId = acc.Id);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the important part here is that the old value differs
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Name = 'something different', Id = cpa.Id) };

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT AFTER_UPDATE');
    System.assertEquals(2, acc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should ensure distinct values');
  }

  @IsTest
  static void shouldCountDistinctFromTriggerOnDelete() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ new ContactPointAddress(ParentId = acc.Id) });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.countDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT_DISTINCT BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT BEFORE_DELETE should simply decrement');
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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated COUNT AFTER_UPDATE');
    System.assertEquals(null, acc.AnnualRevenue, 'COUNT AFTER_UPDATE should decrement when field is removed');
  }

  @IsTest
  static void shouldKeepCountUnchangedFromTriggerAfterUpdateEvenIfValueChanges() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated COUNT AFTER_UPDATE');
  }

  @IsTest
  static void countFullRecordSetProperlyFetchesAllMatchingChildren() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 2;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    insert new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 50, Name = 'one', ParentId = acc.Id),
      new ContactPointAddress(PreferenceRank = 50, Name = 'two', ParentId = acc.Id)
    };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 50, ParentId = acc.Id);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.shouldRun = true;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = 1) };
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'PreferenceRank = 50',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        LookupObject__c = 'Account',
        IsFullRecordSet__c = true,
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Account should have been updated');
    System.assertEquals(3, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldDecrementCountFromTriggerBeforeDeleteIfValueIsRemoved() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Decimal originalValue = 9;
    acc.AnnualRevenue = originalValue;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should not have been populated COUNT BEFORE_DELETE');
    System.assertEquals(originalValue - 1, acc.AnnualRevenue, 'COUNT BEFORE_DELETE should decrement when field is removed');
  }

  @IsTest
  static void shouldNotCountNullValues() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress() });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'Records should not have been populated COUNT AFTER_INSERT');
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
    System.assertEquals(100100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should add the original opp amount to the default override based on CMDT');
  }

  @IsTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadataCount() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Decimal originalValue = 1;
    acc.AnnualRevenue = originalValue;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = originalValue.intValue());
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'ContactPointAddress',
        FullRecalculationDefaultNumberValue__c = 0,
        CalcItemWhereClause__c = 'PreferenceRank != ' + cpa.PreferenceRank
      )
    };
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata BEFORE_DELETE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT BEFORE_DELETE should reset to the default override based on CMDT');
  }

  @IsTest
  static void shouldNotDoubleCountOnDecrementForMatches() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Decimal originalValue = 3;
    acc.AnnualRevenue = originalValue;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    Opportunity opp = new Opportunity(AccountId = acc.Id, Amount = 100, Name = 'Will Not Match', CloseDate = System.today().addDays(2), StageName = 'A');
    insert new List<Opportunity>{
      new Opportunity(AccountId = acc.Id, Amount = 1, Name = 'First Match', CloseDate = System.today().addDays(-2), StageName = 'A'),
      new Opportunity(AccountId = acc.Id, Amount = 2, Name = 'Second Match', CloseDate = System.today().addDays(-2), StageName = 'A'),
      opp
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<Opportunity>{ opp });
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Opportunity',
        IsFullRecordSet__c = true,
        CalcItemWhereClause__c = 'CloseDate <= TODAY'
      )
    };
    Opportunity oldOpp = opp.clone(true);
    oldOpp.CloseDate = System.today().addDays(-2);
    Rollup.oldRecordsMap = new Map<Id, SObject>{ opp.Id => oldOpp };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT AFTER_UPDATE should properly decrement when one item is updated to not match');
  }

  @IsTest
  static void shouldOverrideNumberBasedDefaultForNonMatches() {
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
        FullRecalculationDefaultNumberValue__c = 0,
        CalcItemWhereClause__c = 'PreferenceRank != 100'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated based on metadata AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should use the default override even for a non-match');
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
        FullRecalculationDefaultStringValue__c = 'Z',
        IsFullRecordSet__c = true
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
        CalcItemWhereClause__c = 'name = \'RollupZ\'',
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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'IsFullRecordSet__c should force account to reset its rollup value AFTER_INSERT');
    System.assertEquals(null, acc.AnnualRevenue, 'Full record set flag should force empty match set to still update lookup item');
  }

  @IsTest
  static void shouldResetRollupValueWhenIsFullRecordSetAndUpdatedItemNoLongerMatches() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 50;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(Name = 'RollupZ', ParentId = acc.Id, PreferenceRank = 50);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.oldRecordsMap = new Map<Id, SObject>{
      cpa.Id => new ContactPointAddress(Id = cpa.Id, Name = 'something else', ParentId = acc.Id, PreferenceRank = 50)
    };
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
        CalcItem__c = 'ContactPointAddress'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'IsFullRecordSet__c should force non-match to reset its rollup value AFTER_UPDATE');
    System.assertEquals(null, acc.AnnualRevenue, 'Full record set flag should force empty match set to still update lookup item');
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
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT AFTER_INSERT should count when the field is present on the child object based on CMDT');
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
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should count when the field is present on the child object batched');
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
    System.assertEquals(100, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT should count when the field is present on the child object batched');
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
      new ContactPointAddress(PreferenceRank = 100),
      new ContactPointAddress(PreferenceRank = 200)
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
      new ContactPointAddress(PreferenceRank = 100),
      new ContactPointAddress(PreferenceRank = 200)
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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa });
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => cpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    System.assertEquals(secondCpa.PreferenceRank, acc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa PreferenceRank');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 150;
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank + 30; // the amount is really unimportant; that it doesn't match what's in the database is
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa });
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    System.assertEquals(updatedSecondCpa.PreferenceRank, acc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpa amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMaxAndNoOtherSObjectsExist() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa });
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX AFTER_UPDATE');
    System.assertEquals(updatedSecondCpa.PreferenceRank, acc.AnnualRevenue, 'MAX AFTER_UPDATE should take the maximum cpaortunity amount');
  }

  @IsTest
  static void shouldMaxNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 250, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(originalCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.maxFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX BEFORE_DELETE');
    System.assertEquals(null, acc.AnnualRevenue, 'MAX BEFORE_DELETE should take the maximum cpaortunity amount');
  }

  @IsTest
  static void shouldMinNumbersSuccessfullyAfterInsert() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 100),
      new ContactPointAddress(PreferenceRank = 200)
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
      new ContactPointAddress(PreferenceRank = 100),
      new ContactPointAddress(PreferenceRank = 200)
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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = 200;
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa });
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    System.assertEquals(175, acc.AnnualRevenue, 'MIN AFTER_UPDATE should take the minimum cpaortunity amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMin() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    ContactPointAddress updatedCpa = cpa.clone(true, true);
    updatedCpa.PreferenceRank = secondCpa.PreferenceRank + 50; // the amount isn't important - that it's now more than the second CPA PreferenceRank is
    ContactPointAddress updatedSecondCpa = secondCpa.clone(true, true);
    updatedSecondCpa.PreferenceRank = secondCpa.PreferenceRank - 30; // the amount is really unimportant; that it doesn't match what's in the database is
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa });
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    System.assertEquals(updatedSecondCpa.PreferenceRank, acc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @IsTest
  static void shouldTakeIntoAccountInMemorySObjectsWhenUpdatedItemIsNoLongerMinAndNoOtherSObjectsExist() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>(originalCpas);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ updatedCpa, updatedSecondCpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN AFTER_UPDATE');
    System.assertEquals(updatedSecondCpa.PreferenceRank, acc.AnnualRevenue, 'MIN AFTER_UPDATE should take the min cpaortunity amount');
  }

  @IsTest
  static void shouldMinNumbersSuccessfullyOnDeleteWhenDeletedItemIsNoLongerMax() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 150;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 150, ParentId = acc.Id, Name = 'testCpa');
    ContactPointAddress secondCpa = new ContactPointAddress(PreferenceRank = 175, ParentId = acc.Id, Name = 'testCpaTwo');
    List<ContactPointAddress> originalCpas = new List<ContactPointAddress>{ cpa, secondCpa };
    insert originalCpas;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.oldRecordsMap = new Map<Id, SObject>(Rollup.records);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE');
    System.assertEquals(175, acc.AnnualRevenue, 'MIN BEFORE_DELETE should take the minimum cpaortunity amount');
  }

  @IsTest
  static void shouldConcatOnUpdate() {
    // AFTER_INSERT test is handled in the "shouldBatchThreeOperations" method
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'second test string');

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldCpa.Id => oldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_UPDATE');
    System.assertEquals(cpa.Name, acc.AccountNumber, 'CONCAT AFTER_UPDATE should replace the old string value with the new');
  }

  @IsTest
  static void shouldConcatOnDelete() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'beginning test string something';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress notDeleted = new ContactPointAddress(ParentId = acc.Id, Name = 'beginning');
    ContactPointAddress alsoNotDeleted = new ContactPointAddress(ParentId = acc.Id, Name = 'something');
    ContactPointAddress deletedCpa = new ContactPointAddress(ParentId = acc.Id, Name = 'test string');
    insert new List<ContactPointAddress>{ notDeleted, alsoNotDeleted, deletedCpa };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ deletedCpa });
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT BEFORE_DELETE');
    System.assertEquals(
      notDeleted.Name + ', ' + alsoNotDeleted.Name,
      acc.AccountNumber,
      'CONCAT BEFORE_DELETE should replace the outgoing string value with empty string'
    );
  }

  @IsTest
  static void shouldSortConcatStringWithCustomOptions() {
    Account acc = [SELECT Id, Name, AccountNumber FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'a', PreferenceRank = 1);
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = acc.Id, Name = 'b', PreferenceRank = 0);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa, cpaTwo });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatFromApex(
        ContactPointAddress.Name,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AccountNumber,
        Account.SObjectType,
        null,
        null,
        new List<RollupOrderBy__mdt>{
          new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank', SortOrder__c = RollupMetaPicklists.SortOrder.Ascending, Ranking__c = 0)
        }
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT AFTER_INSERT');
    System.assertEquals('b, a', acc.AccountNumber, 'Should have been sorted according to rollup order bys');
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
  static void shouldDistinctifyForConcatDistinct() {
    ContactPointAddress cpa = new ContactPointAddress(Name = 'apples, oranges, pears');
    ContactPointAddress secondCpa = new ContactPointAddress(Name = 'apples, pears');
    ContactPointAddress thirdCpa = new ContactPointAddress(Name = 'apples, oranges, plums, peaches');

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa, thirdCpa });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Name, Account.SObjectType, '').runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_INSERT');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('apples, oranges, peaches, pears, plums', updatedAcc.Name, 'CONCAT_DISTINCT AFTER_INSERT should only add unique values');
  }

  @IsTest
  static void shouldConcatDistinctOnUpdate() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(Name = 'second test string', ParentId = acc.Id);
    ContactPointAddress secondCpa = new ContactPointAddress(Name = 'third test string', ParentId = acc.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa, secondCpa });
    ContactPointAddress oldCpa = cpa.clone(true, true);
    oldCpa.Name = acc.AccountNumber;
    ContactPointAddress secondoldCpa = secondCpa.clone(true, true);
    secondoldCpa.Name = acc.AccountNumber;
    Rollup.oldRecordsMap = new Map<Id, SObject>{ oldCpa.Id => oldCpa, secondoldCpa.Id => secondoldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_UPDATE');
    System.assertEquals(
      'second test string, third test string',
      acc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should be the distinct combo of the old and new strings'
    );
  }

  @IsTest
  static void shouldConcatDistinctOnUpdateWhereOnlyNewItemIsAdded() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'first test string again';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(Name = acc.AccountNumber, ParentId = acc.Id);
    ContactPointAddress secondCpa = new ContactPointAddress(Name = 'third test string', ParentId = acc.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ cpa, secondCpa });
    ContactPointAddress secondoldCpa = secondCpa.clone(true, true);
    secondoldCpa.Name = 'some other string';
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => cpa, secondoldCpa.Id => secondoldCpa };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated CONCAT_DISTINCT AFTER_UPDATE');
    System.assertEquals(
      'first test string again, third test string',
      acc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should be the distinct combo of the old and new strings'
    );
  }

  @IsTest
  static void shouldProperlyShortCircuitOnConcatDistinctDeleteWhenDistinctValueStillPresentOnOtherItem() {
    Account acc = [SELECT Id, Name FROM Account];
    String originalAccountName = acc.Name;
    String somethingElse = 'Something else';
    acc.Name = acc.Name + ', ' + somethingElse;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
    System.assertEquals(originalAccountName, acc.Name);
  }

  @IsTest
  static void shouldRemoveTextOnConcatDistinctDelete() {
    Account acc = [SELECT Id, Name, Description FROM Account];
    String originalAccountName = acc.Name;
    String somethingElse = 'Something else';
    acc.Name = acc.Name + ', ' + somethingElse;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress originalName = new ContactPointAddress(Name = originalAccountName, ParentId = acc.Id, PreferenceRank = 0);
    ContactPointAddress somethingElseName = new ContactPointAddress(Name = somethingElse, ParentId = acc.Id, PreferenceRank = 1);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ originalName, somethingElseName };
    insert cpas;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ somethingElseName });
    Rollup.oldRecordsMap = new Map<Id, SObject>{ somethingElseName.Id => somethingElseName };
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT'
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItemWhereClause__c = 'Parent.Type = \'Account\'',
        GrandparentRelationshipFieldPath__c = 'Parent.Description'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Account should be updated CONCAT_DISTINCT delete');
    System.assertEquals(originalAccountName, acc.Name);
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
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'B'), new ContactPointAddress(Name = 'A') };

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
    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = ''), new ContactPointAddress(Name = 'A') };

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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    List<ContactPointAddress> testCpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(testCpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpas[0].Id => new ContactPointAddress(Id = testCpas[0].Id, Name = 'A') };

    Test.startTest();
    Rollup.minFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AccountNumber, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN BEFORE_DELETE STRING');
    System.assertEquals('', acc.AccountNumber, 'MIN BEFORE_DELETE should take the minimum string');
  }

  @IsTest
  static void shouldMaxOnStringsBeforeDelete() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'A';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
    System.assertEquals(originalCpaNameGreater ? cpa.Name : testCpas[0].Name, acc.AccountNumber, 'MAX BEFORE_DELETE should take the maximum string');
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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, ParentId = acc.Id),
      new ContactPointAddress(PreferenceRank = 200000, ParentId = acc.Id)
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_INSERT');
    System.assertEquals(
      (testCpa.PreferenceRank + cpas[0].PreferenceRank + cpas[1].PreferenceRank) / 3.00,
      acc.AnnualRevenue,
      'AVERAGE AFTER_INSERT should take into account all values'
    );
  }

  @IsTest
  static void shouldAverageOnUpdate() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 100;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress testCpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Pre-existing', ParentId = acc.Id);
    insert testCpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 200000, ParentId = acc.Id),
      new ContactPointAddress(PreferenceRank = 200000, ParentId = acc.Id)
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpas[0].Id => new ContactPointAddress(PreferenceRank = 100000, Id = cpas[0].Id),
      cpas[1].Id => new ContactPointAddress(PreferenceRank = 100000, Id = cpas[1].Id)
    };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE AFTER_UPDATE');
    System.assertEquals(
      (testCpa.PreferenceRank + cpas[0].PreferenceRank + cpas[1].PreferenceRank) / 3.00,
      acc.AnnualRevenue,
      'AVERAGE AFTER_UPDATE should take into account all values, including those from memory'
    );
  }

  @IsTest
  static void shouldAverageOnDelete() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 200;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress testCpaOne = new ContactPointAddress(PreferenceRank = 100, Name = 'Pre-existing one', ParentId = acc.Id);
    ContactPointAddress testCpaTwo = new ContactPointAddress(PreferenceRank = 300, Name = 'Pre-existing two', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ testCpaOne, testCpaTwo };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ testCpaTwo };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ testCpaOne.Id => testCpaOne };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated AVERAGE BEFORE_DELETE');
    System.assertEquals(testCpaOne.PreferenceRank, acc.AnnualRevenue, 'AVERAGE BEFORE_DELETE should take into account only non-deleted values');
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
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Hi', PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatDistinctFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Description, Account.SObjectType, 'a').runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
    System.assertEquals('a', mock.Records.get(0).get(Account.Description));
  }

  @IsTest
  static void shouldPassRecalcValueForConcat() {
    rollupOp = Rollup.Op.CONCAT;
    RollupCalculator.Factory = new FactoryMock();
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Hi', PreferenceRank = 5) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.concatFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.Description, Account.SObjectType, 'a').runCalc();
    Test.stopTest();

    System.assertEquals('a', testMetadata.FullRecalculationDefaultStringValue__c);
    System.assertEquals('a', mock.Records.get(0).get(Account.Description));
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
    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpa };

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATE AFTER_INSERT');
    System.assertEquals(taskTwo.ActivityDate, cpa.ActiveFromDate);
  }

  @IsTest
  static void shouldMinDateOnInsert() {
    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpa };

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Task>{ taskOne, taskTwo }, cpa.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, ContactPointAddress.Id, ContactPointAddress.ActiveFromDate, ContactPointAddress.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    System.assertEquals(taskOne.ActivityDate, cpa.ActiveFromDate);
  }

  @IsTest
  static void shouldMinDateOnInsertWhereParentDateIsNull() {
    Campaign camp = new Campaign(Id = RollupTestUtils.createId(Campaign.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ camp };

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = System.today().addDays(-50));
    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = System.today().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Task>{ taskOne, taskTwo }, camp.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhatId, Campaign.Id, Campaign.EndDate, Campaign.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_INSERT');
    System.assertEquals(taskOne.ActivityDate, camp.EndDate);
  }

  @IsTest
  static void shouldMinDateOnUpdate() {
    Contact con = new Contact(LastName = 'Min date on insert test', BirthDate = System.today());
    insert con;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    Task taskOne = new Task(Subject = 'Test One', ActivityDate = con.BirthDate.addDays(-50), WhoId = con.Id);
    insert taskOne;

    Task taskTwo = new Task(Subject = 'Test Two', ActivityDate = con.BirthDate.addDays(5), Id = RollupTestUtils.createId(Task.SObjectType), WhoId = con.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Task>{ taskTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Task>(new List<Task>{ new Task(Id = taskTwo.Id, ActivityDate = con.BirthDate, WhoId = con.Id) });

    Test.startTest();
    Rollup.minFromApex(Task.ActivityDate, Task.WhoId, Contact.Id, Contact.BirthDate, Contact.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATE AFTER_UPDATE');
    System.assertEquals(taskOne.ActivityDate, con.BirthDate);
  }

  @IsTest
  static void shouldMaxDatetimeOnInsert() {
    Contract con = new Contract(Id = RollupTestUtils.createId(Contract.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50));
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Event>{ eventOne, eventTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_INSERT');
    System.assertEquals(eventTwo.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnInsert() {
    Contract con = new Contract(Id = RollupTestUtils.createId(Contract.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    Event eventOne = new Event(ActivityDateTime = System.now().addDays(-50));
    Event eventTwo = new Event(ActivityDateTime = System.now().addDays(50));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Event>{ eventOne, eventTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_INSERT');
    System.assertEquals(eventOne.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnUpdate() {
    Contract con = new Contract(Id = RollupTestUtils.createId(Contract.SObjectType), ActivatedDate = System.now());
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    // now the "new" version of eventOne is no longer the min
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), Id = RollupTestUtils.createId(Event.SObjectType));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Event>{ eventOne, eventTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing min
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME AFTER_UPDATE');
    System.assertEquals(eventTwo.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMaxDatetimeOnUpdate() {
    Contract con = new Contract(Id = RollupTestUtils.createId(Contract.SObjectType), ActivatedDate = System.now());
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    // now the "new" version of eventOne is no longer the max
    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate.addDays(-25), Id = RollupTestUtils.createId(Event.SObjectType));
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(50), Id = RollupTestUtils.createId(Event.SObjectType));

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Event>{ eventOne, eventTwo }, con.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    // the point here is that the old record equaled the existing max
    Rollup.oldRecordsMap = new Map<Id, Event>{ eventOne.Id => new Event(Id = eventOne.Id, WhatId = con.Id, ActivityDateTime = con.ActivatedDate) };

    Test.startTest();
    Rollup.maxFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MAX DATETIME AFTER_UPDATE');
    System.assertEquals(eventTwo.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMaxDatetimeOnDelete() {
    Contract con = [SELECT Id FROM Contract];
    // it's important that this test and the one below it don't have time instances with more than second granularity, since Apex can't retrieve those values
    con.ActivatedDate = Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

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
    System.assertEquals(eventTwo.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMinDatetimeOnDelete() {
    Contract con = [SELECT Id FROM Contract];
    // it's important that this test and the one above it don't have time instances with more than second granularity, since Apex can't retrieve those values
    con.ActivatedDate = Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    Event eventOne = new Event(ActivityDateTime = con.ActivatedDate);
    Event eventTwo = new Event(ActivityDateTime = con.ActivatedDate.addDays(-50), DurationInMinutes = 50, WhatId = con.Id);
    insert eventTwo;

    RollupTestUtils.DMLMock mock = RollupTestUtils.getWhatIdMock(new List<Event>{ eventOne }, con.Id);
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;
    Rollup.oldRecordsMap = new Map<Id, Event>(new List<Event>{ eventOne });

    Test.startTest();
    Rollup.minFromApex(Event.ActivityDateTime, Event.WhatId, Contract.Id, Contract.ActivatedDate, Contract.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MIN DATETIME BEFORE_DELETE');
    System.assertEquals(eventTwo.ActivityDateTime, con.ActivatedDate);
  }

  @IsTest
  static void shouldMinTimeOnInsert() {
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'someKey');
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    System.assertEquals(cp1.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @IsTest
  static void shouldMaxTimeOnInsert() {
    ContactPointEmail cpe = new ContactPointEmail(EmailDomain = 'Lookupfield', Id = RollupTestUtils.createId(ContactPointEmail.SObjectType));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @IsTest
  static void shouldMaxTimeOnUpdate() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      EmailDomain = 'someKey',
      Id = RollupTestUtils.createId(ContactPointEmail.SObjectType)
    );
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @IsTest
  static void shouldMinTimeOnUpdate() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0),
      Id = RollupTestUtils.createId(ContactPointEmail.SObjectType),
      EmailDomain = 'io'
    );
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    Rollup.oldRecordsMap = new Map<Id, SObject>{
      cp1.Id => new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Id = cp1.Id, Name = cp1.Name)
    };
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
    System.assertEquals(cp1.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  @IsTest
  static void shouldMinTimeOnDelete() {
    ContactPointEmail cpe = new ContactPointEmail(
      BestTimeToContactEndTime = Time.newInstance(5, 5, 5, 5),
      EmailDomain = 'someKey',
      Id = RollupTestUtils.createId(ContactPointEmail.SObjectType)
    );
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ cpe };

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
    System.assertEquals(cp2.BestTimeToContactEndTime, cpe.BestTimeToContactEndTime);
  }

  // MOST

  @IsTest
  static void usesMostCommonValue() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
    ContactPointAddress commonOne = new ContactPointAddress(PreferenceRank = 100, Name = 'one', ParentId = acc.Id);
    ContactPointAddress commonTwo = new ContactPointAddress(PreferenceRank = 100, Name = 'one', ParentId = acc.Id);
    ContactPointAddress uncommon = new ContactPointAddress(PreferenceRank = 300, Name = 'two', ParentId = acc.Id);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ commonOne, commonTwo, uncommon });

    Test.startTest();
    Rollup.mostFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been populated MOST');
    System.assertEquals(commonOne.PreferenceRank, acc.AnnualRevenue);
  }

  @IsTest
  static void mostReparentsCorrectly() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account secondParent = new Account(Name = 'Reparented');
    insert secondParent;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, secondParent };
    insert new ContactPointAddress(Name = 'remaining value on second parent', PreferenceRank = 200, ParentId = secondParent.Id);
    ContactPointAddress commonOne = new ContactPointAddress(PreferenceRank = 100, Name = 'one', ParentId = acc.Id);

    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ commonOne });
    Rollup.oldRecordsMap = new Map<Id, SObject>{
      commonOne.Id => new ContactPointAddress(ParentId = secondParent.Id, PreferenceRank = commonOne.PreferenceRank, Id = commonOne.Id)
    };

    Test.startTest();
    Rollup.mostFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'MOST should have run correctly for reparenting');
    System.assertEquals(commonOne.PreferenceRank, acc.AnnualRevenue);
    System.assertEquals(200, secondParent.AnnualRevenue);
  }

  /** CDC trigger tests */

  @IsTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnCreate() {
    // CDC functions ** nearly ** the same as regular triggers, yet the SObjects supplied to ChangeEventTriggers
    // differ in two subtle ways: not all the fields are populated (just the changed ones), and the reference info
    // is supplied on a separate object, the ChangeEventHeader
    // Unfortunately, these two "tiny" differences means a lot of other code needs to be tested
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, Name = 'test cdc', ParentId = acc.Id);
    insert cpa;

    EventBus.ChangeEventHeader header = new EventBus.ChangeEventHeader();
    header.changeType = 'CREATE';
    header.recordIds = new List<Id>{ cpa.Id };
    header.entityName = 'ContactPointAddress';
    ContactPointAddressChangeEvent ev = new ContactPointAddressChangeEvent(ChangeEventHeader = header, PreferenceRank = 500);

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
    System.assertEquals(500, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldWorkForChangeDataEventCaptureTriggersOnUpdate() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
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
    System.assertEquals(500, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldWorkForChangeDataCaptureTriggersOnDelete() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Decimal originalAnnualRevenue = 10000;
    acc.AnnualRevenue = originalAnnualRevenue;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

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
    System.assertEquals(originalAnnualRevenue - ev.PreferenceRank, acc.AnnualRevenue);
  }

  /** Batch test */

  @IsTest
  static void shouldRunSuccessfullyAsBatch() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1);

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
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(1, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @IsTest
  static void shouldRunAsBatchableWhenDefaultIsBatchableAndRecordsAreLessThanBatchableLimit() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1) });
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1000, ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Batchable);

    Test.startTest();
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    Account acc = (Account) mock.Records[0];
    System.assertEquals(1, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker' LIMIT 1]?.Status);
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
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 300, Name = 'AnotherRollupTest');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals(325, acc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
    System.assertEquals(null, oldAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @IsTest
  static void shouldCorrectlyReparentWhenOnlyNewParentIsPartOfRollup() {
    // Unhappy path - query for related rows
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 25, Name = 'AnotherRollupTest');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals(cpa.PreferenceRank, acc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
    System.assertEquals(null, oldAcc.AnnualRevenue, 'SUM AFTER_UPDATE should take the diff between the current amount and the pre-existing one');
  }

  @IsTest
  static void shouldCorrectlyReparentWhenOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 50, Name = 'Old Parent');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

    ContactPointAddress cpa = new ContactPointAddress(
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType),
      PreferenceRank = 50,
      ParentId = acc.Id,
      Name = 'Does Not Match'
    );
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = oldAcc.AnnualRevenue.intValue(), Id = cpa.Id, Name = 'Match')
    };

    Test.startTest();
    Rollup.sumFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType,
        null,
        RollupEvaluator.getWhereEval('Name NOT IN (\'' + cpa.Name + '\')', cpa.getSObjectType())
      )
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Only old account should have been updated, ' + mock.Records);
    System.assertEquals(null, oldAcc.AnnualRevenue, 'SUM AFTER_UPDATE should remove current amount from old parent');
    System.assertEquals(null, acc.AnnualRevenue, 'SUM AFTER_UPDATE should not count excluded item on new parent');
  }

  @IsTest
  static void shouldNotDecrementForReparentingWhereItemDoesNotMatch() {
    Account acc = [SELECT Id, AnnualRevenue, NumberOfEmployees FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 0, NumberOfEmployees = 50, Name = 'AnotherRollupTest');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

    ContactPointAddress cpa = new ContactPointAddress(
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType),
      PreferenceRank = 50,
      ParentId = acc.Id,
      Name = 'Non-match'
    );
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{
      cpa.Id => new ContactPointAddress(ParentId = oldAcc.Id, PreferenceRank = cpa.PreferenceRank, Id = cpa.Id, Name = cpa.Name)
    };

    Test.startTest();
    Rollup.batch(
      Rollup.sumFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType,
        0,
        RollupEvaluator.getWhereEval('Name NOT IN (\'' + cpa.Name + '\')', cpa.getSObjectType())
      ),
      Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.NumberOfEmployees, Account.SObjectType, 0)
    );
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), mock.Records);
    System.assertEquals(0, acc.AnnualRevenue);
    System.assertEquals(0, oldAcc.AnnualRevenue);
    System.assertEquals(50, acc.NumberOfEmployees);
    System.assertEquals(0, oldAcc.NumberOfEmployees);
  }

  @IsTest
  static void shouldReparentSameObjectRollups() {
    Rollup.onlyUseMockmetadata = true;
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    Account clearedParent = new Account(AnnualRevenue = 25, Name = 'clear parent same object');
    insert clearedParent;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, clearedParent };

    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, Account>{ clearedParent.Id => new Account(ParentId = acc.Id, AnnualRevenue = 25, Id = clearedParent.Id) };
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
    System.assertEquals(null, acc.AnnualRevenue, 'Count should have been decremented');
  }

  @IsTest
  static void shouldCorrectlyReparentForStrings() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];
    Account oldAcc = new Account(Name = 'Something');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals('Y', acc.Name, 'MAX AFTER_UPDATE should take the maximum string');
    System.assertEquals('', oldAcc.Name, 'MAX AFTER_UPDATE should be empty after reparenting');
  }

  @IsTest
  static void shouldCorrectlyReparentForStringsCountDistinct() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 1, Name = 'Something');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals(2, acc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should count only the distinct entries');
    System.assertEquals(null, oldAcc.AnnualRevenue, 'COUNT DISTINCT AFTER_UPDATE should be empty after reparenting');
  }

  @IsTest
  static void shouldCorrectlyReparentForStringCount() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 1, Name = 'Something');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals(1, acc.AnnualRevenue, 'COUNT AFTER_UPDATE should only count updated entries reparented to it');
    System.assertEquals(null, oldAcc.AnnualRevenue, 'Old account should have had its annual revenue decremented');
  }

  @IsTest
  static void shouldCorrectlyReparentForAverage() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Account oldAcc = new Account(AnnualRevenue = 50, Name = 'AnotherRollupTest');
    insert oldAcc;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc, oldAcc };

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
    System.assertEquals(50, acc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should properly attribute the new amount to the new parent');
    System.assertEquals(null, oldAcc.AnnualRevenue, 'AVERAGE AFTER_UPDATE should properly decrement the old amount from the old parent');
  }

  /** Re-queueing */
  @IsTest
  static void shouldRequeueRollupsWhenQueryLimitsExceeded() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 1) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.defaultControl = new RollupControl__mdt(
      MaxNumberOfQueries__c = 1,
      MaxRollupRetries__c = 1,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous
    );
    Rollup.specificControl = Rollup.defaultControl;

    Test.startTest();
    Rollup.batch(
      Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType),
      Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.NumberOfEmployees, Account.SObjectType)
    );
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Rollup run should have run');
    Account acc = (Account) mock.Records.get(0);
    System.assertEquals(1, acc.AnnualRevenue);
    System.assertEquals(1, acc.NumberOfEmployees);
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

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
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
    Account acc = [SELECT Id FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
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
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable'].Status);
  }

  @IsTest
  static void shouldDeferGrandparentRollupSafelyTillAllParentRecordsAreRetrievedWithBatch() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 0, MaxNumberOfQueries__c = 2, MaxRollupRetries__c = 100);
    // start as synchronous rollup to allow for one deferral
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, MaxNumberOfQueries__c = 4);
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

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ new ContactPointAddress(ParentId = childAcc.Id, Name = 'One') });
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
    System.assertEquals('One', updatedAccount.Name);
  }

  @IsTest
  static void encapsulatesNamespaceInfoProperly() {
    Rollup.NamespaceInfo namespaceInfo = Rollup.getNamespaceInfo();

    String rollupObjectName = Rollup__mdt.SObjectType.toString();
    System.assertEquals(rollupObjectName + '.' + Rollup__mdt.RollupOperation__c.toString(), nameSpaceInfo.safeRollupOperationField);
    System.assertEquals(rollupObjectName, nameSpaceInfo.safeObjectName);
    System.assertEquals(Rollup.class.getName() == 'Rollup' ? '' : Rollup.class.getName().substringBefore('.Rollup') + '__', nameSpaceInfo.namespace);
  }

  @IsTest
  static void transformsToGroupByRollup() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Group One', PreferenceRank = 50), new ContactPointAddress(Name = 'Group Two') }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.Description, Account.SObjectType)
      .modifyMetadata(new Rollup__mdt(GroupByFields__c = 'Name', IsTableFormatted__c = true))
      .runCalc();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size());
    System.assertEquals(
      '<table><tr><th>Name</th><th>PreferenceRank</th></tr><tr><td>Group One</td><td>50</td></tr><tr><td>Group Two</td><td>null</td></tr></table>',
      mock.Records[0].get('Description')
    );
  }

  @IsTest
  static void fallsBackToRunningSyncWhenOutOfAsyncJobs() {
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(
      new List<ContactPointAddress>{ new ContactPointAddress(Name = 'One', PreferenceRank = 50) }
    );
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    // one over the default limit
    RollupLimits.currentAsyncJobsUsed = 250001;

    // specifically no Test.startTest()/Test.stopTest() to prove it's been run sync
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();

    System.assertEquals(1, mock.Records.size());
    System.assertEquals(50, mock.Records[0].get(Account.AnnualRevenue));
  }

  @IsTest
  static void doesNotPersistPossiblyStaleFieldsWhenTheyAreNotUpdated() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.NumberOfEmployees = 1;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = acc.Id);

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(new List<ContactPointAddress>{ cpa });
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.oldRecordsMap = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 0, Id = cpa.Id) };

    Test.startTest();
    Rollup.averageFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    Assert.areEqual(50, acc.AnnualRevenue);
    Assert.areEqual(acc.AnnualRevenue, mock.Records.get(0).get(Account.AnnualRevenue));
    Assert.isNull(mock.Records.get(0).get(Account.NumberOfEmployees), 'Should not persist potentially stale value');
  }

  @IsTest
  static void isNoOpWhenParentFieldIsNullOnInsert() {
    Rollup.onlyUseMockMetadata = true;
    ContactPointAddress cpa = new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), PreferenceRank = 50, ParentId = null);
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<SObject>{ cpa };

    String rollupResponse = Rollup.averageFromApex(
        ContactPointAddress.PreferenceRank,
        ContactPointAddress.ParentId,
        Account.Id,
        Account.AnnualRevenue,
        Account.SObjectType
      )
      .runCalc();

    Assert.areEqual('no-op', rollupResponse);
  }

  @IsTest
  static void rollupGroupingOperationOccursIndependentlyOfDownstreamRollups() {
    Account acc = [SELECT Id, Phone FROM Account];
    acc.AnnualRevenue = 2; // should match count of contacts, below, to begin with
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    Opportunity opp = new Opportunity(CloseDate = System.today(), Amount = 3, AccountId = acc.Id, StageName = '1', Name = 'Winning Record');
    insert opp;
    insert new List<SObject>{ new Contact(LastName = '1', AccountId = acc.Id), new Contact(LastName = '2', AccountId = acc.Id) };
    Rollup.onlyUseMockMetadata = true;
    RollupGrouping__mdt parentGrouping = new RollupGrouping__mdt(Id = RollupTestUtils.createId(RollupGrouping__mdt.SObjectType), RollupOperation__c = 'MAX');
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Contact',
        LookupFieldOnCalcItem__c = 'AccountId',
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        RollupGrouping__r = parentGrouping
      ),
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupFieldOnCalcItem__c = 'AccountId',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        RollupGrouping__r = parentGrouping
      )
    };

    Test.startTest();
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;
    Rollup.records = new List<Opportunity>{ opp };
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, Amount = 1, AccountId = acc.Id) };
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    Assert.areEqual(opp.Amount, acc.AnnualRevenue);
  }
}
