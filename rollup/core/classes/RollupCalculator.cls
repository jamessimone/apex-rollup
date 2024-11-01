@SuppressWarnings('PMD.NcssTypeCount')
public without sharing abstract class RollupCalculator {
  private Boolean isCDCUpdate = false;
  private Boolean isFirstTimeThrough = true;
  private Boolean isMultiCurrencyRollup;
  private Boolean isRecursiveRecalc = false;
  private List<SObject> calcItems;
  private Map<Id, SObject> oldCalcItems;
  private RollupState state;

  private final RollupRepository repo;

  protected final Object defaultVal;
  protected final SObjectField opFieldOnCalcItem;
  protected final SObjectField opFieldOnLookupObject;
  protected final SObjectField lookupKeyField;
  protected final Rollup__mdt metadata;
  protected final Boolean isChangedFieldCalc;
  protected final SObjectType calcItemSObjectType;

  protected Set<Id> childrenIds = new Set<Id>();
  protected Set<Object> distinctValues = new Set<Object>();
  protected Rollup.Op op;
  protected String lookupKeyQuery;
  protected String lookupRecordKey;
  protected Rollup.Evaluator eval;
  protected Boolean shouldShortCircuit = false;
  protected Object returnVal;
  protected Boolean isLastItem = false;
  protected Boolean shouldTriggerFullRecalc;
  protected String parentIsoCode;
  protected Boolean isFullRecalc = false;
  protected Boolean isDistinct = false;
  protected Boolean hasCustomStateCalculation = false;

  @TestVisible
  private static Factory testFactory;
  private static Boolean isGroupByRollup = false;

  public static Factory Factory {
    get {
      Factory = Factory ?? testFactory ?? new RollupCalculator.Factory();
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

  protected RollupCalculator() {
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
    this.isMultiCurrencyRollup = this.isMultiCurrencyRollup ??
      RollupCurrencyInfo.isMultiCurrency() &&
      (this.opFieldOnCalcItem?.getDescribe().getType() == DisplayType.CURRENCY ||
      this.opFieldOnLookupObject?.getDescribe().getType() == DisplayType.CURRENCY);
    this.isChangedFieldCalc = String.isNotBlank(this.metadata.ChangedFieldsOnCalcItem__c);
    this.isDistinct = this.metadata.IsDistinct__c == true;
    this.calcItemSObjectType = opFieldOnCalcItem?.getDescribe().getSObjectType();
    this.repo = new RollupRepository(RollupMetaPicklists.getAccessLevel(this.metadata));
    this.updateAdvancedCurrencyMappings();
  }

  public virtual void setDefaultValues(String lookupRecordKey, Object priorVal) {
    this.shouldShortCircuit = false;
    this.lookupRecordKey = lookupRecordKey;
    this.returnVal = priorVal ?? this.defaultVal ?? RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnLookupObject);
    this.lookupKeyQuery =
      this.lookupKeyField +
      ' = \'' +
      lookupRecordKey +
      '\'' +
      (String.isBlank(metadata.CalcItemWhereClause__c) ? '' : ' AND (' + metadata.CalcItemWhereClause__c + ')');
    this.childrenIds = new Set<Id>();
  }

  public virtual Object getReturnValue() {
    if (this.state != null && this.hasCustomStateCalculation == false) {
      RollupState.GenericInfo possibleInfo = (RollupState.GenericInfo) this.state.getState(this.lookupRecordKey, this.metadata, RollupState.GenericInfo.class);
      possibleInfo.value = this.returnVal != this.defaultVal ? this.returnVal : possibleInfo.value;
    }
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
    this.calcItems = calcItems;
    this.oldCalcItems = oldCalcItems;
    // if we're already in a full recalc, we've got all the items we need already
    this.shouldTriggerFullRecalc = this.isFullRecalc == false;
    this.rollupResults(this.winnowItems(calcItems, oldCalcItems));
  }

  public void setState(RollupState state) {
    this.state = state;
  }

  // all of these are no-ops by default; child classes opt-in to the rollup types applicable
  public virtual void handleCountDistinct(WinnowResult result) {
  }
  public virtual void handleUpdateCountDistinct(WinnowResult result) {
  }
  public virtual void handleSumOrCount(WinnowResult result) {
  }
  public virtual void handleUpdateSumOrCount(WinnowResult result) {
  }
  public virtual void handleDeleteSumOrCount(WinnowResult result) {
  }
  public virtual void handleMin(WinnowResult result) {
  }
  public virtual void handleMax(WinnowResult result) {
  }
  public virtual void handleUpdateMinOrMax(WinnowResult result) {
  }
  public virtual void handleConcat(WinnowResult result) {
  }
  public virtual void handleUpdateConcat(WinnowResult result) {
  }
  public virtual void handleDeleteConcat(WinnowResult result) {
  }
  protected virtual void handleShortCircuit(WinnowResult result) {
  }
  protected virtual void setReturnValue() {
  }

  protected virtual void rollupResults(List<WinnowResult> results) {
    this.shouldTriggerFullRecalc = this.shouldTriggerFullRecalc ?? false;
    for (Integer index = 0; index < results.size(); index++) {
      this.isLastItem = index == results.size() - 1;
      WinnowResult result = results[index];
      Boolean doesNotMatch = result.matchesCurrent == false;
      if (doesNotMatch && result.hasOldItem) {
        doesNotMatch = doesNotMatch && result.matchesOld == false;
      }

      // it's only a full recalc situation if there are no items left after winnowing
      // otherwise, for even one item in the list, this should cause "shouldTriggerFullRecalc" to evaluate to false
      if (this.shouldTriggerFullRecalc) {
        this.shouldTriggerFullRecalc = doesNotMatch;
      }

      if (this.shouldShortCircuit) {
        this.handleShortCircuit(result);
        continue;
      } else if (this.isCDCUpdate) {
        // here we don't exclude items because the calc items have already been updated
        this.childrenIds = new Set<Id>();
        this.shouldTriggerFullRecalc = true;
        break;
      } else {
        switch on this.op {
          when COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
            this.handleCountDistinct(result);
          }
          when UPDATE_COUNT_DISTINCT {
            this.handleUpdateCountDistinct(result);
          }
          when SUM, COUNT {
            this.handleSumOrCount(result);
          }
          when UPDATE_SUM, UPDATE_COUNT {
            this.handleUpdateSumOrCount(result);
          }
          when DELETE_SUM, DELETE_COUNT {
            this.handleDeleteSumOrCount(result);
          }
          when MIN {
            this.handleMin(result);
          }
          when MAX {
            this.handleMax(result);
          }
          when UPDATE_MAX, UPDATE_MIN, DELETE_MAX, DELETE_MIN {
            this.handleUpdateMinOrMax(result);
          }
          when CONCAT, CONCAT_DISTINCT {
            this.handleConcat(result);
          }
          when UPDATE_CONCAT, UPDATE_CONCAT_DISTINCT {
            this.handleUpdateConcat(result);
          }
          when DELETE_CONCAT, DELETE_CONCAT_DISTINCT {
            this.handleDeleteConcat(result);
          }
        }
      }

      if (this.shouldShortCircuit && this.isFirstTimeThrough) {
        /**
         * an example of short circuiting - halfway through the list during a MIN operation,
         * Rollup encounters a calcItem whose previous value equals the current min, but the new value
         * is greater than the min. This triggers a full recalc, since it is at once both possible
         * for items outside the list of results to contain the new min, as WELL as for an item
         * WITHIN the existing results to be the new min. This means we have to go back and re-process
         * the records that were already iterated on to ensure that the current operation successfully accounts
         * for everything in-memory and in the database
         */
        this.isFirstTimeThrough = false;
        if (index != 0 && results.size() > 1) {
          index = 0; // resets the for-loop
        }
      }
    }
    // if there were no matching items, it's time for a full recalc (unless a RollupCalculator has overridden this method)
    // this means String, Number, and Datetime variant rollup calculations all need to correctly handle
    // recalculating via "calculateNewAggregateValue"
    if (this.shouldTriggerFullRecalc) {
      this.returnVal = this.calculateNewAggregateValue(this.op, this.childrenIds);
      // bail on calling setReturnValue below
      return;
    } else if (this.shouldTriggerFullRecalc == false && results.isEmpty() && this.isFullRecalc == false) {
      this.returnVal = this.defaultVal;
      return;
    }
    this.setReturnValue();
  }

  @TestVisible
  private class WinnowResult {
    private Object currentValue;
    private Object priorValue;
    private Boolean hasOldItem = false;
    private Boolean matchesCurrent = false;
    private Boolean matchesOld = true;
    private Boolean isReparented = false;
    private final SObject item;

    public WinnowResult(SObject item, Schema.SObjectField token) {
      this(item.get(token));
      this.item = item;
    }

    public WinnowResult(Object currentValue) {
      this.currentValue = currentValue;
      this.matchesCurrent = true;
    }
  }

  protected List<WinnowResult> winnowItems(List<SObject> items, Map<Id, SObject> oldCalcItems) {
    List<RollupOrderBy__mdt> orderBys = this.metadata?.LimitAmount__c != null && this.metadata.RollupOrderBys__r.isEmpty()
      ? new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Id', Ranking__c = 0) }
      : new List<RollupOrderBy__mdt>(this.metadata.RollupOrderBys__r);
    if (orderBys.isEmpty() == false) {
      orderBys.sort(new RollupRepository.OrderBySorter());
      items.sort(new RollupCalcItemSorter(orderBys));
    }
    List<WinnowResult> winnowedItems = new List<WinnowResult>();
    this.transformForMultiCurrencyOrgs(items);
    if (oldCalcItems.isEmpty() == false && this.isMultiCurrencyRollup) {
      List<SObject> tempOldCalcItems = oldCalcItems.values();
      this.transformForMultiCurrencyOrgs(tempOldCalcItems);
      for (SObject oldCalcItem : tempOldCalcItems) {
        oldCalcItems.put(oldCalcItem.Id, this.getTransformedCalcItem(oldCalcItem));
      }
    }
    for (SObject item : items) {
      this.childrenIds.add(item?.Id);
      SObject transformedItem = this.getTransformedCalcItem(item);
      WinnowResult result = new WinnowResult(transformedItem, this.opFieldOnCalcItem);
      Boolean shouldAddToResults = this.eval?.matches(transformedItem) != false;
      Boolean currentItemMatches = shouldAddToResults;
      SObject potentialPriorItem = oldCalcItems.get(transformedItem.Id);
      if (potentialPriorItem != null) {
        result.hasOldItem = true;
        result.isReparented = this.isReparented(transformedItem, potentialPriorItem);
        result.matchesOld = this.eval?.matches(potentialPriorItem) != false;
        result.priorValue = potentialPriorItem.get(this.opFieldOnCalcItem);
      }
      if (currentItemMatches == false) {
        switch on this.op {
          // not all downstream updates for old item matching when new item doesn't have been defined
          // and this switch statement is how other operations opt-in
          when UPDATE_COUNT, UPDATE_CONCAT_DISTINCT, UPDATE_CONCAT, UPDATE_SUM {
            if (this.isChangedFieldCalc == false && result.hasOldItem && result.matchesOld) {
              shouldAddToResults = true;
            }
          }
        }
      }
      if (shouldAddToResults == false) {
        continue;
      }
      if (this.isDistinct) {
        if (this.distinctValues.contains(result.currentValue)) {
          continue;
        }
        this.distinctValues.add(result.currentValue);
      }
      result.matchesCurrent = currentItemMatches;
      winnowedItems.add(result);
      if (this.op == Rollup.Op.SOME) {
        break;
      }
    }
    this.childrenIds.remove(null);
    if (this.metadata.LimitAmount__c != null) {
      // we can only safely remove the items after sorting
      while (winnowedItems.size() > this.metadata.LimitAmount__c && winnowedItems.isEmpty() == false) {
        winnowedItems.remove(winnowedItems.size() - 1);
      }
      // Limit-based rollups always reset the field's value, and always act as a fresh start
      if (this.metadata.RollupOperation__c.contains('DELETE_') || this.metadata.RollupOperation__c.contains('UPDATE_')) {
        this.op = Rollup.Op.valueOf(this.metadata.RollupOperation__c.substringAfter('_'));
      }
    }
    if (this.state != null && this.hasCustomStateCalculation == false) {
      RollupState.GenericInfo info = (RollupState.GenericInfo) this.state.getState(this.lookupRecordKey, this.metadata, RollupState.GenericInfo.class);
      if (info?.value != null) {
        winnowedItems.add(new WinnowResult(info.value));
      }
    }

    return winnowedItems;
  }

  protected virtual Object calculateNewAggregateValue(Rollup.Op op, Iterable<Object> objIds) {
    String operationName = Rollup.getBaseOperationName(op.name());
    String alias = operationName.toLowerCase() + 'Field';
    List<SObject> aggregate = this.tryQuery(this.calcItemSObjectType, new Set<String>{ operationName + '(' + this.opFieldOnCalcItem + ')' + alias }, objIds);
    return aggregate.isEmpty() == false ? aggregate[0].get(alias) : this.defaultVal;
  }

  protected Boolean isReparented(SObject calcItem, SObject oldCalcItem) {
    return oldCalcItem != null && calcItem?.get(this.lookupKeyField) != oldCalcItem.get(this.lookupKeyField);
  }

  protected Object performBaseCalculation(Rollup.Op op, Iterable<Object> objIds) {
    this.returnVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnLookupObject);

    if (this.isRecursiveRecalc == false) {
      this.isRecursiveRecalc = true; // now we're cooking with gas
      Set<String> queryFields = this.getQueryFields();

      List<SObject> allOtherItems = this.tryQuery(this.calcItemSObjectType, queryFields, objIds);
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

  protected List<SObject> tryQuery(Schema.SObjectType sObjectType, Set<String> queryFields, Object bindVar) {
    List<SObject> results;
    try {
      results = this.repo.setQuery(RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(queryFields), 'Id', '!=', this.lookupKeyQuery))
        .setArg(bindVar)
        .get();
    } catch (System.QueryException qex) {
      results = this.repo.setQuery(RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(queryFields), 'Id', '!=')).get();
    }
    return results;
  }

  private SObject getTransformedCalcItem(SObject calcItem) {
    return this.isMultiCurrencyRollup ? RollupCurrencyInfo.getCalcItem(calcItem, this.parentIsoCode) : calcItem;
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
      RollupCurrencyInfo.overrideDatedMultiCurrency(this.metadata.CalcItem__c, fieldMappings);
    }
  }

  private without sharing class CountDistinctRollupCalculator extends RollupCalculator {
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
      this.isIdCount = this.opFieldOnCalcItem.toString() == 'Id';
      Object defaultVal = RollupFieldInitializer.Current.getDefaultValue(opFieldOnLookupObject);
      if (defaultVal != 0 && this.returnVal != defaultVal && this.isIdCount == false) {
        this.distinctValues.add(this.returnVal);
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.distinctValues.size() == 0 ? this.defaultVal : Decimal.valueOf(this.distinctValues.size());
    }

    protected override void handleShortCircuit(WinnowResult result) {
      if (result.currentValue != null && this.op != Rollup.Op.DELETE_COUNT_DISTINCT) {
        this.distinctValues.add(result.currentValue);
      }
    }

    public override void handleCountDistinct(WinnowResult result) {
      Object potentiallyNullValue = result.currentValue;
      if (this.op != Rollup.Op.DELETE_COUNT_DISTINCT && potentiallyNullValue != null) {
        this.distinctValues.add(potentiallyNullValue);
      } else if (this.op == Rollup.Op.DELETE_COUNT_DISTINCT) {
        this.distinctValues = new Set<Object>();
        this.calculateNewAggregateValue(this.op, this.childrenIds);
      }
      this.shouldShortCircuit = true;
    }

    public override void handleUpdateCountDistinct(WinnowResult result) {
      this.shouldShortCircuit = true;
      this.handleShortCircuit(result);
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, Iterable<Object> objIds) {
      if (this.shouldTriggerFullRecalc == true) {
        this.distinctValues = new Set<Object>();
      }
      Boolean isArchivable = this.calcItemSObjectType == Task.SObjectType || this.calcItemSObjectType == Event.SObjectType;
      Boolean isGroupable = isArchivable == false && this.opFieldOnCalcItem.getDescribe().isGroupable();
      List<String> queryFields = new List<String>{ String.valueOf(this.opFieldOnCalcItem) };
      if (isGroupable) {
        queryFields.add('COUNT(' + (this.isIdCount ? '' : 'Id') + ')');
      }

      this.repo.setQuery(
          RollupQueryBuilder.Current.getQuery(
            this.calcItemSObjectType,
            queryFields,
            'Id',
            '!=',
            this.lookupKeyQuery + ('\nAND ' + this.opFieldOnCalcItem + ' != null')
          ) + (isGroupable && this.isIdCount == false ? ('\nGROUP BY ' + this.opFieldOnCalcItem) : '')
        )
        .setArg(objIds);

      if (this.isIdCount) {
        Integer result = this.repo.getCount();
        for (Integer index = 0; index < result; index++) {
          this.distinctValues.add(index);
        }
      } else {
        List<SObject> results = this.repo.get();
        String calcItemOpField = this.opFieldOnCalcItem.toString();
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
      } else if (this.returnVal == null) {
        this.returnDecimal = (Decimal) this.defaultVal;
      }
    }

    protected virtual Decimal getDecimalOrDefault(Object potentiallyUninitialized) {
      if (potentiallyUninitialized instanceof Decimal) {
        return (Decimal) potentiallyUninitialized;
      } else {
        return potentiallyUninitialized == null ? 0.00 : 1.00;
      }
    }

    protected virtual Decimal getNumericValue(Object currentValue) {
      return this.getDecimalOrDefault(currentValue);
    }

    protected virtual Decimal getNumericChangedValue(WinnowResult result) {
      Decimal newVal = this.getNumericValue(result.currentValue);
      Decimal oldVal = result.hasOldItem ? this.getNumericValue(result.priorValue) : 0;

      if (this.isFullRecalc && result.matchesCurrent) {
        return newVal;
      } else if (this.isFullRecalc && result.matchesOld) {
        return 0;
      } else if (result.isReparented) {
        return result.matchesCurrent ? newVal : 0;
      } else if (result.matchesCurrent && result.matchesOld == false && this.isChangedFieldCalc == false && this.isFullRecalc == false) {
        return newVal;
      } else if (result.matchesCurrent == false && result.matchesOld && this.isChangedFieldCalc == false && this.isFullRecalc == false) {
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
        this.returnVal = this.defaultVal;
      }
      return super.getReturnValue();
    }

    protected override void handleShortCircuit(WinnowResult result) {
      switch on this.op {
        when UPDATE_MAX {
          // re-maxing by way of query has occurred, but is it **correct**?
          // if one of the other updated children is numerically superior, assign the new max
          Decimal newVal = this.getNumericValue(result.currentValue);
          if (newVal > returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
        when UPDATE_MIN {
          // re-"min"-ing has occurred by way of query, but is an in-memory child even less?
          Decimal newVal = this.getNumericValue(result.currentValue);
          if (newVal < returnDecimal) {
            this.returnDecimal = newVal;
          }
        }
      }
    }

    public override void handleSumOrCount(WinnowResult result) {
      this.returnDecimal += this.getNumericValue(result.currentValue);
    }

    public override void handleUpdateSumOrCount(WinnowResult result) {
      this.returnDecimal += this.getNumericChangedValue(result);
    }

    public override void handleDeleteSumOrCount(WinnowResult result) {
      this.returnDecimal -= this.getNumericValue(result.currentValue);
    }

    public override void handleMax(WinnowResult result) {
      Decimal numericValue = this.getNumericValue(result.currentValue);
      if (numericValue > this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleMin(WinnowResult result) {
      Decimal numericValue = this.getNumericValue(result.currentValue);
      if (numericValue < this.returnDecimal || this.returnDecimal == 0) {
        this.returnDecimal = numericValue;
      }
    }

    public override void handleUpdateMinOrMax(WinnowResult result) {
      Decimal newVal = this.getNumericValue(result.currentValue);
      Decimal thisPriorVal = this.getNumericValue(result.hasOldItem ? result.priorValue : result.currentValue);
      if (
        thisPriorVal != 0 &&
        thisPriorVal == this.returnDecimal &&
        (this.op.name().contains(Rollup.Op.MAX.name()) && newVal <= thisPriorVal ||
        this.op.name().contains(Rollup.Op.MIN.name()) && newVal >= thisPriorVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, this.childrenIds);
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
      if (this.shouldTriggerFullRecalc == false) {
        this.returnVal = this.returnDecimal;
      }
    }

    protected virtual override Object calculateNewAggregateValue(Rollup.Op op, Iterable<Object> objIds) {
      Object aggregate;
      try {
        aggregate = super.calculateNewAggregateValue(op, objIds);
      } catch (Exception ex) {
        aggregate = this.performBaseCalculation(op, objIds);
      }
      // for count-based rollups, fine to use 0 in the event of no matches
      // but otherwise, it's more accurate to be nulling out the parent fields if there isn't a max, for example
      if (aggregate == 0 && op.name().contains('COUNT') == false) {
        aggregate = null;
      }
      return aggregate ?? this.defaultVal;
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
        this.returnVal = Datetime.newInstance(((Decimal) superReturnVal).longValue());
      } else if (superReturnVal == 0) {
        this.returnVal = this.defaultVal;
      }
      return super.getReturnValue();
    }

    public virtual override void setDefaultValues(String lookupRecordKey, Object priorVal) {
      priorVal = priorVal ?? RollupFieldInitializer.Current.defaultDateTime;
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

    protected override Object calculateNewAggregateValue(Rollup.Op op, Iterable<Object> excludedItems) {
      Object aggregate = super.calculateNewAggregateValue(op, excludedItems);
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
      if (superReturnVal instanceof Datetime) {
        this.returnVal = ((Datetime) superReturnVal).dateGmt();
      }
      return super.getReturnValue();
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
        this.returnVal = ((Datetime) returnValue).timeGmt();
      }
      return super.getReturnValue();
    }

    protected override Decimal getDecimalOrDefault(Object potentiallyUninitialized) {
      Datetime defaultDatetime;
      if (potentiallyUninitialized instanceof Time) {
        defaultDatetime = Datetime.newInstanceGmt(RollupFieldInitializer.Current.defaultDateTime.dateGmt(), (Time) potentiallyUninitialized);
      } else if (potentiallyUninitialized instanceof Decimal) {
        defaultDatetime = Datetime.newInstance(((Decimal) potentiallyUninitialized).longValue());
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
      this.returnVal = potentialReturnVal < 0 ? 0.00 : potentialReturnVal;
      return super.getReturnValue();
    }

    protected override Decimal getNumericValue(Object value) {
      return value != null ? 1.00 : 0.00;
    }

    protected override Decimal getNumericChangedValue(WinnowResult result) {
      // for a reparenting, the item counts towards the new record on an update
      if (result.isReparented) {
        return result.matchesCurrent ? 1.00 : 0.00;
      }

      // for updates, we have to decrement the count if the value has been cleared out
      Decimal retVal = 0.00;
      Object current = result.currentValue;
      Object prior = result.priorValue;
      Object defaultVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnCalcItem);
      if (this.isFullRecalc && result.matchesCurrent) {
        retVal = 1.00;
      } else if (this.isFullRecalc && result.matchesOld) {
        retVal = 0;
      } else if (current == null && prior != null || result.matchesOld && result.matchesCurrent == false) {
        retVal = -1.00;
      } else if (current != defaultVal && prior == defaultVal || result.matchesOld == false && result.matchesCurrent || current != null && prior == null) {
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
      } else {
        this.concatDelimiter = this.metadata.ConcatDelimiter__c?.unescapeJava() ?? ', ';
      }
    }
  }

  private without sharing virtual class StringRollupCalculator extends DelimiterCalculator {
    private String stringVal;

    private final Boolean isConcatDistinct;

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
      super.setDefaultValues(lookupRecordKey, this.isConcatDistinct ? '' : priorVal);
      if (this.returnVal instanceof String) {
        this.stringVal = (String) this.returnVal;
      }
    }

    protected override void setReturnValue() {
      if (this.op.name().contains(Rollup.Op.CONCAT.name()) && this.concatDelimiter != '\n') {
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
      } else {
        this.stringVal = this.stringVal.trim();
      }
      this.returnVal = this.stringVal;
    }

    protected override void handleShortCircuit(WinnowResult result) {
      switch on this.op {
        when UPDATE_MAX, UPDATE_MIN {
          String newVal = String.valueOf(result.currentValue);
          if (this.isTrueFor(newVal, this.stringVal)) {
            this.stringVal = newVal;
          }
        }
        when DELETE_CONCAT_DISTINCT {
          this.handleConcatDistinctDelete(result);
        }
      }
    }

    public override void handleConcat(WinnowResult result) {
      String newVal = String.valueOf(result.currentValue);
      if (this.shouldConcat(newVal)) {
        this.stringVal += this.concatWithDelimiter(newVal);
      }
    }

    public override void handleUpdateConcat(WinnowResult result) {
      String newVal = String.valueOf(result.currentValue);
      String priorString = String.valueOf(result.hasOldItem ? result.priorValue : newVal);
      if (result.matchesCurrent == false && result.hasOldItem && result.matchesOld) {
        this.handleDeleteConcat(result);
      } else if (this.shouldConcat(newVal) || priorString != newVal) {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, this.isConcatDistinct ? '' : priorString, newVal);
      }
    }

    public override void handleDeleteConcat(WinnowResult result) {
      String existingVal = String.valueOf(result.currentValue);
      if (String.isBlank(existingVal)) {
        return;
      } else if (this.isConcatDistinct) {
        this.shouldShortCircuit = this.op.name().contains('DELETE');
        this.handleConcatDistinctDelete(result);
      } else {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, existingVal, '');
      }
    }

    public override void handleMin(WinnowResult result) {
      String newVal = String.valueOf(result.currentValue);
      if (this.isTrueFor(newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    public override void handleMax(WinnowResult result) {
      this.handleMin(result);
    }

    public override void handleUpdateMinOrMax(WinnowResult result) {
      String newVal = String.valueOf(result.currentValue);
      String priorString = String.valueOf(result.hasOldItem ? result.priorValue : result.currentValue);

      if (
        (this.op.name().contains(Rollup.Op.MAX.name()) && priorString == this.stringVal && newVal <= this.stringVal) ||
        (this.op.name().contains(Rollup.Op.MIN.name()) &&
        priorString == this.stringVal &&
        newVal >= this.stringVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, this.childrenIds);
        this.stringVal = String.valueOf(potentialReturnValue ?? '');
      } else if (this.isTrueFor(newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, Iterable<Object> objIds) {
      this.stringVal = (String) super.performBaseCalculation(op, objIds);
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

    private void handleConcatDistinctDelete(WinnowResult result) {
      // we do a replace first, in case this is a reparenting operation
      this.stringVal = this.replaceWithDelimiter(this.stringVal, (String) result.currentValue, '');
      // we have to wait till it's the last iteration; this is what ensures that all of the deleted
      // items are accounted for in this.childrenIds (for proper exclusion)
      if (this.isLastItem) {
        List<SObject> relatedItems = this.repo.setArg(this.childrenIds)
          .setQuery(
            RollupQueryBuilder.Current.getQuery(
              this.calcItemSObjectType,
              new List<String>{ this.opFieldOnCalcItem.toString() },
              'Id',
              '!=',
              this.lookupKeyQuery
            )
          )
          .get();
        for (SObject relatedItem : relatedItems) {
          this.handleConcat(new WinnowResult(relatedItem, this.opFieldOnCalcItem));
        }
      }
    }
  }

  private without sharing class PicklistRollupCalculator extends StringRollupCalculator {
    private final RollupFieldInitializer.PicklistController picklistController {
      get {
        this.picklistController = this.picklistController ?? new RollupFieldInitializer.PicklistController(this.opFieldOnCalcItem.getDescribe());
        return this.picklistController;
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
    private RollupState.AverageInfo info;

    public AverageRollupCalculator(
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      SObjectField lookupKeyField
    ) {
      super(op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupKeyField);
      this.hasCustomStateCalculation = true;
    }
    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      this.info = (RollupState.AverageInfo) (this.state?.getState(this.lookupRecordKey, this.metadata, RollupState.AverageInfo.class));
      if (this.info != null) {
        this.distinctValues.addAll(this.info.distinctNumerators);
      }
      this.rollupResults(this.winnowItems(calcItems, oldCalcItems));
    }

    protected override void rollupResults(List<WinnowResult> results) {
      Decimal numerator = this.info?.numerator ?? 0.00;
      Decimal denominator = results.size() + (this.info?.denominator ?? 0.00);

      for (WinnowResult result : results) {
        Decimal current = (Decimal) result.currentValue ?? 0.00;
        numerator += current;
        this.info?.increment(current);
      }

      Decimal average = (Decimal) this.defaultVal;
      // We can't do the division if the denominator is 0
      if (denominator != 0) {
        average = numerator / denominator;
      }
      this.returnVal = average;
    }
  }

  private without sharing class FirstLastRollupCalculator extends RollupCalculator {
    private RollupState.SObjectInfo info;

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
      this.hasCustomStateCalculation = true;
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      this.info = (RollupState.SObjectInfo) this.state?.getState(this.lookupRecordKey, this.metadata, RollupState.SObjectInfo.class);
      if (this.info?.item != null) {
        calcItems.add(this.info.item);
      }
      this.rollupResults(this.winnowItems(calcItems, oldCalcItems));
    }

    protected override void rollupResults(List<WinnowResult> results) {
      if (results.isEmpty()) {
        this.returnVal = this.defaultVal;
      } else {
        Integer retrievalIndex = 0;
        switch on this.op {
          when LAST, UPDATE_LAST, DELETE_LAST {
            retrievalIndex = results.size() - 1;
          }
        }
        WinnowResult result = results[retrievalIndex];
        this.info?.setItem(result.item);
        this.returnVal = result.currentValue;
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
      this.hasCustomStateCalculation = true;
    }

    protected override void rollupResults(List<WinnowResult> results) {
      RollupState.MostInfo info = (RollupState.MostInfo) this.state?.getState(this.lookupRecordKey, this.metadata, RollupState.MostInfo.class);
      this.occurrenceToCount = new Map<Object, Integer>();
      this.largestCountPointer = info?.largestPointCounter ?? -1;
      this.returnVal = info?.value ?? this.defaultVal;

      for (WinnowResult result : results) {
        Object value = result.currentValue;
        Integer localCount = this.occurrenceToCount.get(value) ?? 0;
        this.occurrenceToCount.put(value, ++localCount);
        if (this.largestCountPointer < localCount) {
          this.largestCountPointer = localCount;
          this.returnVal = value;
          info?.setValues(localCount, value);
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

    protected override void rollupResults(List<WinnowResult> filteredItems) {
      Boolean matches = false;
      switch on this.op {
        when ALL {
          matches = this.calcItems.size() == filteredItems.size();
        }
        when NONE, SOME {
          Boolean isSome = this.op == Rollup.Op.SOME;
          matches = filteredItems.isEmpty() == (isSome == false);
          if (isSome && this.isTruthy() && this.oldCalcItems?.isEmpty() == true) {
            matches = true;
          }
        }
      }
      this.returnVal = null;

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

    private Boolean isTruthy() {
      return this.returnVal == true || this.returnVal == 1 || this.returnVal == 'true';
    }
  }

  private without sharing class GroupByCalculator extends DelimiterCalculator {
    private final GroupingFormatter formatter;
    private final System.Comparator<SObject> sorter;
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
      this.innerCalculator.setState(this.state);
      this.innerCalculator.parentIsoCode = this.parentIsoCode;
      this.innerCalculator.isMultiCurrencyRollup = this.isMultiCurrencyRollup;

      calcItems.sort(this.sorter);
      List<WinnowResult> results = this.winnowItems(calcItems, oldCalcItems);

      Map<String, List<SObject>> groupingStringToItems = new Map<String, List<SObject>>();
      for (WinnowResult result : results) {
        String currentGrouping = '';
        for (Integer index = 0; index < this.fieldNames.size(); index++) {
          String fieldName = this.fieldNames[index];
          Boolean isFirst = index == 0;
          Boolean isLast = index == this.fieldNames.size() - 1;
          Object groupingVal = result.item.get(fieldName) ?? '(blank)';
          currentGrouping += this.formatter.getGroupingColumn(fieldName, groupingVal, isFirst, isLast);
        }
        List<SObject> groupedItems = groupingStringToItems.get(currentGrouping);
        if (groupedItems == null) {
          groupedItems = new List<SObject>();
          groupingStringToItems.put(currentGrouping, groupedItems);
        }
        groupedItems.add(result.item);
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
      this.metadata.GroupByRowEndDelimiter__c = this.metadata.GroupByRowEndDelimiter__c ??
        (opFieldOnLookupObject.getDescribe().isHtmlFormatted() ? '<br>' : '\n');
      this.metadata.GroupByRowStartDelimiter__c = this.metadata.GroupByRowStartDelimiter__c ?? '• ';
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
        this.columnHeaders.add(this.thOpen + this.targetField.toString() + this.thClose + suffix);
      }
      return prefix + this.tdOpen + String.valueOf(groupingValue) + this.tdClose + suffix;
    }

    public String getGroupingStart() {
      return '<table>' + String.join(this.columnHeaders, '');
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

  public class ValueRollupCalculator extends RollupCalculator {
    private final RollupCalculator innerCalc;
    private final List<WinnowResult> results = new List<WinnowResult>();

    public ValueRollupCalculator(RollupCalculator innerCalc, Iterable<Object> valuesToReduce) {
      this.innerCalc = innerCalc;
      for (Object value : valuesToReduce) {
        this.results.add(new WinnowResult(value));
      }
    }

    public override Object getReturnValue() {
      this.innerCalc.rollupResults(this.results);
      return this.innerCalc.getReturnValue();
    }

    public Rollup.Op getOp() {
      return this.innerCalc.op;
    }

    public ValueRollupCalculator setOperation(Rollup.Op op) {
      this.innerCalc.op = op;
      return this;
    }
  }

  private static Object getDefaultRecalculationValue(Rollup__mdt meta) {
    // some operations could possibly use either default value
    // we also have to cast to Object to avoid the compilation error:
    // "Incompatible types in null coalescing operator: Decimal, String"
    return (Object) meta.FullRecalculationDefaultNumberValue__c ?? (Object) meta.FullRecalculationDefaultStringValue__c;
  }
}
