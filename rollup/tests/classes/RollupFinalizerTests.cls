@IsTest
private class RollupFinalizerTests {
  public virtual class ExampleFinalizerContext implements System.FinalizerContext {
    public Id getAsyncApexJobId() {
      return RollupTestUtils.createId(AsyncApexJob.SObjectType);
    }

    public String getRequestId() {
      return System.Request.getCurrent().getRequestId();
    }

    public virtual ParentJobResult getResult() {
      return ParentJobResult.UNHANDLED_EXCEPTION;
    }

    public Exception getException() {
      return new DmlException();
    }
  }

  private class SuccessfulFinalizerContext extends ExampleFinalizerContext {
    public override ParentJobResult getResult() {
      return ParentJobResult.SUCCESS;
    }
  }

  private static final List<String> TRACKING_PROCESSOR_RUN_ORDER = new List<String>();
  private class TrackingProcessor extends RollupAsyncProcessor {
    private final String name;
    private final Boolean startsAsync;

    public TrackingProcessor(String name, Boolean startsAsync) {
      super((Rollup.InvocationPoint) null);
      this.name = name;
      this.startsAsync = startsAsync;
    }

    public override String runCalc() {
      TRACKING_PROCESSOR_RUN_ORDER.add(this.name);
      return this.startsAsync ? 'started' : this.getNoProcessId();
    }
  }

  @IsTest
  static void trailingCabooseAlwaysRunsAfterRegularCabooses() {
    RollupFinalizer finalizer = new RollupFinalizer();
    finalizer.setTrailingCaboose(new TrackingProcessor('trailing', false));
    finalizer.addCaboose(new TrackingProcessor('first', false));
    finalizer.addCaboose(new TrackingProcessor('second', false));

    Test.startTest();
    finalizer.execute(new SuccessfulFinalizerContext());
    Test.stopTest();

    Assert.areEqual(new List<String>{ 'first', 'second', 'trailing' }, TRACKING_PROCESSOR_RUN_ORDER);
  }

  @IsTest
  static void trailingCabooseWaitsForConductorThatStartedAsync() {
    RollupFinalizer finalizer = new RollupFinalizer();
    finalizer.setTrailingCaboose(new TrackingProcessor('trailing', false));
    finalizer.addCaboose(new TrackingProcessor('conductor', true));

    Test.startTest();
    finalizer.execute(new SuccessfulFinalizerContext());
    Test.stopTest();

    Assert.areEqual(new List<String>{ 'conductor' }, TRACKING_PROCESSOR_RUN_ORDER, 'Only one async start is allowed per finalizer');
    finalizer.execute(new SuccessfulFinalizerContext());
    Assert.areEqual(new List<String>{ 'conductor', 'trailing' }, TRACKING_PROCESSOR_RUN_ORDER, 'Trailing caboose should run on the next finalizer pass');
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
