@IsTest
private class RollupCalcItemReplacerTests {
  static final Integer ACC_ANNUAL_REVENUE = 5;
  @TestSetup
  static void setup() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    insert new Account(Name = RollupCalcItemReplacerTests.class.getName(), AnnualRevenue = ACC_ANNUAL_REVENUE);
  }

  @IsTest
  static void shouldNotTryToQueryRelationshipFieldsWhenTheyAlreadyExistOnPassedInRecords() {
    Account acc = [SELECT Id, Name FROM Account];

    Contact con = new Contact(LastName = 'Lookup to Account', AccountId = acc.Id);
    insert con;
    con = [SELECT Id, Account.Name FROM Contact];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    List<SObject> replacedContacts = replacer.replace(
      new List<Contact>{ con },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'Account.Name = \'' + acc.Name + '\'', CalcItem__c = 'Contact') }
    );

    System.assertEquals(true, replacedContacts[0].getPopulatedFieldsAsMap().containsKey('Account'));
    con = (Contact) replacedContacts[0];
    System.assertEquals(RollupCalcItemReplacerTests.class.getName(), con.Account.Name);
  }

  @IsTest
  static void shouldSafelyRequeryRelationshipFields() {
    Account acc = [SELECT Id, Name FROM Account];

    Contact con = new Contact(LastName = 'Lookup to Account', AccountId = acc.Id);
    insert con;
    con = [SELECT Id, LastName, Account.Id FROM Contact];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    List<SObject> replacedContacts = replacer.replace(
      new List<Contact>{ con },
      new List<Rollup__mdt>{
        new Rollup__mdt(CalcItemWhereClause__c = 'Account.Name = \'' + acc.Name + '\' AND Account.Owner.Id != null', CalcItem__c = 'Contact')
      }
    );

    System.assertEquals(true, replacedContacts[0].getPopulatedFieldsAsMap().containsKey('Account'));
    con = (Contact) replacedContacts[0];
    System.assertEquals(RollupCalcItemReplacerTests.class.getName(), con.Account.Name);
    System.assertNotEquals(null, con.Account.Owner.Id);
  }

  @IsTest
  static void shouldWorkWithNonReparentableItems() {
    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'test non reparent', Name = 'opp', Amount = 5);
    Contact con = new Contact(LastName = 'Con');
    insert new List<SObject>{ opp, con };

    OpportunityContactRole oppConRole = new OpportunityContactRole(OpportunityId = opp.Id, ContactId = con.Id);
    insert oppConRole;

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    List<SObject> replacedOppContactRoles = replacer.replace(
      new List<OpportunityContactRole>{ oppConRole },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'Opportunity.Amount = 1', CalcItem__c = 'OpportunityContactRole') }
    );
    oppConRole = (OpportunityContactRole) replacedOppContactRoles[0];

    System.assertEquals(opp.Amount, oppConRole.Opportunity.Amount, 'Should not fail due to Relationship not editable error');
  }

  @IsTest
  static void shouldNotQueryRelationshipFieldsFromAnotherObject() {
    Account parentAccount = [SELECT Id FROM Account];
    Account acc = new Account(ParentId = parentAccount.Id, Name = 'Child account');
    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'test non reparent', Name = 'opp', Amount = 5);
    Contact con = new Contact(LastName = 'Con');
    insert new List<SObject>{ opp, con, acc };

    OpportunityContactRole oppConRole = new OpportunityContactRole(OpportunityId = opp.Id, ContactId = con.Id);
    insert oppConRole;

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    replacer.replace(
      new List<OpportunityContactRole>{ oppConRole },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'Opportunity.Amount = 1', CalcItem__c = 'OpportunityContactRole') }
    );

    // now call replace on another object without the field used above
    List<Account> accounts = replacer.replace(
      new List<Account>{ acc },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'Parent.Name = \'someName\'', CalcItem__c = 'Account') }
    );

    System.assertNotEquals(null, accounts[0].Parent.Name, 'Should be able to access parent field after re-querying for it');
  }

  @IsTest
  static void shouldRetrieveQueryFieldsPartOfOrderBy() {
    Account acc = [SELECT Id, Name FROM Account];

    Contact con = new Contact(LastName = 'Ordered by Account Name', AccountId = acc.Id);
    insert con;
    con = [SELECT Id, LastName, Account.Id FROM Contact];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(CalcItem__c = 'Contact'),
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Account.Name') }
    );
    List<Contact> replacedContacts = replacer.replace(new List<Contact>{ con }, new List<Rollup__mdt>{ meta });

    System.assertNotEquals(null, replacedContacts[0].Account.Name);
  }

  @IsTest
  static void addsMissingBaseFieldsToCalcItems() {
    Account acc = [SELECT Id FROM Account];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 2)
    );
    acc = (Account) replacer.replace(
      new List<Account>{ acc, acc },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'AnnualRevenue != 0', CalcItem__c = 'Account') }
    )[0];

    System.assertEquals(ACC_ANNUAL_REVENUE, acc.AnnualRevenue);
  }

  @IsTest
  static void skipsNonUpdateableFields() {
    Account acc = [SELECT Id, CreatedDate FROM Account];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1)
    );
    Account updatedAccount = (Account) replacer.replace(
      new List<Account>{ acc },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'CreatedDate != null', CalcItem__c = 'Account') }
    )[0];

    System.assertEquals(acc.CreatedDate, updatedAccount.CreatedDate);
  }

  @IsTest
  static void skipsNonMetaMatches() {
    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(new RollupControl__mdt(ReplaceCalcItemsAsyncWhenOverCount__c = 1));

    Contact updatedContact = (Contact) replacer.replace(
      new List<Contact>{ new Contact() },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'AnnualRevenue > 0', CalcItem__c = 'Account') }
    )[0];

    System.assertNotEquals(null, updatedContact);
  }

  @IsTest
  static void worksWithParantheticalNotClauses() {
    Account acc = [SELECT Id FROM Account];

    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 2)
    );
    acc = (Account) replacer.replace(
      new List<Account>{ acc, acc },
      new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'NOT(AnnualRevenue != 0 AND Name != null)', CalcItem__c = 'Account') }
    )[0];

    System.assertEquals(ACC_ANNUAL_REVENUE, acc.AnnualRevenue);
  }

  @IsTest
  static void exclusiveWhereClauseWithMultipleMetadataRecordsDoesNotBlowUpList() {
    Account acc = [SELECT Id FROM Account];
    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 3)
    );

    List<SObject> records = replacer.replace(
      new List<Account>{ acc, acc },
      new List<Rollup__mdt>{
        new Rollup__mdt(CalcItemWhereClause__c = 'Id != \'' + acc.Id + '\' AND Owner.Name = null', CalcItem__c = 'Account'),
        new Rollup__mdt(CalcItemWhereClause__c = 'AnnualRevenue = null', CalcItem__c = 'Account')
      }
    );

    Assert.areEqual(0, records.size());
  }

  @IsTest
  static void doesNotUseAndForMultipleParentWhereClauses() {
    Account acc = [SELECT Id FROM Account];
    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 3)
    );

    List<SObject> records = replacer.replace(
      new List<Account>{ acc, acc },
      new List<Rollup__mdt>{
        new Rollup__mdt(CalcItemWhereClause__c = 'Id != \'' + acc.Id + '\' AND Owner.Name = null', CalcItem__c = 'Account'),
        new Rollup__mdt(CalcItemWhereClause__c = 'Owner.Name != null AND Type != null', CalcItem__c = 'Account')
      }
    );

    Assert.areEqual(1, records.size());
    Assert.areEqual(acc.Id, records[0].Id);
  }

  @IsTest
  static void doesNotReplaceForCustomTypeFields() {
    List<Account> accounts = [SELECT Id FROM Account];
    RollupCalcItemReplacer replacer = new RollupCalcItemReplacer(
      new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 3)
    );
    List<Rollup__mdt> metas = new List<Rollup__mdt>{ new Rollup__mdt(CalcItemWhereClause__c = 'Parent.Type__r = \'hello\'', CalcItem__c = 'Account') };

    List<SObject> records = replacer.replace(accounts, metas);

    Assert.areEqual(1, records.size());
    Assert.isTrue(replacer.hasProcessedMetadata(metas, accounts));
  }
}
