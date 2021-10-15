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
}
