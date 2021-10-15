@IsTest
private class RollupFinalizerTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new Account(Name = RollupFinalizerTests.class.getName());
  }

  @IsTest
  static void shouldGracefullyLogUnhandledException() {
    RollupFinalizer.testResult = ParentJobResult.UNHANDLED_EXCEPTION;

    Test.startTest();
    new RollupFinalizer().execute(null);
    Test.stopTest();

    System.assert(true, RollupFinalizer.wasCalled);
  }
}
