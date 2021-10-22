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
      'NEXT_N_MONTHS:2',
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
    Date yesterdayDate = System.today().addDays(-1);
    Datetime yesterdayDatetime = System.now().addDays(-1).date();
    RollupDateLiteral yesterday = RollupDateLiteral.get('YESTERDAY');

    System.assertEquals(true, yesterday.matches(yesterdayDate, '='), 'Date value should have matched: ' + yesterdayDate);
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '='), 'Datetime value should have matched: ' + yesterdayDatetime);

    System.assertEquals(true, yesterday.matches(yesterdayDate, '>='));
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '>='));
    System.assertEquals(true, yesterday.matches(System.today().addDays(2), '>'));
    System.assertNotEquals(true, yesterday.matches(System.now().addDays(-3), '>'));
    System.assertNotEquals(true, yesterday.matches(yesterdayDate.addDays(-1), '>'));

    System.assertEquals(true, yesterday.matches(System.now().addDays(-3), '<'));
    System.assertEquals(true, yesterday.matches(yesterdayDate, '<='));
    System.assertEquals(true, yesterday.matches(yesterdayDatetime, '<='));
    System.assertNotEquals(true, yesterday.matches(System.today().addDays(2), '<='));
  }

  @IsTest
  static void shouldWorkForToday() {
    Date thisDate = System.today();
    Datetime thisDatetime = System.now().date();
    RollupDateLiteral thisDay = RollupDateLiteral.get('TODAY');

    System.assertEquals(true, thisDay.matches(thisDate, '='), 'Date value should have matched: ' + thisDate);
    System.assertEquals(true, thisDay.matches(thisDatetime, '='), 'Datetime value should have matched: ' + thisDatetime);

    System.assertEquals(true, thisDay.matches(thisDate, '>='));
    System.assertEquals(true, thisDay.matches(thisDatetime, '>='));
    System.assertEquals(true, thisDay.matches(System.today().addDays(2), '>'));
    System.assertNotEquals(true, thisDay.matches(System.now().addDays(-2), '>'));
    System.assertNotEquals(true, thisDay.matches(thisDate, '>'));

    System.assertEquals(true, thisDay.matches(System.now().addDays(-2), '<'));
    System.assertEquals(true, thisDay.matches(thisDate, '<='));
    System.assertEquals(true, thisDay.matches(thisDatetime, '<='));
    System.assertNotEquals(true, thisDay.matches(System.today().addDays(2), '<='));
  }

  @IsTest
  static void shouldWorkForTomorrow() {
    Date tomorrowDate = System.today().addDays(1);
    Datetime tomorrowDatetime = System.now().addDays(1).date();
    RollupDateLiteral tomorrow = RollupDateLiteral.get('TOMORROW');

    System.assertEquals(true, tomorrow.matches(tomorrowDate, '='), 'Date value should have matched: ' + tomorrowDate);
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '='), 'Datetime value should have matched: ' + tomorrowDatetime);

    System.assertEquals(true, tomorrow.matches(tomorrowDate, '>='));
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '>='));
    System.assertEquals(true, tomorrow.matches(System.today().addDays(2), '>'));
    System.assertNotEquals(true, tomorrow.matches(System.now().addDays(-2), '>'));
    System.assertNotEquals(true, tomorrow.matches(tomorrowDate, '>'));

    System.assertEquals(true, tomorrow.matches(System.now().addDays(-2), '<'));
    System.assertEquals(true, tomorrow.matches(tomorrowDate, '<='));
    System.assertEquals(true, tomorrow.matches(tomorrowDatetime, '<='));
    System.assertNotEquals(true, tomorrow.matches(System.today().addDays(2), '<='));
  }

  @IsTest
  static void shouldWorkForLastWeek() {
    Date definitiveLastWeekDate = System.today().toStartOfWeek().addDays(-7);
    Datetime lastWeekDatetime = Datetime.newInstanceGmt(definitiveLastWeekDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastWeek = RollupDateLiteral.get('LAST_WEEK');

    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate, '='), 'Date value should have matched: ' + definitiveLastWeekDate + ' | ' + lastWeek);
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '='), 'Datetime value should have matched: ' + lastWeekDatetime);
    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate.addDays(2), '='));

    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate, '>='));
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '>='));
    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate.toStartOfWeek().addDays(8), '>'));
    System.assertNotEquals(
      true,
      lastWeek.matches(definitiveLastWeekDate.toStartOfWeek().addDays(2), '>'),
      'Should only consider days past last week as greater than'
    );
    System.assertNotEquals(true, lastWeek.matches(definitiveLastWeekDate, '>'));

    System.assertEquals(true, lastWeek.matches(lastWeekDatetime.addDays(-2), '<'));
    System.assertEquals(true, lastWeek.matches(definitiveLastWeekDate.addDays(-2), '<='));
    System.assertEquals(true, lastWeek.matches(lastWeekDatetime, '<='));
    System.assertNotEquals(true, lastWeek.matches(System.today().toStartOfWeek(), '<='));
  }

  @IsTest
  static void shouldWorkForThisWeek() {
    Date startOfWeekDate = System.today().toStartOfWeek();
    Datetime thisWeekDatetime = Datetime.newInstanceGmt(startOfWeekDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral thisWeek = RollupDateLiteral.get('THIS_WEEK');

    System.assertEquals(true, thisWeek.matches(startOfWeekDate, '='), 'Date value should have matched: ' + startOfWeekDate + ' | ' + thisWeek);
    System.assertEquals(true, thisWeek.matches(thisWeekDatetime, '='), 'Datetime value should have matched: ' + thisWeekDatetime);
    System.assertEquals(true, thisWeek.matches(startOfWeekDate.addDays(2), '='));

    System.assertEquals(true, thisWeek.matches(startOfWeekDate, '>='));
    System.assertEquals(true, thisWeek.matches(thisWeekDatetime, '>='));
    System.assertEquals(true, thisWeek.matches(System.today().addDays(8), '>'));
    System.assertNotEquals(true, thisWeek.matches(System.now().addDays(-9), '>'));
    System.assertNotEquals(true, thisWeek.matches(startOfWeekDate, '>'));

    System.assertEquals(true, thisWeek.matches(System.now().addDays(-11), '<'));
    System.assertEquals(true, thisWeek.matches(startOfWeekDate, '<='));
    System.assertEquals(true, thisWeek.matches(thisWeekDatetime, '<='));
    System.assertNotEquals(true, thisWeek.matches(System.today().addDays(8), '<='));
  }

  @IsTest
  static void shouldWorkForNextWeek() {
    Date startOfNextWeekDate = System.today();
    if (startOfNextWeekDate != startOfNextWeekDate.toStartOfWeek()) {
      startOfNextWeekDate = startOfNextWeekDate.toStartOfWeek();
    }
    startOfNextWeekDate = startOfNextWeekDate.addDays(7);
    Datetime startOfNextWeekDatetime = Datetime.newInstanceGmt(startOfNextWeekDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextWeek = RollupDateLiteral.get('NEXT_WEEK');

    System.assertEquals(true, nextWeek.matches(startOfNextWeekDate, '='), 'Date value should have matched: ' + startOfNextWeekDate + ' | ' + nextWeek);
    System.assertEquals(true, nextWeek.matches(startOfNextWeekDatetime, '='), 'Datetime value should have matched: ' + startOfNextWeekDatetime);
    System.assertEquals(true, nextWeek.matches(startOfNextWeekDate.addDays(2), '='));

    System.assertEquals(true, nextWeek.matches(startOfNextWeekDate, '>='));
    System.assertEquals(true, nextWeek.matches(startOfNextWeekDatetime, '>='));
    System.assertEquals(true, nextWeek.matches(System.today().addDays(15), '>'));
    System.assertNotEquals(true, nextWeek.matches(System.now().addDays(-15), '>'));
    System.assertNotEquals(true, nextWeek.matches(startOfNextWeekDate, '>'));

    System.assertEquals(true, nextWeek.matches(System.now().addDays(-15), '<'));
    System.assertEquals(true, nextWeek.matches(startOfNextWeekDate, '<='));
    System.assertEquals(true, nextWeek.matches(startOfNextWeekDatetime, '<='));
    System.assertEquals(true, nextWeek.matches(System.today().toStartOfWeek().addDays(6), '<'));
  }

  @IsTest
  static void shouldWorkForLastMonth() {
    Date startOfLastMonthDate = System.today().toStartOfMonth().addMonths(-1);
    Datetime startOfLastMonthDatetime = Datetime.newInstanceGmt(startOfLastMonthDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastMonth = RollupDateLiteral.get('LAST_MONTH');

    System.assertEquals(true, lastMonth.matches(startOfLastMonthDate, '='), 'Date value should have matched: ' + startOfLastMonthDate + ' ' + lastMonth);
    System.assertEquals(true, lastMonth.matches(startOfLastMonthDatetime, '='), 'Datetime value should have matched: ' + startOfLastMonthDatetime);
    System.assertEquals(true, lastMonth.matches(startOfLastMonthDate.addDays(2), '='));

    System.assertEquals(true, lastMonth.matches(startOfLastMonthDate, '>='));
    System.assertEquals(true, lastMonth.matches(startOfLastMonthDatetime, '>='));
    System.assertEquals(true, lastMonth.matches(System.today().toStartOfMonth(), '>'));
    System.assertNotEquals(true, lastMonth.matches(System.now().addMonths(-2), '>'));
    System.assertNotEquals(true, lastMonth.matches(startOfLastMonthDatetime, '>'));

    System.assertEquals(true, lastMonth.matches(System.now().addMonths(-2), '<'));
    System.assertEquals(true, lastMonth.matches(startOfLastMonthDate, '<='));
    System.assertEquals(true, lastMonth.matches(startOfLastMonthDatetime, '<='));
    System.assertNotEquals(true, lastMonth.matches(System.today().toStartOfMonth(), '<='));
  }

  @IsTest
  static void shouldWorkForThisMonth() {
    Date startOfThisMonthDate = System.today().toStartOfMonth();
    Datetime startOfThisMonthDatetime = Datetime.newInstanceGmt(startOfThisMonthDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral thisMonth = RollupDateLiteral.get('THIS_MONTH');

    System.assertEquals(true, thisMonth.matches(startOfThisMonthDate, '='), 'Date value should have matched: ' + startOfThisMonthDate);
    System.assertEquals(true, thisMonth.matches(startOfThisMonthDatetime, '='), 'Datetime value should have matched: ' + startOfThisMonthDatetime);

    System.assertEquals(true, thisMonth.matches(startOfThisMonthDate, '>='));
    System.assertEquals(true, thisMonth.matches(startOfThisMonthDatetime, '>='));
    System.assertEquals(true, thisMonth.matches(System.today().toStartOfMonth().addMonths(1), '>'));
    System.assertNotEquals(true, thisMonth.matches(System.now().addMonths(-1), '>'));
    System.assertNotEquals(true, thisMonth.matches(startOfThisMonthDate, '>'));

    System.assertEquals(true, thisMonth.matches(System.now().addMonths(-2), '<'));
    System.assertEquals(true, thisMonth.matches(startOfThisMonthDate, '<='));
    System.assertEquals(true, thisMonth.matches(startOfThisMonthDatetime, '<='));
    System.assertNotEquals(true, thisMonth.matches(System.today().toStartOfMonth().addMonths(2), '<='));
    System.assertNotEquals(true, thisMonth.matches(System.today().addMonths(1).toStartOfMonth(), '<='));
  }

  @IsTest
  static void shouldWorkForNextMonth() {
    Date startOfNextMonthDate = System.today().toStartOfMonth().addMonths(1);
    Datetime startOfNextMonthDatetime = Datetime.newInstanceGmt(startOfNextMonthDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextMonth = RollupDateLiteral.get('NEXT_MONTH');

    System.assertEquals(true, nextMonth.matches(startOfNextMonthDate, '='), 'Date value should have matched: ' + startOfNextMonthDate);
    System.assertEquals(true, nextMonth.matches(startOfNextMonthDatetime, '='), 'Datetime value should have matched: ' + startOfNextMonthDatetime);

    System.assertEquals(true, nextMonth.matches(startOfNextMonthDate, '>='));
    System.assertEquals(true, nextMonth.matches(startOfNextMonthDatetime, '>='));
    System.assertEquals(true, nextMonth.matches(System.today().toStartOfMonth().addMonths(2), '>'));
    System.assertNotEquals(true, nextMonth.matches(System.now().addMonths(-1), '>'));
    System.assertNotEquals(true, nextMonth.matches(startOfNextMonthDate, '>'));

    System.assertEquals(true, nextMonth.matches(System.now().addMonths(-2), '<'));
    System.assertEquals(true, nextMonth.matches(startOfNextMonthDate, '<='));
    System.assertEquals(true, nextMonth.matches(startOfNextMonthDatetime, '<='));
    System.assertNotEquals(true, nextMonth.matches(System.today().toStartOfMonth().addMonths(2), '<='));
  }

  @IsTest
  static void shouldWorkForLast90Days() {
    Date lastNinetyDaysDate = System.today().addDays(-91);
    Datetime lastNinetyDaysDatetime = Datetime.newInstanceGmt(lastNinetyDaysDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNinetyDays = RollupDateLiteral.get('LAST_90_DAYS');

    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDate, '='), 'Date value should have matched: ' + lastNinetyDaysDate);
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetime, '='), 'Datetime value should have matched: ' + lastNinetyDaysDatetime);
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetime.addDays(2), '='), 'value is in bound ending: ' + lastNinetyDaysDatetime);

    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDate, '>='));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetime, '>='));
    System.assertEquals(true, lastNinetyDays.matches(System.today().addDays(1), '>'));
    System.assertNotEquals(true, lastNinetyDays.matches(System.now().addMonths(-4), '>'));
    System.assertNotEquals(true, lastNinetyDays.matches(lastNinetyDaysDate, '>'));

    System.assertEquals(true, lastNinetyDays.matches(System.now().addMonths(-4), '<'));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDate, '<='));
    System.assertEquals(true, lastNinetyDays.matches(lastNinetyDaysDatetime, '<='));
    System.assertNotEquals(true, lastNinetyDays.matches(System.today().addMonths(4), '<='));
  }

  @IsTest
  static void shouldWorkForNext90Days() {
    Date nextNinetyDaysDate = System.today().addDays(91);
    Datetime nextNinetyDaysDatetime = Datetime.newInstanceGmt(nextNinetyDaysDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextNinetyDays = RollupDateLiteral.get('NEXT_90_DAYS');

    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDate, '='), 'Date value should have matched: ' + nextNinetyDays + ', ' + nextNinetyDaysDate);
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDatetime, '='), 'Datetime value should have matched: ' + nextNinetyDaysDatetime);
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDate.addDays(-2), '='), 'Date value is in bound ending: ' + nextNinetyDaysDatetime);

    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDate, '>='));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDatetime, '>='));
    System.assertEquals(true, nextNinetyDays.matches(System.today().addDays(92), '>'));
    System.assertNotEquals(true, nextNinetyDays.matches(System.now().addDays(88), '>'));
    System.assertNotEquals(true, nextNinetyDays.matches(nextNinetyDaysDate, '>'));

    System.assertEquals(true, nextNinetyDays.matches(System.now().addDays(-2), '<'));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDate, '<='));
    System.assertEquals(true, nextNinetyDays.matches(nextNinetyDaysDatetime, '<='));
    System.assertNotEquals(true, nextNinetyDays.matches(System.today().addDays(93), '<='));
  }

  @IsTest
  static void shouldWorkForLastNDays() {
    Date lastNDaysDate = System.today().addDays(-5);
    Datetime lastNDaysDatetime = Datetime.newInstanceGmt(lastNDaysDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNDays = RollupDateLiteral.get('LAST_N_DAYS:5');

    System.assertEquals(true, lastNDays.matches(lastNDaysDate, '='), 'Date value should have matched: ' + lastNDaysDate + ', ' + lastNDays);
    System.assertEquals(true, lastNDays.matches(lastNDaysDate.addDays(1), '='), 'Date value is within: ' + lastNDays);
    System.assertEquals(true, lastNDays.matches(lastNDaysDatetime, '='), 'Datetime value should have matched: ' + lastNDaysDatetime + ', ' + lastNDays);
    System.assertNotEquals(true, lastNDays.matches(System.today().addDays(2), '='), 'Should not include future days');

    System.assertEquals(true, lastNDays.matches(lastNDaysDate, '>='));
    System.assertEquals(true, lastNDays.matches(lastNDaysDatetime, '>='));
    System.assertEquals(true, lastNDays.matches(System.today().addDays(1), '>'));
    System.assertNotEquals(true, lastNDays.matches(System.now().addDays(-7), '>'));
    System.assertNotEquals(true, lastNDays.matches(lastNDaysDate, '>'));

    System.assertEquals(true, lastNDays.matches(lastNDaysDate, '<='));
    System.assertEquals(true, lastNDays.matches(lastNDaysDatetime, '<='));
    System.assertNotEquals(true, lastNDays.matches(System.today().addDays(2), '<='));
    System.assertNotEquals(true, lastNDays.matches(System.now().addDays(2), '<='));
  }

  @IsTest
  static void shouldWorkForNextNDays() {
    Date nextNDaysDate = System.today().addDays(5);
    Datetime nextNDaysDatetime = Datetime.newInstanceGmt(nextNDaysDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNDays = RollupDateLiteral.get('NEXT_N_DAYS:5');

    System.assertEquals(true, lastNDays.matches(nextNDaysDate, '='), 'Date value should have matched: ' + nextNDaysDate + ', ' + lastNDays);
    System.assertEquals(true, lastNDays.matches(nextNDaysDatetime, '='), 'Datetime value should have matched: ' + nextNDaysDatetime + ', ' + lastNDays);
    System.assertEquals(true, lastNDays.matches(nextNDaysDate.addDays(-1), '='), 'Date value is within: ' + lastNDays);

    System.assertEquals(true, lastNDays.matches(nextNDaysDate, '>='));
    System.assertEquals(true, lastNDays.matches(nextNDaysDatetime, '>='));
    System.assertEquals(true, lastNDays.matches(System.today().addDays(6), '>'));
    System.assertNotEquals(true, lastNDays.matches(System.now().addDays(3), '>'));
    System.assertNotEquals(true, lastNDays.matches(nextNDaysDate, '>'));

    System.assertEquals(true, lastNDays.matches(System.today(), '<'), 'Today should be less than NEXT_N_DAYS');
    System.assertEquals(true, lastNDays.matches(nextNDaysDate, '<='));
    System.assertEquals(true, lastNDays.matches(nextNDaysDatetime, '<='));
    System.assertEquals(true, lastNDays.matches(System.now().addDays(-2), '<'));
    System.assertNotEquals(true, lastNDays.matches(System.today().addDays(6), '<='));
  }

  @IsTest
  static void shouldWorkForLastNWeeks() {
    Date lastNWeeksDate = System.today().toStartOfWeek().addDays(-14);
    Datetime lastNWeeksDatetime = Datetime.newInstanceGmt(lastNWeeksDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNWeeks = RollupDateLiteral.get('LAST_N_WEEKS:2');

    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDate, '='), 'Date value should have matched: ' + lastNWeeksDate);
    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDate.addDays(6), '='), 'Date value is within' + lastNWeeks);
    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDatetime, '='), 'Datetime value should have matched: ' + lastNWeeksDatetime);

    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDate, '>='));
    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDatetime, '>='));
    System.assertEquals(true, lastNWeeks.matches(System.today(), '>'));
    System.assertNotEquals(true, lastNWeeks.matches(System.now().addDays(-9), '>'));
    System.assertNotEquals(true, lastNWeeks.matches(lastNWeeksDate, '>'));

    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDate, '<='));
    System.assertEquals(true, lastNWeeks.matches(lastNWeeksDatetime, '<='));
    System.assertNotEquals(true, lastNWeeks.matches(System.now().addDays(2), '<'));
  }

  @IsTest
  static void shouldWorkForNextNWeeks() {
    Date nextNWeeksDate = System.today().toStartOfWeek().addDays(21);
    Datetime nextNWeeksDatetime = Datetime.newInstanceGmt(nextNWeeksDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextNWeeks = RollupDateLiteral.get('NEXT_N_WEEKS:2');

    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDate, '='), 'Date value should have matched: ' + nextNWeeksDate + ' | ' + nextNWeeks);
    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDate.addDays(-3), '='), 'Date was within: ' + nextNWeeks);
    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDatetime, '='), 'Datetime value should have matched: ' + nextNWeeksDatetime);

    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDate, '>='));
    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDatetime, '>='));
    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDate.addDays(2), '>'));
    System.assertNotEquals(true, nextNWeeks.matches(System.now().date().toStartOfWeek().addDays(-1), '>'));
    System.assertNotEquals(true, nextNWeeks.matches(nextNWeeksDate, '>'));

    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDate, '<='));
    System.assertEquals(true, nextNWeeks.matches(nextNWeeksDatetime, '<='));
    System.assertNotEquals(true, nextNWeeks.matches(System.now().addDays(22), '<'));
  }

  @IsTest
  static void shouldWorkForLastNMonths() {
    Date lastNMonthsDate = System.today().toStartOfMonth().addMonths(-2);
    Datetime lastNMonthsDatetime = Datetime.newInstanceGmt(lastNMonthsDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNMonths = RollupDateLiteral.get('LAST_N_MONTHS:2');

    System.assertEquals(true, lastNMonths.matches(lastNMonthsDate, '='), 'Date value should have matched: ' + lastNMonthsDate + ' | ' + lastNMonths);
    System.assertEquals(true, lastNMonths.matches(lastNMonthsDate.addDays(30), '='), 'Date was within: ' + lastNMonths);
    System.assertEquals(true, lastNMonths.matches(lastNMonthsDatetime, '='), 'Datetime value should have matched: ' + lastNMonthsDatetime);

    System.assertEquals(true, lastNMonths.matches(lastNMonthsDate, '>='));
    System.assertEquals(true, lastNMonths.matches(lastNMonthsDatetime, '>='));
    System.assertEquals(true, lastNMonths.matches(System.today(), '>'));
    System.assertNotEquals(true, lastNMonths.matches(System.now().date().toStartOfMonth().addDays(-1), '>'));
    System.assertNotEquals(true, lastNMonths.matches(lastNMonthsDate, '>'));

    System.assertEquals(true, lastNMonths.matches(lastNMonthsDate, '<='));
    System.assertEquals(true, lastNMonths.matches(lastNMonthsDatetime, '<='));
    System.assertNotEquals(true, lastNMonths.matches(System.now(), '<'));
  }

  @IsTest
  static void shouldWorkForNextNMonths() {
    Date nextNMonthsDate = System.today().toStartOfMonth().addMonths(2);
    Datetime nextNMonthsDatetime = Datetime.newInstanceGmt(nextNMonthsDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextNMonths = RollupDateLiteral.get('NEXT_N_MONTHS:2');

    System.assertEquals(true, nextNMonths.matches(nextNMonthsDate, '='), 'Date value should have matched: ' + nextNMonthsDate + ' | ' + nextNMonths);
    System.assertEquals(true, nextNMonths.matches(nextNMonthsDate.addDays(30), '='), 'Date was within: ' + nextNMonths);
    System.assertEquals(true, nextNMonths.matches(nextNMonthsDatetime, '='), 'Datetime value should have matched: ' + nextNMonthsDatetime);

    System.assertEquals(true, nextNMonths.matches(nextNMonthsDate, '>='));
    System.assertEquals(true, nextNMonths.matches(nextNMonthsDatetime, '>='));
    System.assertEquals(true, nextNMonths.matches(System.today().addMonths(3), '>'));
    System.assertNotEquals(true, nextNMonths.matches(System.now().date().toStartOfMonth().addMonths(1), '>'));
    System.assertNotEquals(true, nextNMonths.matches(nextNMonthsDate, '>'));

    System.assertEquals(true, nextNMonths.matches(nextNMonthsDate, '<='));
    System.assertEquals(true, nextNMonths.matches(nextNMonthsDatetime, '<='));
    System.assertNotEquals(true, nextNMonths.matches(System.now().addMonths(3), '<'));
  }

  @IsTest
  static void shouldWorkForThisYear() {
    Date startOfThisYearDate = Date.newInstance(System.today().year(), 1, 1);
    Datetime startOfThisYearDatetime = Datetime.newInstanceGmt(startOfThisYearDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral thisYear = RollupDateLiteral.get('THIS_YEAR');

    System.assertEquals(true, thisYear.matches(startOfThisYearDate, '='), 'Date value should have matched: ' + thisYear);
    System.assertEquals(true, thisYear.matches(startOfThisYearDatetime, '='), 'Datetime value should have matched: ' + startOfThisYearDatetime);
    System.assertEquals(true, thisYear.matches(startOfThisYearDate.addMonths(6), '='), 'Date within bounds: ' + thisYear);

    System.assertEquals(true, thisYear.matches(startOfThisYearDate, '>='));
    System.assertEquals(true, thisYear.matches(startOfThisYearDatetime, '>='));
    System.assertEquals(true, thisYear.matches(System.today().addYears(2), '>'), 'Year should be greater: ' + thisYear);
    System.assertNotEquals(true, thisYear.matches(System.now().addYears(-1), '>'));
    System.assertNotEquals(true, thisYear.matches(startOfThisYearDate.addYears(-1), '>'));

    System.assertEquals(true, thisYear.matches(System.today().addYears(-1), '<'));
    System.assertEquals(true, thisYear.matches(startOfThisYearDate, '<='));
    System.assertEquals(true, thisYear.matches(startOfThisYearDatetime, '<='));
    System.assertNotEquals(true, thisYear.matches(System.today().addYears(2), '<='));
  }

  @IsTest
  static void shouldWorkForLastYear() {
    Date startOfLastYearDate = Date.newInstance(System.today().year() - 1, 1, 1);
    Datetime startOfLastYearDatetime = Datetime.newInstanceGmt(startOfLastYearDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastYear = RollupDateLiteral.get('LAST_YEAR');

    System.assertEquals(true, lastYear.matches(startOfLastYearDate, '='), 'Date value should have matched: ' + startOfLastYearDate + ' ' + lastYear);
    System.assertEquals(true, lastYear.matches(startOfLastYearDatetime, '='), 'Datetime value should have matched: ' + startOfLastYearDatetime);
    System.assertEquals(true, lastYear.matches(startOfLastYearDate.addMonths(6), '='), 'Date within bounds: ' + lastYear);

    System.assertEquals(true, lastYear.matches(startOfLastYearDate, '>='));
    System.assertEquals(true, lastYear.matches(startOfLastYearDatetime, '>='));
    System.assertEquals(true, lastYear.matches(System.today(), '>'));
    System.assertNotEquals(true, lastYear.matches(System.now().addYears(-2), '>'));
    System.assertNotEquals(true, lastYear.matches(startOfLastYearDatetime.addYears(-2), '>'));

    System.assertEquals(true, lastYear.matches(System.now().addYears(-3), '<'));
    System.assertEquals(true, lastYear.matches(startOfLastYearDate, '<='));
    System.assertEquals(true, lastYear.matches(startOfLastYearDatetime, '<='));
    System.assertNotEquals(true, lastYear.matches(System.today().addYears(1), '<='));
  }

  @IsTest
  static void shouldWorkForNextYear() {
    Date startOfNextYearDate = Date.newInstance(System.today().year() + 1, 1, 1);
    Datetime startOfNextYearDatetime = Datetime.newInstanceGmt(startOfNextYearDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral nextYear = RollupDateLiteral.get('NEXT_YEAR');

    System.assertEquals(true, nextYear.matches(startOfNextYearDate, '='), 'Date value should have matched: ' + startOfNextYearDate);
    System.assertEquals(true, nextYear.matches(startOfNextYearDatetime, '='), 'Datetime value should have matched: ' + startOfNextYearDatetime);
    System.assertEquals(true, nextYear.matches(startOfNextYearDate.addMonths(6), '='), 'Date within bounds: ' + nextYear);

    System.assertEquals(true, nextYear.matches(startOfNextYearDate, '>='));
    System.assertEquals(true, nextYear.matches(startOfNextYearDatetime, '>='));
    System.assertEquals(true, nextYear.matches(Date.newInstance(System.today().year() + 2, 1, 1), '>'));
    System.assertNotEquals(true, nextYear.matches(System.now(), '>'));
    System.assertNotEquals(true, nextYear.matches(startOfNextYearDate.addDays(-2), '>'));

    System.assertEquals(true, nextYear.matches(System.now().addYears(-1), '<'));
    System.assertEquals(true, nextYear.matches(startOfNextYearDate, '<='));
    System.assertEquals(true, nextYear.matches(startOfNextYearDatetime, '<='));
    System.assertNotEquals(true, nextYear.matches(Date.newInstance(System.today().year() + 2, 1, 1), '<='));
  }

  @IsTest
  static void shouldWorkForLastNYears() {
    Integer yearsInThePast = 3;
    Date lastNYearsDate = Date.newInstance(System.today().year() - (yearsInThePast - 1), 1, 1);
    Datetime lastNYearsDatetime = Datetime.newInstanceGmt(lastNYearsDate, Time.newInstance(0, 0, 0, 0));
    RollupDateLiteral lastNYears = RollupDateLiteral.get('LAST_N_YEARS:' + yearsInThePast);
    Date firstOfLastYear = Date.newInstance(System.today().year() - 1, 1, 1);

    System.assertEquals(true, lastNYears.matches(lastNYearsDate, '='), 'Date value should have matched: ' + lastNYearsDate + ' | ' + lastNYears);
    System.assertEquals(true, lastNYears.matches(lastNYearsDate.addYears(1), '='), 'Date was within: ' + lastNYears);
    System.assertEquals(true, lastNYears.matches(lastNYearsDatetime, '='), 'Datetime value should have matched: ' + lastNYearsDatetime);
    System.assertNotEquals(
      true,
      lastNYears.matches(Datetime.newInstanceGmt(firstOfLastYear, Time.newInstance(0, 0, 0, 1)), '='),
      'Should not equal anything past 00:00:00 on first date of last year'
    );

    System.assertEquals(true, lastNYears.matches(lastNYearsDate, '>='));
    System.assertEquals(true, lastNYears.matches(lastNYearsDatetime, '>='));
    System.assertEquals(true, lastNYears.matches(System.today(), '>'));
    System.assertNotEquals(true, lastNYears.matches(System.now().addYears(-5), '>'));
    System.assertNotEquals(true, lastNYears.matches(lastNYearsDate, '>'));

    System.assertEquals(true, lastNYears.matches(lastNYearsDate, '<='));
    System.assertEquals(true, lastNYears.matches(lastNYearsDatetime, '<='));
    System.assertNotEquals(true, lastNYears.matches(System.now(), '<'));
  }

  @IsTest
  static void shouldWorkForNextNYears() {
    Integer yearsInTheFuture = 3;
    Date nextNYearsDate = Date.newInstance(System.today().year() + yearsInTheFuture, 1, 1);
    Datetime nextNYearsDatetime = Datetime.newInstanceGmt(nextNYearsDate, Time.newInstance(11, 59, 59, 59));
    RollupDateLiteral nextNYears = RollupDateLiteral.get('NEXT_N_YEARS:' + yearsInTheFuture);
    Date lastDayOfThisYear = Date.newInstance(System.today().year(), 12, 31);

    System.assertEquals(true, nextNYears.matches(nextNYearsDate, '='), 'Date value should have matched: ' + nextNYearsDate + ' | ' + nextNYears);
    System.assertEquals(true, nextNYears.matches(nextNYearsDate.addYears(-1), '='), 'Date was within: ' + nextNYears);
    System.assertEquals(true, nextNYears.matches(nextNYearsDatetime, '='), 'Datetime value should have matched: ' + nextNYearsDatetime);
    System.assertNotEquals(
      true,
      nextNYears.matches(Datetime.newInstanceGmt(lastDayOfThisYear, Time.newInstance(11, 59, 59, 59)), '='),
      'Should not equal anything befre 00:00:00 on first date of next year'
    );

    System.assertEquals(true, nextNYears.matches(nextNYearsDate, '>='));
    System.assertEquals(true, nextNYears.matches(nextNYearsDatetime, '>='));
    System.assertEquals(true, nextNYears.matches(System.today().addYears(yearsInTheFuture + 1), '>'));
    System.assertNotEquals(true, nextNYears.matches(System.now().addYears(-5), '>'));
    System.assertNotEquals(true, nextNYears.matches(nextNYearsDate, '>'));

    System.assertEquals(true, nextNYears.matches(nextNYearsDate, '<='));
    System.assertEquals(true, nextNYears.matches(nextNYearsDatetime, '<='));
    System.assertNotEquals(true, nextNYears.matches(System.now().addYears(2), '<'));
  }
}
