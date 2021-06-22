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

    Case one = new Case(Amount__c = 1, AccountId = acc.Id, Description = 'distinct');
    Case two = new Case(Amount__c = 2, AccountId = acc.Id, Description = 'again');

    Test.startTest();
    insert new List<Case>{ one, two };

    one.Amount__c = 2;
    one.AccountId = reparentAccount.Id;
    update one;
    Test.stopTest();

    acc = [SELECT Id, Description, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    reparentAccount = [SELECT Id, Description, AnnualRevenue FROM Account WHERE Id = :reparentAccount.Id];

    System.assertEquals(2, acc.AnnualRevenue, 'First account sum field should be decremented on reparent');
    System.assertEquals(two.Description, acc.Description, 'CONCAT_DISTINCT should remove extra text on reparent');

    System.assertEquals(2, reparentAccount.AnnualRevenue, 'Second account sum field should include updated amount');
    System.assertEquals(one.Description, reparentAccount.Description, 'Second account should have only reparented case description');
  }
}