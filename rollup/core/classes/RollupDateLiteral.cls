@SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
public without sharing abstract class RollupDateLiteral {
  private static final Pattern RELATIVE_LITERAL_PATTERN {
    get {
      RELATIVE_LITERAL_PATTERN = RELATIVE_LITERAL_PATTERN ??
        Pattern.compile('(LAST_|NEXT_|)N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_QUARTERS|FISCAL_YEARS)(|_AGO):\\s?\\d*');
      return RELATIVE_LITERAL_PATTERN;
    }
    set;
  }
  private static final Pattern DATE_FUNCTION_PATTERN {
    get {
      DATE_FUNCTION_PATTERN = DATE_FUNCTION_PATTERN ??
        Pattern.compile(
          '(CALENDAR_MONTH|CALENDAR_QUARTER|CALENDAR_YEAR|DAY_IN_MONTH|DAY_IN_WEEK|DAY_IN_YEAR|DAY_ONLY|FISCAL_MONTH|' +
          'FISCAL_QUARTER|FISCAL_YEAR|HOUR_IN_DAY|WEEK_IN_MONTH|WEEK_IN_YEAR)\\(.+?\\)'
        );
      return DATE_FUNCTION_PATTERN;
    }
    set;
  }

  private static Time START_TIME {
    get {
      return Time.newInstance(0, 0, 0, 0);
    }
  }

  private static Time END_TIME {
    get {
      return Time.newInstance(23, 59, 59, 59);
    }
  }

  private static Datetime START_OF_TODAY {
    get {
      return Datetime.newInstance(System.today().year(), System.today().month(), System.today().day());
    }
  }

  private static final FiscalInfo FISCAL_INFO {
    get {
      FISCAL_INFO = FISCAL_INFO ?? getFiscalInfo();
      return FISCAL_INFO;
    }
    set;
  }

  protected Datetime ref;
  protected Datetime bound;

  private static final Map<String, Type> KEY_TO_DATE_LITERAL {
    get {
      KEY_TO_DATE_LITERAL = KEY_TO_DATE_LITERAL ??
        new Map<String, Type>{
          'YESTERDAY' => YesterdayLiteral.class,
          'TODAY' => TodayLiteral.class,
          'TOMORROW' => TomorrowLiteral.class,
          'LAST_WEEK' => LastWeekLiteral.class,
          'THIS_WEEK' => ThisWeekLiteral.class,
          'NEXT_WEEK' => NextWeekLiteral.class,
          'LAST_MONTH' => LastMonthLiteral.class,
          'THIS_MONTH' => ThisMonthLiteral.class,
          'NEXT_MONTH' => NextMonthLiteral.class,
          'LAST_90_DAYS' => Last90DaysLiteral.class,
          'NEXT_90_DAYS' => Next90DaysLiteral.class,
          'LAST_N_DAYS' => LastNDaysLiteral.class,
          'N_DAYS_AGO' => NDaysAgoLiteral.class,
          'NEXT_N_DAYS' => NextNDaysLiteral.class,
          'LAST_N_WEEKS' => LastNWeeksLiteral.class,
          'N_WEEKS_AGO' => NWeeksAgoLiteral.class,
          'NEXT_N_WEEKS' => NextNWeeksLiteral.class,
          'LAST_N_MONTHS' => LastNMonthsLiteral.class,
          'N_MONTHS_AGO' => NMonthsAgoLiteral.class,
          'NEXT_N_MONTHS' => NextNMonthsLiteral.class,
          'LAST_QUARTER' => LastQuarterLiteral.class,
          'THIS_QUARTER' => ThisQuarterLiteral.class,
          'NEXT_QUARTER' => NextQuarterLiteral.class,
          'LAST_N_QUARTERS' => LastNQuartersLiteral.class,
          'N_QUARTERS_AGO' => NQuartersAgoLiteral.class,
          'NEXT_N_QUARTERS' => NextNQuartersLiteral.class,
          'THIS_YEAR' => ThisYearLiteral.class,
          'LAST_YEAR' => LastYearLiteral.class,
          'NEXT_YEAR' => NextYearLiteral.class,
          'LAST_N_YEARS' => LastNYearsLiteral.class,
          'N_YEARS_AGO' => NYearsAgoLiteral.class,
          'NEXT_N_YEARS' => NextNYearsLiteral.class,
          'LAST_FISCAL_QUARTER' => LastFiscalQuarterLiteral.class,
          'THIS_FISCAL_QUARTER' => ThisFiscalQuarterLiteral.class,
          'NEXT_FISCAL_QUARTER' => NextFiscalQuarterLiteral.class,
          'LAST_N_FISCAL_QUARTERS' => LastNFiscalQuartersLiteral.class,
          'N_FISCAL_QUARTERS_AGO' => NFiscalQuartersAgoLiteral.class,
          'NEXT_N_FISCAL_QUARTERS' => NextNFiscalQuartersLiteral.class,
          'LAST_FISCAL_YEAR' => LastFiscalYearLiteral.class,
          'THIS_FISCAL_YEAR' => ThisFiscalYearLiteral.class,
          'NEXT_FISCAL_YEAR' => NextFiscalYearLiteral.class,
          'LAST_N_FISCAL_YEARS' => LastNFiscalYearsLiteral.class,
          'N_FISCAL_YEARS_AGO' => NFiscalYearsAgoLiteral.class,
          'NEXT_N_FISCAL_YEARS' => NextNFiscalYearsLiteral.class,
          // Functions
          'CALENDAR_MONTH(' => CalendarMonthFunctionLiteral.class,
          'CALENDAR_YEAR(' => CalendarYearFunctionLiteral.class,
          'CALENDAR_QUARTER(' => CalendarQuarterFunctionLiteral.class,
          'DAY_IN_MONTH(' => DayInMonthFunctionLiteral.class,
          'DAY_IN_WEEK(' => DayInWeekFunctionLiteral.class,
          'DAY_IN_YEAR(' => DayInYearFunctionLiteral.class,
          'DAY_ONLY(' => DayOnlyFunctionLiteral.class,
          'FISCAL_MONTH(' => FiscalMonthFunctionLiteral.class,
          'FISCAL_QUARTER(' => FiscalQuarterFunctionLiteral.class,
          'FISCAL_YEAR(' => FiscalYearFunctionLiteral.class,
          'HOUR_IN_DAY(' => HourInDayFunctionLiteral.class,
          'WEEK_IN_MONTH(' => WeekInMonthFunctionLiteral.class,
          'WEEK_IN_YEAR(' => WeekInYearFunctionLiteral.class
        };
      return KEY_TO_DATE_LITERAL;
    }
    set;
  }

  public static Boolean isSoqlDateFunction(String val) {
    return DATE_FUNCTION_PATTERN.matcher(val).matches();
  }

  public static Boolean isDateLiteral(String key) {
    return KEY_TO_DATE_LITERAL.containsKey(key) || RELATIVE_LITERAL_PATTERN.matcher(key).matches();
  }

  public static RollupDateLiteral get(String key) {
    List<String> possibleDynamicValues = key.split(':');
    RollupDateLiteral literal = getLazyLoadedLiteral(possibleDynamicValues[0], possibleDynamicValues.size() > 1 ? possibleDynamicValues[1].trim() : '');
    return literal;
  }

  public static RollupDateLiteral getFunction(String key, String val) {
    return getLazyLoadedLiteral(key.substringBefore('(') + '(', val);
  }

  private static RollupDateLiteral getLazyLoadedLiteral(String dictionaryKey, String possibleDynamicValue) {
    Type literalType = KEY_TO_DATE_LITERAL.get(dictionaryKey);
    RollupDateLiteral literal = (RollupDateLiteral) literalType.newInstance();
    literal.setDynamicValue(possibleDynamicValue);
    return literal;
  }

  private static Datetime getRelativeDatetime(Date relativeDate, Time relativeTime) {
    return Datetime.newInstance(relativeDate, relativeTime);
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private static FiscalInfo getFiscalInfo() {
    FiscalInfo fiscalInfo = new FiscalInfo();
    // using DateLiterals **in** RollupDateLiteral? Is this irony?
    List<Period> fiscalPeriods = [
      SELECT StartDate, EndDate, Type
      FROM Period
      WHERE (Type = 'Quarter' AND EndDate = THIS_FISCAL_QUARTER) OR (Type = 'Year' AND EndDate >= THIS_FISCAL_YEAR AND EndDate <= THIS_FISCAL_YEAR)
    ];
    for (Period fiscalPeriod : fiscalPeriods) {
      if (fiscalPeriod.Type == 'Year') {
        fiscalInfo.FiscalYearStartDate = fiscalPeriod.StartDate;
        fiscalInfo.FiscalYearEndDate = fiscalPeriod.EndDate;
      } else if (fiscalPeriod.Type == 'Quarter') {
        fiscalInfo.CurrentQuarterStartDate = fiscalPeriod.StartDate;
        fiscalInfo.CurrentQuarterEndDate = fiscalPeriod.EndDate;
      }
    }
    return fiscalInfo;
  }

  private static Integer getQuarter(Integer month) {
    Integer calendarQuarter;
    switch on month {
      when 1, 2, 3 {
        calendarQuarter = 1;
      }
      when 4, 5, 6 {
        calendarQuarter = 2;
      }
      when 7, 8, 9 {
        calendarQuarter = 3;
      }
      when else {
        calendarQuarter = 4;
      }
    }
    return calendarQuarter;
  }

  private static Integer getCurrentQuarter() {
    return getQuarter(START_OF_TODAY.month());
  }

  private static Integer getCurrentQuarterStartMonth() {
    Integer currentQuarter = getCurrentQuarter();
    Integer quarterStartMonth;
    switch on currentQuarter {
      when 1 {
        quarterStartMonth = 1;
      }
      when 2 {
        quarterStartMonth = 4;
      }
      when 3 {
        quarterStartMonth = 7;
      }
      when else {
        quarterStartMonth = 10;
      }
    }
    return quarterStartMonth;
  }

  private static Date getPriorQuarterStart() {
    Integer currentQuarterStartMonth = getCurrentQuarterStartMonth();
    Boolean isFirstQuarter = currentQuarterStartMonth == 1;
    return Date.newInstance(System.today().year() - (isFirstQuarter ? 1 : 0), isFirstQuarter ? 10 : (currentQuarterStartMonth - 3), 1);
  }

  private static Date getNextQuarterStart() {
    Integer currentQuarterStartMonth = getCurrentQuarterStartMonth();
    Integer nextQuarterStartMonth = currentQuarterStartMonth == 10 ? 1 : currentQuarterStartMonth + 3;
    Integer yearForNextQuarterOffset = nextQuarterStartMonth == 1 ? 1 : 0;
    return Date.newInstance(System.today().year() + yearForNextQuarterOffset, nextQuarterStartMonth, 1);
  }

  public Boolean matches(Object val, String comparison) {
    Object castValue;
    // "The exact start and stop of the range depends on the date literal and the locale of the user sending the query."
    if (val == null) {
      return this.getEquals(comparison, false);
    } else if (val instanceof Date) {
      castValue = val;
    } else {
      // ensure we are in local time, and not UTC
      castValue = Datetime.newInstance(((Datetime) val).getTime());
    }

    switch on comparison {
      when '=', '!=' {
        return this.getEquals(comparison, this.isEqualTo(castValue));
      }
      when '>=', '>' {
        return comparison == '>=' ? this.isGreaterThan(castValue) || this.isEqualTo(castValue) : this.isGreaterThan(castValue);
      }
      when '<=', '<' {
        return comparison == '<=' ? this.isLessThan(castValue) || this.isEqualTo(castValue) : this.isLessThan(castValue);
      }
      when else {
        return false;
      }
    }
  }

  public virtual override String toString() {
    return 'ref: ' + this.ref + ' | bound: ' + this.bound;
  }

  protected virtual Boolean isEqualTo(Object val) {
    if (val instanceof Date) {
      Date dateVal = (Date) val;
      return this.ref.date() <= dateVal && dateVal <= this.bound.date();
    }
    Datetime datetimeVal = (Datetime) val;
    return this.ref <= datetimeVal && datetimeVal <= this.bound;
  }
  protected virtual Boolean isGreaterThan(Object val) {
    if (val instanceof Date) {
      Date dateVal = (Date) val;
      return dateVal > this.bound.date() && dateVal > this.ref.date();
    }
    Datetime datetimeVal = (Datetime) val;
    return datetimeVal > this.bound && datetimeVal > this.ref;
  }
  protected virtual Boolean isLessThan(Object val) {
    if (val instanceof Date) {
      Date dateVal = (Date) val;
      return dateVal < this.bound.date() && dateVal < this.ref.date();
    }
    Datetime datetimeVal = (Datetime) val;
    return datetimeVal < this.bound && datetimeVal < this.ref;
  }

  protected virtual void setDynamicValue(String num) {
  }

  private Boolean getEquals(String comparison, Boolean val) {
    return comparison == '=' ? val : !val;
  }

  private class FiscalInfo {
    public Date CurrentQuarterStartDate { get; set; }
    public Date CurrentQuarterEndDate { get; set; }
    public Date FiscalYearStartDate { get; set; }
    public Date FiscalYearEndDate { get; set; }
  }

  private class YesterdayLiteral extends RollupDateLiteral {
    public YesterdayLiteral() {
      this.ref = getRelativeDatetime(System.today().addDays(-1), START_TIME);
      this.bound = getRelativeDatetime(this.ref.date(), END_TIME);
    }
  }

  private class TodayLiteral extends RollupDateLiteral {
    public TodayLiteral() {
      this.ref = START_OF_TODAY;
      this.bound = getRelativeDatetime(this.ref.date(), END_TIME);
    }
  }

  private class TomorrowLiteral extends RollupDateLiteral {
    public TomorrowLiteral() {
      this.ref = START_OF_TODAY.addDays(1);
      this.bound = getRelativeDatetime(this.ref.date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the week before the most recent first day of the week and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class LastWeekLiteral extends RollupDateLiteral {
    public LastWeekLiteral() {
      this.bound = getRelativeDatetime(System.today().toStartOfWeek().addDays(-1), END_TIME);
      this.ref = getRelativeDatetime(this.bound.date().addDays(-6), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week on or before the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class ThisWeekLiteral extends RollupDateLiteral {
    public ThisWeekLiteral() {
      this.ref = getRelativeDatetime(System.today().toStartOfWeek(), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addDays(6).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week after the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class NextWeekLiteral extends RollupDateLiteral {
    public NextWeekLiteral() {
      this.ref = getRelativeDatetime(System.today().toStartOfWeek().addDays(7), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addDays(6).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month before the current day and continues for all the days of that month.
   */
  private class LastMonthLiteral extends RollupDateLiteral {
    public LastMonthLiteral() {
      this.ref = getRelativeDatetime(System.today().addMonths(-1).toStartOfMonth(), START_TIME);
      Date relativeDate = this.ref.addMonths(1).date();
      if (relativeDate.day() == 1) {
        relativeDate = relativeDate.addDays(-1);
      }
      this.bound = offsetToFirstDay(getRelativeDatetime(relativeDate, END_TIME));
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month that the current day is in and continues for all the days of that month.
   */
  private class ThisMonthLiteral extends RollupDateLiteral {
    public ThisMonthLiteral() {
      this.ref = getRelativeDatetime(System.today().toStartOfMonth(), START_TIME);
      Date relativeDate = this.ref.addMonths(1).date();
      if (relativeDate.day() == 1) {
        relativeDate = relativeDate.addDays(-1);
      }
      this.bound = offsetToFirstDay(getRelativeDatetime(relativeDate, END_TIME));
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month after the month that the current day is in and continues for all the days of that month.
   */
  private class NextMonthLiteral extends RollupDateLiteral {
    public NextMonthLiteral() {
      this.ref = getRelativeDatetime(System.today().toStartOfMonth().addMonths(1), START_TIME);
      Date relativeDate = this.ref.addMonths(1).date();
      if (relativeDate.day() == 1) {
        relativeDate = relativeDate.addDays(-1);
      }
      this.bound = offsetToFirstDay(getRelativeDatetime(relativeDate, END_TIME));
    }
  }

  /**
   * Starts with the current day and continues for the past 90 days.
   * This includes the current day, not just previous days. So it includes 91 days in total.
   */
  private class Last90DaysLiteral extends RollupDateLiteral {
    public Last90DaysLiteral() {
      this.bound = getRelativeDatetime(START_OF_TODAY.date(), END_TIME);
      this.ref = getRelativeDatetime(this.bound.addDays(-91).date(), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 of the next day and continues for the next 90 days.
   */
  private class Next90DaysLiteral extends RollupDateLiteral {
    public Next90DaysLiteral() {
      this.ref = START_OF_TODAY.addDays(1);
      this.bound = getRelativeDatetime(this.ref.addDays(89).dateGmt(), END_TIME);
    }
  }

  /**
   * For the number n provided, starts with the current day and continues for the past n days.
   * This includes the current day, not just previous days. For example, LAST_N_DAYS:1 includes yesterday and today.
   */
  private class LastNDaysLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = getRelativeDatetime(START_OF_TODAY.dateGmt(), END_TIME); // includes all of today
      this.ref = getRelativeDatetime(START_OF_TODAY.addDays(-(dateRange + 1)).dateGmt(), END_TIME);
    }
  }

  /**
   * For the number n provided, creates a fixed bound set n days in the past
   */
  private class NDaysAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(START_OF_TODAY.addDays(-dateRange).dateGmt(), START_TIME);
      this.bound = getRelativeDatetime(this.ref.dateGmt(), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the next day and continues for the next n days.
   * This does not include the current day. For example, NEXT_N_DAYS:1 is equivalent to TOMORROW.
   */
  private class NextNDaysLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = START_OF_TODAY.addDays(1); // excludes today
      this.bound = getRelativeDatetime(START_OF_TODAY.date().addDays(dateRange), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the last day of the previous week and continues for the past n weeks.
   */
  private class LastNWeeksLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = getRelativeDatetime(START_OF_TODAY.date().toStartOfWeek().addDays(-1), END_TIME);
      this.ref = getRelativeDatetime(this.bound.date().addDays(-1 * 7 * dateRange).addDays(1), START_TIME);
    }
  }

  /**
   * For the number n provided, creates a fixed week bound set n weeks ago in the past
   */
  private class NWeeksAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      this.ref = getRelativeDatetime(System.today().toStartOfWeek().addDays(-7 * Integer.valueOf(num)), START_TIME);
      this.bound = getRelativeDatetime(this.ref.date().addDays(6), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the first day of the next week and continues for the next n weeks.
   */
  private class NextNWeeksLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(System.today().toStartOfWeek().addDays(7), START_TIME);
      this.bound = getRelativeDateTime(this.ref.date().addDays(7 * dateRange).addDays(-1), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the last day of the previous month and continues for the past n months.
   */
  private class LastNMonthsLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      Date lastDayPreviousMonth = System.today().toStartOfMonth().addDays(-1);
      this.bound = getRelativeDatetime(lastDayPreviousMonth, END_TIME);
      this.ref = getRelativeDatetime(lastDayPreviousMonth.toStartOfMonth().addMonths(-(dateRange - 1)), START_TIME);
    }
  }

  /**
   * For the number n provided, creates a fixed month bound set n months ago in the past
   */
  private class NMonthsAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(System.today().toStartOfMonth().addMonths(-dateRange), START_TIME);
      this.bound = getRelativeDatetime(this.ref.date().addMonths(1).addDays(-1), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the first day of the next month and continues for the next n months.
   */
  private class NextNMonthsLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(System.today().toStartOfMonth().addMonths(1), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(dateRange).dateGmt().toStartOfMonth(), END_TIME));
    }
  }

  /**
   * Starts 00:00:00 of the previous quarter and continues to the end of that quarter.
   */
  private virtual class LastQuarterLiteral extends RollupDateLiteral {
    public LastQuarterLiteral() {
      this.ref = getRelativeDatetime(this.getLastQuarterStart(), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(3).date(), END_TIME));
    }

    protected virtual Date getLastQuarterStart() {
      return getPriorQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 of the current quarter and continues to the end of the current quarter.
   */
  private virtual class ThisQuarterLiteral extends RollupDateLiteral {
    public ThisQuarterLiteral() {
      this.ref = getRelativeDatetime(this.getThisQuarterStart(), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(3).date(), END_TIME));
    }

    protected virtual Date getThisQuarterStart() {
      return Date.newInstance(System.today().year(), getCurrentQuarterStartMonth(), 1);
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of that quarter.
   */
  private virtual class NextQuarterLiteral extends RollupDateLiteral {
    public NextQuarterLiteral() {
      this.ref = getRelativeDatetime(this.getNextQuarterDate(), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(3).date(), END_TIME));
    }

    protected virtual Date getNextQuarterDate() {
      return getNextQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 of the previous quarter and continues to the end of the previous nth quarter.
   */
  private virtual class LastNQuartersLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.getLastQuarterStart(), END_TIME));
      this.ref = offsetToFirstDay(getRelativeDateTime(this.bound.addMonths(-3 * quarterRange).dateGmt(), START_TIME));
    }

    protected virtual Date getLastQuarterStart() {
      return Date.newInstance(System.today().year(), getCurrentQuarterStartMonth(), 1);
    }
  }

  /**
   * For the number n provided, creates a fixed quarter bound set n quarters ago in the past
   */
  private class NQuartersAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(Date.newInstance(System.today().year(), getCurrentQuarterStartMonth(), 1).addMonths(-quarterRange * 3), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(3).date(), END_TIME));
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of the nth quarter.
   */
  private virtual class NextNQuartersLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(this.getNextQuarterDate(), START_TIME);
      this.bound = offsetToFirstDay(getRelativeDatetime(this.ref.addMonths(quarterRange * 3).date(), END_TIME));
    }

    protected virtual Date getNextQuarterDate() {
      return getNextQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the current year and continues through the end of December 31 of the current year.
   */
  private class ThisYearLiteral extends RollupDateLiteral {
    public ThisYearLiteral() {
      this.ref = Datetime.newInstance(System.today().year(), 1, 1);
      this.bound = getEndOfYear(System.today().year());
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the previous year and continues through the end of December 31 of that year.
   */
  private class LastYearLiteral extends RollupDateLiteral {
    public LastYearLiteral() {
      Integer lastYearNumber = System.today().year() - 1;
      this.ref = Datetime.newInstance(lastYearNumber, 1, 1);
      this.bound = getEndOfYear(lastYearNumber);
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the following year and continues through the end of December 31 of that year
   */
  private class NextYearLiteral extends RollupDateLiteral {
    public NextYearLiteral() {
      Integer nextYearNumber = System.today().year() + 1;
      this.ref = Datetime.newInstance(nextYearNumber, 1, 1);
      this.bound = getEndOfYear(nextYearNumber);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 on January 1 of the previous year and continues through the end of December 31 of the previous nth year.
   */
  private virtual class LastNYearsLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(this.getStartOfLastYear().addYears(-(dateRange - 1)), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addYears(dateRange).date().addDays(-1), END_TIME);
    }

    protected virtual Date getStartOfLastYear() {
      return Date.newInstance(System.today().year() - 1, 1, 1);
    }
  }

  /**
   * For the number n provided, creates a fixed year bound set n years ago in the past
   */
  private class NYearsAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(Date.newInstance(System.today().year(), 1, 1).addYears(-dateRange), START_TIME);
      this.bound = getEndOfYear(this.ref.year());
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the following year and continues through the end of December 31 of the nth year.
   */
  private virtual class NextNYearsLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(this.getStartOfNextYear(), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addYears(dateRange).date().addDays(-1), END_TIME);
    }

    protected virtual Date getStartOfNextYear() {
      return Date.newInstance(System.today().year() + 1, 1, 1);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the last fiscal quarter and continues through the end of the last day of that fiscal quarter.
   */
  private class LastFiscalQuarterLiteral extends LastQuarterLiteral {
    protected override Date getLastQuarterStart() {
      return FISCAL_INFO.CurrentQuarterStartDate.addMonths(-3);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the current fiscal quarter and continues through the end of the last day of the fiscal quarter.
   */
  private class ThisFiscalQuarterLiteral extends RollupDateLiteral {
    public ThisFiscalQuarterLiteral() {
      this.ref = getRelativeDatetime(FISCAL_INFO.CurrentQuarterStartDate, START_TIME);
      this.bound = getRelativeDatetime(FISCAL_INFO.CurrentQuarterEndDate, END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the next fiscal quarter and continues through the end of the last day of that fiscal quarter.
   */
  private class NextFiscalQuarterLiteral extends NextQuarterLiteral {
    protected override Date getNextQuarterDate() {
      return FISCAL_INFO.CurrentQuarterStartDate.addMonths(3);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the last fiscal quarter and continues through the end of the last day of the previous nth fiscal quarter.
   */
  private class LastNFiscalQuartersLiteral extends LastNQuartersLiteral {
    protected override Date getLastQuarterStart() {
      return FISCAL_INFO.CurrentQuarterStartDate;
    }
  }

  /**
   * For the number n provided, creates a fixed fiscal quarter bound set n fiscal quarters ago in the past
   */
  private class NFiscalQuartersAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(FISCAL_INFO.CurrentQuarterStartDate.addMonths(-3 * quarterRange), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addMonths(3).dateGmt().addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the next fiscal quarter and continues through the end of the last day of the nth fiscal quarter.
   */
  private class NextNFiscalQuartersLiteral extends NextNQuartersLiteral {
    protected override Date getNextQuarterDate() {
      return FISCAL_INFO.CurrentQuarterStartDate.addMonths(3);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the last fiscal year and continues through the end of the last day of that fiscal year.
   */
  private class LastFiscalYearLiteral extends RollupDateLiteral {
    public LastFiscalYearLiteral() {
      this.ref = getRelativeDatetime(FISCAL_INFO.FiscalYearStartDate.addYears(-1), START_TIME);
      this.bound = getRelativeDatetime(FISCAL_INFO.FiscalYearStartDate.addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the current fiscal year and continues through the end of the last day of the fiscal year.
   */
  private class ThisFiscalYearLiteral extends RollupDateLiteral {
    public ThisFiscalYearLiteral() {
      this.ref = getRelativeDatetime(FISCAL_INFO.FiscalYearStartDate, START_TIME);
      this.bound = getRelativeDatetime(this.ref.addYears(1).date().addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the next fiscal year and continues through the end of the last day of that fiscal year.
   */
  private class NextFiscalYearLiteral extends RollupDateLiteral {
    public NextFiscalYearLiteral() {
      this.ref = getRelativeDatetime(FISCAL_INFO.FiscalYearStartDate.addYears(1), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addYears(1).date().addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the last fiscal year and continues through the end of the last day of the previous nth fiscal year.
   */
  private class LastNFiscalYearsLiteral extends LastNYearsLiteral {
    protected override Date getStartOfLastYear() {
      return FISCAL_INFO.FiscalYearStartDate.addYears(-1);
    }
  }

  /**
   * For the number n provided, creates a fixed fiscal year bound set n fiscal years ago in the past
   */
  private class NFiscalYearsAgoLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String num) {
      Integer yearRange = Integer.valueOf(num);
      this.ref = getRelativeDatetime(FISCAL_INFO.FiscalYearStartDate.addYears(-yearRange), START_TIME);
      this.bound = getRelativeDatetime(this.ref.addYears(1).date().addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the next fiscal year and continues through the end of the last day of the nth fiscal year.
   */
  private class NextNFiscalYearsLiteral extends NextNYearsLiteral {
    protected override Date getStartOfNextYear() {
      return FISCAL_INFO.FiscalYearStartDate.addYears(1);
    }
  }

  /**
   * Function Section.
   */

  private abstract class FunctionLiteral extends RollupDateLiteral {
    protected Integer bound;
    protected Boolean wasDate = false;

    public override String toString() {
      return String.valueOf(this.bound);
    }

    protected override void setDynamicValue(String num) {
      this.bound = Integer.valueOf(num);
    }

    protected abstract Integer getComparisonNumber(Datetime val);

    protected override Boolean isEqualTo(Object val) {
      Datetime castVal = this.getTimezoneAdjustedDatetime(val);
      return this.bound == this.getComparisonNumber(castVal);
    }
    protected override Boolean isGreaterThan(Object val) {
      Datetime castVal = this.getTimezoneAdjustedDatetime(val);
      return this.bound < this.getComparisonNumber(castVal);
    }
    protected override Boolean isLessThan(Object val) {
      Datetime castVal = this.getTimezoneAdjustedDatetime(val);
      return this.bound > this.getComparisonNumber(castVal);
    }
    private Datetime getTimezoneAdjustedDatetime(Object val) {
      if (val instanceof Date) {
        val = Datetime.newInstanceGmt((Date) val, END_TIME);
        this.wasDate = true;
      } else {
        this.wasDate = false;
        val = Datetime.newInstance(((Datetime) val).getTime());
      }
      return (Datetime) val;
    }
  }

  private class CalendarMonthFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.monthGmt();
    }
  }

  private class CalendarYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.yearGmt();
    }
  }

  private class CalendarQuarterFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return getQuarter(val.monthGmt());
    }
  }

  private class DayInMonthFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.dayGmt();
    }
  }

  private class DayInWeekFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      Date startOfWeek = val.dateGmt().toStartOfWeek();
      Integer daysBetween = startOfWeek.daysBetween(val.dateGmt());
      return daysBetween + 1;
    }
  }

  private class DayInYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.dayOfYearGmt();
    }
  }

  // there's always an exception to the rule!
  /** Returns a Date representing the day portion of a DateTime field. */
  private class DayOnlyFunctionLiteral extends RollupDateLiteral {
    protected override void setDynamicValue(String dateString) {
      this.ref = Datetime.newInstanceGmt(Date.valueOf(dateString), START_TIME);
      this.bound = this.ref.addDays(1);
    }
  }

  private class FiscalMonthFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      Integer yearDiff = FISCAL_INFO.FiscalYearStartDate.year() - val.yearGmt();
      if (yearDiff > 0) {
        val = val.addYears(yearDiff);
      }
      Integer monthsBetween = FISCAL_INFO.FiscalYearStartDate.monthsBetween(val.dateGmt()) + 1;
      return getFiscalMonthsOffset(monthsBetween);
    }
  }

  private static Integer getFiscalMonthsOffset(Integer monthsSinceFiscalStart) {
    if (Math.abs(monthsSinceFiscalStart) > 12) {
      monthsSinceFiscalStart = Math.mod(monthsSinceFiscalStart, 12);
    }
    if (monthsSinceFiscalStart == 0) {
      monthsSinceFiscalStart = 12;
    } else if (monthsSinceFiscalStart < 0) {
      monthsSinceFiscalStart = monthsSinceFiscalStart + 12;
    }
    return monthsSinceFiscalStart;
  }

  private class FiscalQuarterFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      Integer fiscalQuarter;
      Integer monthsSinceFiscalStart = getFiscalMonthsOffset(FISCAL_INFO.FiscalYearStartDate.monthsBetween(val.dateGmt()) + 1);
      if (monthsSinceFiscalStart == 0) {
        monthsSinceFiscalStart = 12;
      }
      switch on monthsSinceFiscalStart {
        when 1, 2, 3, -9, -10, -11 {
          fiscalQuarter = 1;
        }
        when 4, 5, 6, -6, -7, -8 {
          fiscalQuarter = 2;
        }
        when 7, 8, 9, -3, -4, -5 {
          fiscalQuarter = 3;
        }
        when 10, 11, 12, -1, -2, -12 {
          fiscalQuarter = 4;
        }
      }
      return fiscalQuarter;
    }
  }

  private class FiscalYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      Integer fiscalYear = val.yearGmt();
      if (val.dateGmt() > FISCAL_INFO.FiscalYearEndDate) {
        fiscalYear++;
      } else if (
        val.monthGmt() >= FISCAL_INFO.FiscalYearStartDate.month() &&
        // Fiscal year is a cursed concept, in that start/ending in January
        // behaves completely differently than every other possible combo
        FISCAL_INFO.FiscalYearStartDate.month() != 1
      ) {
        fiscalYear++;
      }
      return fiscalYear;
    }
  }

  private class HourInDayFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      if (this.wasDate) {
        return this.bound;
      }
      return val.hourGmt();
    }
  }

  private class WeekInMonthFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return getWeekNumber(val.dayGmt());
    }
  }

  private static Datetime getEndOfYear(Integer yearNumber) {
    return getRelativeDatetime(Date.newInstance(yearNumber, 12, 31), END_TIME);
  }

  private static Datetime offsetToFirstDay(Datetime ref) {
    if (ref.dayGmt() != 1 && ref.day() == 1) {
      ref = ref.addDays(-1);
    }
    return ref;
  }

  private static Integer getWeekNumber(Integer dayNumber) {
    Integer currentWeek;
    if (dayNumber <= 7) {
      currentWeek = 1;
    } else if (dayNumber > 7 && dayNumber <= 14) {
      currentWeek = 2;
    } else if (dayNumber > 14 && dayNumber <= 21) {
      currentWeek = 3;
    } else if (dayNumber > 21 && dayNumber <= 28) {
      currentWeek = 4;
    } else {
      currentWeek = 5;
    }
    return currentWeek;
  }

  /**
   * The first week is from January 1 through January 7.
   */
  private class WeekInYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return Integer.valueOf(val.format('w'));
    }
  }
}
