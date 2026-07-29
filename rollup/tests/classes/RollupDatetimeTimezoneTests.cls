@IsTest
private class RollupDatetimeTimezoneTests {
  // Without proper GMT normalization in RollupCalculator, these assertions
  // would fail for any user not in UTC because Datetime.newInstance(Long) and
  // Datetime.newInstance(Date, Time) interpret args in the running user's local timezone.

  @IsTest
  static void datetimeRollupRoundTripIsTimezoneInvariant() {
    User pacificUser = createUserWithTimezone('America/Los_Angeles');

    System.runAs(pacificUser) {
      // A known Datetime whose GMT components we'll verify survive the round-trip
      Datetime knownDt = Datetime.newInstanceGmt(2024, 6, 15, 22, 30, 0);

      Rollup__mdt metadata = new Rollup__mdt();
      RollupCalculator calc = RollupCalculator.Factory.getCalculator(
        RollupOperation.MAX,
        Event.ActivityDateTime,
        Event.ActivityDateTime,
        metadata,
        Event.WhatId
      );
      calc.setDefaultValues(RollupTestUtils.createId(Account.SObjectType), knownDt);

      // Feed the known Datetime through the calculator as a calc item
      Event evt = new Event(ActivityDateTime = knownDt, Id = RollupTestUtils.createId(Event.SObjectType));
      calc.performRollup(new List<SObject>{ evt }, new Map<Id, SObject>());

      Datetime result = (Datetime) calc.getReturnValue();

      // The GMT components must match the original — timezone must not shift them
      System.assertEquals(knownDt.yearGmt(), result.yearGmt(), 'yearGmt mismatch');
      System.assertEquals(knownDt.monthGmt(), result.monthGmt(), 'monthGmt mismatch');
      System.assertEquals(knownDt.dayGmt(), result.dayGmt(), 'dayGmt mismatch');
      System.assertEquals(knownDt.hourGmt(), result.hourGmt(), 'hourGmt mismatch');
      System.assertEquals(knownDt.minuteGmt(), result.minuteGmt(), 'minuteGmt mismatch');
      System.assertEquals(knownDt.secondGmt(), result.secondGmt(), 'secondGmt mismatch');
    }
  }

  @IsTest
  static void dateStringEpochUsesGmtMidnight() {
    User pacificUser = createUserWithTimezone('America/Los_Angeles');

    System.runAs(pacificUser) {
      // A Date-only string that flows through getDecimalOrDefault's catch branch
      String dateString = '2024-06-15';
      Date expectedDate = Date.valueOf(dateString);
      Long expectedEpoch = Datetime.newInstanceGmt(expectedDate, Time.newInstance(0, 0, 0, 0)).getTime();

      Rollup__mdt metadata = new Rollup__mdt();
      RollupCalculator calc = RollupCalculator.Factory.getCalculator(
        RollupOperation.MIN,
        Event.ActivityDateTime,
        Event.ActivityDateTime,
        metadata,
        Event.WhatId
      );
      // Pass the date string as the "prior value" — setDefaultValues routes through getDecimalOrDefault
      calc.setDefaultValues(RollupTestUtils.createId(Account.SObjectType), dateString);

      // Feed a later Datetime so the MIN stays on our date-string value
      Event evt = new Event(ActivityDateTime = Datetime.newInstanceGmt(2025, 1, 1, 0, 0, 0), Id = RollupTestUtils.createId(Event.SObjectType));
      calc.performRollup(new List<SObject>{ evt }, new Map<Id, SObject>());

      Datetime result = (Datetime) calc.getReturnValue();

      // The epoch of the result must equal GMT midnight of that date, regardless of user timezone
      System.assertEquals(expectedEpoch, result.getTime(), 'Date-string epoch should equal GMT midnight');
    }
  }

  private static User createUserWithTimezone(String timeZoneSidKey) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String uniqueness = String.valueOf(Crypto.getRandomInteger()).right(6);
    return new User(
      Alias = 'tztest',
      Email = 'tztest' + uniqueness + '@rolluptest.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'TzTest',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = timeZoneSidKey,
      UserName = 'tztest' + uniqueness + '@rolluptest.invalid'
    );
  }
}
