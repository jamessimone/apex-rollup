@isTest
private class InvocableDrivenTests {
  // Driven by extra-tests/flows/Rollup_Integration_Multiple_Deferred_Case_Rollups.flow-meta.xml

  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    Account acc = new Account(Name = 'InvocableDrivenRollupTests');
    insert acc;
  }

  @isTest
  static void shouldRollupMultipleDMLStatementsWithinSingleTransaction() {
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

  // TODO - add test with calc item where clause filtering on parent field!
}
