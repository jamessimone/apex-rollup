@SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
public abstract class RollupDateLiteral {
  private static final String RELATIVE_LITERAL_REGEX = '(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_​QUARTERS|FISCAL_​YEARS):?\\d*';

  private static final Datetime NOWISH {
    get {
      if (NOWISH == null) {
        return Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));
      }
      return NOWISH;
    }
    set;
  }

  private static final Map<String, Object> KEY_TO_DATE_LITERAL = new Map<String, Object>{
    'YESTERDAY' => YesterdayLiteral.class,
    'TODAY' => TodayLiteral.class,
    'TOMORROW' => TomorrowLiteral.class,
    'LAST_WEEK' => LastWeekLiteral.class,
    'THIS_WEEK' => ThisWeekLiteral.class,
    'NEXT_WEEK' => null,
    'LAST_MONTH' => null,
    'THIS_MONTH' => null,
    'NEXT_MONTH' => null,
    'LAST_90_DAYS' => null,
    'NEXT_90_DAYS' => null,
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

  public Boolean matches(String val, String comparison) {
    Datetime castValue;
    try {
      castValue = Datetime.parse(val);
    } catch (TypeException ex) {
      Date dateVal = Date.parse(val);
      castValue = Datetime.newInstance(dateVal, Time.newInstance(0, 0, 0, 0));
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

  protected abstract Datetime getRef();

  protected Boolean isEqualTo(Datetime val) {
    return this.getRef() == val;
  }
  protected Boolean isLessThan(Datetime val) {
    return this.getRef() < val;
  }
  protected Boolean isGreaterThan(Datetime val) {
    return this.getRef() > val;
  }

  protected virtual void setDynamicValue(String afterColon) {
  }

  private class YesterdayLiteral extends RollupDateLiteral {
    private final Datetime ref = NOWISH.addDays(-1);
    protected override Datetime getRef() {
      return this.ref;
    }
  }

  private class TodayLiteral extends RollupDateLiteral {
    protected override Datetime getRef() {
      return NOWISH;
    }
  }

  private class TomorrowLiteral extends RollupDateLiteral {
    private final Datetime ref = NOWISH.addDays(1);
    protected override Datetime getRef() {
      return this.ref;
    }
  }

  private class LastWeekLiteral extends RollupDateLiteral {
    // TODO - need to align to ThisWeekLiteral, it's not a literal seven days back
    private final Datetime ref = NOWISH.addDays(-7);
    protected override Datetime getRef() {
      return this.ref;
    }
  }

  private class ThisWeekLiteral extends RollupDateLiteral {
    private final Datetime ref = Datetime.newInstance(NOWISH.date().toStartOfWeek(), Time.newInstance(0, 0, 0, 0));

    protected override Datetime getRef() {
      return this.ref;
    }
  }
}
