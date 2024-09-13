@IsTest
private class InvocableDrivenTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new Account(Name = InvocableDrivenTests.class.getName());
  }

  @IsTest
  static void shouldWorkWithRefreshContext() {
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];
    // Description and Subject both are referenced in the Flow
    Case matchesFlow = new Case(Description = 'Name Match', AccountId = acc.Id, Subject = 'Refresh Test');
    Case nonMatch = new Case(Description = 'Non match', AccountId = acc.Id, Subject = 'Child Object Where Clause test');

    Test.startTest();
    insert new List<Case>{ matchesFlow, nonMatch };
    Test.stopTest();

    acc = [SELECT Site FROM Account];
    System.assertEquals(matchesFlow.Description, acc.Site, 'Description should have been CONCAT to account Site');
  }

  @IsTest
  static void shouldPerformDeleteOnRefreshOperationWhereOldValueMatches() {
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];

    // Description and Subject both are referenced in the Flow
    Case matchesFlow = new Case(Description = 'Name Match', AccountId = acc.Id, Subject = 'Refresh Test');

    Test.startTest();
    insert matchesFlow;
    matchesFlow.Subject = 'Now not a match';
    update matchesFlow;
    Test.stopTest();

    acc = [SELECT Site FROM Account];
    System.assertEquals(null, acc.Site, 'Description should have been removed once case no longer matched');
  }

  @IsTest
  static void shouldWorkWhenBatchedFromRefresh() {
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1);
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];
    // Description and Subject both are referenced in the Flow
    Case matchesFlow = new Case(Description = 'Name Match', AccountId = acc.Id, Subject = 'Refresh Test');

    Test.startTest();
    insert matchesFlow;
    Test.stopTest();

    acc = [SELECT Site FROM Account];
    System.assertEquals(matchesFlow.Description, acc.Site, 'Description should have been CONCAT to account Site');
  }

  @IsTest
  static void shouldRollupMultipleDMLStatementsWithinSingleTransaction() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];
    Account reparentAccount = new Account(Name = 'Reparent');
    insert reparentAccount;

    Case one = new Case(AccountId = acc.Id, Description = 'distinct', Subject = 'One');
    Case two = new Case(AccountId = acc.Id, Description = 'again', Subject = 'Two');
    Case three = new Case(AccountId = reparentAccount.Id, Description = 'something else', Subject = 'Excluded');
    Case four = new Case(AccountId = reparentAccount.Id, Description = one.Description, Subject = 'Excluded');

    Test.startTest();
    insert new List<Case>{ one, two, three, four };

    one.AccountId = reparentAccount.Id;
    update one;

    // Trigger recursive update after reparenting
    // this is important because it not only validates that the recursion
    // detection is working properly, but also because it validates that the
    // recursion detection is necessary to calculate the results properly!
    one.Subject = 'Z';
    update one;
    Test.stopTest();

    acc = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    reparentAccount = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees FROM Account WHERE Id = :reparentAccount.Id];

    System.assertEquals(two.Description, acc.Description, 'CONCAT_DISTINCT should remove extra text on reparent');
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals(two.Subject, acc.Name);

    System.assertEquals(3, reparentAccount.NumberOfEmployees, 'Second account should properly reflect reparented record for number of employees');
    System.assertEquals(one.Description + ', ' + three.Description, reparentAccount.Description, 'Second account should have only reparented case description');
    System.assertEquals(one.Subject, reparentAccount.Name, 'Second account name field should reflect last subject');
  }

  @IsTest
  static void shouldCorrectlyFilterOnParentFieldsForInsert() {
    // Driven by extra-tests/flows/Rollup_Integration_Parent_Where_Clause_Filtering.flow-meta.xml
    // Rollup operation is LAST on the Phone field with an order by on LastName
    Account acc = [SELECT Id FROM Account];
    Account matchingAccount = new Account(Name = 'Test Parent Fields');
    insert matchingAccount;

    Contact childOne = new Contact(AccountId = acc.Id, LastName = 'X', Phone = '6176191911');
    Contact childTwo = new Contact(AccountId = matchingAccount.Id, LastName = 'A', Phone = '6176191912');
    Contact childThree = new Contact(AccountId = matchingAccount.Id, LastName = 'B', Phone = '6176191900');

    Test.startTest();
    insert new List<Contact>{ childOne, childTwo, childThree };
    Test.stopTest();

    acc = [SELECT Phone FROM Account WHERE Id = :acc.Id];
    System.assertEquals(null, acc.Phone, 'Phone should not have been updated since child object where clause does not match');
    matchingAccount = [SELECT Phone FROM Account WHERE Id = :matchingAccount.Id];
    System.assertEquals(childThree.Phone, matchingAccount.Phone, 'Phone should have been ordered by LastName!');
  }

  @IsTest
  static void shouldCorrectlyFilterOnParentFieldsForUpdate() {
    // Driven by extra-tests/flows/Rollup_Integration_Parent_Where_Clause_Filtering.flow-meta.xml
    // Rollup operation is LAST on the Phone field with an order by on LastName
    Account acc = [SELECT Id FROM Account];
    Account matchingAccount = new Account(Name = 'Test Parent Fields');
    insert matchingAccount;

    Test.startTest();
    Contact childOne = new Contact(AccountId = acc.Id, LastName = 'X', Phone = '6176191911');
    Contact childTwo = new Contact(AccountId = matchingAccount.Id, LastName = 'A', Phone = '6176191912');
    Contact childThree = new Contact(AccountId = matchingAccount.Id, LastName = 'Z', Phone = '6176191900');
    List<Contact> cons = new List<Contact>{ childOne, childTwo, childThree };
    insert cons;

    childOne.AccountId = matchingAccount.Id;
    childThree.AccountId = acc.Id; // verify that parent-level filtering is working
    update cons;
    Test.stopTest();

    acc = [SELECT Phone FROM Account WHERE Id = :acc.Id];
    matchingAccount = [SELECT Phone FROM Account WHERE Id = :matchingAccount.Id];
    System.assertEquals(childOne.Phone, matchingAccount.Phone, 'Phone should have been updated based on new ordering');
    System.assertEquals(null, acc.Phone, 'Account phone should be cleared out since parent name field does not match');
  }

  @IsTest
  static void clearingParentFieldShouldProperlyDecrementSum() {
    // driven by extra-tests\flows\Rollup_Integration_Clear_Lookup_Fields.flow-meta.xml
    // Rollup operation is SUM with defer processing set to false
    Integer initialNumber = 3;
    Account acc = [SELECT Id FROM Account];

    ContactPointEmail one = new ContactPointEmail(ParentId = acc.Id, PreferenceRank = 1, EmailAddress = 'test@one.com');
    ContactPointEmail two = new ContactPointEmail(ParentId = acc.Id, PreferenceRank = initialNumber, EmailAddress = 'test@two.com');
    insert new List<ContactPointEmail>{ one, two };

    Test.startTest();
    one.ParentId = null;
    update one;
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(initialNumber, acc.AnnualRevenue?.intValue(), 'Amount should have properly decremented');
  }

  @IsTest
  static void shouldClearParentFieldOnDelete() {
    // driven by extra-tests/flows/Rollup_Integration_refresh_on_delete_clears_value.flow-meta.xml
    Account parent = new Account(AnnualRevenue = 1, Name = 'Parent');
    insert parent;

    ContactRequest child = new ContactRequest(WhatId = parent.Id);
    insert child;

    Test.startTest();
    delete child;
    Test.stopTest();

    parent = [SELECT AnnualRevenue FROM Account WHERE Id = :parent.Id];
    System.assertEquals(null, parent.AnnualRevenue);
  }

  @IsTest
  static void refreshWorksWithEmptyCollectionsWhenParentIdIsProvided() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress child = new ContactPointAddress(Name = 'RollupIntegrationRefresh', PreferenceRank = 99, ParentId = acc.Id);
    insert child;

    Flow.Interview flowInterview = new Flow.Interview.Rollup_Integration_Refresh_With_Empty_Collections(
      new Map<String, Object>{ 'parentRecordIdForEmptyChildrenCollections' => acc.Id }
    );

    Test.startTest();
    flowInterview.start();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(child.PreferenceRank, acc.AnnualRevenue);
  }

  @IsTest
  static void orderBysRetainRanking() {
    RollupParent__c parent = new RollupParent__c(Name = 'Parent');
    insert parent;

    RollupChild__c childOne = new RollupChild__c(
      RollupParent__c = parent.Id,
      NumberField__c = 1,
      TextField__c = 'b',
      Id = RollupTestUtils.createId(RollupChild__c.SObjectType)
    );
    RollupChild__c childTwo = new RollupChild__c(
      RollupParent__c = parent.Id,
      NumberField__c = 1,
      TextField__c = 'a',
      Id = RollupTestUtils.createId(RollupChild__c.SObjectType)
    );

    Flow.Interview flowInterview = new Flow.Interview.Rollup_Integration_Rollup_Order_Bys(
      new Map<String, Object>{ 'rollupChildren' => new List<RollupChild__c>{ childOne, childTwo } }
    );

    Test.startTest();
    flowInterview.start();
    Test.stopTest();

    parent = [SELECT TextField__c FROM RollupParent__c WHERE Id = :parent.Id];
    System.assertEquals(childTwo.TextField__c, parent.TextField__c);
  }
}
