@IsTest
private class RollupParentResetProcessorTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void shouldNotFailWhenRollupFieldNotFilterable() {
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'Description', LookupObject__c = 'Account') },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Exception ex;
    try {
      processor.runCalc();
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(null, ex, 'Should not fail when fields are unfilterable!');
  }

  @IsTest
  static void shouldNotFailWhenRollupMetadataIsEmpty() {
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>(),
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Exception ex;
    try {
      processor.runCalc();
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(null, ex, 'Should not fail when empty list passed');
  }

  @IsTest
  static void shouldNotFailWhenSomeRunsAreValidAndSomeAreNot() {
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'AnnualRevenue', LookupObject__c = 'Account') },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );
    processor.runCalc(); // this one is valid

    processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'Description', LookupObject__c = 'Account') },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Exception ex;
    try {
      processor.runCalc();
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(null, ex, 'Should not fail when invocations are valid then invalid');
  }

  @IsTest
  static void correctlyQueriesEvenWhenResetFieldIsNotFilterable() {
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'Description', LookupObject__c = 'Account') },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Exception ex;
    try {
      processor.runCalc();
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(null, ex, 'Should not fail when field is not filterable');
  }

  @IsTest
  static void doesNotBlowUpOnWhenMultipleMetadataPresentForDifferentParents() {
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'Description', LookupObject__c = 'Account'),
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'FirstName', LookupObject__c = 'Contact')
      },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Exception ex;
    try {
      processor.runCalc();
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(null, ex, 'Should not fail when different parent fields present');
  }

  @IsTest
  static void usesOverrideValueWhenApplicable() {
    insert new List<SObject>{ new Account(Name = 'Account With Null'), new Contact(LastName = 'Contact With Null') };
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          FullRecalculationDefaultNumberValue__c = 0
        ),
        new Rollup__mdt(
          RollupFieldOnLookupObject__c = 'AccountNumber',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          FullRecalculationDefaultStringValue__c = 'a'
        )
      },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    processor.runCalc();

    Account resetAccount = [SELECT AnnualRevenue, AccountNumber FROM Account];
    System.assertEquals(0, resetAccount.AnnualRevenue);
    System.assertEquals('a', resetAccount.AccountNumber);
  }

  @IsTest
  static void skipsTransformWhenDisabled() {
    Rollup.defaultControl = Rollup.getDefaultControl();
    Rollup.defaultControl.ShouldSkipResettingParentFields__c = true;
    Rollup.defaultControl.ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous;

    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'AnnualRevenue', LookupObject__c = 'Account') },
      Account.SObjectType,
      'SELECT Id\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    Test.startTest();
    Rollup.batch(new List<Rollup>{ processor });
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :RollupParentResetProcessor.class.getName()]);
  }

  @IsTest
  static void shouldNotResetWhenParentAlreadyMatchesDuringFullRecalc() {
    Decimal originalValue = 3;
    Account acc = new Account(AnnualRevenue = originalValue, Name = 'Should Not Reset');
    insert acc;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Amount = 100, Name = 'Will Not Match', CloseDate = System.today().addDays(2), StageName = 'A');
    insert new List<Opportunity>{
      new Opportunity(AccountId = acc.Id, Amount = originalValue - 1, Name = 'First Match', CloseDate = System.today().addDays(-2), StageName = 'A'),
      new Opportunity(AccountId = acc.Id, Amount = originalValue - 2, Name = 'Second Match', CloseDate = System.today().addDays(-2), StageName = 'A'),
      opp
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          RollupFieldOnCalcItem__c = 'Amount',
          LookupObject__c = 'Account',
          LookupFieldOnCalcItem__c = 'AccountId',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'SUM',
          CalcItem__c = 'Opportunity',
          IsFullRecordSet__c = true,
          CalcItemWhereClause__c = 'CloseDate <= TODAY'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );

    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(originalValue, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void skipsMetadataForDifferentResetParents() {
    insert new Account(AnnualRevenue = 5, Name = 'Should reset');
    RollupParentResetProcessor processor = new RollupParentResetProcessor(
      new List<Rollup__mdt>{
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'AnnualRevenue', LookupObject__c = 'Account', LookupFieldOnLookupObject__c = 'Id'),
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'FirstName', LookupObject__c = 'Contact')
      },
      Account.SObjectType,
      'SELECT Id, AnnualRevenue\nFROM Account WHERE Id != null',
      new Set<String>(),
      null
    );

    processor.runCalc();

    Assert.areEqual(null, [SELECT AnnualRevenue FROM Account].AnnualRevenue);
  }
}
