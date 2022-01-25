public without sharing class RollupFirstLastSorter {
  private final Sorter sorter;

  public RollupFirstLastSorter(Rollup.Op op, List<RollupOrderBy__mdt> orderBys) {
    this.sorter = new Sorter(op, orderBys);
  }

  public void sort(List<SObject> itemsToSort) {
    // there need to be ordering rules and at least 2 items to sort
    if (itemsToSort.size() <= 1) {
      return;
    }

    this.sorter.sort(itemsToSort);

    // TODO, null sort order, sort order
  }

  private class Sorter extends RollupComparer {
    private final Boolean isFirst;
    private final List<RollupOrderBy__mdt> orderByOptions;

    public Sorter(Rollup.Op op, List<RollupOrderBy__mdt> orderByOptions) {
      this.isFirst = op.name().contains(Rollup.Op.FIRST.name());
      this.orderByOptions = this.initializeOrderByOptions(orderByOptions);
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

        returnVal = firstVal > secondVal ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
      } else if (potentialFirstVal instanceof String) {
        String firstVal = (String) potentialFirstVal;
        String secondVal = (String) potentialSecondVal;

        returnVal = firstVal > secondVal ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
      } else if (potentialFirstVal instanceof Decimal) {
        Decimal firstVal = (Decimal) potentialFirstVal;
        Decimal secondVal = (Decimal) potentialSecondVal;

        returnVal = firstVal > secondVal ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
      }

      return this.isFirst ? returnVal : returnVal * -1;
    }
  }
}
