public without sharing abstract class RollupCalculator {
  private Boolean isCDCUpdate = false;
  private Boolean isFirstTimeThrough = true;
  private Boolean isMultiCurrencyRollup;
  private Boolean isRecursiveRecalc = false;
  private Boolean isFullRecalc = false;
  private final RollupRepository repo;

  protected final Object defaultVal;
  protected final SObjectField opFieldOnCalcItem;
  protected final SObjectField opFieldOnLookupObject;
  protected final SObjectField lookupKeyField;
  protected final Rollup__mdt metadata;
  protected final Boolean isChangedFieldCalc;
  protected final SObjectType calcItemSObjectType;

  protected Rollup.Op op;
  protected String lookupKeyQuery;
  protected String lookupRecordKey;
  protected Rollup.Evaluator eval;
  protected Boolean shouldShortCircuit = false;
  protected Object returnVal;
  protected Boolean isLastItem = false;
  protected Boolean shouldTriggerFullRecalc;
  protected String parentIsoCode;

  @TestVisible
  private static Factory testFactory;
  private static Boolean isGroupByRollup = false;

  public static Factory Factory {
    get {
      if (Factory == null) {
        Factory = testFactory == null ? new RollupCalculator.Factory() : testFactory;
      }
      return Factory;
    }
    set;
  }

  public virtual class Factory {
    public virtual RollupCalculator getCalculator(
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      RollupCalculator calc;
      if (metadata.GroupByFields__c != null && isGroupByRollup == false) {
        return new GroupByCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      }
      switch on op {
        when ALL, NONE, SOME {
          calc = new ConditionalCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when AVERAGE, UPDATE_AVERAGE, DELETE_AVERAGE {
          calc = new AverageRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when COUNT_DISTINCT, UPDATE_COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
          calc = new CountDistinctRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when COUNT, UPDATE_COUNT, DELETE_COUNT {
          calc = new CountRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when FIRST, UPDATE_FIRST, DELETE_FIRST, LAST, UPDATE_LAST, DELETE_LAST {
          calc = new FirstLastRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when MOST {
          calc = new MostRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
        }
        when else {
          switch on (isGroupByRollup ? opFieldOnCalcItem : opFieldOnLookupObject).getDescribe().getType() {
            when Currency, Double, Integer, Long, Percent {
              calc = new DecimalRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
            }
            when Combobox, Email, EncryptedString, Id, MultiPicklist, Phone, Picklist, Reference, String, TextArea, URL {
              calc = new PicklistRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
            }
            when Date {
              calc = new DateRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
            }
            when Time {
              calc = new TimeRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
            }
            when Datetime {
              calc = new DatetimeRollupCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
            }
          }
        }
      }
      if (calc == null) {
        throw new IllegalArgumentException('Calculation not defined for parent field: ' + String.valueOf(opFieldOnLookupObject) + ' and op: ' + op);
      }

      return calc;
    }
  }

  protected RollupCalculator(
    Rollup.Op op,
    SObjectField opFieldOnCalcItem,
    SObjectField opFieldOnLookupObject,
    Rollup__mdt metadata,
    SObjectField lookupKeyField
  ) {
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.op = op;
    this.metadata = metadata;
    this.lookupKeyField = lookupKeyField;
    this.defaultVal = getDefaultRecalculationValue(metadata);
    if (this.isMultiCurrencyRollup == null) {
      this.isMultiCurrencyRollup =
        RollupCurrencyInfo.isMultiCurrency() &&
        (this.opFieldOnCalcItem?.getDescribe().getType() == DisplayType.CURRENCY ||
        this.opFieldOnLookupObject?.getDescribe().getType() == DisplayType.CURRENCY);
    }
    this.isChangedFieldCalc = String.isNotBlank(this.metadata.ChangedFieldsOnCalcItem__c);
    this.calcItemSObjectType = opFieldOnCalcItem?.getDescribe().getSObjectType();
    this.repo = new RollupRepository(RollupMetaPicklists.getAccessLevel(this.metadata));
    this.updateAdvancedCurrencyMappings();
  }

  public virtual void setDefaultValues(String lookupRecordKey, Object priorVal) {
    this.shouldShortCircuit = false;
    this.lookupRecordKey = lookupRecordKey;
    if (priorVal == null) {
      this.returnVal = this.defaultVal != null ? this.defaultVal : RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnLookupObject);
    } else {
      this.returnVal = priorVal;
    }
    this.lookupKeyQuery =
      this.lookupKeyField +
      ' = \'' +
      lookupRecordKey +
      '\'' +
      (String.isBlank(metadata.CalcItemWhereClause__c) ? '' : ' AND (' + metadata.CalcItemWhereClause__c + ')');
  }

  public virtual Object getReturnValue() {
    return this.returnVal;
  }

  public void setCDCUpdate(Boolean isCDCUpdate) {
    this.isCDCUpdate = isCDCUpdate;
  }

  public void setEvaluator(Rollup.Evaluator eval) {
    this.eval = eval;
  }

  public void setFullRecalc(Boolean isFullRecalc) {
    this.isFullRecalc = isFullRecalc;
  }

  public void setMultiCurrencyInfo(SObject parentRecord) {
    if (parentRecord.getPopulatedFieldsAsMap().containsKey(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME)) {
      this.parentIsoCode = (String) parentRecord.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME);
    }
  }

  public virtual void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    // if we're already in a full recalc, we've got all the items we need already
    this.shouldTriggerFullRecalc = this.isFullRecalc == false;
    List<Id> exclusionIds = new List<Id>();
    for (SObject calcItem : calcItems) {
      if (calcItem.Id != null) {
        exclusionIds.add(calcItem.Id);
      }
    }
    List<SObject> localCalcItems = this.winnowItems(calcItems, oldCalcItems);

    for (Integer index = 0; index < localCalcItems.size(); index++) {
      this.isLastItem = index == localCalcItems.size() - 1;
      SObject calcItem = localCalcItems[index];
      Boolean doesNotMatch = this.eval?.matches(calcItem) == false;
      if (doesNotMatch && oldCalcItems.containsKey(calcItem.Id)) {
        doesNotMatch = doesNotMatch && this.eval?.matches(oldCalcItems.get(calcItem.Id)) == false;
      }

      // it's only a full recalc situation if there are no items left after winnowing
      // otherwise, for even one item in the list, this should cause "shouldTriggerFullRecalc" to evaluate to false
      if (this.shouldTriggerFullRecalc) {
        this.shouldTriggerFullRecalc = doesNotMatch;
      }

      if (this.shouldShortCircuit) {
        this.handleShortCircuit(calcItem);
        continue;
      } else if (this.isCDCUpdate) {
        // here we don't exclude items because the calc items have already been updated
        exclusionIds = new List<Id>();
        this.shouldTriggerFullRecalc = true;
        break;
      } else {
        switch on this.op {
          when COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
            this.handleCountDistinct(calcItem);
          }
          when UPDATE_COUNT_DISTINCT {
            this.handleUpdateCountDistinct(calcItem);
          }
          when SUM, COUNT {
            this.handleSumOrCount(calcItem);
          }
          when UPDATE_SUM, UPDATE_COUNT {
            this.handleUpdateSumOrCount(calcItem, oldCalcItems);
          }
          when DELETE_SUM, DELETE_COUNT {
            this.handleDeleteSumOrCount(calcItem);
          }
          when MIN {
            this.handleMin(calcItem);
          }
          when MAX {
            this.handleMax(calcItem);
          }
          when UPDATE_MAX, UPDATE_MIN, DELETE_MAX, DELETE_MIN {
            this.handleUpdateMinOrMax(calcItem, oldCalcItems);
          }
          when CONCAT, CONCAT_DISTINCT {
            this.handleConcat(calcItem);
          }
          when UPDATE_CONCAT, UPDATE_CONCAT_DISTINCT {
            this.handleUpdateConcat(calcItem, oldCalcItems);
          }
          when DELETE_CONCAT, DELETE_CONCAT_DISTINCT {
            this.handleDeleteConcat(calcItem);
          }
        }
      }

      if (this.shouldShortCircuit && this.isFirstTimeThrough) {
        /**
         * an example of short circuiting - halfway through the list during a MIN operation,
         * Rollup encounters a calcItem whose previous value equals the current min, but the new value
         * is greater than the min. This triggers a full recalc, since it is at once both possible
         * for items outside the list of calcItems to contain the new min, as WELL as for an item
         * WITHIN the existing calcItems to be the new min. This means we have to go back and re-process
         * the records that were already iterated on to ensure that the current operation successfully accounts
         * for everything in-memory and in the database
         */
        this.isFirstTimeThrough = false;
        if (index != 0 && calcItems.size() > 1) {
          index = 0; // resets the for-loop
        }
      }
    }
    // if there were no matching items, it's time for a full recalc
    // AVERAGE and FIRST/LAST *also* handle this operation, but they override the entirety of the method we're in
    // ("performRollup"); this means String, Number, and Datetime variant rollup calculations all need to correctly handle
    // recalculating via "calculateNewAggregateValue"
    if (this.shouldTriggerFullRecalc) {
      this.returnVal = this.calculateNewAggregateValue(this.op, exclusionIds, this.calcItemSObjectType);
      // bail on calling setReturnValue below
      return;
    } else if (this.shouldTriggerFullRecalc == false && localCalcItems.isEmpty()) {
      this.returnVal = this.defaultVal;
      return;
    }
    this.setReturnValue();
  }

  // all of these are no-ops by default; child classes opt-in to the rollup types applicable
  public virtual void handleCountDistinct(SObject calcItem) {
  }
  public virtual void handleUpdateCountDistinct(SObject calcItem) {
  }
  public virtual void handleSumOrCount(SObject calcItem) {
  }
  public virtual void handleUpdateSumOrCount(SObject calcItem, Map<Id, SObject> oldCalcItems) {
  }
  public virtual void handleDeleteSumOrCount(SObject calcItem) {
  }
  public virtual void handleMin(SObject calcItem) {
  }
  public virtual void handleMax(SObject calcItem) {
  }
  public virtual void handleUpdateMinOrMax(SObject calcItem, Map<Id, SObject> oldCalcItems) {
  }
  public virtual void handleConcat(SObject calcItem) {
  }
  public virtual void handleUpdateConcat(SObject calcItem, Map<Id, SObject> oldCalcItems) {
  }
  public virtual void handleDeleteConcat(SObject calcItem) {
  }
  protected virtual void handleShortCircuit(SObject calcItem) {
  }
  protected virtual void setReturnValue() {
  }

  protected List<SObject> winnowItems(List<SObject> items, Map<Id, SObject> oldCalcItems) {
    List<SObject> temporaryItems = new List<SObject>();
    this.transformForMultiCurrencyOrgs(items);
    if (oldCalcItems.isEmpty() == false && this.isMultiCurrencyRollup) {
      List<SObject> tempOldCalcItems = oldCalcItems.values();
      this.transformForMultiCurrencyOrgs(tempOldCalcItems);
      for (SObject oldCalcItem : tempOldCalcItems) {
        oldCalcItems.put(oldCalcItem.Id, this.getTransformedCalcItem(oldCalcItem));
      }
    }
    for (SObject item : items) {
      Boolean currentItemMatches = this.eval?.matches(item) != false;
      if (currentItemMatches == false) {
        switch on this.op {
          // not all downstream updates for old item matching when new item doesn't have been defined
          // and this switch statement is how other operations opt-in
          when UPDATE_COUNT, UPDATE_CONCAT_DISTINCT, UPDATE_CONCAT, UPDATE_SUM {
            if (this.isChangedFieldCalc == false && oldCalcItems.containsKey(item.Id) && this.eval?.matches(oldCalcItems.get(item.Id)) != false) {
              currentItemMatches = true;
            }
          }
        }
      }
      if (currentItemMatches) {
        temporaryItems.add(this.getTransformedCalcItem(item));
        if (this.op == Rollup.Op.SOME) {
          break;
        }
      }
    }
    List<RollupOrderBy__mdt> orderBys = this.metadata?.LimitAmount__c != null && this.metadata.RollupOrderBys__r.isEmpty()
      ? new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Id', Ranking__c = 0) }
      : this.metadata.RollupOrderBys__r;
    if (orderBys.isEmpty() == false) {
      new RollupCalcItemSorter(orderBys).sort(temporaryItems);
    }
    if (this.metadata?.LimitAmount__c != null) {
      // we can only safely remove the items after sorting
      while (temporaryItems.size() > this.metadata.LimitAmount__c && temporaryItems.isEmpty() == false) {
        temporaryItems.remove(items.size() - 1);
      }
      // Limit-based rollups always reset the field's value, and always act as a fresh start
      if (this.metadata.RollupOperation__c.contains('DELETE_') || this.metadata.RollupOperation__c.contains('UPDATE_')) {
        this.op = Rollup.Op.valueOf(this.metadata.RollupOperation__c.substringAfter('_'));
      }
    }

    return temporaryItems;
  }

  protected virtual Object calculateNewAggregateValue(Rollup.Op op, List<Object> objIds, SObjectType sObjectType) {
    String operationName = Rollup.getBaseOperationName(op.name());
    String alias = operationName.toLowerCase() + 'Field';
    List<SObject> aggregate = this.tryQuery(sObjectType, new Set<String>{ operationName + '(' + this.opFieldOnCalcItem + ')' + alias }, objIds);
    return aggregate.isEmpty() == false ? aggregate[0].get(alias) : this.defaultVal;
  }

  protected Boolean isReparented(SObject calcItem, SObject oldCalcItem) {
    return oldCalcItem != null && calcItem?.get(this.lookupKeyField) != oldCalcItem.get(this.lookupKeyField);
  }

  protected Object performBaseCalculation(Rollup.Op op, List<Object> objIds, SObjectType sObjectType) {
    this.returnVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnLookupObject);

    if (this.isRecursiveRecalc == false) {
      this.isRecursiveRecalc = true; // now we're cooking with gas
      Set<String> queryFields = this.getQueryFields();

      List<SObject> allOtherItems = this.tryQuery(sObjectType, queryFields, objIds);
      if (allOtherItems.isEmpty()) {
        // break out of recursion if there's nothing to calculate
        this.returnVal = this.defaultVal;
      } else {
        Rollup.Op baseOp = Rollup.Op.valueOf(Rollup.getBaseOperationName(op.name()));
        RollupCalculator calc = Factory.getCalculator(baseOp, this.opFieldOnCalcItem, this.opFieldOnLookupObject, this.metadata, this.lookupKeyField);
        calc.setDefaultValues(this.lookupRecordKey, this.returnVal);
        calc.parentIsoCode = this.parentIsoCode;
        calc.performRollup(allOtherItems, new Map<Id, SObject>());
        this.returnVal = calc.getReturnValue();
      }
    }
    return this.returnVal;
  }

  protected Set<String> getQueryFields() {
    Set<String> queryFields = new Set<String>{ String.valueOf(this.opFieldOnCalcItem), this.metadata.LookupFieldOnCalcItem__c };
    for (RollupOrderBy__mdt orderByInfo : this.metadata.RollupOrderBys__r) {
      queryFields.add(orderByInfo.FieldName__c);
    }
    if (String.isNotBlank(this.metadata.CalcItemWhereClause__c)) {
      queryFields.addAll(RollupEvaluator.getWhereEval(this.metadata.CalcItemWhereClause__c, this.calcItemSObjectType).getQueryFields());
    }
    return queryFields;
  }

  private List<SObject> tryQuery(SObjectType sObjectType, Set<String> queryFields, Object objIds) {
    List<SObject> results;
    try {
      results = this.repo.setQuery(RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(queryFields), 'Id', '!=', this.lookupKeyQuery))
        .setArg(objIds)
        .get();
    } catch (System.QueryException qex) {
      results = this.repo.setQuery(RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(queryFields), 'Id', '!=')).get();
    }
    return results;
  }

  private SObject getTransformedCalcItem(SObject calcItem) {
    return this.isMultiCurrencyRollup ? RollupCurrencyInfo.getCalcItem(calcItem) : calcItem;
  }

  private void transformForMultiCurrencyOrgs(List<SObject> calcItems) {
    if (this.isMultiCurrencyRollup) {
      RollupCurrencyInfo.transform(calcItems, this.opFieldOnCalcItem, this.parentIsoCode, this.metadata.RollupOrderBys__r);
    }
  }

  private void updateAdvancedCurrencyMappings() {
    if (this.metadata.CurrencyFieldMapping__c != null) {
      List<String> fieldMappings = this.metadata.CurrencyFieldMapping__c.split(',');
      for (Integer index = 0; index < fieldMappings.size(); index++) {
        fieldMappings[index] = fieldMappings[index].trim();
      }
    }
  }

  private without sharing class CountDistinctRollupCalculator extends RollupCalculator {
    private Set<Object> distinctValues = new Set<Object>();
    private Boolean isIdCount;
    public CountDistinctRollupCalculator(
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      super.setDefaultValues(lookupRecordKey, priorVal);
      this.distinctValues = new Set<Object>();
      this.isIdCount = this.opFieldOnCalcItem.getDescribe().getName() == 'Id';
      Object defaultVal = RollupFieldInitializer.Current.getDefaultValue(opFieldOnLookupObject);
      if (defaultVal != 0 && this.returnVal != defaultVal && this.isIdCount == false) {
        this.distinctValues.add(this.returnVal);
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.distinctValues.size() == 0 ? this.defaultVal : Decimal.valueOf(this.distinctValues.size());
    }

    protected override void handleShortCircuit(SObject calcItem) {
      Object currentVal = calcItem.get(this.opFieldOnCalcItem);
      if (currentVal != null && this.op != Rollup.Op.DELETE_COUNT_DISTINCT) {
        this.distinctValues.add(currentVal);
      }
    }

    public override void handleCountDistinct(SObject calcItem) {
      Object potentiallyNullValue = calcItem.get(this.opFieldOnCalcItem);
      if (this.op != Rollup.Op.DELETE_COUNT_DISTINCT && potentiallyNullValue != null) {
        this.distinctValues.add(potentiallyNullValue);
      } else if (this.op == Rollup.Op.DELETE_COUNT_DISTINCT) {
        this.distinctValues = new Set<Object>();
        this.calculateNewAggregateValue(this.op, new List<Id>{ calcItem.Id }, calcItem.getSObjectType());
      }
      this.shouldShortCircuit = true;
    }

    public override void handleUpdateCountDistinct(SObject calcItem) {
      this.shouldShortCircuit = true;
      this.handleShortCircuit(calcItem);
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, List<Object> objIds, SObjectType sObjectType) {
      if (this.shouldTriggerFullRecalc == true) {
        this.distinctValues = new Set<Object>();
      }
      Boolean isArchivable = sObjectType == Task.SObjectType || sObjectType == Event.SObjectType;
      Boolean isGroupable = isArchivable == false && this.opFieldOnCalcItem.getDescribe().isGroupable();
      List<String> queryFields = new List<String>{ String.valueOf(this.opFieldOnCalcItem) };
      if (isGroupable) {
        queryFields.add('COUNT(' + (this.isIdCount ? '' : 'Id') + ')');
      }

      this.repo.setQuery(
          RollupQueryBuilder.Current.getQuery(sObjectType, queryFields, 'Id', '!=', this.lookupKeyQuery + ('\nAND ' + this.opFieldOnCalcItem + '!= null')) +
          (isGroupable && this.isIdCount == false ? ('\nGROUP BY ' + this.opFieldOnCalcItem) : '')
        )
        .setArg(objIds);

      if (this.isIdCount) {
        Integer result = this.repo.getCount();
        for (Integer index = 0; index < result; index++) {
          this.distinctValues.add(index);
        }
      } else {
        List<SObject> results = this.repo.get();
        String calcItemOpField = this.opFieldOnCalcItem.getDescribe().getName();
        for (SObject res : results) {
          // have to use the String representation of the this.opFieldOnCalcItem to avoid:
          // System.SObjectException: SObject.FieldName does not belong to SObject type AggregateResult
          this.distinctValues.add(res.get(calcItemOpField));
        }
      }
      return this.distinctValues.isEmpty() && this.defaultVal != null ? this.defaultVal : this.distinctValues.size();
    }
  }

  private without sharing virtual class DecimalRollupCalculator extends RollupCalculator {
    private Decimal returnDecimal;
    public DecimalRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public virtual override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      super.setDefaultValues(lookupRecordKey, priorVal);
      if (this.returnVal instanceof Decimal) {
        this.returnDecimal = (Decimal) this.returnVal;
      }
    }

    protected virtual Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      if (potentiallyUnitializedDecimal instanceof Decimal) {
        return (Decimal) potentiallyUnitializedDecimal;
      } else {
        return Decimal.valueOf(potentiallyUnitializedDecimal == null ? 0 : 1);
      }
    }

    protected virtual Decimal getNumericValue(SObject calcItem) {
      return this.getDecimalOrDefault(calcItem.get(this.opFieldOnCalcItem));
    }

    protected virtual Decimal getNumericChangedValue(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      SObject oldCalcItem = oldCalcItems.get(calcItem.Id);

      Decimal newVal = this.getNumericValue(calcItem);
      Decimal oldVal = oldCalcItem != null ? this.getNumericValue(oldCalcItem) : 0;

      Boolean matchesCurrent = this.eval?.matches(calcItem) != false;
      Boolean matchesOld = oldCalcItem != null && this.eval?.matches(oldCalcItem) != false;

      if (this.isFullRecalc && matchesCurrent) {
        return newVal;
      } else if (this.isReparented(calcItem, oldCalcItem)) {
        return newVal;
      } else if (matchesCurrent && matchesOld == false && this.isChangedFieldCalc == false) {
        return newVal;
      } else if (matchesCurrent == false && matchesOld && this.isChangedFieldCalc == false) {
        return oldVal * Decimal.valueOf(-1).setScale(oldVal.scale());
      }

      // could be negative, could be positive ... could be 0!
      return newVal - oldVal;
    }

    public virtual override Object getReturnValue() {
      if (this.returnVal == RollupFieldInitializer.Current.maximumLongValue || this.returnVal == RollupFieldInitializer.Current.minimumLongValue) {
        this.returnVal = 0.00;
      }
      if (this.returnVal == 0) {
        this.returnVal = this.metadata.FullRecalculationDefaultNumberValue__c != null ? this.metadata.FullRecalculationDefaultNumberValue__c : null;
      }
      return this.returnVal;
    }

    protected override void handleShortCircuit(SObject calcItem) {
      switch on this.op {
        when UPDATE_MAX {
          // re-maxing by way of query has occurred, but is it **correct**?
          // if one of the other updated calcItems is numerically superior, assign the new max
          Decimal newVal = this.getNumericValue(calcItem);
          if (newVal > returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
        when UPDATE_MIN {
          // re-"min"-ing has occurred by way of query, but is an in-memory calcItem even less?
          Decimal newVal = this.getNumericValue(calcItem);
          if (newVal < returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
      }
    }

    public override void handleSumOrCount(SObject calcItem) {
      this.returnDecimal += this.getNumericValue(calcItem);
    }

    public override void handleUpdateSumOrCount(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      this.returnDecimal += this.getNumericChangedValue(calcItem, oldCalcItems);
    }

    public override void handleDeleteSumOrCount(SObject calcItem) {
      this.returnDecimal -= this.getNumericValue(calcItem);
    }

    public override void handleMax(SObject calcItem) {
      Decimal numericValue = this.getNumericValue(calcItem);
      if (numericValue > this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleMin(SObject calcItem) {
      Decimal numericValue = this.getNumericValue(calcItem);
      if (numericValue < this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleUpdateMinOrMax(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      Decimal newVal = this.getNumericValue(calcItem);
      Decimal thisPriorVal = this.getNumericValue((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem));
      if (
        thisPriorVal != 0 &&
        thisPriorVal == this.returnDecimal &&
        (this.op.name().contains(Rollup.Op.MAX.name()) && newVal <= thisPriorVal ||
        this.op.name().contains(Rollup.Op.MIN.name()) && newVal >= thisPriorVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, oldCalcItems.values(), calcItem.getSObjectType());
        this.returnDecimal = this.getDecimalOrDefault(potentialReturnValue);
        if (this.returnDecimal == 0 && this.op.name().contains('DELETE') == false) {
          this.returnDecimal = newVal;
        }
      } else if (this.op == Rollup.Op.UPDATE_MAX && newVal > this.returnDecimal) {
        this.returnDecimal = newVal;
      } else if (this.op == Rollup.Op.UPDATE_MIN && newVal < this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = newVal;
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.returnDecimal;
    }

    protected virtual override Object calculateNewAggregateValue(Rollup.Op op, List<Object> objIds, SObjectType sObjectType) {
      Object aggregate;
      try {
        aggregate = super.calculateNewAggregateValue(op, objIds, sObjectType);
      } catch (Exception ex) {
        aggregate = this.performBaseCalculation(op, objIds, sObjectType);
      }
      // for count-based rollups, fine to use 0 in the event of no matches
      // but otherwise, it's more accurate to be nulling out the parent fields if there isn't a max, for example
      if (aggregate == 0 && op.name().contains('COUNT') == false) {
        aggregate = null;
      } else if (aggregate == null) {
        aggregate = this.defaultVal;
      }
      return aggregate;
    }
  }

  private without sharing virtual class DatetimeRollupCalculator extends DecimalRollupCalculator {
    public DatetimeRollupCalculator(
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public virtual override Object getReturnValue() {
      Object superReturnVal = super.getReturnValue();
      if (superReturnVal instanceof Decimal) {
        superReturnVal = Datetime.newInstance(((Decimal) superReturnVal).longValue());
      }
      return superReturnVal;
    }

    public virtual override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      if (priorVal == null) {
        priorVal = RollupFieldInitializer.Current.defaultDateTime;
      }
      if (priorVal instanceof Datetime) {
        priorVal = ((Datetime) priorVal).getTime();
      }
      super.setDefaultValues(lookupRecordKey, priorVal);
    }

    protected virtual override Decimal getDecimalOrDefault(Object potentiallyUninitialized) {
      if (potentiallyUninitialized == null) {
        return RollupFieldInitializer.Current.defaultDateTime.getTime();
      }
      Datetime datetimeWithMs;
      if (potentiallyUninitialized instanceof String) {
        String potentialDatetimeValue = (String) potentiallyUninitialized;
        try {
          datetimeWithMs = Datetime.valueOf((String) potentialDatetimeValue);
        } catch (Exception ex) {
          datetimeWithMs = Datetime.newInstance(Date.valueOf(potentialDatetimeValue), Time.newInstance(0, 0, 0, 0));
        }
      } else if (potentiallyUninitialized instanceof Decimal) {
        datetimeWithMs = Datetime.newInstance(((Decimal) potentiallyUninitialized).longValue());
      } else {
        datetimeWithMs = (Datetime) potentiallyUninitialized;
      }

      return RollupFieldInitializer.Current.getApexCompliantDatetime(datetimeWithMs).getTime();
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, List<Object> excludedItems, SObjectType sObjectType) {
      Object aggregate = super.calculateNewAggregateValue(op, excludedItems, sObjectType);
      if (aggregate instanceof Datetime) {
        aggregate = ((Datetime) aggregate).getTime();
      }
      return aggregate;
    }
  }

  private without sharing class DateRollupCalculator extends DatetimeRollupCalculator {
    public DateRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      if (priorVal instanceof Date) {
        priorVal = Datetime.newInstanceGmt((Date) priorVal, Time.newInstance(0, 0, 0, 0)).getTime();
      }
      super.setDefaultValues(lookupRecordKey, priorVal);
    }

    public override Object getReturnValue() {
      Object superReturnVal = super.getReturnValue();
      return superReturnVal == 0 ? this.defaultVal : ((Datetime) superReturnVal)?.dateGmt();
    }
  }

  private without sharing class TimeRollupCalculator extends DatetimeRollupCalculator {
    public TimeRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      if (priorVal instanceof Time) {
        priorVal = Datetime.newInstanceGmt(RollupFieldInitializer.Current.defaultDateTime.dateGmt(), (Time) priorVal);
      }
      super.setDefaultValues(lookupRecordKey, priorVal);
    }

    public override Object getReturnValue() {
      Object returnValue = super.getReturnValue();
      if (returnValue instanceof Datetime) {
        returnValue = ((Datetime) returnValue).timeGmt();
      } else if (returnValue == 0) {
        returnValue = this.defaultVal;
      }
      return returnValue;
    }

    protected override Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      Datetime defaultDatetime;
      if (potentiallyUnitializedDecimal instanceof Time) {
        defaultDatetime = Datetime.newInstanceGmt(RollupFieldInitializer.Current.defaultDateTime.dateGmt(), (Time) potentiallyUnitializedDecimal);
      } else if (potentiallyUnitializedDecimal instanceof Decimal) {
        defaultDatetime = Datetime.newInstance(((Decimal) potentiallyUnitializedDecimal).longValue());
      }
      return (defaultDatetime != null ? defaultDatetime : RollupFieldInitializer.Current.defaultDateTime).getTime();
    }
  }

  private without sharing class CountRollupCalculator extends DecimalRollupCalculator {
    public CountRollupCalculator(
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override Object getReturnValue() {
      this.setReturnValue();
      // we shouldn't encourage negative counts. it's totally possible as a rollup is implemented and updates happen before
      // inserts or deletes, but it doesn't really make sense in the context of tracking
      Integer potentialReturnVal = ((Decimal) super.getReturnValue())?.intValue();
      return potentialReturnVal < 0 ? 0.00 : potentialReturnVal;
    }

    protected override Decimal getNumericValue(SObject calcItem) {
      return calcItem.get(this.opFieldOnCalcItem) != null ? 1.00 : 0.00;
    }

    protected override Decimal getNumericChangedValue(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      SObject oldCalcItem = oldCalcItems.get(calcItem.Id);

      // for a reparenting, the item counts towards the new record on an update
      if (this.isReparented(calcItem, oldCalcItem)) {
        return 1.00;
      }

      Boolean matchesCurrent = this.eval?.matches(calcItem) != false;
      Boolean matchesPrior = oldCalcItem != null && this.eval?.matches(oldCalcItem) != false;

      // for updates, we have to decrement the count if the value has been cleared out
      Decimal retVal = 0.00;
      Object current = calcItem.get(this.opFieldOnCalcItem);
      Object prior = oldCalcItem?.get(this.opFieldOnCalcItem);
      Object defaultVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnCalcItem);
      if (this.isFullRecalc && matchesCurrent) {
        retVal = 1.00;
      } else if (current == null && prior != null || matchesPrior && matchesCurrent == false) {
        retVal = -1.00;
      } else if (current != defaultVal && prior == defaultVal || matchesPrior == false && matchesCurrent || current != null && prior == null) {
        retVal = 1.00;
      } else if (current == false && prior == true) {
        retVal = -1.00;
      }
      return retVal;
    }
  }

  private static Boolean isConcatDistinct(Rollup.Op op) {
    return op.name().contains(Rollup.Op.CONCAT_DISTINCT.name());
  }

  private without sharing abstract class DelimiterCalculator extends RollupCalculator {
    protected final String concatDelimiter;

    public DelimiterCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      Schema.SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      if (opFieldOnLookupObject.getDescribe().getType() == Schema.DisplayType.MULTIPICKLIST) {
        this.concatDelimiter = ';';
      } else if (this.metadata.ConcatDelimiter__c != null) {
        this.concatDelimiter = this.metadata.ConcatDelimiter__c;
      } else {
        this.concatDelimiter = ', ';
      }
    }
  }

  private without sharing virtual class StringRollupCalculator extends DelimiterCalculator {
    private String stringVal;

    private final Boolean isConcatDistinct;
    private final Set<Id> concatDistinctIds = new Set<Id>();

    public StringRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      Schema.SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      this.isConcatDistinct = isConcatDistinct(this.op);
    }

    public virtual override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      super.setDefaultValues(lookupRecordKey, isConcatDistinct(this.op) ? '' : priorVal);
      if (this.returnVal instanceof String) {
        this.stringVal = (String) this.returnVal;
      }
    }

    protected override void setReturnValue() {
      if (this.op.name().contains(Rollup.Op.CONCAT.name())) {
        String trimmedDelimiter = this.concatDelimiter.trim();
        String possibleReturnValue = this.stringVal.normalizeSpace();
        while (possibleReturnValue.endsWith(trimmedDelimiter)) {
          possibleReturnValue = possibleReturnValue.substringBeforeLast(trimmedDelimiter).trim();
        }
        while (possibleReturnValue.startsWith(trimmedDelimiter)) {
          possibleReturnValue = possibleReturnValue.substringAfter(trimmedDelimiter).trim();
        }

        this.stringVal = possibleReturnValue.trim();
        this.sortAndConcat();
      }
      this.returnVal = this.stringVal;
    }

    protected override void handleShortCircuit(SObject calcItem) {
      switch on this.op {
        when UPDATE_MAX, UPDATE_MIN {
          String newVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
          if (this.isTrueFor(newVal, this.stringVal)) {
            this.stringVal = newVal;
          }
        }
        when DELETE_CONCAT_DISTINCT {
          this.handleConcatDistinctDelete(calcItem);
        }
      }
    }

    public override void handleConcat(SObject calcItem) {
      String newVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      if (this.shouldConcat(newVal)) {
        this.stringVal += this.concatWithDelimiter(newVal);
      }
    }

    public override void handleUpdateConcat(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      String newVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      SObject priorItem = oldCalcItems.get(calcItem.Id);
      String priorString = String.valueOf(priorItem != null ? priorItem.get(this.opFieldOnCalcItem) : newVal);
      if (this.eval?.matches(calcItem) == false && priorItem != null && this.eval?.matches(priorItem) == true) {
        this.handleDeleteConcat(calcItem);
      } else if (this.shouldConcat(newVal) || priorString != newVal) {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, this.isConcatDistinct ? '' : priorString, newVal);
      }
    }

    public override void handleDeleteConcat(SObject calcItem) {
      String existingVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      if (String.isBlank(existingVal)) {
        return;
      } else if (this.isConcatDistinct) {
        this.shouldShortCircuit = this.op.name().contains('DELETE');
        this.handleConcatDistinctDelete(calcItem);
      } else {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, existingVal, '');
      }
    }

    public override void handleMin(SObject calcItem) {
      String newVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      if (this.isTrueFor(newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    public override void handleMax(SObject calcItem) {
      this.handleMin(calcItem);
    }

    public override void handleUpdateMinOrMax(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      String newVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      String priorString = String.valueOf((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(this.opFieldOnCalcItem) : newVal));

      if (
        (this.op.name().contains(Rollup.Op.MAX.name()) && priorString == this.stringVal && newVal <= this.stringVal) ||
        (this.op.name().contains(Rollup.Op.MIN.name()) &&
        priorString == this.stringVal &&
        newVal >= this.stringVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, oldCalcItems.values(), calcItem.getSObjectType());
        this.stringVal = potentialReturnValue == null ? '' : String.valueOf(potentialReturnValue);
      } else if (this.isTrueFor(newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, List<Object> objIds, SObjectType sObjectType) {
      this.stringVal = (String) super.performBaseCalculation(op, objIds, sObjectType);
      return this.stringVal;
    }

    protected virtual Boolean isTrueFor(String newVal, String priorVal) {
      Boolean isTrueFor = false;
      if (this.op.name().contains(Rollup.Op.MAX.name())) {
        isTrueFor = newVal > priorVal || String.isBlank(priorVal);
      } else if (this.op.name().contains(Rollup.Op.MIN.name())) {
        isTrueFor = newVal < priorVal || String.isBlank(priorVal);
      }
      return isTrueFor;
    }

    protected virtual void sort(List<String> values) {
      values.sort();
    }

    private void sortAndConcat() {
      List<String> values = this.stringVal.split(this.concatDelimiter);
      if (this.isConcatDistinct) {
        values = new List<String>(new Set<String>(values));
      }
      for (Integer index = values.size() - 1; index >= 0; index--) {
        if (String.isBlank(values[index])) {
          values.remove(index);
          continue;
        }
        if (this.metadata.SplitConcatDelimiterOnCalcItem__c == true) {
          List<String> splitValues = values[index].split(this.concatDelimiter);
          values.remove(index);
          for (String splitVal : splitValues) {
            if (values.contains(splitVal) == false) {
              values.add(splitVal);
            }
          }
        }
      }
      if (this.metadata.RollupOrderBys__r.isEmpty()) {
        this.sort(values);
      }
      this.stringVal = String.join(values, this.concatDelimiter);
    }

    private Boolean shouldConcat(String newVal) {
      return String.isNotBlank(newVal);
    }

    private String concatWithDelimiter(String newVal) {
      return (String.isBlank(this.stringVal) || this.stringVal.endsWith(this.concatDelimiter) ? '' : this.concatDelimiter) + newVal + this.concatDelimiter;
    }

    private String replaceWithDelimiter(String existingVal, String matchingVal, String replacementVal) {
      if (String.isNotBlank(matchingVal) && existingVal.contains(matchingVal)) {
        return existingVal.replace(matchingVal, replacementVal) + this.concatDelimiter;
      }
      return existingVal += this.concatDelimiter + replacementVal;
    }

    private void handleConcatDistinctDelete(SObject calcItem) {
      // we do a replace first, in case this is a reparenting operation
      this.stringVal = this.replaceWithDelimiter(this.stringVal, (String) calcItem.get(this.opFieldOnCalcItem), '');
      this.concatDistinctIds.add(calcItem.Id);
      // we have to wait till it's the last iteration; this is what ensures that all of the deleted
      // items are accounted for in concatDistinctIds (for proper exclusion)
      if (this.isLastItem) {
        List<SObject> relatedItems = this.repo.setArg(this.concatDistinctIds)
          .setQuery(
            RollupQueryBuilder.Current.getQuery(
              calcItem.getSObjectType(),
              new List<String>{ this.opFieldOnCalcItem.getDescribe().getName() },
              'Id',
              '!=',
              this.lookupKeyQuery
            )
          )
          .get();
        for (SObject relatedItem : relatedItems) {
          this.handleConcat(relatedItem);
        }
      }
    }
  }

  private without sharing class PicklistRollupCalculator extends StringRollupCalculator {
    private final RollupFieldInitializer.PicklistController picklistController {
      get {
        if (picklistController == null) {
          picklistController = new RollupFieldInitializer.PicklistController(this.opFieldOnCalcItem.getDescribe());
        }
        return picklistController;
      }
      set;
    }
    public PicklistRollupCalculator(
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      Schema.SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      super.setDefaultValues(lookupRecordKey, priorVal);
      if (
        this.op.name().contains('CONCAT') &&
        this.picklistController.isPicklist() &&
        this.stringVal == this.picklistController.getDefaultValue(this.opFieldOnCalcItem)
      ) {
        this.stringVal = '';
      }
    }

    protected override Boolean isTrueFor(String newVal, String priorVal) {
      if (this.picklistController.isPicklist() == false) {
        return super.isTrueFor(newVal, priorVal);
      } else if (this.picklistController.isMultiSelectPicklist()) {
        // this operation isn't valid in SOQL, but at this point we wouldn't let a thing like that slow us down ...
        Integer newValRank = 0;
        Integer priorValRank = 0;
        for (String pickVal : newVal.split(';')) {
          newValRank += this.picklistController.getRank(pickVal, this.op);
        }
        for (String priorPickVal : priorVal.split(';')) {
          priorValRank += this.picklistController.getRank(priorPickVal, this.op);
        }
        return this.op.name().contains(Rollup.Op.MIN.name()) ? newValRank < priorValRank : newValRank > priorValRank;
      }
      return this.picklistController.isTrueFor(newVal, priorVal, this.op);
    }

    protected override void sort(List<String> picklistValues) {
      if (this.picklistController.isPicklist() == false) {
        super.sort(picklistValues);
      } else {
        this.picklistController.sort(picklistValues);
      }
    }
  }

  private without sharing class AverageRollupCalculator extends RollupCalculator {
    public AverageRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }
    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      List<SObject> applicableCalcItems = this.op == Rollup.Op.DELETE_AVERAGE ? new List<SObject>() : calcItems;
      applicableCalcItems = this.winnowItems(applicableCalcItems, oldCalcItems);
      Decimal oldSum;
      Decimal denominator = Decimal.valueOf(applicableCalcItems.size());
      if (this.isFullRecalc == false) {
        denominator += this.repo.setQuery(RollupQueryBuilder.Current.getQuery(this.calcItemSObjectType, new List<String>(), 'Id', '!=', this.lookupKeyQuery))
          .setArg(calcItems)
          .getCount();
        oldSum = (Decimal) this.calculateNewAggregateValue(Rollup.Op.SUM, calcItems, this.calcItemSObjectType);
      }

      if (oldSum == null) {
        oldSum = 0.00;
      }
      Decimal newSum = 0.00;
      for (SObject calcItem : applicableCalcItems) {
        Object potentialDecimal = calcItem.get(this.opFieldOnCalcItem);
        newSum += potentialDecimal == null ? 0.00 : (Decimal) potentialDecimal;
      }

      Decimal average = (Decimal) this.defaultVal;
      // We can't do the division if the denominator is 0
      if (denominator != 0) {
        Decimal numerator = oldSum + newSum;
        average = numerator / denominator;
      }
      this.returnVal = average;
    }
  }

  private without sharing class FirstLastRollupCalculator extends RollupCalculator {
    public FirstLastRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      Map<String, SObjectField> fieldMap = this.calcItemSObjectType.getDescribe().fields.getMap();
      for (RollupOrderBy__mdt orderByInfo : this.metadata.RollupOrderBys__r) {
        SObjectField orderByFirstLastField = fieldMap.get(orderByInfo.FieldName__c);
        this.isMultiCurrencyRollup =
          this.isMultiCurrencyRollup || (UserInfo.isMultiCurrencyOrganization() && orderByFirstLastField?.getDescribe().getType() == DisplayType.CURRENCY);
        if (this.isMultiCurrencyRollup) {
          break;
        }
      }
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      if (this.isFullRecalc == false) {
        Set<String> queryFields = this.getQueryFields();
        // a full-recalc is always necessary because we don't retain the information about the order by field
        // we have to exclude the current items on delete, otherwise they'll be incorrectly considered
        List<SObject> additionalItems = this.repo.setQuery(
            RollupQueryBuilder.Current.getQuery(this.calcItemSObjectType, new List<String>(queryFields), 'Id', '!=', this.lookupKeyQuery)
          )
          .setArg(calcItems)
          .get();
        switch on this.op {
          when DELETE_FIRST, DELETE_LAST {
            calcItems = additionalItems;
          }
          when else {
            calcItems.addAll(additionalItems);
          }
        }
      }

      calcItems = this.winnowItems(calcItems, oldCalcItems);

      if (calcItems.isEmpty()) {
        this.returnVal = this.defaultVal;
      } else {
        Integer retrievalIndex = 0;
        switch on this.op {
          when LAST, UPDATE_LAST, DELETE_LAST {
            retrievalIndex = calcItems.size() - 1;
          }
        }
        this.returnVal = calcItems[retrievalIndex].get(this.opFieldOnCalcItem);
      }
    }
  }

  private without sharing class MostRollupCalculator extends RollupCalculator {
    private Map<Object, Integer> occurrenceToCount = new Map<Object, Integer>();
    private Integer largestCountPointer;
    public MostRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      this.occurrenceToCount = new Map<Object, Integer>();
      this.largestCountPointer = -1;
      this.returnVal = this.defaultVal;
      List<SObject> localCalcItems = this.winnowItems(calcItems, oldCalcItems);

      for (SObject calcItem : localCalcItems) {
        Object value = calcItem.get(this.opFieldOnCalcItem);
        Integer localCount = 0;
        if (this.occurrenceToCount.containsKey(value)) {
          localCount = this.occurrenceToCount.get(value);
        }
        this.occurrenceToCount.put(value, ++localCount);
        if (this.largestCountPointer < localCount) {
          this.largestCountPointer = localCount;
          this.returnVal = value;
        }
      }
    }
  }

  private without sharing class ConditionalCalculator extends RollupCalculator {
    public ConditionalCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      this.returnVal = null;
      // winnowItems modifies the list passed in by reference, so we clone it here
      List<SObject> filteredItems = this.winnowItems(new List<SObject>(calcItems), oldCalcItems);
      Boolean matches = false;
      switch on this.op {
        when ALL {
          matches = calcItems.size() == filteredItems.size();
        }
        when NONE, SOME {
          matches = filteredItems.isEmpty() == this.op.name().contains(Rollup.Op.SOME.name()) == false;
        }
      }

      if (this.defaultVal != null && matches == false) {
        this.returnVal = this.defaultVal;
        return;
      }

      switch on this.opFieldOnLookupObject.getDescribe().getType() {
        when CURRENCY, DOUBLE, INTEGER {
          this.returnVal = matches ? 1 : 0;
        }
        when STRING, TEXTAREA {
          this.returnVal = String.valueOf(matches);
        }
        when else {
          this.returnVal = matches;
        }
      }
    }
  }

  private without sharing class GroupByCalculator extends DelimiterCalculator {
    private final GroupingFormatter formatter;
    private final RollupComparer sorter;
    private final RollupCalculator innerCalculator;
    private final List<String> fieldNames = new List<String>();
    private GroupByCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      this.setupFields();
      // have to cast here to avoid "Incompatible types in ternary operator: RollupCalculator.DefaultGroupingFormatter, RollupCalculator.TableGroupingFormatter"
      this.formatter = this.metadata.IsTableFormatted__c == true
        ? (GroupingFormatter) new TableGroupingFormatter(opFieldOnCalcItem)
        : (GroupingFormatter) new DefaultGroupingFormatter(this.metadata, this.concatDelimiter, this.opFieldOnLookupObject);
      this.sorter = new RollupCalcItemSorter(this.fieldNames);
      isGroupByRollup = true;
      this.innerCalculator = Factory.getCalculator(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      isGroupByRollup = false;
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      // ceremony section - curry the values from this to the inner calculator
      this.innerCalculator.setEvaluator(this.eval);
      this.innerCalculator.setFullRecalc(this.isFullRecalc);
      this.innerCalculator.setCDCUpdate(this.isCDCUpdate);
      this.innerCalculator.parentIsoCode = this.parentIsoCode;
      this.innerCalculator.isMultiCurrencyRollup = this.isMultiCurrencyRollup;

      this.winnowItems(calcItems, oldCalcItems);
      this.sorter.sort(calcItems);

      Map<String, List<SObject>> groupingStringToItems = new Map<String, List<SObject>>();
      for (SObject item : calcItems) {
        String currentGrouping = '';
        for (Integer index = 0; index < this.fieldNames.size(); index++) {
          String fieldName = this.fieldNames[index];
          Boolean isFirst = index == 0;
          Boolean isLast = index == this.fieldNames.size() - 1;
          Object groupingVal = item.get(fieldName);
          if (groupingVal == null) {
            groupingVal = '(blank)';
          }
          currentGrouping += this.formatter.getGroupingColumn(fieldName, groupingVal, isFirst, isLast);
        }
        if (groupingStringToItems.containsKey(currentGrouping)) {
          groupingStringToItems.get(currentGrouping).add(item);
        } else {
          groupingStringToItems.put(currentGrouping, new List<SObject>{ item });
        }
      }

      String newGroupingValue = this.formatter.getGroupingStart();
      for (String groupingKey : groupingStringToItems.keySet()) {
        this.innerCalculator.setDefaultValues(this.lookupRecordKey, RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnCalcItem));
        this.innerCalculator.performRollup(groupingStringToItems.get(groupingKey), oldCalcItems);
        this.innerCalculator.setReturnValue();
        newGroupingValue += this.formatter.getGroupingRowStart(groupingKey) + this.innerCalculator.getReturnValue() + this.formatter.getGroupingRowEnd();
      }
      this.returnVal = String.isBlank(newGroupingValue) ? null : this.formatter.getGroupingEnd(newGroupingValue);
    }

    private void setupFields() {
      List<String> fieldNames = this.metadata.GroupByFields__c.split(',');
      for (String fieldName : fieldNames) {
        String trimmedFieldName = fieldName.trim();
        if (trimmedFieldName == RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME) {
          this.isMultiCurrencyRollup = false;
        }
        this.fieldNames.add(trimmedFieldName);
      }
    }
  }

  private interface GroupingFormatter {
    String getGroupingStart();
    String getGroupingColumn(String fieldName, Object groupingValue, Boolean isFirst, Boolean isLast);
    String getGroupingRowStart(String groupingKey);
    String getGroupingRowEnd();
    String getGroupingEnd(String groupByString);
  }

  private class DefaultGroupingFormatter implements GroupingFormatter {
    private final String delimiter;
    private final Rollup__mdt metadata;

    public DefaultGroupingFormatter(Rollup__mdt metadata, String delimiter, Schema.SObjectField opFieldOnLookupObject) {
      this.metadata = metadata;
      this.delimiter = delimiter;
      this.setupDelimiters(opFieldOnLookupObject);
    }

    public String getGroupingColumn(String fieldName, Object groupingValue, Boolean isFirst, Boolean isLast) {
      return String.valueOf(groupingValue) + this.delimiter;
    }

    public String getGroupingStart() {
      return '';
    }

    public String getGroupingRowStart(String groupingKey) {
      return this.metadata.GroupByRowStartDelimiter__c + groupingKey;
    }

    public String getGroupingRowEnd() {
      return this.metadata.GroupByRowEndDelimiter__c;
    }

    public String getGroupingEnd(String groupByString) {
      return groupByString.removeEnd(this.getGroupingRowEnd());
    }

    private void setupDelimiters(Schema.SObjectField opFieldOnLookupObject) {
      if (this.metadata.GroupByRowEndDelimiter__c == null) {
        Boolean isRichText = opFieldOnLookupObject.getDescribe().isHtmlFormatted();
        this.metadata.GroupByRowEndDelimiter__c = isRichText ? '<br>' : '\n';
      }

      if (this.metadata.GroupByRowStartDelimiter__c == null) {
        this.metadata.GroupByRowStartDelimiter__c = '• ';
      }
    }
  }

  private class TableGroupingFormatter implements GroupingFormatter {
    private final Map<String, Schema.SObjectField> fieldNameToToken;
    private final Schema.SObjectField targetField;
    private final Set<String> columnHeaders = new Set<String>();

    private final String tdOpen = '<td>';
    private final String tdClose = '</td>';
    private final String thOpen = '<th>';
    private final String thClose = '</th>';
    private final String trOpen = '<tr>';
    private final String trClose = '</tr>';

    public TableGroupingFormatter(Schema.SObjectField targetField) {
      this.fieldNameToToken = targetField.getDescribe().getSObjectType().getDescribe().fields.getMap();
      this.targetField = targetField;
    }

    public String getGroupingColumn(String fieldName, Object groupingValue, Boolean isFirst, Boolean isLast) {
      String prefix = isFirst ? this.trOpen : '';
      String suffix = isLast ? this.trClose : '';
      this.columnHeaders.add(prefix + this.thOpen + this.fieldNameToToken.get(fieldName).getDescribe().getLabel() + this.thClose);
      if (isLast) {
        this.columnHeaders.add(this.thOpen + this.targetField.getDescribe().getName() + this.thClose + suffix);
      }
      return prefix + this.tdOpen + String.valueOf(groupingValue) + this.tdClose + suffix;
    }

    public String getGroupingStart() {
      return '<table>' + String.join(new List<String>(this.columnHeaders), '');
    }

    public String getGroupingRowStart(String groupingKey) {
      return groupingKey.replace(this.trClose, '') + this.tdOpen;
    }

    public String getGroupingRowEnd() {
      return this.tdClose + this.trClose;
    }

    public String getGroupingEnd(String groupByString) {
      return groupByString + '</table>';
    }
  }

  private static Object getDefaultRecalculationValue(Rollup__mdt meta) {
    // some operations could possibly use either default value
    // we also have to cast to Object to avoid the compilation error:
    // "Incompatible types in ternary operator: String, Decimal"
    return (meta.FullRecalculationDefaultNumberValue__c != null
      ? (Object) meta.FullRecalculationDefaultNumberValue__c
      : (Object) meta.FullRecalculationDefaultStringValue__c);
  }
}
