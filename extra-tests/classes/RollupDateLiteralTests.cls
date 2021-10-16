@IsTest
private class RollupDateLiteralTests {
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
      'THIS_QUARTER',
      'LAST_QUARTER',
      'NEXT_QUARTER',
      'NEXT_N_QUARTERS:24',
      'LAST_N_QUARTERS:2',
      'THIS_YEAR',
      'LAST_YEAR',
      'NEXT_YEAR',
      'LAST_N_YEARS:2',
      'NEXT_N_YEARS:2',
      'THIS_FISCAL_QUARTER',
      'LAST_FISCAL_QUARTER',
      'NEXT_FISCAL_QUARTER',
      'LAST_N_FISCAL_​QUARTERS:2',
      'NEXT_N_FISCAL_​QUARTERS:2',
      'LAST_FISCAL_YEAR',
      'THIS_FISCAL_YEAR',
      'NEXT_FISCAL_YEAR',
      'LAST_N_FISCAL_​YEARS:2',
      'NEXT_N_FISCAL_​YEARS:2'
    };

    for (String dateLiteral : dateLiterals) {
      System.assertEquals(true, RollupDateLiteral.isDateLiteral(dateLiteral), 'Date literal was not detected properly: ' + dateLiteral);
    }
  }

  @IsTest
  static void shouldWorkForYesterday() {
    String yesterdayDate = System.today().addDays(-1).format();
    String yesterdayDatetime = System.now().addDays(-1).date().format();
    RollupDateLiteral yesterday = RollupDateLiteral.get('YESTERDAY');

    System.assertEquals(true, yesterday.matches(yesterdayDate, '='), 'Date value should have matched: ' + yesterdayDate);
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '='), 'Datetime value should have matched: ' + yesterdayDatetime);

    System.assertEquals(true, yesterday.matches(yesterdayDate, '>='));
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '>='));
    System.assertEquals(true, yesterday.matches(System.today().addDays(-2).format(), '>'));
    System.assertNotEquals(true, yesterday.matches(System.now().format(), '>'));
    System.assertNotEquals(true, yesterday.matches(yesterdayDate, '>'));

    System.assertEquals(true, yesterday.matches(System.now().format(), '<'));
    System.assertEquals(true, yesterday.matches(yesterdayDate, '<='));
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '<='));
    System.assertNotEquals(true, yesterday.matches(System.today().addDays(-2).format(), '<='));
  }

  @IsTest
  static void shouldWorkForToday() {
    String thisDate = System.today().format();
    String thisDatetime = System.now().date().format();
    RollupDateLiteral thisDay = RollupDateLiteral.get('TODAY');

    System.assertEquals(true, thisDay.matches(thisDate, '='), 'Date value should have matched: ' + thisDate);
    System.assertEquals(true, thisDay.matches(thisDatetime, '='), 'Datetime value should have matched: ' + thisDatetime);

    System.assertEquals(true, thisDay.matches(thisDate, '>='));
    System.assertEquals(true, thisDay.matches(thisDatetime, '>='));
    System.assertEquals(true, thisDay.matches(System.today().addDays(-2).format(), '>'));
    System.assertNotEquals(true, thisDay.matches(System.now().addDays(1).format(), '>'));
    System.assertNotEquals(true, thisDay.matches(thisDate, '>'));

    System.assertEquals(true, thisDay.matches(System.now().format(), '<'));
    System.assertEquals(true, thisDay.matches(thisDate, '<='));
    System.assertEquals(true, thisDay.matches(thisDatetime, '<='));
    System.assertNotEquals(true, thisDay.matches(System.today().addDays(-2).format(), '<='));
  }

  @IsTest
  static void shouldWorkForTomorrow() {
    String tomorrowDate = System.today().addDays(1).format();
    String tomorrowDatetime = System.now().addDays(1).date().format();
    RollupDateLiteral tomorrow = RollupDateLiteral.get('TOMORROW');

    System.assertEquals(true, tomorrow.matches(tomorrowDate, '='), 'Date value should have matched: ' + tomorrowDate);
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '='), 'Datetime value should have matched: ' + tomorrowDatetime);

    System.assertEquals(true, tomorrow.matches(tomorrowDate, '>='));
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '>='));
    System.assertEquals(true, tomorrow.matches(System.today().addDays(-1).format(), '>'));
    System.assertNotEquals(true, tomorrow.matches(System.now().addDays(2).format(), '>'));
    System.assertNotEquals(true, tomorrow.matches(tomorrowDate, '>'));

    System.assertEquals(true, tomorrow.matches(System.now().addDays(2).format(), '<'));
    System.assertEquals(true, tomorrow.matches(tomorrowDate, '<='));
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '<='));
    System.assertNotEquals(true, tomorrow.matches(System.today().format(), '<='));
  }

  @IsTest
  static void shouldWorkForLastWeek() {
    Date definitiveLastWeekDate = System.today().toStartOfWeek().addDays(-7);
    String lastWeekDate = definitiveLastWeekDate.format();
    String lastWeekDatetime = Datetime.newInstance(definitiveLastWeekDate, Time.newInstance(0, 0, 0, 0)).format();
    RollupDateLiteral lastWeek = RollupDateLiteral.get('LAST_WEEK');

    System.assertEquals(true, lastWeek.matches(lastWeekDate, '='), 'Date value should have matched: ' + lastWeekDate);
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '='), 'Datetime value should have matched: ' + lastWeekDatetime);

    System.assertEquals(true, lastWeek.matches(lastWeekDate, '>='));
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '>='));
    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate.toStartOfWeek().addDays(-1).format(), '>'));
    System.assertNotEquals(true, lastWeek.matches(System.now().addDays(-6).format(), '>'));
    System.assertNotEquals(true, lastWeek.matches(lastWeekDate, '>'));

    System.assertEquals(true, lastWeek.matches(System.now().addDays(2).format(), '<'));
    System.assertEquals(true, lastWeek.matches(lastWeekDate, '<='));
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '<='));
    System.assertNotEquals(true, lastWeek.matches(System.today().toStartOfWeek().addDays(-9).format(), '<='));
  }

  @IsTest
  static void shouldWorkForThisWeek() {
    Date startOfWeekDate = System.today().toStartOfWeek();
    String thisWeekDate = startOfWeekDate.format();
    String thisWeekDatetime = Datetime.newInstance(startOfWeekDate, Time.newInstance(0, 0, 0, 0)).format();
    RollupDateLiteral thisWeek = RollupDateLiteral.get('THIS_WEEK');

    System.assertEquals(true, thisWeek.matches(thisWeekDate, '='), 'Date value should have matched: ' + thisWeekDate);
    System.assertEquals(true, thisWeek.matches(thisWeekDate, '='), 'Datetime value should have matched: ' + thisWeekDatetime);

    System.assertEquals(true, thisWeek.matches(thisWeekDate, '>='));
    System.assertEquals(true, thisWeek.matches(thisWeekDatetime, '>='));
    System.assertEquals(true, thisWeek.matches(System.today().addDays(-8).format(), '>'));
    System.assertNotEquals(true, thisWeek.matches(System.now().addDays(9).format(), '>'));
    System.assertNotEquals(true, thisWeek.matches(thisWeekDate, '>'));

    System.assertEquals(true, thisWeek.matches(System.now().addDays(11).format(), '<'));
    System.assertEquals(true, thisWeek.matches(thisWeekDate, '<='));
    System.assertEquals(true, thisWeek.matches(thisWeekDatetime, '<='));
    System.assertNotEquals(true, thisWeek.matches(System.today().addDays(-8).format(), '<='));
  }

  @IsTest
  static void shouldWorkForNextWeek() {
    Date startOfNextWeekDate = System.today().toStartOfWeek().addDays(7);
    Datetime startOfNextWeekDatetime = Datetime.newInstance(startOfNextWeekDate, Time.newInstance(0, 0, 0, 0));
    String nextWeekDate = startOfNextWeekDate.format();
    String nextWeekDatetime = startOfNextWeekDatetime.format();
    RollupDateLiteral nextWeek = RollupDateLiteral.get('NEXT_WEEK');

    System.assertEquals(true, nextWeek.matches(nextWeekDate, '='), 'Date value should have matched: ' + nextWeekDate);
    System.assertEquals(true, nextWeek.matches(nextWeekDate, '='), 'Datetime value should have matched: ' + nextWeekDatetime);

    System.assertEquals(true, nextWeek.matches(nextWeekDate, '>='));
    System.assertEquals(true, nextWeek.matches(nextWeekDatetime, '>='));
    System.assertEquals(true, nextWeek.matches(System.today().addDays(-8).format(), '>'));
    System.assertNotEquals(true, nextWeek.matches(System.now().addDays(9).format(), '>'));
    System.assertNotEquals(true, nextWeek.matches(nextWeekDate, '>'));

    System.assertEquals(true, nextWeek.matches(System.now().addDays(15).format(), '<'));
    System.assertEquals(true, nextWeek.matches(nextWeekDate, '<='));
    System.assertEquals(true, nextWeek.matches(nextWeekDatetime, '<='));
    System.assertNotEquals(true, nextWeek.matches(System.today().toStartOfWeek().addDays(6).format(), '<='));
  }

  @IsTest
  static void shouldWorkForLastMonth() {
    Date startOfLastMonthDate = System.today().toStartOfMonth().addMonths(-1);
    Datetime startOfLastMonthDatetime = Datetime.newInstance(startOfLastMonthDate, Time.newInstance(0, 0, 0, 0));
    String lastMonthDate = startOfLastMonthDate.format();
    String lastMonthDatetime = startOfLastMonthDatetime.format();
    RollupDateLiteral lastMonth = RollupDateLiteral.get('LAST_MONTH');

    System.assertEquals(true, lastMonth.matches(lastMonthDate, '='), 'Date value should have matched: ' + lastMonth);
    System.assertEquals(true, lastMonth.matches(lastMonthDatetime, '='), 'Datetime value should have matched: ' + lastMonthDatetime);

    System.assertEquals(true, lastMonth.matches(lastMonthDate, '>='));
    System.assertEquals(true, lastMonth.matches(lastMonthDatetime, '>='));
    System.assertEquals(true, lastMonth.matches(System.today().toStartOfMonth().addMonths(-2).format(), '>'));
    System.assertNotEquals(true, lastMonth.matches(System.now().format(), '>'));
    System.assertNotEquals(true, lastMonth.matches(lastMonthDate, '>'));

    System.assertEquals(true, lastMonth.matches(System.now().addMonths(1).format(), '<'));
    System.assertEquals(true, lastMonth.matches(lastMonthDate, '<='));
    System.assertEquals(true, lastMonth.matches(lastMonthDatetime, '<='));
    System.assertNotEquals(true, lastMonth.matches(System.today().toStartOfMonth().addMonths(-2).format(), '<='));
  }

  @IsTest
  static void shouldWorkForThisMonth() {
    Date startOfThisMonthDate = System.today().toStartOfMonth();
    Datetime startOfThisMonthDatetime = Datetime.newInstance(startOfThisMonthDate, Time.newInstance(0, 0, 0, 0));
    String thisMonthDate = startOfThisMonthDate.format();
    String thisMonthDatetime = startOfThisMonthDatetime.format();
    RollupDateLiteral thisMonth = RollupDateLiteral.get('THIS_MONTH');

    System.assertEquals(true, thisMonth.matches(thisMonthDate, '='), 'Date value should have matched: ' + thisMonth);
    System.assertEquals(true, thisMonth.matches(thisMonthDatetime, '='), 'Datetime value should have matched: ' + thisMonthDatetime);

    System.assertEquals(true, thisMonth.matches(thisMonthDate, '>='));
    System.assertEquals(true, thisMonth.matches(thisMonthDatetime, '>='));
    System.assertEquals(true, thisMonth.matches(System.today().toStartOfMonth().addMonths(-2).format(), '>'));
    System.assertNotEquals(true, thisMonth.matches(System.now().format(), '>'));
    System.assertNotEquals(true, thisMonth.matches(thisMonthDate, '>'));

    System.assertEquals(true, thisMonth.matches(System.now().addMonths(1).format(), '<'));
    System.assertEquals(true, thisMonth.matches(thisMonthDate, '<='));
    System.assertEquals(true, thisMonth.matches(thisMonthDatetime, '<='));
    System.assertNotEquals(true, thisMonth.matches(System.today().toStartOfMonth().addMonths(-2).format(), '<='));
  }

  @IsTest
  static void shouldWorkForNextMonth() {
    Date startOfNextMonthDate = System.today().toStartOfMonth().addMonths(1);
    Datetime startOfNextMonthDatetime = Datetime.newInstance(startOfNextMonthDate, Time.newInstance(0, 0, 0, 0));
    String nextMonthDate = startOfNextMonthDate.format();
    String nextMonthDatetime = startOfNextMonthDatetime.format();
    RollupDateLiteral nextMonth = RollupDateLiteral.get('NEXT_MONTH');

    System.assertEquals(true, nextMonth.matches(nextMonthDate, '='), 'Date value should have matched: ' + nextMonth);
    System.assertEquals(true, nextMonth.matches(nextMonthDatetime, '='), 'Datetime value should have matched: ' + nextMonthDatetime);

    System.assertEquals(true, nextMonth.matches(nextMonthDate, '>='));
    System.assertEquals(true, nextMonth.matches(nextMonthDatetime, '>='));
    System.assertEquals(true, nextMonth.matches(System.today().toStartOfMonth().addMonths(-1).format(), '>'));
    System.assertNotEquals(true, nextMonth.matches(System.now().addMonths(2).format(), '>'));
    System.assertNotEquals(true, nextMonth.matches(nextMonthDate, '>'));

    System.assertEquals(true, nextMonth.matches(System.now().addMonths(2).format(), '<'));
    System.assertEquals(true, nextMonth.matches(nextMonthDate, '<='));
    System.assertEquals(true, nextMonth.matches(nextMonthDatetime, '<='));
    System.assertNotEquals(true, nextMonth.matches(System.today().toStartOfMonth().addMonths(-1).format(), '<='));
  }

  @IsTest
  static void shouldWorkForLast90Days() {
    Date lastNinetyDaysDate = System.today().addDays(-91);
    Datetime lastNinetyDaysDatetime = Datetime.newInstance(lastNinetyDaysDate, Time.newInstance(0, 0, 0, 0));
    String lastNinetyDaysDateString = lastNinetyDaysDate.format();
    String lastNinetyDaysDatetimeString = lastNinetyDaysDatetime.format();
    RollupDateLiteral lastNinetyDays = RollupDateLiteral.get('LAST_90_DAYS');

    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDateString, '='), 'Date value should have matched: ' + lastNinetyDays);
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetimeString, '='), 'Datetime value should have matched: ' + lastNinetyDaysDatetimeString);

    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDateString, '>='));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetimeString, '>='));
    System.assertEquals(true, lastNinetyDays.matches(System.today().addMonths(-4).format(), '>'));
    System.assertNotEquals(true, lastNinetyDays.matches(System.now().addMonths(2).format(), '>'));
    System.assertNotEquals(true, lastNinetyDays.matches(lastNinetyDaysDateString, '>'));

    System.assertEquals(true, lastNinetyDays.matches(System.now().addMonths(2).format(), '<'));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDateString, '<='));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetimeString, '<='));
    System.assertNotEquals(true, lastNinetyDays.matches(System.today().addMonths(-4).format(), '<='));
  }

  @IsTest
  static void shouldWorkForNext90Days() {
    Date nextNinetyDaysDate = System.today().addDays(91);
    Datetime nextNinetyDaysDatetime = Datetime.newInstanceGmt(nextNinetyDaysDate, Time.newInstance(0, 0, 0, 0));
    String nextNinetyDaysDateString = nextNinetyDaysDate.format();
    String nextNinetyDaysDatetimeString = nextNinetyDaysDatetime.format();
    RollupDateLiteral nextNinetyDays = RollupDateLiteral.get('NEXT_90_DAYS');

    System.assertEquals(
      true,
      nextNinetyDays.matches(nextNinetyDaysDateString, '='),
      'Date value should have matched: ' +
      nextNinetyDays +
      ', ' +
      nextNinetyDaysDateString
    );
    System.assertEquals(
      true,
      nextNinetyDays.matches(nextNinetyDaysDatetimeString, '='),
      'Datetime value should have matched: ' +
      nextNinetyDaysDatetimeString +
      ', ' +
      nextNinetyDays
    );

    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDateString, '>='));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDatetimeString, '>='));
    System.assertEquals(true, nextNinetyDays.matches(System.today().addDays(89).format(), '>'));
    System.assertNotEquals(true, nextNinetyDays.matches(System.now().addDays(5).format(), '>'));
    System.assertNotEquals(true, nextNinetyDays.matches(nextNinetyDaysDateString, '>'));

    System.assertEquals(true, nextNinetyDays.matches(System.now().addDays(2).format(), '<'));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDateString, '<='));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDatetimeString, '<='));
    System.assertNotEquals(true, nextNinetyDays.matches(System.today().addDays(92).format(), '<='));
  }
}
