public without sharing virtual class RollupState {
  private final Map<String, Map<Type, RollupState>> keyToState {
    get {
      this.keyToState = this.keyToState ?? new Map<String, Map<Type, RollupState>>();
      return this.keyToState;
    }
    set;
  }

  public RollupState getState(String firstKey, Type secondKey) {
    return this.keyToState.get(firstKey)?.get(secondKey);
  }

  public virtual Type getType() {
    return RollupState.class;
  }

  public void setState(String key, RollupState state) {
    Map<Type, RollupState> firstKeyStates = this.keyToState.get(key);
    if (firstKeyStates == null) {
      firstKeyStates = new Map<Type, RollupState>();
      this.keyToState.put(key, firstKeyStates);
    }
    firstKeyStates.put(state.getType(), state);
  }

  public class AverageInfo extends RollupState {
    public Decimal denominator = 0;
    public Decimal numerator = 0;
    public Set<Object> distinctNumerators {
      get {
        this.distinctNumerators = this.distinctNumerators ?? new Set<Object>();
        return this.distinctNumerators;
      }
      private set;
    }

    public void increment(Decimal value) {
      this.numerator += value;
      this.denominator++;
      this.distinctNumerators.add(value);
    }

    public override Type getType() {
      return AverageInfo.class;
    }
  }

  public class MostInfo extends RollupState {
    public Integer largestPointCounter = -1;

    public void setLargestPointCounter(Integer newWinner) {
      this.largestPointCounter = newWinner;
    }

    public override Type getType() {
      return MostInfo.class;
    }
  }

  public class SObjectInfo extends RollupState {
    public SObject item;

    public void setItem(SObject item) {
      this.item = item;
    }

    public override Type getType() {
      return SObjectInfo.class;
    }
  }
}
