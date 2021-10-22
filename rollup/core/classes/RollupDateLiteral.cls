@SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
public without sharing abstract class RollupDateLiteral {
  private static final Pattern RELATIVE_LITERAL_PATTERN = Pattern.compile(
    '(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_​QUARTERS|FISCAL_​YEARS):\\s?\\d*'
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

  private static final Map<String, Object> KEY_TO_DATE_LITERAL = new Map<String, Object>{
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
    'LAST_N_FISCAL_​QUARTERS' => null,
    'NEXT_N_FISCAL_​QUARTERS' => null,
    'LAST_FISCAL_YEAR' => null,
    'THIS_FISCAL_YEAR' => null,
    'NEXT_FISCAL_YEAR' => null,
    'LAST_N_FISCAL_​YEARS' => null,
    'NEXT_N_FISCAL_​YEARS' => null
  };

  public static Boolean isDateLiteral(String key) {
    return KEY_TO_DATE_LITERAL.containsKey(key) || RELATIVE_LITERAL_PATTERN.matcher(key).matches();
  }

  public static RollupDateLiteral get(String key) {
    List<String> possibleDynamicValues = key.split(':');
    RollupDateLiteral literal = getLazyLoadedLiteral(possibleDynamicValues[0], possibleDynamicValues.size() > 1 ? possibleDynamicValues[1].trim() : '');
    return literal;
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
      ((RollupDateLiteral) literal).setDynamicValue(possibleDynamicValue);
      KEY_TO_DATE_LITERAL.put(dictionaryKey, literal);
    }
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

  private static Integer getCurrentQuarter() {
    Integer currentQuarterStartingMonth;
    switch on System.today().month() {
      when 1, 2, 3 {
        currentQuarterStartingMonth = 1;
      }
      when 4, 5, 6 {
        currentQuarterStartingMonth = 4;
      }
      when 7, 8, 9 {
        currentQuarterStartingMonth = 7;
      }
      when else {
        currentQuarterStartingMonth = 10;
      }
    }
    return currentQuarterStartingMonth;
  }

  private static Date getPriorQuarterStart() {
    Integer currentQuarterStartMonth = getCurrentQuarter();
    Boolean isFirstQuarter = currentQuarterStartMonth == 1;
    return Date.newInstance(System.today().year() - (isFirstQuarter ? 1 : 0), isFirstQuarter ? 10 : (currentQuarterStartMonth - 3), 1);
  }

  private static Integer getNextQuarterStartingMonth() {
    Integer currentQuarterStartMonth = getCurrentQuarter();
    return currentQuarterStartMonth == 10 ? 1 : currentQuarterStartMonth + 3;
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
    return this.ref.format();
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
      this.ref = START_OF_TODAY.addDays(-dateRange);
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
      return Date.newInstance(System.today().year(), getCurrentQuarter(), 1);
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of that quarter.
   */
  private virtual class NextQuarterLiteral extends RangedLiteral {
    public NextQuarterLiteral() {
      this.ref = Datetime.newInstanceGmt(this.getNextQuarterStart(), START_TIME);
      Integer endMonth = this.ref.addMonths(3).month();
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(2).addDays(Date.daysInMonth(this.ref.year(), endMonth)).date(), END_TIME);
    }

    protected virtual Date getNextQuarterStart() {
      Integer nextQuarterStartingMonth = getNextQuarterStartingMonth();
      return Date.newInstance(System.today().year() + (nextQuarterStartingMonth == 1 ? 1 : 0), nextQuarterStartingMonth, 1);
    }
  }

  /**
   * Starts 00:00:00 of the previous quarter and continues to the end of the previous nth quarter.
   */
  private class LastNQuartersLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num) - 1;

      this.bound = Datetime.newInstanceGmt(getPriorQuarterStart(), START_TIME);
      this.ref = this.bound.addMonths(quarterRange * -3);
    }
  }

  /**
   * Starts 00:00:00 of the next quarter and continues to the end of the nth quarter.
   */
  private class NextNQuartersLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer quarterRange = Integer.valueOf(num);
      Integer nextQuarterStartingMonth = getNextQuarterStartingMonth();
      Integer yearForNextQuarterOffset = nextQuarterStartingMonth == 1 ? 1 : 0;

      this.ref = Datetime.newInstanceGmt(Date.newInstance(System.today().year() + yearForNextQuarterOffset, nextQuarterStartingMonth, 1), START_TIME);
      this.bound = Datetime.newInstanceGmt(this.ref.addMonths(quarterRange * 3).date(), END_TIME);
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
  private class LastNYearsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.bound = Datetime.newInstanceGmt(Date.newInstance(System.today().year() - 1, 1, 1), START_TIME);
      this.ref = Datetime.newInstanceGmt(this.bound.addYears(-dateRange).date(), END_TIME);
    }
  }

  /**
   * Starts 00:00:00 on January 1 of the following year and continues through the end of December 31 of the nth year.
   */
  private class NextNYearsLiteral extends RangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(Date.newInstance(System.today().year() + 1, 1, 1), START_TIME);
      this.bound = Datetime.newInstanceGmt(Date.newInstance(this.ref.year() + dateRange, 12, 31), END_TIME);
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
    protected override Date getNextQuarterStart() {
      return FISCAL_INFO.CurrentQuarterStartDate.addMonths(3);
    }
  }
}
