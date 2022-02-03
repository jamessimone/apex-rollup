@IsTest
private class InvocableDrivenTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    Account acc = new Account(Name = InvocableDrivenTests.class.getName());
    insert acc;
  }

  @IsTest
  static void shouldWorkWithRefreshContext() {
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];

    // Description and Subject both are referenced in the Flow
    Case matchesFlow = new Case(Description = 'Name Match', AccountId = acc.Id, Subject = 'Refresh Test');
    Case nonMatch = new Case(Description = 'Non match', AccountId = acc.Id, Subject = 'Calc Item Where Clause test');

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
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1, IsRollupLoggingEnabled__c = true, BatchChunkSize__c = 1000);
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
    // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml
    Account acc = [SELECT Id FROM Account];
    Account reparentAccount = new Account(Name = 'Reparent');
    insert reparentAccount;

    Date today = System.today();

    Case one = new Case(Amount__c = 1, AccountId = acc.Id, Description = 'distinct', Subject = 'One', DateField__c = today.addDays(-2));
    Case two = new Case(Amount__c = 2, AccountId = acc.Id, Description = 'again', Subject = 'Two', DateField__c = today);
    Case three = new Case(Amount__c = 0, AccountId = reparentAccount.Id, Description = 'something else', Subject = 'Three');
    Case four = new Case(Amount__c = 0, AccountId = reparentAccount.Id, Description = one.Description, Subject = 'Four');

    Test.startTest();
    insert new List<Case>{ one, two, three, four };

    one.Amount__c = 2;
    one.AccountId = reparentAccount.Id;
    update one;

    // Trigger recursive update after reparenting
    // this is important because it not only validates that the recursion
    // detection is working properly, but also because it validates that the
    // recursion detection is necessary to calculate the results properly!
    one.Subject = 'Z';
    update one;
    Test.stopTest();

    acc = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees, DateField__c FROM Account WHERE Id = :acc.Id];
    reparentAccount = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees, DateField__c FROM Account WHERE Id = :reparentAccount.Id];

    System.assertEquals(today, acc.DateField__c, 'LAST should have been updated to new last');
    System.assertEquals(2, acc.AnnualRevenue, 'First account sum field should be decremented on reparent');
    System.assertEquals(two.Description, acc.Description, 'CONCAT_DISTINCT should remove extra text on reparent');
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals(two.Subject, acc.Name);

    System.assertEquals(today.addDays(-2), reparentAccount.DateField__c);
    System.assertEquals(3, reparentAccount.NumberOfEmployees, 'Second account should properly reflect reparented record for number of employees');
    System.assertEquals(one.Description + ', ' + three.Description, reparentAccount.Description, 'Second account should have only reparented case description');
    System.assertEquals(2, reparentAccount.AnnualRevenue, 'Second account sum field should include updated amount');
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
    System.assertEquals(null, acc.Phone, 'Phone should not have been updated since calc item where clause does not match');
    matchingAccount = [SELECT Phone FROM Account WHERE Id = :matchingAccount.Id];
    System.assertEquals(childTwo.Phone, matchingAccount.Phone, 'Phone should have been ordered by LastName!');
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
    System.assertEquals(childTwo.Phone, matchingAccount.Phone, 'Phone should have been updated based on new ordering');
    System.assertEquals(null, acc.Phone, 'Account phone should be cleared out since parent name field does not match');
  }
}
