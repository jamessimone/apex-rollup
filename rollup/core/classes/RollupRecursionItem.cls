public without sharing class RollupRecursionItem {

  public final String lookupKey;
  public final Object rollupValue;
  public final Id Id;

  public RollupRecursionItem(SObject item, Rollup__mdt metadata) {
    this.lookupKey = (String) item.get(metadata.LookupFieldOnCalcItem__c);
    this.rollupValue = item.get(metadata.RollupFieldOnCalcItem__c);
    this.Id = item.Id;
  }

  public Boolean equals(Object thatItem) {
    if (thatItem instanceof RollupRecursionItem) {
      RollupRecursionItem that = (RollupRecursionItem) thatItem;
      return this.lookupKey == that.lookupKey && this.rollupValue == that.rollupValue && this.Id == that.Id;
    }

    return false;
  }

  /*
  * The below is taken, in part, from the excellent HashCodeUtils written by George Doenlen
  * https://github.com/gdoenlen/apexstruct/blob/master/src/classes/HashCodeUtil.cls
  * anything that works about it is solely due to him; anything that doesn't is due to me
  */
  private static final Integer NULL_HASH = 0;
  private static final Integer PRIME = 31;
  private Integer hash = 7;

  public Integer hashCode() {
    Integer hashToReturn;
    Integer idHash = this.getHash(this.Id);
    Integer lookupHash = this.getHash(this.lookupKey);
    Integer valHash = this.getHash(this.rollupValue);
    try {
      hashToReturn = idHash + lookupHash + valHash;
    } catch (Exception ex) {
      // in the event the integer overflows
      hashToReturn = idHash + valHash - lookupHash;
    }
    return hashToReturn;
  }

  private Integer getHash(Object potentialVal) {
    this.hash = potentialVal == null ? this.getHash(NULL_HASH) : potentialVal.hashCode() + this.calculateSeed(this.hash);
    return hash;
  }

  private Integer calculateSeed(Integer hashSeed) {
    return hashSeed * PRIME;
  }
}
