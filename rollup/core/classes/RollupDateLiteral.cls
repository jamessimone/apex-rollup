public abstract class RollupDateLiteral {
  private static final Map<String, Type> KEY_TO_DATE_LITERAL = new Map<String, Type>{
    'YESTERDAY' => YesterdayLiteral.class,
    'TODAY' => null,
    'TOMORROW' => null,
    'LAST_WEEK' => null,
    'THIS_WEEK' => null,
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

  private static final String RELATIVE_LITERAL_REGEX = '(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|YEARS|QUARTERS|FISCAL_​QUARTERS|FISCAL_​YEARS):?\\d*';

  public static Boolean isDateLiteral(String key) {
    return KEY_TO_DATE_LITERAL.containsKey(key) || Pattern.matches(RELATIVE_LITERAL_REGEX, key);
  }

  public static RollupDateLiteral get(String key) {
    return (RollupDateLiteral) KEY_TO_DATE_LITERAL.get(key.substringBefore(':')).newInstance();
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

  protected abstract Boolean isEqualTo(Datetime val);
  protected abstract Boolean isGreaterThan(Datetime val);
  protected abstract Boolean isLessThan(Datetime val);

  private class YesterdayLiteral extends RollupDateLiteral {
    private final Datetime that = Datetime.newInstance(System.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
    protected override Boolean isEqualTo(Datetime val) {
      return val == that;
    }
    protected override Boolean isLessThan(Datetime val) {
      return val < that;
    }
    protected override Boolean isGreaterThan(Datetime val) {
      return val > that;
    }
  }
}
