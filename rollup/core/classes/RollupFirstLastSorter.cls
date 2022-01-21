public without sharing class RollupFirstLastSorter extends RollupComparer {
  private final Boolean isFirst;
  private final List<RollupOrderBy__mdt> orderBys;

  public RollupFirstLastSorter(Rollup.Op op, List<RollupOrderBy__mdt> orderBys) {
    this.isFirst = op.name().contains(Rollup.Op.FIRST.name());
    this.orderBys = orderBys;
  }

  public override Integer compare(Object o1, Object o2) {
    Integer returnVal = 0;
    SObject objOne = (SObject) o1;
    SObject objTwo = (SObject) o2;

    Object potentialFirstVal = objOne.get('TODO fixme');
    Object potentialSecondVal = objTwo.get('TODO fixme');

    // nulls last; return early if everything is null OR if the values match
    if (potentialFirstVal == null && potentialSecondVal != null) {
      returnVal = this.moveTowardFrontOfList;
    } else if (potentialSecondVal == null && potentialFirstVal != null) {
      returnVal = this.moveTowardBackOfList;
    } else if ((potentialFirstVal == null && potentialSecondVal == null) || (potentialFirstVal == potentialSecondVal)) {
      return returnVal;
    }

    // otherwise, cast to one of the three most basic types in order to call the equality comparators
    // all times / dates/ and datetimes will respond true to instanceof Datetime
    // all numbers will respond true to instanceof Decimal
    if (potentialFirstVal instanceof Datetime) {
      Datetime firstVal = (Datetime) potentialFirstVal;
      Datetime secondVal = (Datetime) potentialSecondVal;

      returnVal = firstVal > secondVal ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    } else if (potentialFirstVal instanceof String) {
      String firstVal = (String) potentialFirstVal;
      String secondVal = (String) potentialSecondVal;

      returnVal = firstVal > secondVal ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    } else if (potentialFirstVal instanceof Decimal) {
      Decimal firstVal = (Decimal) potentialFirstVal;
      Decimal secondVal = (Decimal) potentialSecondVal;

      returnVal = firstVal > secondVal ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    }

    return this.isFirst ? returnVal : returnVal * -1;
  }
}
