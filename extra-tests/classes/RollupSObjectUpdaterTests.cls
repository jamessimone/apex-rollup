@IsTest
public class RollupSObjectUpdaterTests {
  private static Boolean dispatcherMockWasCalled = false;

  @IsTest
  static void shouldAllowDatetimeToBeSavedAsDate() {
    Datetime now = System.now();

    Opportunity opp = new Opportunity();

    new RollupSObjectUpdater(Opportunity.CloseDate).updateField(opp, now);

    System.assertEquals(now.dateGmt(), opp.CloseDate);
  }

  @IsTest
  static void shouldAllowDecimalToBeSavedAsInteger() {
    Account acc = new Account();
    new RollupSObjectUpdater(Account.NumberOfEmployees).updateField(acc, 3.00);

    System.assertEquals(3, acc.NumberOfEmployees);
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
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    // replicated dispatch plugin existing
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = RollupSObjectUpdater.DISPATCH_NAME) };
    RollupPlugin.parameterMock = new RollupPluginParameter__mdt(Value__c = DispatcherMock.class.getName());
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    updater.doUpdate(new List<SObjecT>{ new Account() });

    System.assertEquals(true, dispatcherMockWasCalled);
  }

  public class DispatcherMock implements RollupSObjectUpdater.IDispatcher {
    public void dispatch(List<SObject> records) {
      dispatcherMockWasCalled = true;
    }
  }
}
