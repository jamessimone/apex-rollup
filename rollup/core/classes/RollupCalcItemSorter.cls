public without sharing class RollupCalcItemSorter extends RollupComparer {
  private final List<RollupOrderBy__mdt> orderByOptions;
  private final Map<Schema.DescribeFieldResult, RollupFieldInitializer.PicklistController> fieldToPicklistController;

  public RollupCalcItemSorter(List<String> sortByFields) {
    this(transformFieldNames(sortByFields));
  }

  public RollupCalcItemSorter(List<RollupOrderBy__mdt> orderBys) {
    this.fieldToPicklistController = new Map<Schema.DescribeFieldResult, RollupFieldInitializer.PicklistController>();
    this.orderByOptions = this.initializeOrderByOptions(orderBys);
  }

  public override Integer compare(Object o1, Object o2) {
    Integer comparisonVal = 0;
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
      comparisonVal = this.getSortRanking(objOne, objTwo, orderByOption, picklistController);
      if (comparisonVal != 0) {
        return comparisonVal;
      }
    }

    return comparisonVal;
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
    Integer sortRanking = 0;
    if (String.isBlank(orderByOption.FieldName__c)) {
      return sortRanking;
    }
    Object potentialFirstVal = this.getFieldValue(objOne, orderByOption.FieldName__c);
    Object potentialSecondVal = this.getFieldValue(objTwo, orderByOption.FieldName__c);
    // (from the developer docs): "Default [sort] order is ascending. By default, null values are sorted first."
    if (potentialFirstVal == null && potentialSecondVal != null) {
      return orderByOption.NullSortOrder__c == RollupMetaPicklists.NullSortOrder.NullsFirst ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
    } else if (potentialSecondVal == null && potentialFirstVal != null) {
      return orderByOption.NullSortOrder__c == RollupMetaPicklists.NullSortOrder.NullsFirst ? this.moveTowardBackOfList : this.moveTowardFrontOfList;
    } else if (potentialFirstVal == potentialSecondVal) {
      return sortRanking;
    }

    // otherwise, cast to one of the three most basic types in order to call the equality comparators
    // all times / dates/ and datetimes will respond true to instanceof Datetime
    // all numbers will respond true to instanceof Decimal
    if (potentialFirstVal instanceof Datetime) {
      Datetime firstVal = (Datetime) potentialFirstVal;
      Datetime secondVal = (Datetime) potentialSecondVal;

      sortRanking = this.getSortOrder(firstVal > secondVal, orderByOption);
    } else if (potentialFirstVal instanceof String) {
      String firstVal = (String) potentialFirstVal;
      String secondVal = (String) potentialSecondVal;

      if (picklistController.isPicklist() || picklistController.isMultiSelectPicklist()) {
        sortRanking = picklistController.isTrueFor(firstVal, secondVal, Rollup.Op.MIN) ? this.moveTowardFrontOfList : this.moveTowardBackOfList;
      } else {
        sortRanking = this.getSortOrder(firstVal > secondVal, orderByOption);
      }
    } else if (potentialFirstVal instanceof Decimal) {
      Decimal firstVal = (Decimal) potentialFirstVal;
      Decimal secondVal = (Decimal) potentialSecondVal;

      sortRanking = this.getSortOrder(firstVal > secondVal, orderByOption);
    }

    return sortRanking;
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

  private static List<RollupOrderBy__mdt> transformFieldNames(List<String> sortByFields) {
    List<RollupOrderBy__mdt> rollupOrderBys = new List<RollupOrderBy__mdt>();
    for (Integer index = 0; index < sortByFields.size(); index++) {
      String sortByField = sortByFields[index].trim();
      rollupOrderBys.add(new RollupOrderBy__mdt(FieldName__c = sortByField, Ranking__c = index));
    }
    return rollupOrderBys;
  }
}
