public without sharing class RollupFirstLastSorter extends RollupComparer {
  private final Boolean isFirst;
  private final List<RollupOrderBy__mdt> orderByOptions;

  public RollupFirstLastSorter(Rollup.Op op, List<RollupOrderBy__mdt> orderBys) {
    this.isFirst = op.name().contains(Rollup.Op.FIRST.name());
    this.orderByOptions = this.initializeOrderByOptions(orderBys);
  }

  public override Integer compare(Object o1, Object o2) {
    Integer returnVal = 0;
    SObject objOne = (SObject) o1;
    SObject objTwo = (SObject) o2;

    for (RollupOrderBy__mdt orderByOption : this.orderByOptions) {
      returnVal = this.getSortRanking(objOne, objTwo, orderByOption);
      if (returnVal != 0) {
        return returnVal;
      }
    }

    return returnVal;
  }

  private List<RollupOrderBy__mdt> initializeOrderByOptions(List<RollupOrderBy__mdt> orderByOptions) {
    for (RollupOrderBy__mdt orderByOption : orderByOptions) {
      if (orderByOption.NullSortOrder__c == null) {
        orderByOption.NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsFirst;
      }
      if (orderByOption.SortOrder__c == null) {
        orderByOption.SortOrder__c = RollupMetaPicklists.SortOrder.Ascending;
      }
    }
    return orderByOptions;
  }

  private Integer getSortRanking(SObject objOne, SObject objTwo, RollupOrderBy__mdt orderByOption) {
    Object potentialFirstVal = objOne.get(orderByOption.FieldName__c);
    Object potentialSecondVal = objTwo.get(orderByOption.FieldName__c);
    Integer returnVal = 0;
    // (from the developer docs): "Default [sort] order is ascending. By default, null values are sorted first."
    if (potentialFirstVal == null && potentialSecondVal != null) {
      return orderByOption.NullSortOrder__c == RollupMetaPicklists.NullSortOrder.NullsFirst ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    } else if (potentialSecondVal == null && potentialFirstVal != null) {
      return orderByOption.NullSortOrder__c == RollupMetaPicklists.NullSortOrder.NullsFirst ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
    } else if (potentialFirstVal == potentialSecondVal) {
      return returnVal;
    }

    // otherwise, cast to one of the three most basic types in order to call the equality comparators
    // all times / dates/ and datetimes will respond true to instanceof Datetime
    // all numbers will respond true to instanceof Decimal
    if (potentialFirstVal instanceof Datetime) {
      Datetime firstVal = (Datetime) potentialFirstVal;
      Datetime secondVal = (Datetime) potentialSecondVal;

      returnVal = this.getSortOrder(firstVal > secondVal, orderByOption);
    } else if (potentialFirstVal instanceof String) {
      // TODO picklist sorting: "sorting is defined by the picklist sort determined during setup"
      String firstVal = (String) potentialFirstVal;
      String secondVal = (String) potentialSecondVal;

      returnVal = this.getSortOrder(firstVal > secondVal, orderByOption);
    } else if (potentialFirstVal instanceof Decimal) {
      Decimal firstVal = (Decimal) potentialFirstVal;
      Decimal secondVal = (Decimal) potentialSecondVal;

      returnVal = this.getSortOrder(firstVal > secondVal, orderByOption);
    }

    return this.isFirst ? returnVal : returnVal * -1;
  }

  private Integer getSortOrder(Boolean equalityCheck, RollupOrderBy__mdt orderByOption) {
    if (orderByOption.SortOrder__c == RollupMetaPicklists.SortOrder.Ascending) {
      return equalityCheck ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
    } else {
      return equalityCheck ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    }
  }
}
