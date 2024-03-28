public without sharing class RollupRecursionItem {
  private final Id Id;
  private final Integer stackCount;
  private final String lookupKey;
  private final Object rollupValue;
  private final String uniqueOperation;
  private final List<Object> additionalValues = new List<Object>();
  private final Hasher hasher;

  public RollupRecursionItem(SObject item, Rollup__mdt metadata, Integer stackCount) {
    this.lookupKey = (String) item?.get(metadata.LookupFieldOnCalcItem__c);
    this.rollupValue = item?.get(metadata.RollupFieldOnCalcItem__c);
    this.Id = item?.Id;
    this.stackCount = stackCount;
    this.uniqueOperation = metadata.RollupOperation__c + metadata.CalcItemWhereClause__c;
    this.hasher = new Hasher().add(this.lookupKey).add(this.rollupValue).add(this.Id).add(this.uniqueOperation);
    Map<String, Object> fieldsToValues = item?.getPopulatedFieldsAsMap();
    if (fieldsToValues != null && String.isNotBlank(metadata.CalcItemWhereClause__c)) {
      List<String> whereFields = RollupEvaluator.getWhereEval(metadata.CalcItemWhereClause__c, item?.getSObjectType()).getQueryFields();
      for (String whereField : whereFields) {
        if (fieldsToValues.containsKey(whereField)) {
          Object whereVal = fieldsToValues.get(whereField);
          this.additionalValues.add(whereVal);
          this.hasher.add(whereVal);
        }
      }
    }
  }

  // need to define both "equals" and "hashCode" so that a Set<RollupRecursionItem> can use "contains"
  // properly, as both Maps and Sets use these methods to define equality between keyed items
  public Boolean equals(Object thatItem) {
    if (thatItem instanceof RollupRecursionItem) {
      RollupRecursionItem that = (RollupRecursionItem) thatItem;
      return this.lookupKey == that.lookupKey &&
        this.rollupValue == that.rollupValue &&
        this.Id == that.Id &&
        this.additionalValues == that.additionalValues &&
        this.uniqueOperation == that.uniqueOperation &&
        // only match if everything else is true AND the stackCount has increased
        this.stackCount != that.stackCount;
    }

    return false;
  }

  public override Integer hashCode() {
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
  @SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
  private static final Integer NULL_HASH = 0;
  @SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
  private static final Integer PRIME = 31;

  private class Hasher {
    private Integer hash = 7; // chosen at random to start seeding the hash

    public Hasher add(Object o) {
      this.addHash(o?.hashCode() ?? NULL_HASH);
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
