@IsTest
private class RollupFinalizerTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new Account(Name = RollupFinalizerTests.class.getName());
  }

  @IsTest
  static void shouldRestartRollupWhenQueueableFails() {
    Account acc = [SELECT Id FROM Account];

    RollupFinalizer.testResult = ParentJobResult.UNHANDLED_EXCEPTION;
    Rollup.records = new List<Opportunity>{ new Opportunity(AccountId = acc.Id, Amount = 5) };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup roll = Rollup.sumFromApex(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType);

    Test.startTest();
    new RollupFinalizer(roll).execute(null);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(5, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldGracefullyRecoverFromThrownException() {
    RollupFinalizer.testResult = ParentJobResult.UNHANDLED_EXCEPTION;

    Test.startTest();
    new RollupFinalizer(null).execute(null);
    Test.stopTest();

    System.assert(true, 'Should make it here');
  }
}
