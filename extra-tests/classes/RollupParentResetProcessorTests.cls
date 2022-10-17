@IsTest
private class RollupParentResetProcessorTests {
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
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'AnnualRevenue', LookupObject__c = 'Account', FullRecalculationDefaultNumberValue__c = 0),
        new Rollup__mdt(RollupFieldOnLookupObject__c = 'AccountNumber', LookupObject__c = 'Account', FullRecalculationDefaultStringValue__c = 'a')
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
}
