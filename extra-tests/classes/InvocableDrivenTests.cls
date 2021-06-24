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

    Case one = new Case(Amount__c = 1, AccountId = acc.Id, Description = 'distinct', Subject = 'One');
    Case two = new Case(Amount__c = 2, AccountId = acc.Id, Description = 'again', Subject = 'Two');
    Case three = new Case(Amount__c = 0, AccountId = reparentAccount.Id, Description = 'something else', Subject = 'Three');
    Case four = new Case(Amount__c = 0, AccountId = reparentAccount.Id, Description = one.Description, Subject = 'Four');

    Test.startTest();
    insert new List<Case>{ one, two, three, four };

    one.Amount__c = 2;
    one.AccountId = reparentAccount.Id;
    update one;

    one.Subject = 'Z';
    update one;
    Test.stopTest();

    acc = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    reparentAccount = [SELECT Id, Description, AnnualRevenue, Name, NumberOfEmployees FROM Account WHERE Id = :reparentAccount.Id];

    System.assertEquals(2, acc.AnnualRevenue, 'First account sum field should be decremented on reparent');
    System.assertEquals(two.Description, acc.Description, 'CONCAT_DISTINCT should remove extra text on reparent');
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals(two.Subject, acc.Name);

    System.assertEquals(3, reparentAccount.NumberOfEmployees, 'Second account should properly reflect reparented record for number of employees');
    System.assertEquals(one.Description + ', ' + three.Description, reparentAccount.Description, 'Second account should have only reparented case description');
    System.assertEquals(one.Subject, reparentAccount.Name, 'Second account name field should reflect last subject');
    System.assertEquals(2, reparentAccount.AnnualRevenue, 'Second account sum field should include updated amount');
  }
}