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
    // replicate the existence of a dispatch plugin
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = RollupSObjectUpdater.DISPATCH_NAME) };
    RollupPlugin.parameterMock = new RollupPluginParameter__mdt(Value__c = DispatcherMock.class.getName());
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    updater.doUpdate(new List<SObjecT>{ new Account() });

    System.assertEquals(true, dispatcherMockWasCalled);
  }

  @IsTest
  static void shouldSortBySObjectTypePriorToUpdate() {
    Account one = new Account(Name = RollupSObjectUpdaterTests.class.getName());
    Individual two = new Individual(LastName = 'Two');
    Account three = new Account(Name = 'Three');
    Individual four = new Individual(LastName = 'Four');
    List<SObject> records = new List<SObject>{ one, two, three, four };
    insert records;

    new RollupSObjectUpdater().doUpdate(records);

    System.assertEquals(one, records[0]);
    System.assertEquals(three, records[1]);
    System.assertEquals(two, records[2]);
    System.assertEquals(four, records[3]);
  }

  public class DispatcherMock implements RollupSObjectUpdater.IDispatcher {
    public void dispatch(List<SObject> records) {
      dispatcherMockWasCalled = true;
    }
  }
}
