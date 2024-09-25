@IsTest
public class RollupSObjectUpdaterTests {
  private static Boolean dispatcherMockWasCalled = false;
  private static List<SObject> mockUpdatedRecords;

  @IsTest
  static void shouldAllowDatetimeToBeSavedAsDate() {
    Datetime now = System.now();

    Opportunity opp = new Opportunity();

    new RollupSObjectUpdater().updateField(Opportunity.CloseDate, opp, now);

    System.assertEquals(now.dateGmt(), opp.CloseDate);
  }

  @IsTest
  static void shouldAllowDecimalToBeSavedAsInteger() {
    Account acc = new Account();
    new RollupSObjectUpdater().updateField(Account.NumberOfEmployees, acc, 3.00);

    System.assertEquals(3, acc.NumberOfEmployees);
  }

  @IsTest
  static void convertsStringsToDatetimes() {
    Datetime nowish = System.now();
    String nowishString = nowish.format();

    Event ev = new Event();
    new RollupSObjectUpdater().updateField(Event.ActivityDatetime, ev, nowishString);

    System.assertEquals(nowish.addSeconds(-nowish.second()), ev.ActivityDatetime);
  }

  @IsTest
  static void convertsStringsToDates() {
    Date today = System.today();
    String todayString = today.format();

    Task t = new Task();
    new RollupSObjectUpdater().updateField(Task.ActivityDate, t, todayString);

    System.assertEquals(today, t.ActivityDate);
  }

  @IsTest
  static void shouldRethrowForUnhandledConversion() {
    SObjectException ex;

    try {
      new RollupSObjectUpdater().updateField(Opportunity.CloseDate, new Opportunity(), 1);
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

    updater.doUpdate(new List<SObject>{ new Account() });

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

  @IsTest
  static void stringifiesNonTextFieldsProperly() {
    Blob blobValue = EncodingUtil.base64Decode('10101010');
    Opportunity opp = new Opportunity();

    new RollupSObjectUpdater().updateField(Opportunity.Description, opp, blobValue);

    System.assertEquals(String.valueOf(blobValue), opp.Description);
  }

  @IsTest
  static void onlyUpdatesRecordsWithRollupChanges() {
    Account acc = new Account(Name = 'Should Not Be Updated');
    insert acc;
    acc = [SELECT Id, LastModifiedDate FROM Account];
    waitSeconds(1);

    new RollupSObjectUpdater().doUpdate([SELECT Id FROM Account WHERE Id = :acc.Id]);

    Account updatedAccount = [SELECT Id, LastModifiedDate FROM Account];
    System.assertEquals(acc, updatedAccount, 'Last modified date should not have updated if only Id was passed');
  }

  @IsTest
  static void doesNotSplitUpdatesWhenForcedSyncUpdateEnabled() {
    RollupSObjectUpdater.UPDATER_NAME = MockUpdater.class.getName();
    RollupPlugin.pluginMocks = new List<RollupPlugin__mdt>{ new RollupPlugin__mdt(DeveloperName = RollupSObjectUpdater.UPDATER_NAME) };
    RollupSObjectUpdater updater = new RollupSObjectUpdater();
    updater.forceSyncUpdate();
    updater.addRollupControl(new RollupControl__mdt(MaxParentRowsUpdatedAtOnce__c = 1));

    updater.doUpdate(new List<SObject>{ new Account(), new Contact() });

    System.assertEquals(2, mockUpdatedRecords.size());
  }

  @IsTest
  static void updatesSettingsWhenPreAndPostUpdaterIsUsed() {
    upsert new RollupSettings__c();
    RollupSettings__c initial = RollupSettings__c.getInstance();

    waitSeconds(1);
    RollupSObjectUpdater.UPDATER_NAME = MockUpdater.class.getName();
    RollupPlugin.parameterMock = new RollupPluginParameter__mdt(
      Value__c = RollupSObjectUpdater.class.getName() + '.' + 'PreAndPostUpdater',
      RollupPlugin__c = RollupPlugin__mdt.getInstance(RollupSObjectUpdater.PRE_AND_POST_UPDATER_NAME).Id
    );
    RollupSObjectUpdater updater = new RollupSObjectUpdater();
    updater.forceSyncUpdate();
    updater.doUpdate(new List<SObject>{ new Account() });

    System.assertNotEquals(initial, RollupSettings__c.getInstance());
  }

  @IsTest
  static void shouldThrowWhenControlValueEnabledForFailedSaves() {
    RollupSObjectUpdater updater = new RollupSObjectUpdater();
    updater.addRollupControl(new RollupControl__mdt(ShouldThrowOnSaveErrors__c = true));

    String message = '';
    try {
      updater.doUpdate(new List<SObject>{ new Account() });
      Assert.fail('Error should be thrown for account without Id');
    } catch (System.DmlException ex) {
      message = ex.getMessage();
    }

    Assert.areEqual('Update failed. First exception on row 0; first error: MISSING_ARGUMENT, Id not specified in an update call: []', message);
  }

  @IsTest
  static void nullRollupControlDoesNotPreventExecution() {
    RollupLimits.stubbedQueryRows = 50001;
    RollupControl__mdt control = new RollupControl__mdt();
    RollupSObjectUpdater updater = new RollupSObjectUpdater();

    updater.forceSyncUpdate();
    updater.addRollupControl(control);
    control = null;

    Exception ex;
    try {
      updater.doUpdate(new List<SObject>{ new Account(Id = RollupTestUtils.createId(Account.SObjectType)) });
    } catch (Exception e) {
      ex = e;
    }
    Assert.isNull(ex);
  }

  public class MockUpdater implements RollupSObjectUpdater.IUpdater {
    public void performUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options) {
      mockUpdatedRecords = recordsToUpdate;
    }
  }

  @SuppressWarnings('PMD.EmptyWhileStmt')
  private static void waitSeconds(Integer secondAmount) {
    Datetime nowish = System.now();
    while (System.now() < nowish.addSeconds(secondAmount)) {
      // let's waste some time together!
      // we could later compare the hashCode() of
      // the SObjects to ensure no update was made, but
      // I've legitimately seen instances where the update
      // happened so quick that a change in seconds wasn't registered
      // and the hashCode for SObjects is made up of all the selected fields
    }
  }

  public class DispatcherMock implements RollupSObjectUpdater.IDispatcher {
    public void dispatch(List<SObject> records) {
      dispatcherMockWasCalled = true;
    }
  }
}
