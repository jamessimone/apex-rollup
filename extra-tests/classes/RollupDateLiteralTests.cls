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
    System.assertEquals(true, yesterday.matches(yesterdayDate, '='), 'Datetime value should have matched: ' + yesterdayDatetime);

    // TODO - greater than, less than
  }
}
