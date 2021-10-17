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

  protected final Datetime ref;

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
    'LAST_N_DAYS' => null,
    'NEXT_N_DAYS' => null,
    'LAST_N_WEEKS' => null,
    'NEXT_N_WEEKS' => null,
    'LAST_N_MONTHS' => null,
    'THIS_QUARTER' => null,
    'LAST_QUARTER' => null,
    'NEXT_QUARTER' => null,
    'NEXT_N_QUARTERS' => null,
    'LAST_N_QUARTERS' => null,
    'THIS_YEAR' => null,
    'LAST_YEAR' => null,
    'NEXT_YEAR' => null,
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
    RollupDateLiteral literal = getLazyLoadedLiteral(possibleDynamicValues[0]);
    if (possibleDynamicValues.size() > 1) {
      literal.setDynamicValue(possibleDynamicValues[1]);
    }
    return literal;
  }

  private static RollupDateLiteral getLazyLoadedLiteral(String dictionaryKey) {
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

  protected Boolean isEqualTo(Datetime val) {
    return this.ref == val;
  }
  protected Boolean isLessThan(Datetime val) {
    return this.ref < val;
  }
  protected Boolean isGreaterThan(Datetime val) {
    return this.ref > val;
  }

  protected virtual void setDynamicValue(String afterColon) {
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

  private class LastWeekLiteral extends RollupDateLiteral {
    // Starts 00:00:00 on the first day of the week before the most recent first day of the week and continues for seven full days.
    // Your locale determines the first day of the week.
    public LastWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(-7), START_TIME);
    }
  }

  private class ThisWeekLiteral extends RollupDateLiteral {
    // Starts 00:00:00 on the most recent first day of the week on or before the current day and continues for seven full days.
    // Your locale determines the first day of the week.
    public ThisWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek(), START_TIME);
    }
  }

  private class NextWeekLiteral extends RollupDateLiteral {
    // Starts 00:00:00 on the most recent first day of the week after the current day and continues for seven full days.
    // Your locale determines the first day of the week.
    public NextWeekLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfWeek().addDays(7), START_TIME);
    }
  }

  private class LastMonthLiteral extends RollupDateLiteral {
    // Starts 00:00:00 on the first day of the month before the current day and continues for all the days of that month.
    public LastMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth().addMonths(-1), START_TIME);
    }
  }

  private class ThisMonthLiteral extends RollupDateLiteral {
    // 	Starts 00:00:00 on the first day of the month that the current day is in and continues for all the days of that month.
    public ThisMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth(), START_TIME);
    }
  }

  private class NextMonthLiteral extends RollupDateLiteral {
    // Starts 00:00:00 on the first day of the month after the month that the current day is in and continues for all the days of that month.
    public NextMonthLiteral() {
      this.ref = Datetime.newInstanceGmt(System.today().toStartOfMonth().addMonths(1), START_TIME);
    }
  }

  private class Last90DaysLiteral extends RollupDateLiteral {
    // Starts with the current day and continues for the past 90 days.
    // This includes the current day, not just previous days. So it includes 91 days in total.
    public Last90DaysLiteral() {
      this.ref = START_OF_TODAY.addDays(-91);
    }
  }

  private class Next90DaysLiteral extends RollupDateLiteral {
    // Starts 00:00:00 of the next day and continues for the next 90 days.
    public Next90DaysLiteral () {
      this.ref = START_OF_TODAY.addDays(91);
    }
  }
}
