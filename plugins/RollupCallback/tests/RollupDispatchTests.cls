@IsTest
public class RollupDispatchTests {
  private static Boolean dispatcherMockWasCalled = false;

  @IsTest
  static void shouldNotDispatchWithoutUpdatedRecords() {
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    Test.startTest();
    updater.doUpdate(new List<SObject>());
    Test.stopTest();

    System.assertEquals(false, RollupDispatch.wasCalled);
  }

  @IsTest
  static void shouldNotDispatchWhenPluginParameterOverrides() {
    RollupDispatch.platformEventOverride = String.valueOf(false);
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    Test.startTest();
    updater.doUpdate(new List<SObject>());
    Test.stopTest();

    System.assertEquals(false, RollupDispatch.wasCalled);
  }

  @IsTest
  static void shouldDispatchWhenMetadataPresent() {
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    Test.startTest();
    updater.doUpdate(new List<SObject>{ new Account() });
    System.assertEquals(1, Limits.getPublishImmediateDML(), 'Rollup callback event should have been published');
    Test.stopTest();

    System.assertEquals(true, RollupDispatch.wasCalled);
  }

  @IsTest
  static void shouldAllowForDispatcherParameterOverride() {
    RollupPlugin.parameterMock = new RollupPluginParameter__mdt(Value__c = DispatcherMock.class.getName());
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    Test.startTest();
    updater.doUpdate(new List<SObject>{ new Account() });
    Test.stopTest();

    System.assertEquals(true, RollupDispatch.wasCalled);
    System.assertEquals(true, dispatcherMockWasCalled);
  }

  public class DispatcherMock implements RollupSObjectUpdater.IDispatcher {
    public void dispatch(List<SObject> records) {
      dispatcherMockWasCalled = true;
    }
  }
}
