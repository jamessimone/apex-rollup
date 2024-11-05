@IsTest
private class RollupFinalizerTests {
  public class ExampleFinalizerContext implements System.FinalizerContext {
    public Id getAsyncApexJobId() {
      return RollupTestUtils.createId(AsyncApexJob.SObjectType);
    }

    public String getRequestId() {
      return System.Request.getCurrent().getRequestId();
    }

    public ParentJobResult getResult() {
      return ParentJobResult.UNHANDLED_EXCEPTION;
    }

    public Exception getException() {
      return new DmlException();
    }
  }

  @IsTest
  static void shouldGracefullyLogUnhandledException() {
    System.FinalizerContext fc = new ExampleFinalizerContext();

    Test.startTest();
    new RollupFinalizer().execute(fc);
    Test.stopTest();

    System.assertEquals(true, RollupFinalizer.wasExceptionLogged);
  }
}
