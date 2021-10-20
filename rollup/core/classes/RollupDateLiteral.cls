@SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
public abstract class RollupDateLiteral {
  private static final String RELATIVE_LITERAL_REGEX = '(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_​QUARTERS|FISCAL_​YEARS):?\\d*';

  private static final Time START_TIME {
    get {
      if (START_TIME == null) {
        START_TIME = Time.newInstance(0, 0, 0, 0);
      }
      return START_TIME;
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
    'LAST_N_MONTHS' => null,
    'THIS_QUARTER' => null,
    'LAST_QUARTER' => null,
    'NEXT_QUARTER' => null,
    'NEXT_N_QUARTERS' => null,
    'LAST_N_QUARTERS' => null,
    'THIS_YEAR' => ThisYearLiteral.class,
    'LAST_YEAR' => LastYearLiteral.class,
    'NEXT_YEAR' => NextYearLiteral.class,
    'LAST_N_YEARS' => null,
    'NEXT_N_YEARS' => null,
    'THIS_FISCAL_QUARTER' => null,
    'LAST_FISCAL_QUARTER' => null,
    'NEXT_FISCAL_QUARTER' => null,
    'LAST_N_FISCAL_​QUARTERS' => null,
    'NEXT_N_FISCAL_​QUARTERS' => null,
    'LAST_FISCAL_YEAR' => null,
    'THIS_FISCAL_YEAR' => null,
    'NEXT_FISCAL_YEAR' => null,
    'LAST_N_FISCAL_​YEARS' => null,
    'NEXT_N_FISCAL_​YEARS' => null
  };

  public static Boolean isDateLiteral(String key) {
    return KEY_TO_DATE_LITERAL.containsKey(key) || Pattern.matches(RELATIVE_LITERAL_REGEX, key);
  }

  public static RollupDateLiteral get(String key) {
    List<String> possibleDynamicValues = key.split(':');
    RollupDateLiteral literal = getLazyLoadedLiteral(possibleDynamicValues[0], possibleDynamicValues.size() > 1 ? possibleDynamicValues[1] : '');
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

  public override String toString() {
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
   * Starts 00:00:00 on the first day of the week before the most recent first day of the week and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class LastWeekLiteral extends RollupDateLiteral {
    public LastWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(-7), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week on or before the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class ThisWeekLiteral extends RollupDateLiteral {
    public ThisWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek(), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the most recent first day of the week after the current day and continues for seven full days.
   * Your locale determines the first day of the week.
   */
  private class NextWeekLiteral extends RollupDateLiteral {
    public NextWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(7), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month before the current day and continues for all the days of that month.
   */
  private class LastMonthLiteral extends RollupDateLiteral {
    public LastMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth().addMonths(-1), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month that the current day is in and continues for all the days of that month.
   */
  private class ThisMonthLiteral extends RollupDateLiteral {
    public ThisMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth(), START_TIME);
    }
  }

  /**
   * Starts 00:00:00 on the first day of the month after the month that the current day is in and continues for all the days of that month.
   */
  private class NextMonthLiteral extends RollupDateLiteral {
    public NextMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth().addMonths(1), START_TIME);
    }
  }

  /**
   * Starts with the current day and continues for the past 90 days.
   * This includes the current day, not just previous days. So it includes 91 days in total.
   */
  private class Last90DaysLiteral extends RollupDateLiteral {
    public Last90DaysLiteral() {
      this.ref = START_OF_TODAY.addDays(-91);
    }
  }

  /**
   * Starts 00:00:00 of the next day and continues for the next 90 days.
   */
  private class Next90DaysLiteral extends RollupDateLiteral {
    public Next90DaysLiteral() {
      this.ref = START_OF_TODAY.addDays(91);
    }
  }

  /**
   * NEXT/LAST N Section. Since these are range-based comparisons, a new abstract class is introduced
   */

  private abstract class RangedLiteral extends RollupDateLiteral {
    protected Datetime bound;

    protected abstract override Boolean isEqualTo(Datetime val);
    protected abstract override Boolean isGreaterThan(Datetime val);
    protected abstract override Boolean isLessThan(Datetime val);
  }

  private abstract class LastRangedLiteral extends RangedLiteral {
    protected override Boolean isEqualTo(Datetime val) {
      return this.bound <= val && this.ref >= val;
    }
    protected override Boolean isGreaterThan(Datetime val) {
      return this.bound < val && this.ref > val;
    }
    protected override Boolean isLessThan(Datetime val) {
      return this.bound > val && this.ref < val;
    }
  }

  private abstract class NextRangedLiteral extends RangedLiteral {
    protected override Boolean isEqualTo(Datetime val) {
      return val >= this.ref && this.bound <= val;
    }
    protected override Boolean isGreaterThan(Datetime val) {
      return val > this.ref && val > this.bound;
    }
    protected override Boolean isLessThan(Datetime val) {
      return this.bound > val && this.ref > val;
    }
  }

  /**
   * For the number n provided, starts with the current day and continues for the past n days.
   * This includes the current day, not just previous days. For example, LAST_N_DAYS:1 includes yesterday and today.
   */
  private class LastNDaysLiteral extends LastRangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = START_OF_TODAY.addDays(1); // includes all of today
      this.bound = START_OF_TODAY.addDays(-dateRange);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the next day and continues for the next n days.
   * This does not include the current day. For example, NEXT_N_DAYS:1 is equivalent to TOMORROW.
   */
  private class NextNDaysLiteral extends NextRangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = START_OF_TODAY.addDays(1); // excludes today
      this.bound = START_OF_TODAY.addDays(dateRange);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the last day of the previous week and continues for the past n weeks.
   */
  private class LastNWeeksLiteral extends LastRangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(-1), START_TIME);
      this.bound = this.ref.addDays(-1 * 7 * dateRange);
    }
  }

  /**
   * For the number n provided, starts 00:00:00 of the first day of the next week and continues for the next n weeks.
   */
  private class NextNWeeksLiteral extends NextRangedLiteral {
    protected override void setDynamicValue(String num) {
      Integer dateRange = Integer.valueOf(num);
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(7), START_TIME);
      this.bound = this.ref.addDays(7 * dateRange);
    }
  }

  private class ThisYearLiteral extends RollupDateLiteral {
    public ThisYearLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().year(), 1, 1, START_TIME.hour(), START_TIME.minute(), START_TIME.second());
    }
  }

  private class LastYearLiteral extends RollupDateLiteral {
    public LastYearLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().year() - 1, 1, 1, START_TIME.hour(), START_TIME.minute(), START_TIME.second());
    }
  }

  private class NextYearLiteral extends RollupDateLiteral {
    public NextYearLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().year() + 1, 1, 1, START_TIME.hour(), START_TIME.minute(), START_TIME.second());
    }
  }
}
