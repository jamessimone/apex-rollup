public without sharing class RollupFirstLastSorter extends RollupComparer {
  private final Boolean isFirst;
  private final List<RollupOrderBy__mdt> orderByOptions;
  private final Map<Schema.DescribeFieldResult, RollupFieldInitializer.PicklistController> fieldToPicklistController;

  public RollupFirstLastSorter(Rollup.Op op, List<RollupOrderBy__mdt> orderBys) {
    this.isFirst = op.name().contains(Rollup.Op.FIRST.name());
    this.fieldToPicklistController = new Map<Schema.DescribeFieldResult, RollupFieldInitializer.PicklistController>();
    this.orderByOptions = this.initializeOrderByOptions(orderBys);
  }

  public override Integer compare(Object o1, Object o2) {
    Integer returnVal = 0;
    SObject objOne = (SObject) o1;
    SObject objTwo = (SObject) o2;

    Map<String, SObjectField> fieldTokens = objOne.getSObjectType().getDescribe().fields.getMap();
    for (RollupOrderBy__mdt orderByOption : this.orderByOptions) {
      Schema.DescribeFieldResult fieldDescribe = fieldTokens.get(orderByOption.FieldName__c)?.getDescribe();
      RollupFieldInitializer.PicklistController picklistController;
      if (this.fieldToPicklistController.containsKey(fieldDescribe)) {
        picklistController = this.fieldToPicklistController.get(fieldDescribe);
      } else {
        picklistController = new RollupFieldInitializer.PicklistController(fieldDescribe);
        this.fieldToPicklistController.put(fieldDescribe, picklistController);
      }
      returnVal = this.getSortRanking(objOne, objTwo, orderByOption, picklistController);
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

  private Integer getSortRanking(
    SObject objOne,
    SObject objTwo,
    RollupOrderBy__mdt orderByOption,
    RollupFieldInitializer.PicklistController picklistController
  ) {
    Integer returnVal = 0;
    if (String.isBlank(orderByOption.FieldName__c)) {
      return returnVal;
    }
    Object potentialFirstVal = this.getFieldValue(objOne, orderByOption.FieldName__c);
    Object potentialSecondVal = this.getFieldValue(objTwo, orderByOption.FieldName__c);
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
      String firstVal = (String) potentialFirstVal;
      String secondVal = (String) potentialSecondVal;

      if (picklistController.isPicklist() || picklistController.isMultiSelectPicklist()) {
        Rollup.Op picklistRankingOp = this.isFirst ? Rollup.Op.MIN : Rollup.Op.MAX;
        returnVal = picklistController.isTrueFor(firstVal, secondVal, picklistRankingOp) ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
      } else {
        returnVal = this.getSortOrder(firstVal > secondVal, orderByOption);
      }
    } else if (potentialFirstVal instanceof Decimal) {
      Decimal firstVal = (Decimal) potentialFirstVal;
      Decimal secondVal = (Decimal) potentialSecondVal;

      returnVal = this.getSortOrder(firstVal > secondVal, orderByOption);
    }

    return this.isFirst ? returnVal : returnVal * -1;
  }

  /**
   * An extremely naive implementation of (basically) the same function: RollupEvaluator.getFieldValue()
   * This one will throw if the parent field hasn't been explicitly queried for; in RollupCalcItemReplacer we trust!
   */
  private Object getFieldValue(SObject record, String fieldName) {
    Object val;
    if (fieldName.contains('.')) {
      List<String> splitFieldNames = fieldName.split('\\.');
      String firstRelationshipField = splitFieldNames.remove(0);
      SObject parentRecord = record.getSObject(firstRelationshipField);
      if (splitFieldNames.size() == 1) {
        val = parentRecord.get(splitFieldNames[0]);
      } else {
        val = this.getFieldValue(parentRecord, String.join(splitFieldNames, '.'));
      }
    } else {
      val = record.get(fieldName);
    }
    return val;
  }

  private Integer getSortOrder(Boolean equalityCheck, RollupOrderBy__mdt orderByOption) {
    if (orderByOption.SortOrder__c == RollupMetaPicklists.SortOrder.Ascending) {
      return equalityCheck ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
    } else {
      return equalityCheck ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    }
  }
}
