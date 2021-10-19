@IsTest
private class RollupCalcItemReplacerTests {
  @IsTest
  static void shouldNotTryToQueryRelationshipFieldsWhenTheyAlreadyExistOnPassedInRecords() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = RollupCalcItemReplacerTests.class.getName());
    insert acc;

    Contact con = new Contact(LastName = 'Lookup to Account', AccountId = acc.Id);
    insert con;
    con = [SELECT Id, Account.Name FROM Contact];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    List<SObject> replacedContacts = replacer.replace(
      new List<Contact>{ con },
      new Rollup__mdt(CalcItemWhereClause__c = 'Account.Name = \'' + acc.Name + '\'')
    );

    System.assertEquals(true, replacedContacts[0].getPopulatedFieldsAsMap().containsKey('Account'));
    con = (Contact) replacedContacts[0];
    System.assertEquals(RollupCalcItemReplacerTests.class.getName(), con.Account.Name);
  }

  @IsTest
  static void shouldSafelyRequeryRelationshipFields() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = RollupCalcItemReplacerTests.class.getName());
    insert acc;

    Contact con = new Contact(LastName = 'Lookup to Account', AccountId = acc.Id);
    insert con;
    con = [SELECT Id, LastName, Account.Id FROM Contact];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    List<SObject> replacedContacts = replacer.replace(
      new List<Contact>{ con },
      new Rollup__mdt(CalcItemWhereClause__c = 'Account.Name = \'' + acc.Name + '\' AND Account.Owner.Id != null')
    );

    System.assertEquals(true, replacedContacts[0].getPopulatedFieldsAsMap().containsKey('Account'));
    con = (Contact) replacedContacts[0];
    System.assertEquals(RollupCalcItemReplacerTests.class.getName(), con.Account.Name);
  }
}
