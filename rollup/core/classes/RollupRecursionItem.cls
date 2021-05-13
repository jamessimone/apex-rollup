public without sharing class RollupRecursionItem {
  public final String lookupKey;
  public final Object rollupValue;
  public final Id Id;

  private final Hasher hasher;

  public RollupRecursionItem(SObject item, Rollup__mdt metadata) {
    this.lookupKey = (String) item?.get(metadata.LookupFieldOnCalcItem__c);
    this.rollupValue = item?.get(metadata.RollupFieldOnCalcItem__c);
    this.Id = item?.Id;
    this.hasher = new Hasher()
      .add(this.lookupKey)
      .add(this.rollupValue)
      .add(this.Id);
  }

  // need to define both "equals" and "hashCode" so that a Set<RollupRecursionItem> can use "contains"
  // properly, as both Maps and Sets use these methods to define equality between keyed items
  public Boolean equals(Object thatItem) {
    if (thatItem instanceof RollupRecursionItem) {
      RollupRecursionItem that = (RollupRecursionItem) thatItem;
      return this.lookupKey == that.lookupKey && this.rollupValue == that.rollupValue && this.Id == that.Id;
    }

    return false;
  }

  public Integer hashCode() {
    return this.hasher.get();
  }

  /*
   * The below is taken, in part, from the excellent HashCodeUtils written by George Doenlen
   * https://github.com/gdoenlen/apexstruct/blob/master/src/classes/HashCodeUtil.cls
   * anything that works about it is solely due to him; anything that doesn't is due to me.
   * Many thanks to him for code reviewing this section and helping to improve it; apexstruct was the
   * first repository associated with Salesforce that I ever visited on Github, so it seems nice
   * that we've come full circle since that moment!
   */
  private static final Integer NULL_HASH = 0;
  private static final Integer PRIME = 31;

  private class Hasher {
    private Integer hash = 7; // chosen at random to start seeding the hash

    public Hasher add(Object o) {
      this.addHash(o == null ? NULL_HASH : o.hashCode());
      return this;
    }

    private void addHash(Integer i) {
      this.hash = (this.hash * PRIME) + i;
    }

    public Integer get() {
      return this.hash;
    }
  }
}