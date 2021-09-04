@IsTest
public class RollupSObjectUpdaterTests {
  @IsTest
  static void shouldAllowDatetimeToBeSavedAsDate() {
    Datetime now = System.now();

    Opportunity opp = new Opportunity();

    new RollupSObjectUpdater(Opportunity.CloseDate).updateField(opp, now);

    System.assertEquals(now.dateGmt(), opp.CloseDate);
  }

  @IsTest
  static void shouldRethrowForUnhandledConversion() {
    SObjectException ex;

    try {
      new RollupSObjectUpdater(Opportunity.CloseDate).updateField(new Opportunity(), 1);
    } catch (SObjectException e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @IsTest
  static void shouldDispatchOnUpdate() {
    RollupSObjectUpdater.pluginParameterMock = new RollupPluginParameter__mdt(Value__c = DispatcherMock.class.getName());
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    updater.doUpdate(new List<SObjecT>{ new Account() });

    System.assertEquals(true, dispatcherMockWasCalled);
  }

  private static Boolean dispatcherMockWasCalled = false;
  public class DispatcherMock implements RollupSObjectUpdater.IDispatcher {
    public void dispatch(List<SObject> records) {
      dispatcherMockWasCalled = true;
    }
  }
}
