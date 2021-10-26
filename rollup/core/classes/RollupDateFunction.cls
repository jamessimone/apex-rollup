public without sharing class RollupDateFunction {
  private static final Pattern DATE_FUNCTION_PATTERN = Pattern.compile(
    '(CALENDAR_MONTH|CALENDAR_QUARTER|CALENDAR_YEAR|CALENDAR_YEAR|DAY_IN_MONTH|DAY_IN_WEEK|DAY_IN_YEAR|DAY_ONLY|FISCAL_MONTH' +
    '|FISCAL_QUARTER|FISCAL_YEAR|HOUR_IN_DAY|WEEK_IN_MONTH|WEEK_IN_YEAR)\\(.+?\\)'
  );

  private RollupDateFunction() {
    // only uses static methods
  }

  public static Boolean isSoqlDateFunction(String val) {
    return DATE_FUNCTION_PATTERN.matcher(val).matches();
  }
}
