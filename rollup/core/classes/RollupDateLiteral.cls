@SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
public without sharing abstract class RollupDateLiteral {
  private static final Pattern RELATIVE_LITERAL_PATTERN = Pattern.compile(
    '(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_QUARTERS|FISCAL_YEARS):\\s?\\d*'
  );
  private static final Pattern DATE_FUNCTION_PATTERN = Pattern.compile(
    '(CALENDAR_MONTH|CALENDAR_QUARTER|CALENDAR_YEAR|DAY_IN_MONTH|DAY_IN_WEEK|DAY_IN_YEAR|DAY_ONLY|FISCAL_MONTH|' +
    'FISCAL_QUARTER|FISCAL_YEAR|HOUR_IN_DAY|WEEK_IN_MONTH|WEEK_IN_YEAR)\\(.+?\\)'
  );

  private static final Time START_TIME {
    get {
      if (START_TIME == null) {
        START_TIME = Time.newInstance(0, 0, 0, 0);
      }
      return START_TIME;
    }
    set;
  }

  private static final Time END_TIME {
    get {
      if (END_TIME == null) {
        END_TIME = Time.newInstance(11, 59, 59, 59);
      }
      return END_TIME;
    }
    set;
  }

  private static final Datetime START_OF_TODAY {
    get {
      if (START_OF_TODAY == null) {
        return Datetime.newInstanceGmt(System.today(), START_TIME);
      }
      return START_OF_TODAY;
    }
    set;
  }

  private static final FiscalInfo FISCAL_INFO {
    get {
      if (FISCAL_INFO == null) {
        FISCAL_INFO = getFiscalInfo();
      }
      return FISCAL_INFO;
    }
    set;
  }

  protected Datetime ref;

  private static final Map<String, Object> KEY_TO_DATE_LITERAL {
    get {
      if (KEY_TO_DATE_LITERAL == null) {
        KEY_TO_DATE_LITERAL = new Map<String, Object>{
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
          'NEXT_N_DAYS' => NextNDaysLiteral.class,
          'LAST_N_WEEKS' => LastNWeeksLiteral.class,
          'NEXT_N_WEEKS' => NextNWeeksLiteral.class,
          'LAST_N_MONTHS' => LastNMonthsLiteral.class,
          'NEXT_N_MONTHS' => NextNMonthsLiteral.class,
          'LAST_QUARTER' => LastQuarterLiteral.class,
          'THIS_QUARTER' => ThisQuarterLiteral.class,
          'NEXT_QUARTER' => NextQuarterLiteral.class,
          'LAST_N_QUARTERS' => LastNQuartersLiteral.class,
          'NEXT_N_QUARTERS' => NextNQuartersLiteral.class,
          'THIS_YEAR' => ThisYearLiteral.class,
          'LAST_YEAR' => LastYearLiteral.class,
          'NEXT_YEAR' => NextYearLiteral.class,
          'LAST_N_YEARS' => LastNYearsLiteral.class,
          'NEXT_N_YEARS' => NextNYearsLiteral.class,
          'LAST_FISCAL_QUARTER' => LastFiscalQuarterLiteral.class,
          'THIS_FISCAL_QUARTER' => ThisFiscalQuarterLiteral.class,
          'NEXT_FISCAL_QUARTER' => NextFiscalQuarterLiteral.class,
          'LAST_N_FISCAL_QUARTERS' => LastNFiscalQuartersLiteral.class,
          'NEXT_N_FISCAL_QUARTERS' => NextNFiscalQuartersLiteral.class,
          'LAST_FISCAL_YEAR' => LastFiscalYearLiteral.class,
          'THIS_FISCAL_YEAR' => ThisFiscalYearLiteral.class,
          'NEXT_FISCAL_YEAR' => NextFiscalYearLiteral.class,
          'LAST_N_FISCAL_YEARS' => LastNFiscalYearsLiteral.class,
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
      }
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
    /**
     * neatly solves a thorny issue - we want to cache the RollupDateLiteral instances,
     * but if we key them directly in the map, the memory overhead is MUCH larger
     * since everything will be initialized when the map is first accessed.
     * Instead, each map entry is keyed to the Type of its corresponding literal,
     * and only the Types that we need end up getting initialized
     */
    Object literal = KEY_TO_DATE_LITERAL.get(dictionaryKey);
    if (literal instanceof Type) {
      Type literalType = (Type) literal;
      literal = (RollupDateLiteral) literalType.newInstance();
      KEY_TO_DATE_LITERAL.put(dictionaryKey, literal);
    }
    ((RollupDateLiteral) literal).setDynamicValue(possibleDynamicValue);
    return (RollupDateLiteral) literal;
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private static FiscalInfo getFiscalInfo() {
    FiscalInfo fiscalInfo = new FiscalInfo();
    // using DateLiterals **in** RollupDateLiteral? Is this irony?
    List<Period> fiscalPeriods = [SELECT StartDate, EndDate, Type FROM Period WHERE Type IN ('Quarter', 'Year') AND EndDate = THIS_FISCAL_QUARTER];
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
    return getQuarter(System.today().month());
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
    Datetime castValue;
    if (val == null) {
      return false;
    } else if (val instanceof Date) {
      castValue = Datetime.newInstanceGmt((Date) val, START_TIME);
    } else {
      castValue = (Datetime) val;
    }

    switch on comparison {
      when '=', '!=' {
        return comparison == '=' ? this.isEqualTo(castValue) : this.isEqualTo(castValue) == false;
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
    return this.ref?.format();
  }

  protected virtual Boolean isEqualTo(Datetime val) {
    return this.ref == val;
  }
  protected virtual Boolean isLessThan(Datetime val) {
    return this.ref > val;
  }
  protected virtual Boolean isGreaterThan(Datetime val) {
    return this.ref < val;
  }

  protected virtual void setDynamicValue(String num) {
  }

  private class FiscalInfo {
    public Date CurrentQuarterStartDate { get; set; }
    public Date CurrentQuarterEndDate { get; set; }
    public Date FiscalYearStartDate { get; set; }
    public Date FiscalYearEndDate { get; set; }
  }

  private class YesterdayLiteral extends RollupDateLiteral {
    public YesterdayLiteral() {
      this.ref = START_OF_TODAY.addDays(-1);
    }
  }

  private class TodayLiteral extends RollupDateLiteral {
    public TodayLiteral() {
      this.ref = START_OF_TODAY;
    }
  }

  private class TomorrowLiteral extends RollupDateLiteral {
    public TomorrowLiteral() {
      this.ref = START_OF_TODAY.addDays(1);
    }
  }

  /**
   * NEXT/LAST Section. Since these are range-based comparisons, we have to compare start/end bounds
   */

  private abstract class RangedLiteral extends RollupDateLiteral {
    protected Datetime bound;

    protected override Boolean isEqualTo(Datetime val) {
      return this.ref <= val && val <= this.bound;
    }
    protected override Boolean isGreaterThan(Datetime val) {
      return val > this.bound && val > this.ref;
    }
    protected override Boolean isLessThan(Datetime val) {
      return val < this.bound && val < this.ref;
    }

    public override String toString() {
      return 'ref: ' + this.ref + ' | bound: ' + this.bound;
    }
  }

  /**
   * Starts 00:00:00 on the first day of the week before the most recent first day of the week and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class LastWeekLiteral extends RangedLiteral {
    public LastWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(-7), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addDays(7).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week on or before the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class ThisWeekLiteral extends RangedLiteral {
    public ThisWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek(), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addDays(7).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week after the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class NextWeekLiteral extends RangedLiteral {
    public NextWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(7), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addDays(7).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month before the current day and continues for all the days of that month.
   */
  private class LastMonthLiteral extends RangedLiteral {
    public LastMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().addMonths(-1).toStartOfMonth(), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(1).addDays(-1).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month that the current day is in and continues for all the days of that month.
   */
  private class ThisMonthLiteral extends RangedLiteral {
    public ThisMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth(), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(1).addDays(-1).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month after the month that the current day is in and continues for all the days of that month.
   */
  private class NextMonthLiteral extends RangedLiteral {
    public NextMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth().addMonths(1), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(1).addDays(-1).date(), END_TIME);
    }
  }

  /**
   * Starts with the current day and continues for the past 90 days.
   * This includes the current day, not just previous days. So it includes 91 days in total.
   */
  private class Last90DaysLiteral extends RangedLiteral {
    public Last90DaysLiteral() {
      this.ref = START_OF_TODAY.addDays(-91);
      this.bound = Datetime.newInstanceGmt(System.today(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 of the next day and continues for the next 90 days.
   */
  private class Next90DaysLiteral extends RangedLiteral {
    public Next90DaysLiteral() {
      this.ref = START_OF_TODAY;
      this.bound = Datetime.newInstanceGmt(System.today().addDays(91), END_TIME);
    }
  }

  /**
   * For the number n provided, starts with the current day and continues for the past n days.
   * This includes the current day, not just previous days. For example, LAST_N_DAYS:1 includes yesterday and today.
   */
  private class LastNDaysLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = Datetime.newInstanceGmt(System.today(), END_TIME); // includes all of today
      this.ref = Datetime.newInstanceGmt(START_OF_TODAY.addDays(-(dateRange + 1)).dateGmt(), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the next day and continues for the next n days.
   * This does not include the current day. For example, NEXT_N_DAYS:1 is equivalent to TOMORROW.
   */
  private class NextNDaysLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = START_OF_TODAY.addDays(1); // excludes today
      this.bound = START_OF_TODAY.addDays(dateRange);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the last day of the previous week and continues for the past n weeks.
   */
  private class LastNWeeksLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(-1), END_TIME);
      this.ref = Datetime.newInstanceGmt(this.bound.addDays(-1 * 7 * dateRange).date(), START_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the first day of the next week and continues for the next n weeks.
   */
  private class NextNWeeksLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(7), START_TIME);
      this.bound = this.ref.addDays(7 * dateRange);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the last day of the previous month and continues for the past n months.
   */
  private class LastNMonthsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      Date lastDayPreviousMonth = System.today().toStartOfMonth().addDays(-1);
      this.bound = Datetime.newInstanceGmt(lastDayPreviousMonth, END_TIME);
      this.ref = Datetime.newInstanceGmt(lastDayPreviousMonth.toStartOfMonth().addMonths(-dateRange), START_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the first day of the next month and continues for the next n months.
   */
  private class NextNMonthsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      Date startDayOfNextMonth = System.today().toStartOfMonth().addMonths(1);
      this.ref = Datetime.newInstanceGmt(startDayOfNextMonth, START_TIME);
      this.bound = Datetime.newInstanceGmt(startDayOfNextMonth.addMonths(dateRange).addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 of the previous quarter and continues to the end of that quarter.
   */
  private virtual class LastQuarterLiteral extends RangedLiteral {
    public LastQuarterLiteral() {
      this.ref = Datetime.newInstanceGmt(this.getLastQuarterStart(), START_TIME);
      Integer endMonth = this.ref.addMonths(3).month();
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(2).addDays(Date.daysInMonth(this.ref.year(), endMonth)).date(), END_TIME);
    }

    protected virtual Date getLastQuarterStart() {
      return getPriorQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 of the current quarter and continues to the end of the current quarter.
   */
  private virtual class ThisQuarterLiteral extends RangedLiteral {
    public ThisQuarterLiteral() {
      this.ref = Datetime.newInstanceGmt(this.getThisQuarterStart(), START_TIME);
      Integer endMonth = this.ref.addMonths(3).month();
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(2).addDays(Date.daysInMonth(this.ref.year(), endMonth)).date(), END_TIME);
    }

    protected virtual Date getThisQuarterStart() {
      return Date.newInstance(System.today().year(), getCurrentQuarterStartMonth(), 1);
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of that quarter.
   */
  private virtual class NextQuarterLiteral extends RangedLiteral {
    public NextQuarterLiteral() {
      this.ref = Datetime.newInstanceGmt(this.getNextQuarterDate(), START_TIME);
      Integer endMonth = this.ref.addMonths(3).month();
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(2).addDays(Date.daysInMonth(this.ref.year(), endMonth)).date(), END_TIME);
    }

    protected virtual Date getNextQuarterDate() {
      return getNextQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 of the previous quarter and continues to the end of the previous nth quarter.
   */
  private virtual class LastNQuartersLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num) - 1;
      this.bound = Datetime.newInstanceGmt(this.getLastQuarterStart(), START_TIME);
      this.ref = this.bound.addMonths(quarterRange * -3);
    }

    protected virtual Date getLastQuarterStart() {
      return getPriorQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of the nth quarter.
   */
  private virtual class NextNQuartersLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(this.getNextQuarterDate(), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(quarterRange * 3).date(), END_TIME);
    }

    protected virtual Date getNextQuarterDate() {
      return getNextQuarterStart();
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the current year and continues through the end of December 31 of the current year.
   */
  private class ThisYearLiteral extends RangedLiteral {
    public ThisYearLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().year(), 1, 1);
      this.bound = Datetime.newInstance(Date.newInstance(System.today().year(), 12, 31), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the previous year and continues through the end of December 31 of that year.
   */
  private class LastYearLiteral extends RangedLiteral {
    public LastYearLiteral() {
      Integer lastYearNumber = System.today().year() - 1;
      this.ref = Datetime.newInstanceGmt(lastYearNumber, 1, 1);
      this.bound = Datetime.newInstanceGmt(Date.newInstance(lastYearNumber, 12, 31), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the following year and continues through the end of December 31 of that year
   */
  private class NextYearLiteral extends RangedLiteral {
    public NextYearLiteral() {
      Integer nextYearNumber = System.today().year() + 1;
      this.ref = Datetime.newInstanceGmt(nextYearNumber, 1, 1);
      this.bound = Datetime.newInstanceGmt(Date.newInstance(nextYearNumber, 12, 31), END_TIME);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 on January 1 of the previous year and continues through the end of December 31 of the previous nth year.
   */
  private virtual class LastNYearsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = Datetime.newInstanceGmt(this.getStartOfLastYear(), START_TIME);
      this.ref = Datetime.newInstanceGmt(this.bound.addYears(-dateRange).date(), END_TIME);
    }

    protected virtual Date getStartOfLastYear() {
      return Date.newInstance(System.today().year() - 1, 1, 1);
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the following year and continues through the end of December 31 of the nth year.
   */
  private virtual class NextNYearsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(this.getStartOfNextYear(), START_TIME);
      this.bound = Datetime.newInstanceGmt(Date.newInstance(this.ref.year() + dateRange, 12, 31), END_TIME);
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
  private class ThisFiscalQuarterLiteral extends ThisQuarterLiteral {
    protected override Date getThisQuarterStart() {
      return FISCAL_INFO.CurrentQuarterStartDate;
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
      return FISCAL_INFO.CurrentQuarterStartDate.addMonths(-3);
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
  private class LastFiscalYearLiteral extends RangedLiteral {
    public LastFiscalYearLiteral() {
      this.ref = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearStartDate.addYears(-1), START_TIME);
      this.bound = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearStartDate.addDays(-1), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the current fiscal year and continues through the end of the last day of the fiscal year.
   */
  private class ThisFiscalYearLiteral extends RangedLiteral {
    public ThisFiscalYearLiteral() {
      this.ref = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearStartDate, START_TIME);
      this.bound = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearEndDate, END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the next fiscal year and continues through the end of the last day of that fiscal year.
   */
  private class NextFiscalYearLiteral extends RangedLiteral {
    public NextFiscalYearLiteral() {
      this.ref = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearStartDate.addYears(1), START_TIME);
      this.bound = Datetime.newInstanceGmt(FISCAL_INFO.FiscalYearEndDate.addYears(1), END_TIME);
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

    public override String toString() {
      return String.valueOf(this.bound);
    }

    protected override void setDynamicValue(String num) {
      this.bound = Integer.valueOf(num);
    }

    protected abstract Integer getComparisonNumber(Datetime val);

    protected override Boolean isEqualTo(Datetime val) {
      return this.bound == this.getComparisonNumber(val);
    }
    protected override Boolean isGreaterThan(Datetime val) {
      return this.bound < this.getComparisonNumber(val);
    }
    protected override Boolean isLessThan(Datetime val) {
      return this.bound > this.getComparisonNumber(val);
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
  private class DayOnlyFunctionLiteral extends RangedLiteral {
    protected override void setDynamicValue(String dateString) {
      this.ref = Datetime.newInstanceGmt(Date.valueOf(dateString), START_TIME);
      this.bound = this.ref;
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
        when 1, 2, 3, -10, -11, -12 {
          fiscalQuarter = 1;
        }
        when 4, 5, 6, -7, -8, -9 {
          fiscalQuarter = 2;
        }
        when 7, 8, 9, -4, -5, -6 {
          fiscalQuarter = 3;
        }
        when 10, 11, 12, -1, -2, -3 {
          fiscalQuarter = 4;
        }
      }
      return fiscalQuarter;
    }
  }

  private class FiscalYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.monthGmt() >= FISCAL_INFO.FiscalYearStartDate.month() &&
        val.yearGmt() > FISCAL_INFO.FiscalYearStartDate.year()
        ? val.yearGmt() + 1
        : val.yearGmt();
    }
  }

  private class HourInDayFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return val.hourGmt();
    }
  }

  private class WeekInMonthFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return getWeekNumber(val.dayGmt());
    }
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
   * Week 1 is the first week that has at least 4 days in the current year - yikes!
   * There can also be a week 53. The sadness.
   */
  private class WeekInYearFunctionLiteral extends FunctionLiteral {
    protected override Integer getComparisonNumber(Datetime val) {
      return Integer.valueOf(val.format('ww'));
    }
  }
}
