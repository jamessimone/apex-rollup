@SuppressWarnings('PMD.NcssTypeCount,PMD.ApexUnitTestClassShouldHaveAsserts')
@IsTest
private class RollupDateLiteralTests {
  private static final Integer HOUR_IN_DAY = 8;
  @TestSetup
  static void setup() {
    Datetime localStart = Datetime.newInstance(Date.newInstance(System.today().year() - 2, 1, 1), Time.newInstance(0, 0, 0, 0));
    Datetime localEnd = Datetime.newInstance(localStart.date(), Time.newInstance(23, 59, 59, 59));
    Datetime sentinelEnd = Datetime.newInstance(Date.newInstance(System.today().year() + 3, 1, 1), localStart.time());
    ContactPointAddress cpaParent = new ContactPointAddress(Name = 'Parent');
    insert cpaParent;

    List<ContactPointConsent> cpcs = new List<ContactPointConsent>();
    while (localEnd < sentinelEnd) {
      cpcs.add(new ContactPointConsent(Name = 'Day start ' + localStart, CaptureDate = localStart, ContactPointId = cpaParent.Id));
      cpcs.add(new ContactPointConsent(Name = 'Day end ' + localEnd, CaptureDate = localEnd, ContactPointId = cpaParent.Id));
      localStart = localStart.addDays(1);
      localEnd = localEnd.addDays(1);
    }
    cpcs.add(
      new ContactPointConsent(
        Name = 'Hour in day pre ' + localStart,
        CaptureDate = Datetime.newInstanceGmt(System.today(), Time.newInstance(HOUR_IN_DAY - 1, 0, 0, 0)),
        ContactPointId = cpaParent.Id
      )
    );
    cpcs.add(
      new ContactPointConsent(
        Name = 'Hour in day post ' + localStart,
        CaptureDate = Datetime.newInstanceGmt(System.today(), Time.newInstance(HOUR_IN_DAY + 1, 0, 0, 0)),
        ContactPointId = cpaParent.Id
      )
    );
    insert cpcs;

    insert new List<User>{
      new User(
        LastName = 'Australia User',
        Username = 'Australia' + System.now().getTime() + '@RollupDateLiteralTests.org',
        Email = 'australiauser@rollup.org',
        EmailEncodingKey = 'ISO-8859-1',
        Alias = 'aususer',
        TimeZoneSidKey = 'Australia/Sydney',
        LocaleSidKey = 'en_US',
        LanguageLocaleKey = 'en_US',
        ProfileId = UserInfo.getProfileId()
      ),
      new User(
        LastName = 'Berlin User',
        Username = 'Berlin' + System.now().getTime() + '@RollupDateLiteralTests.org',
        Email = 'berlinuser@rollup.org',
        EmailEncodingKey = 'ISO-8859-1',
        Alias = 'berlusr',
        TimeZoneSidKey = 'Europe/Berlin',
        LocaleSidKey = 'de_DE',
        LanguageLocaleKey = 'de',
        ProfileId = UserInfo.getProfileId()
      )
    };
  }

  @IsTest
  static void shouldProperlyDetectDateLiteralStrings() {
    List<String> dateLiterals = new List<String>{
      'YESTERDAY',
      'TODAY',
      'TOMORROW',
      'LAST_WEEK',
      'THIS_WEEK',
      'NEXT_WEEK',
      'LAST_MONTH',
      'THIS_MONTH',
      'NEXT_MONTH',
      'LAST_90_DAYS',
      'NEXT_90_DAYS',
      'LAST_N_DAYS:2',
      'NEXT_N_DAYS:2',
      'LAST_N_WEEKS:2',
      'NEXT_N_WEEKS:2',
      'LAST_N_MONTHS:2',
      'NEXT_N_MONTHS:2',
      'THIS_QUARTER',
      'LAST_QUARTER',
      'NEXT_QUARTER',
      'NEXT_N_QUARTERS:24',
      'LAST_N_QUARTERS:2',
      'NEXT_N_QUARTERS: 2515', // validate spaces work
      'THIS_YEAR',
      'LAST_YEAR',
      'NEXT_YEAR',
      'LAST_N_YEARS:2',
      'NEXT_N_YEARS:2',
      'THIS_FISCAL_QUARTER',
      'LAST_FISCAL_QUARTER',
      'NEXT_FISCAL_QUARTER',
      'LAST_N_FISCAL_QUARTERS:2',
      'NEXT_N_FISCAL_QUARTERS:2',
      'LAST_FISCAL_YEAR',
      'THIS_FISCAL_YEAR',
      'NEXT_FISCAL_YEAR',
      'LAST_N_FISCAL_YEARS:2',
      'NEXT_N_FISCAL_YEARS:2',
      'N_DAYS_AGO:1',
      'N_WEEKS_AGO:1',
      'N_MONTHS_AGO:1',
      'N_QUARTERS_AGO:1',
      'N_FISCAL_QUARTERS_AGO:1',
      'N_YEARS_AGO:1',
      'N_FISCAL_YEARS_AGO:1'
    };

    for (String dateLiteral : dateLiterals) {
      System.assertEquals(true, RollupDateLiteral.isDateLiteral(dateLiteral), 'Date literal was not detected properly: ' + dateLiteral);
      System.assertEquals(true, String.isNotBlank(RollupDateLiteral.get(dateLiteral).toString()));
    }
  }

  @IsTest
  static void shouldProperlyDetectDateFunctionStrings() {
    List<String> dateFunctions = new List<String>{
      'CALENDAR_MONTH(CreatedDate)',
      'CALENDAR_QUARTER(CreatedDate)',
      'CALENDAR_YEAR(CreatedDate)',
      'CALENDAR_YEAR(CreatedDate)',
      'DAY_IN_MONTH(CreatedDate)',
      'DAY_IN_WEEK(CreatedDate)',
      'DAY_IN_YEAR(CreatedDate)',
      'DAY_ONLY(CreatedDate)',
      'FISCAL_MONTH(CreatedDate)',
      'FISCAL_QUARTER(CreatedDate)',
      'FISCAL_YEAR(CreatedDate)',
      'HOUR_IN_DAY(CreatedDate)',
      'WEEK_IN_MONTH(CreatedDate)',
      'WEEK_IN_YEAR(CreatedDate)'
    };
    for (String dateFunction : dateFunctions) {
      System.assertEquals(true, RollupDateLiteral.isSoqlDateFunction(dateFunction), 'Date function not detected properly: ' + dateFunction);
    }
  }

  // these tests are more or less in the order that the SOQL date literals appear within the corresponding Salesforce Developer doc page for them
  // though I have standardized last/current/next ordering since ... that just makes sense

  private static ContactPointConsent getSentinelCpc(String dateLiteral, String equality) {
    String orderBy;
    switch on equality {
      when '<' {
        orderBy = 'DESC';
      }
      when '>' {
        orderBy = 'ASC';
      }
      when else {
        throw new IllegalArgumentException('Equality not supported: ' + equality);
      }
    }
    String query =
      'SELECT CaptureDate' +
      '\nFROM ContactPointConsent' +
      '\nWHERE ' +
      dateLiteral.replace('=', equality) +
      '\nORDER BY CaptureDate ' +
      orderBy +
      '\nLIMIT 1';
    List<ContactPointConsent> cpcs = Database.query(query);
    return cpcs.isEmpty() ? null : cpcs.get(0);
  }

  static void runFunctionTest(List<User> users, String literal, String val) {
    for (User u : users) {
      RollupLogger.Instance.log('Running ' + literal + ' test for user', u, System.LoggingLevel.DEBUG);
      System.runAs(u) {
        runFunctionTest(literal, val);
      }
    }
  }

  static void runFunctionTest(String functionLiteral, String val) {
    runTestForLiteral(RollupDateLiteral.getFunction(functionLiteral, val), functionLiteral + '(CaptureDate) = ' + val);
  }

  static void runTestForLiteral(List<User> users, String literal) {
    for (User u : users) {
      RollupLogger.Instance.log('Running ' + literal + ' test for user', u, System.LoggingLevel.DEBUG);
      System.runAs(u) {
        runTestForLiteral(literal);
      }
    }
  }

  static void runTestForLiteral(String dateLiteral) {
    runTestForLiteral(RollupDateLiteral.get(dateLiteral), 'CaptureDate = ' + dateLiteral);
  }

  static void runTestForLiteral(RollupDateLiteral literalUnderTest, String stringLiteral) {
    List<ContactPointConsent> matchingCpcs = Database.query('SELECT CaptureDate FROM ContactPointConsent WHERE ' + stringLiteral + ' ORDER BY CaptureDate');
    ContactPointConsent sentinelPreviousCpc = getSentinelCpc(stringLiteral, '<');
    ContactPointConsent sentinelPostCpc = getSentinelCpc(stringLiteral, '>');

    System.assertNotEquals(true, matchingCpcs.isEmpty());
    for (ContactPointConsent cpc : matchingCpcs) {
      assert(literalUnderTest, cpc.CaptureDate, '=');
    }
    if (sentinelPostCpc != null) {
      assert(literalUnderTest, sentinelPostCpc.CaptureDate, '>');
      assert(literalUnderTest, sentinelPostCpc.CaptureDate, '>=');
      assert(literalUnderTest, sentinelPostCpc.CaptureDate.dateGmt(), '>=');
    }
    if (sentinelPreviousCpc != null) {
      assert(literalUnderTest, sentinelPreviousCpc.CaptureDate, '<');
      assert(literalUnderTest, sentinelPreviousCpc.CaptureDate, '<=');
      assert(literalUnderTest, sentinelPreviousCpc.CaptureDate.dateGmt(), '<=');
    }
  }

  static void assert(RollupDateLiteral literal, Object possibleDate, String equality) {
    System.assertEquals(
      true,
      literal.matches(possibleDate, equality),
      'Literal defined as ' + literal + ' should have matched ' + possibleDate + ' for ' + equality + ' for timezone ' + UserInfo.getTimeZone() + '\n'
    );
  }

  static User australiaUser {
    get {
      return [SELECT Id, Name FROM User WHERE LastName = 'Australia User'];
    }
  }

  static User berlinUser {
    get {
      return [SELECT Id, Name FROM User WHERE LastName = 'Berlin User'];
    }
  }

  static User currentUser {
    get {
      return new User(Id = UserInfo.getUserId(), AboutMe = UserInfo.getName());
    }
  }

  @IsTest
  static void shouldWorkForYesterday() {
    runTestForLiteral('YESTERDAY');
  }

  @IsTest
  static void shouldWorkForToday() {
    runTestForLiteral('TODAY');
    System.runAs(australiaUser) {
      runTestForLiteral('TODAY');
    }
  }

  @IsTest
  static void shouldWorkForTomorrow() {
    runTestForLiteral('TOMORROW');
    System.runAs(australiaUser) {
      runTestForLiteral('TOMORROW');
    }
  }

  @IsTest
  static void shouldWorkForLastWeek() {
    runTestForLiteral('LAST_WEEK');
    System.runAs(australiaUser) {
      runTestForLiteral('LAST_WEEK');
    }
  }

  @IsTest
  static void shouldWorkForThisWeek() {
    runTestForLiteral('THIS_WEEK');
  }

  @IsTest
  static void shouldWorkForNextWeek() {
    runTestForLiteral('NEXT_WEEK');
    System.runAs(australiaUser) {
      runTestForLiteral('NEXT_WEEK');
    }
  }

  @IsTest
  static void shouldWorkForLastMonth() {
    runTestForLiteral('LAST_MONTH');
    System.runAs(australiaUser) {
      runTestForLiteral('LAST_MONTH');
    }
  }

  @IsTest
  static void shouldWorkForThisMonth() {
    runTestForLiteral('THIS_MONTH');
    System.runAs(australiaUser) {
      runTestForLiteral('THIS_MONTH');
    }
  }

  @IsTest
  static void shouldWorkForNextMonth() {
    runTestForLiteral('NEXT_MONTH');
    System.runAs(australiaUser) {
      runTestForLiteral('NEXT_MONTH');
    }
  }

  @IsTest
  static void shouldWorkForLast90Days() {
    runTestForLiteral('LAST_90_DAYS');
    System.runAs(berlinUser) {
      runTestForLiteral('LAST_90_DAYS');
    }
  }

  @IsTest
  static void shouldWorkForNext90Days() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_90_DAYS');
  }

  @IsTest
  static void shouldWorkForLastNDays() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'LAST_N_DAYS:5');
  }

  @IsTest
  static void shouldWorkForNDaysAgo() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'N_DAYS_AGO:5');
  }

  @IsTest
  static void shouldWorkForNextNDays() {
    runTestForLiteral('NEXT_N_DAYS:5');
  }

  @IsTest
  static void shouldWorkForLastNWeeks() {
    runTestForLiteral('LAST_N_WEEKS:2');
  }

  @IsTest
  static void shouldWorkForNWeeksAgo() {
    runTestForLiteral('N_WEEKS_AGO:2');
  }

  @IsTest
  static void shouldWorkForNextNWeeks() {
    runTestForLiteral('NEXT_N_WEEKS:2');
  }

  @IsTest
  static void shouldWorkForLastNMonths() {
    runTestForLiteral('LAST_N_MONTHS:2');
  }

  @IsTest
  static void shouldWorkForNMonthsAgo() {
    runTestForLiteral('N_MONTHS_AGO:2');
  }

  @IsTest
  static void shouldWorkForNextNMonths() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_MONTHS:2');
  }

  @IsTest
  static void shouldWorkForLastQuarter() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'LAST_QUARTER');
  }

  @IsTest
  static void shouldWorkForThisQuarter() {
    runTestForLiteral('THIS_QUARTER');
  }

  @IsTest
  static void shouldWorkForNextQuarter() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_QUARTER');
  }

  @IsTest
  static void shouldWorkForLastNQuarters() {
    // TODO get this working for berlinUser
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'LAST_N_QUARTERS: 2');
  }

  @IsTest
  static void shouldWorkForNQuartersAgo() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'N_QUARTERS_AGO:7');
  }

  @IsTest
  static void shouldWorkForNextNQuarters() {
    runTestForLiteral('NEXT_N_QUARTERS: 7');
  }

  @IsTest
  static void shouldWorkForThisYear() {
    runTestForLiteral('THIS_YEAR');
  }

  @IsTest
  static void shouldWorkForLastYear() {
    runTestForLiteral('LAST_YEAR');
  }

  @IsTest
  static void shouldWorkForNextYear() {
    runTestForLiteral('NEXT_YEAR');
  }

  @IsTest
  static void shouldWorkForLastNYears() {
    runTestForLiteral('LAST_N_YEARS: 2');
    // ensure single year fixed range works, as well
    runTestForLiteral('LAST_N_YEARS: 1');
  }

  @IsTest
  static void shouldWorkForNYearsAgo() {
    runTestForLiteral('N_YEARS_AGO:2');
  }

  @IsTest
  static void shouldWorkForNextNYears() {
    runTestForLiteral('NEXT_N_YEARS:1');
  }

  @IsTest
  static void shouldWorkForLastFiscalQuarter() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'LAST_FISCAL_QUARTER');
  }

  @IsTest
  static void shouldWorkForThisFiscalQuarter() {
    runTestForLiteral('THIS_FISCAL_QUARTER');
  }

  @IsTest
  static void shouldWorkForNextFiscalQuarter() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_FISCAL_QUARTER');
  }

  @IsTest
  static void shouldWorkForLastNFiscalQuarters() {
    // TODO get this working for berlinUser
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'LAST_N_FISCAL_QUARTERS: 7');
  }

  @IsTest
  static void shouldWorkForNFiscalQuartersAgo() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'N_FISCAL_QUARTERS_AGO: 2');
  }

  @IsTest
  static void shouldWorkForNextNFiscalQuarters() {
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 1');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 2');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 3');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 4');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 5');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 6');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 7');
    runTestForLiteral(new List<User>{ currentUser, berlinUser }, 'NEXT_N_FISCAL_QUARTERS: 8');
  }

  @IsTest
  static void shouldWorkForLastFiscalYear() {
    runTestForLiteral('LAST_FISCAL_YEAR');
  }

  @IsTest
  static void shouldWorkForThisFiscalYear() {
    runTestForLiteral('THIS_FISCAL_YEAR');
  }

  @IsTest
  static void shouldWorkForNextFiscalYear() {
    runTestForLiteral('NEXT_FISCAL_YEAR');
  }

  @IsTest
  static void shouldWorkForLastNFiscalYears() {
    runTestForLiteral('LAST_N_FISCAL_YEARS: 1');
  }

  @IsTest
  static void shouldWorkForNFiscalYearsAgo() {
    runTestForLiteral('N_FISCAL_YEARS_AGO:1');
  }

  @IsTest
  static void shouldWorkForNextNFiscalYears() {
    runTestForLiteral('NEXT_N_FISCAL_YEARS:1');
  }

  @IsTest
  static void shouldWorkForCalendarMonth() {
    runFunctionTest('CALENDAR_MONTH', '11');
  }

  @IsTest
  static void shouldWorkForCalendarYearFunction() {
    runFunctionTest('CALENDAR_YEAR', String.valueOf(System.today().year()));
  }

  @IsTest
  static void shouldWorkForCalendarQuarterFunction() {
    runFunctionTest('CALENDAR_QUARTER', '2');
  }

  @IsTest
  static void shouldWorkForDayInWeekFunction() {
    runFunctionTest(new List<User>{ currentUser }, 'DAY_IN_WEEK', '2');
  }

  @IsTest
  static void shouldWorkForDayInYearFunction() {
    runFunctionTest('DAY_IN_YEAR', '2');
  }

  @IsTest
  static void shouldWorkForDayOnlyFunction() {
    runFunctionTest('DAY_ONLY', System.now().format('YYYY-MM-dd'));
  }

  @IsTest
  static void shouldWorkForFiscalMonthFunction() {
    runFunctionTest('FISCAL_MONTH', '4');
  }

  @IsTest
  static void shouldWorkForFiscalQuarterFunction() {
    // confusingly, there isn't a standard QUARTER function,
    // so there's no corresponding QUARTER version of this test
    runFunctionTest('FISCAL_QUARTER', '1');
    runFunctionTest('FISCAL_QUARTER', '2');
    runFunctionTest('FISCAL_QUARTER', '3');
    runFunctionTest('FISCAL_QUARTER', '4');
  }

  @IsTest
  static void shouldWorkForFiscalYearFunction() {
    runFunctionTest('FISCAL_YEAR', String.valueOf(System.today().year()));
  }

  @IsTest
  static void shouldWorkForHourInDayFunction() {
    Datetime comparisonDate = Datetime.newInstanceGmt(2020, 1, 1, 4, 0, 0);
    Datetime oneHourBefore = comparisonDate.addHours(-1);
    Datetime oneHourAfter = comparisonDate.addHours(1);
    RollupDateLiteral hourInDay = RollupDateLiteral.getFunction('HOUR_IN_DAY(CreatedDate)', '4');

    System.assertEquals(true, hourInDay.matches(comparisonDate, '='), hourInDay);
    System.assertEquals(false, hourInDay.matches(oneHourBefore, '='));
    System.assertEquals(false, hourInDay.matches(oneHourAfter, '='));
    System.assertEquals(false, hourInDay.matches(comparisonDate, '!='));

    System.assertEquals(true, hourInDay.matches(oneHourAfter, '>'));
    System.assertEquals(true, hourInDay.matches(oneHourBefore, '<'));
  }

  @IsTest
  static void shouldWorkForWeekInMonthFunction() {
    // This test doesn't fit the paradigm necessary in "runFunctionTest"
    // for example, there's no possible value for a WEEK_IN_MONTH(CaptureDate) < 1
    for (User u : new List<User>{ currentUser, berlinUser }) {
      System.runAs(u) {
        Datetime comparisonDate = Datetime.newInstance(2020, 1, 1);
        Datetime oneWeekBefore = comparisonDate.addDays(-7);
        Datetime oneWeekAfter = comparisonDate.addDays(7);
        RollupDateLiteral weekInMonth = RollupDateLiteral.getFunction('WEEK_IN_MONTH(CreatedDate)', '1');

        System.assertEquals(true, weekInMonth.matches(comparisonDate, '='), weekInMonth + '\n' + u);
        System.assertEquals(false, weekInMonth.matches(oneWeekBefore, '='));
        System.assertEquals(false, weekInMonth.matches(oneWeekAfter, '='));
        System.assertEquals(false, weekInMonth.matches(comparisonDate, '!='));

        System.assertEquals(true, weekInMonth.matches(oneWeekAfter, '>'));
        // deviation - last week of the last month exceeds the first week of this month
        System.assertEquals(true, weekInMonth.matches(oneWeekBefore, '>'));

        comparisonDate = Datetime.newInstance(2020, 1, 8);
        oneWeekBefore = comparisonDate.addDays(-7);
        oneWeekAfter = comparisonDate.addDays(7);
        weekInMonth = RollupDateLiteral.getFunction('WEEK_IN_MONTH(CreatedDate)', '2');

        System.assertEquals(true, weekInMonth.matches(comparisonDate, '='), weekInMonth);
        System.assertEquals(false, weekInMonth.matches(oneWeekBefore, '='));
        System.assertEquals(false, weekInMonth.matches(oneWeekAfter, '='));
        System.assertEquals(false, weekInMonth.matches(comparisonDate, '!='));

        System.assertEquals(true, weekInMonth.matches(oneWeekAfter, '>'));
        System.assertEquals(true, weekInMonth.matches(oneWeekBefore, '<'));

        comparisonDate = Datetime.newInstance(2020, 1, 15);
        oneWeekBefore = comparisonDate.addDays(-7);
        oneWeekAfter = comparisonDate.addDays(7);
        weekInMonth = RollupDateLiteral.getFunction('WEEK_IN_MONTH(CreatedDate)', '3');

        System.assertEquals(true, weekInMonth.matches(comparisonDate, '='), weekInMonth);
        System.assertEquals(false, weekInMonth.matches(oneWeekBefore, '='));
        System.assertEquals(false, weekInMonth.matches(oneWeekAfter, '='));
        System.assertEquals(false, weekInMonth.matches(comparisonDate, '!='));

        System.assertEquals(true, weekInMonth.matches(oneWeekAfter, '>'));
        System.assertEquals(true, weekInMonth.matches(oneWeekBefore, '<'));

        // ensure february is handled correctly
        comparisonDate = Datetime.newInstance(2020, 2, 28);
        oneWeekBefore = comparisonDate.addDays(-7);
        oneWeekAfter = comparisonDate.addDays(7);
        weekInMonth = RollupDateLiteral.getFunction('WEEK_IN_MONTH(CreatedDate)', '4');

        System.assertEquals(true, weekInMonth.matches(comparisonDate, '='), weekInMonth);
        System.assertEquals(false, weekInMonth.matches(oneWeekBefore, '='));
        System.assertEquals(false, weekInMonth.matches(oneWeekAfter, '='));
        System.assertEquals(false, weekInMonth.matches(comparisonDate, '!='));

        // deviation - week after is now week one of the next month
        System.assertEquals(true, weekInMonth.matches(oneWeekAfter, '<'));
        System.assertEquals(true, weekInMonth.matches(oneWeekBefore, '<'));

        comparisonDate = Datetime.newInstance(2020, 12, 29);
        oneWeekBefore = comparisonDate.addDays(-7);
        oneWeekAfter = comparisonDate.addDays(7);
        weekInMonth = RollupDateLiteral.getFunction('WEEK_IN_MONTH(CreatedDate)', '5');

        System.assertEquals(true, weekInMonth.matches(comparisonDate, '='), weekInMonth);
        System.assertEquals(false, weekInMonth.matches(oneWeekBefore, '='));
        System.assertEquals(false, weekInMonth.matches(oneWeekAfter, '='));
        System.assertEquals(false, weekInMonth.matches(comparisonDate, '!='));

        // deviation - week after is now week one of the next month
        System.assertEquals(true, weekInMonth.matches(oneWeekAfter, '<'));
        System.assertEquals(true, weekInMonth.matches(oneWeekBefore, '<'));
      }
    }
  }

  @IsTest
  static void shouldWorkForWeekInYearFunction() {
    // TODO - there are some edge cases with SimpleDateFormat (https://docs.oracle.com/javase/7/docs/api/java/text/SimpleDateFormat.html)
    // that the current implementation doesn't QUITE cover which the commented out lines expose ...
    // runFunctionTest('WEEK_IN_YEAR', '14');
    // runFunctionTest('WEEK_IN_YEAR', '52');
    Datetime comparisonDate = Datetime.newInstance(2020, 4, 1);
    Datetime oneWeekBefore = comparisonDate.addDays(-7);
    Datetime oneWeekAfter = comparisonDate.addDays(7);
    RollupDateLiteral weekInYear = RollupDateLiteral.getFunction('WEEK_IN_YEAR(CreatedDate)', '14');

    System.assertEquals(true, weekInYear.matches(comparisonDate, '='), weekInYear);
    System.assertEquals(false, weekInYear.matches(oneWeekBefore, '='));
    System.assertEquals(false, weekInYear.matches(oneWeekAfter, '='));
    System.assertEquals(false, weekInYear.matches(comparisonDate, '!='));

    comparisonDate = Datetime.newInstance(2020, 12, 22);
    oneWeekBefore = comparisonDate.addDays(-7);
    oneWeekAfter = comparisonDate.addDays(7);
    // TODO according to SOQL, the below should actually be 51
    weekInYear = RollupDateLiteral.getFunction('WEEK_IN_YEAR(CreatedDate)', '52');

    System.assertEquals(true, weekInYear.matches(comparisonDate, '='), weekInYear);
    System.assertEquals(false, weekInYear.matches(oneWeekBefore, '='));
    System.assertEquals(false, weekInYear.matches(oneWeekAfter, '='));
    System.assertEquals(false, weekInYear.matches(comparisonDate, '!='));
  }

  // @IsTest
  static void printsLocalesWithDifferingWeekStarts() {
    // from https://help.salesforce.com/s/articleView?id=xcloud.admin_supported_locales.htm&type=5
    // I had to run this in two parts because System.runAs() performs a DML statement each time
    List<String> locales = new List<String>{
      // 'af_ZA',
      // 'am_ET',
      // 'ar_AE',
      // 'ar_BH',
      // 'ar_DZ',
      // 'ar_EG',
      // 'ar_IQ',
      // 'ar_JO',
      // 'ar_KW',
      // 'ar_LB',
      // 'ar_LY',
      // 'ar_MA',
      // 'ar_OM',
      // 'ar_QA',
      // 'ar_SA',
      // 'ar_TN',
      // 'ar_YE',
      // 'az_AZ',
      // 'be_BY',
      // 'bg_BG',
      // 'bn_BD',
      // 'bn_IN',
      // 'bs_BA',
      // 'ca_ES',
      // 'cs_CZ',
      // 'cy_GB',
      // 'da_DK',
      // 'de_AT',
      // 'de_BE',
      // 'de_CH',
      // 'de_DE',
      // 'de_LU',
      // 'dz_BT',
      // 'el_CY',
      // 'el_GR',
      // 'en_AE',
      // 'en_AG',
      // 'en_AU',
      // 'en_BB',
      // 'en_BE',
      // 'en_BM',
      // 'en_BS',
      // 'en_BW',
      // 'en_BZ',
      // 'en_CA',
      // 'en_CM',
      // 'en_CY',
      // 'en_DE',
      // 'en_ER',
      // 'en_FJ',
      // 'en_FK',
      // 'en_GB',
      // 'en_GH',
      // 'en_GI',
      // 'en_GM',
      // 'en_GY',
      // 'en_HK',
      // 'en_ID',
      // 'en_IE',
      // 'en_IL',
      // 'en_IN',
      // 'en_IT',
      // 'en_JM',
      // 'en_KE',
      // 'en_KY',
      // 'en_LR',
      // 'en_MG',
      // 'en_MT',
      // 'en_MU',
      // 'en_MW',
      // 'en_MY',
      // 'en_NA',
      // 'en_NG',
      // 'en_NL',
      // 'en_NZ',
      // 'en_PG',
      // 'en_PH',
      // 'en_PK',
      // 'en_RW',
      // 'en_SB',
      // 'en_SC',
      // 'en_SG',
      // 'en_SH',
      // 'en_SL',
      // 'en_SX',
      // 'en_SZ',
      // 'en_TO',
      // 'en_TT',
      // 'en_TZ',
      // 'en_UG',
      // 'en_VU',
      // 'en_WS',
      // 'en_ZA',
      // 'es_AR',
      // 'es_BO',
      // 'es_CL',
      // 'es_CO',
      // 'es_CR',
      // 'es_DO',
      // 'es_EC',
      // 'es_ES',
      // 'es_GT',
      // 'es_HN',
      // 'es_MX',
      // 'es_NI',
      // 'es_PA',
      // 'es_PE',
      // 'es_PR',
      // 'es_PY',
      // 'es_SV',
      // 'es_US',
      // 'es_UY',
      // 'es_VE',
      // 'et_EE',
      // 'eu_ES',
      // 'fi_FI',
      // 'fr_BE',
      // 'fr_CA',
      // 'fr_CH',
      // 'fr_FR',
      // 'fr_GN',
      // 'fr_HT',
      // 'fr_KM',
      // 'fr_LU',
      // 'fr_MA',
      // 'fr_MC',
      // 'fr_MR',
      // 'fr_WF',
      // 'ga_IE',
      // 'gu_IN',
      'haw_US',
      'hi_IN',
      'hmn_US',
      'hr_HR',
      'ht_HT',
      'ht_US',
      'hu_HU',
      'hy_AM',
      'in_ID',
      'is_IS',
      'it_CH',
      'it_IT',
      'iw_IL',
      'ja_JP',
      'ji_US',
      'ka_GE',
      'kk_KZ',
      'kl_GL',
      'km_KH',
      'kn_IN',
      'ko_KR',
      'ky_KG',
      'lb_LU',
      'lo_LA',
      'lt_LT',
      'lu_CD',
      'lv_LV',
      'mi_NZ',
      'mk_MK',
      'ml_IN',
      'mr_IN',
      'ms_BN',
      'ms_MY',
      'mt_MT',
      'my_MM',
      'ne_NP',
      'nl_AW',
      'nl_BE',
      'nl_NL',
      'nl_SR',
      'no_NO',
      'pa_IN',
      'pl_PL',
      'ps_AF',
      'pt_AO',
      'pt_BR',
      'pt_CV',
      'pt_MZ',
      'pt_PT',
      'pt_ST',
      'rm_CH',
      'rn_BI',
      'ro_MD',
      'ro_RO',
      'ru_AM',
      'ru_BY',
      'ru_KG',
      'ru_KZ',
      'ru_LT',
      'ru_MD',
      'ru_PL',
      'ru_RU',
      'ru_UA',
      'sh_BA',
      'sh_CS',
      'sh_ME',
      'sk_SK',
      'sl_SI',
      'sm_US',
      'sm_WS',
      'so_DJ',
      'so_SO',
      'sq_AL',
      'sr_BA',
      'sr_CS',
      'sr_RS',
      'sv_SE',
      'sw_KE',
      'ta_IN',
      'ta_LK',
      'te_IN',
      'tg_TJ',
      'th_TH',
      'ti_ET',
      'tl_PH',
      'tr_TR',
      'uk_UA',
      'ur_PK',
      'uz_LATN_UZ',
      'vi_VN',
      'xh_ZA',
      'yo_BJ',
      'zh_CN',
      'zh_CN_PINYIN',
      'zh_CN_STROKE',
      'zh_HK',
      'zh_HK_STROKE',
      'zh_MO',
      'zh_MY',
      'zh_SG',
      'zh_TW',
      'zh_TW_STROKE',
      'zu_ZA'
    };
    List<User> users = new List<User>();
    for (String locale : locales) {
      users.add(
        new User(
          LocaleSidKey = locale,
          Username = locale + '@example.com',
          LastName = locale,
          Email = locale + '@example.com',
          alias = locale.length() > 8 ? locale.substring(0, 8) : locale,
          TimeZoneSidKey = 'America/Los_Angeles',
          EmailEncodingKey = 'ISO-8859-1',
          ProfileId = UserInfo.getProfileId(),
          LanguageLocaleKey = 'en_US'
        )
      );
    }
    insert users;

    Date startOfWeek = System.today().toStartOfWeek();
    Map<String, Date> localesWithDifferentStart = new Map<String, Date>();
    for (User u : users) {
      System.runAs(u) {
        Date possibleStartOfWeek = System.today().toStartOfWeek();
        if (System.today().toStartOfWeek() != startOfWeek) {
          localesWithDifferentStart.put(UserInfo.getLocale(), possibleStartOfWeek);
        }
      }
    }
    if (localesWithDifferentStart.isEmpty() == false) {
      System.assert(false, JSON.serializePretty(localesWithDifferentStart));
    }

    /** Final (combined) output:
     *  {                   
                                               "zh_MY" : "2026-02-23",                                      
                                               "yo_BJ" : "2026-02-23",                                      
                                               "vi_VN" : "2026-02-23",                                      
                                               "uz_LATN_UZ" : "2026-02-23",                                 
                                               "uk_UA" : "2026-02-23",                                      
                                               "tr_TR" : "2026-02-23",                                      
                                               "tg_TJ" : "2026-02-23",                                      
                                               "ta_LK" : "2026-02-23",                                      
                                               "sv_SE" : "2026-02-23",                                      
                                               "sr_RS" : "2026-02-23",                                      
                                               "sr_CS" : "2026-02-23",                                      
                                               "sr_BA" : "2026-02-23",                                      
                                               "sq_AL" : "2026-02-23",                                      
                                               "so_SO" : "2026-02-23",                                      
                                               "so_DJ" : "2026-02-21",                                      
                                               "sl_SI" : "2026-02-23",                                      
                                               "sk_SK" : "2026-02-23",                                      
                                               "sh_ME" : "2026-02-23",                                      
                                               "sh_CS" : "2026-02-23",                                      
                                               "sh_BA" : "2026-02-23",                                      
                                               "ru_UA" : "2026-02-23",                                      
                                               "ru_RU" : "2026-02-23",                                      
                                               "ru_PL" : "2026-02-23",                                      
                                               "ru_MD" : "2026-02-23",                                      
                                               "ru_LT" : "2026-02-23",                                      
                                               "ru_KZ" : "2026-02-23",                                      
                                               "ru_KG" : "2026-02-23",                                      
                                               "ru_BY" : "2026-02-23",                                      
                                               "ru_AM" : "2026-02-23",                                      
                                               "ro_RO" : "2026-02-23",                                      
                                               "ro_MD" : "2026-02-23",                                      
                                               "rn_BI" : "2026-02-23",                                      
                                               "rm_CH" : "2026-02-23",                                      
                                               "pt_ST" : "2026-02-23",                                      
                                               "pt_CV" : "2026-02-23",                                      
                                               "pt_AO" : "2026-02-23",                                      
                                               "ps_AF" : "2026-02-21",                                      
                                               "pl_PL" : "2026-02-23",                                      
                                               "no_NO" : "2026-02-23",                                      
                                               "nl_SR" : "2026-02-23",                                      
                                               "nl_NL" : "2026-02-23",                                      
                                               "nl_BE" : "2026-02-23",                                      
                                               "nl_AW" : "2026-02-23",                                      
                                               "ms_MY" : "2026-02-23",                                      
                                               "ms_BN" : "2026-02-23",                                      
                                               "mk_MK" : "2026-02-23",                                      
                                               "mi_NZ" : "2026-02-23",                                      
                                               "lv_LV" : "2026-02-23",                                      
                                               "lu_CD" : "2026-02-23",                                      
                                               "lt_LT" : "2026-02-23",                                      
                                               "lb_LU" : "2026-02-23",                                      
                                               "ky_KG" : "2026-02-23",                                      
                                               "kl_GL" : "2026-02-23",                                      
                                               "kk_KZ" : "2026-02-23",                                      
                                               "ka_GE" : "2026-02-23",                                      
                                               "it_IT" : "2026-02-23",                                      
                                               "it_CH" : "2026-02-23",                                      
                                               "is_IS" : "2026-02-23",                                      
                                               "hy_AM" : "2026-02-23",                                      
                                               "hu_HU" : "2026-02-23",                                      
                                               "ht_HT" : "2026-02-23",                                      
                                               "hr_HR" : "2026-02-23" ,
                                               "ga_IE" : "2026-02-23",                                     
                                               "fr_WF" : "2026-02-23",                                     
                                               "fr_MR" : "2026-02-23",                                     
                                               "fr_MC" : "2026-02-23",                                     
                                               "fr_MA" : "2026-02-23",                                     
                                               "fr_LU" : "2026-02-23",                                     
                                               "fr_KM" : "2026-02-23",                                     
                                               "fr_HT" : "2026-02-23",                                     
                                               "fr_GN" : "2026-02-23",                                     
                                               "fr_FR" : "2026-02-23",                                     
                                               "fr_CH" : "2026-02-23",                                     
                                               "fr_BE" : "2026-02-23",                                     
                                               "fi_FI" : "2026-02-23",                                     
                                               "eu_ES" : "2026-02-23",                                     
                                               "et_EE" : "2026-02-23",                                     
                                               "es_UY" : "2026-02-23",                                     
                                               "es_ES" : "2026-02-23",                                     
                                               "es_EC" : "2026-02-23",                                     
                                               "es_CR" : "2026-02-23",                                     
                                               "es_CL" : "2026-02-23",                                     
                                               "es_BO" : "2026-02-23",                                     
                                               "es_AR" : "2026-02-23",                                     
                                               "en_VU" : "2026-02-23",                                     
                                               "en_UG" : "2026-02-23",                                     
                                               "en_TZ" : "2026-02-23",                                     
                                               "en_TO" : "2026-02-23",                                     
                                               "en_SZ" : "2026-02-23",                                     
                                               "en_SX" : "2026-02-23",                                     
                                               "en_SL" : "2026-02-23",                                     
                                               "en_SH" : "2026-02-23",                                     
                                               "en_SC" : "2026-02-23",                                     
                                               "en_SB" : "2026-02-23",                                     
                                               "en_RW" : "2026-02-23",                                     
                                               "en_PG" : "2026-02-23",                                     
                                               "en_NZ" : "2026-02-23",                                     
                                               "en_NL" : "2026-02-23",                                     
                                               "en_NG" : "2026-02-23",                                     
                                               "en_NA" : "2026-02-23",                                     
                                               "en_MY" : "2026-02-23",                                     
                                               "en_MW" : "2026-02-23",                                     
                                               "en_MU" : "2026-02-23",                                     
                                               "en_MG" : "2026-02-23",                                     
                                               "en_LR" : "2026-02-23",                                     
                                               "en_KY" : "2026-02-23",                                     
                                               "en_IT" : "2026-02-23",                                     
                                               "en_IE" : "2026-02-23",                                     
                                               "en_GY" : "2026-02-23",                                     
                                               "en_GM" : "2026-02-23",                                     
                                               "en_GI" : "2026-02-23",                                     
                                               "en_GH" : "2026-02-23",                                     
                                               "en_GB" : "2026-02-23",                                     
                                               "en_FK" : "2026-02-23",                                     
                                               "en_FJ" : "2026-02-23",                                     
                                               "en_ER" : "2026-02-23",                                     
                                               "en_DE" : "2026-02-23",                                     
                                               "en_CY" : "2026-02-23",                                     
                                               "en_CM" : "2026-02-23",                                     
                                               "en_BM" : "2026-02-23",                                     
                                               "en_BE" : "2026-02-23",                                     
                                               "en_BB" : "2026-02-23",                                     
                                               "en_AU" : "2026-02-23",                                     
                                               "en_AE" : "2026-02-21",                                     
                                               "el_GR" : "2026-02-23",                                     
                                               "el_CY" : "2026-02-23",                                     
                                               "de_LU" : "2026-02-23",                                     
                                               "de_DE" : "2026-02-23",                                     
                                               "de_CH" : "2026-02-23",                                     
                                               "de_BE" : "2026-02-23",                                     
                                               "de_AT" : "2026-02-23",                                     
                                               "da_DK" : "2026-02-23",                                     
                                               "cy_GB" : "2026-02-23",                                     
                                               "cs_CZ" : "2026-02-23",                                     
                                               "ca_ES" : "2026-02-23",                                     
                                               "bs_BA" : "2026-02-23",                                     
                                               "bg_BG" : "2026-02-23",                                     
                                               "be_BY" : "2026-02-23",                                     
                                               "az_AZ" : "2026-02-23",                                     
                                               "ar_TN" : "2026-02-23",                                     
                                               "ar_QA" : "2026-02-21",                                     
                                               "ar_OM" : "2026-02-21",                                     
                                               "ar_MA" : "2026-02-23",                                     
                                               "ar_LY" : "2026-02-21",                                     
                                               "ar_LB" : "2026-02-23",                                     
                                               "ar_KW" : "2026-02-21",                                     
                                               "ar_JO" : "2026-02-21",                                     
                                               "ar_IQ" : "2026-02-21",                                     
                                               "ar_EG" : "2026-02-21",                                     
                                               "ar_DZ" : "2026-02-21",                                     
                                               "ar_BH" : "2026-02-21",                                     
                                               "ar_AE" : "2026-02-21"                                      
                                             } 
     */
  }
}
