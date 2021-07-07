public without sharing abstract class RollupCalculator {
  private Boolean isCDCUpdate = false;
  private Boolean isFirstTimeThrough = true;
  private Boolean isRecursiveRecalc = false;

  protected final SObjectField opFieldOnCalcItem;
  protected final SObjectField opFieldOnLookupObject;
  protected final SObjectField lookupKeyField;
  protected final Rollup.Op op;
  protected final Rollup__mdt metadata;
  protected final String lookupKeyQuery;
  protected final String lookupRecordKey;

  protected Rollup.Evaluator eval;
  protected Boolean shouldShortCircuit = false;
  protected Object returnVal;
  protected Boolean isLastItem = false;
  protected Boolean shouldTriggerFullRecalc;

  @testVisible
  private static Factory testFactory;

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
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      RollupCalculator calc;
      if (op.name().contains(Rollup.Op.COUNT_DISTINCT.name())) {
        calc = new CountDistinctRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (op.name().contains(Rollup.Op.COUNT.name())) {
        calc = new CountRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (op.name().contains(Rollup.Op.AVERAGE.name())) {
        calc = new AverageRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (op.name().contains(Rollup.Op.FIRST.name()) || op.name().contains(Rollup.Op.LAST.name())) {
        calc = new FirstLastRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (priorVal instanceof Decimal) {
        calc = new DecimalRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (priorVal instanceof String) {
        calc = new PicklistRollupCalculator(
          priorVal,
          op,
          opFieldOnCalcItem,
          opFieldOnLookupObject,
          metadata,
          lookupRecordKey,
          lookupKeyField,
          metadata.ConcatDelimiter__c
        );
      } else if (priorVal instanceof Date) {
        // not obvious: the order of these else if's is of supreme importance
        // Date has to go before Datetime; in the same way that all numbers test true as an instanceof Decimal
        // all Dates test true as Datetimes ...
        calc = new DateRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (priorVal instanceof Time) {
        calc = new TimeRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else if (priorval instanceof Datetime) {
        calc = new DatetimeRollupCalculator(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
      } else {
        throw new IllegalArgumentException('Calculation not defined for: ' + JSON.serialize(priorVal));
      }
      return calc;
    }
  }

  protected RollupCalculator(
    Object priorVal,
    Rollup.Op op,
    SObjectField opFieldOnCalcItem,
    SObjectField opFieldOnLookupObject,
    Object defaultVal,
    Rollup__mdt metadata,
    String lookupRecordKey,
    SObjectField lookupKeyField
  ) {
    this.opFieldOnLookupObject = opFieldOnLookupObject;
    this.opFieldOnCalcItem = opFieldOnCalcItem;
    this.lookupRecordKey = lookupRecordKey;
    this.lookupKeyField = lookupKeyField;
    this.op = op;
    this.metadata = metadata;

    if (defaultVal != null) {
      this.returnVal = defaultVal;
    } else {
      this.returnVal = priorVal == null ? RollupFieldInitializer.Current.getDefaultValue(opFieldOnLookupObject) : priorVal;
    }
    this.lookupKeyQuery =
      lookupKeyField +
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

  public virtual void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
    this.shouldTriggerFullRecalc = true;
    Set<Id> exclusionIds = new Set<Id>();
    for (SObject calcItem : calcItems) {
      if (calcItem.Id != null) {
        exclusionIds.add(calcItem.Id);
      }
    }
    List<SObject> localCalcItems = this.winnowItems(calcItems, oldCalcItems);

    for (Integer index = 0; index < localCalcItems.size(); index++) {
      this.isLastItem = index == localCalcItems.size() - 1;
      SObject calcItem = localCalcItems[index];
      SObject oldCalcItem = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem;
      Boolean doesNotMatch = this.eval?.matches(calcItem) == false || this.eval?.matches(calcItem) == false && this.eval?.matches(oldCalcItem) == false;

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
        this.returnVal = this.calculateNewAggregateValue(this.op, new Set<Id>(), calcItem.getSObjectType());
        // not just a break, a return. We don't want to pass go - we don't want to call "setReturnValue" below
        return;
      } else {
        switch on op {
          when COUNT_DISTINCT, DELETE_COUNT_DISTINCT {
            this.handleCountDistinct(calcItem);
          }
          when UPDATE_COUNT_DISTINCT {
            this.handleUpdateCountDistinct(calcItem, oldCalcItems);
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
    // if, after iterating, every item doesn't match, it's time for a full recalc
    // AVERAGE and FIRST/LAST *also* handle this operation, but they override the entirety of the method we're in
    // ("performRollup"); this means String, Number, and Datetime variant rollup calculations all need to correctly handle
    // recalculating via "calculateNewAggregateValue"
    if (this.shouldTriggerFullRecalc) {
      this.returnVal = this.calculateNewAggregateValue(this.op, exclusionIds, this.getCalcItemType());
      // bail on calling setReturnValue below
      return;
    }
    this.setReturnValue();
  }

  // all of these are no-ops by default; child classes opt-in to the rollup types applicable
  public virtual void handleCountDistinct(SObject calcItem) {
  }
  public virtual void handleUpdateCountDistinct(SObject calcItem, Map<Id, SObject> oldCalcItems) {
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
    List<SObject> temporaryItems = new List<SObject>(items);
    items.clear(); // the List may not be strongly typed, but this is a good way to keep it typed if it is
    for (SObject item : temporaryItems) {
      SObject potentialOldItem = oldCalcItems.containsKey(item.Id) ? oldCalcItems.get(item.Id) : item;
      if (this.eval?.matches(item) != false) {
        items.add(item);
      } else if (this.op == Rollup.Op.UPDATE_COUNT && this.eval?.matches(item) == false && this.eval?.matches(potentialOldItem) == true) {
        // TODO - handle old item matching, new item not matching situation for (other non-full recalc) operations
        items.add(item);
      }
    }

    return items;
  }

  protected SObjectType getCalcItemType() {
    return ((SObject) Type.forName(this.metadata.CalcItem__c).newInstance()).getSObjectType();
  }

  protected virtual Object calculateNewAggregateValue(Rollup.Op op, Set<Id> objIds, SObjectType sObjectType) {
    String operationName = Rollup.getBaseOperationName(op.name());
    String alias = operationName.toLowerCase() + 'Field';
    String query = RollupQueryBuilder.Current.getQuery(
      sObjectType,
      new List<String>{ operationName + '(' + this.opFieldOnCalcItem + ')' + alias },
      'Id',
      '!=',
      this.lookupKeyQuery
    );
    List<SObject> aggregate = Database.query(query);
    return aggregate.isEmpty() == false ? aggregate[0].get(alias) : null;
  }

  protected Boolean isReparented(SObject calcItem, SObject oldCalcItem) {
    return calcItem.get(this.lookupKeyField) != oldCalcItem.get(this.lookupKeyField);
  }

  protected Object performBaseCalculation(Rollup.Op op, Set<Id> objIds, SObjectType sObjectType) {
    this.returnVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnLookupObject);

    if (this.isRecursiveRecalc == false) {
      this.isRecursiveRecalc = true; // now we're cooking with gas

      List<SObject> allOtherItems = Database.query(
        RollupQueryBuilder.Current.getQuery(
          sObjectType,
          new List<String>{ this.metadata.LookupFieldOnCalcItem__c, String.valueOf(this.opFieldOnCalcItem) },
          'Id',
          '!=',
          this.lookupKeyQuery
        )
      );

      if (allOtherItems.isEmpty()) {
        // break out of recursion if there's nothing to calculate
        this.returnVal = null;
      } else {
        Rollup.Op baseOp = Rollup.opNameToOp.get(Rollup.getBaseOperationName(op.name()));
        RollupCalculator calc = Factory.getCalculator(
          this.returnVal,
          baseOp,
          this.opFieldOnCalcItem,
          this.opFieldOnLookupObject,
          this.metadata,
          this.lookupRecordKey,
          this.lookupKeyField
        );
        calc.performRollup(allOtherItems, new Map<Id, SObject>());
        this.returnVal = calc.getReturnValue();
      }
    }
    return this.returnVal;
  }

  private class CountDistinctRollupCalculator extends RollupCalculator {
    private final Set<Object> distinctValues;
    public CountDistinctRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata.FullRecalculationDefaultNumberValue__c, metadata, lookupRecordKey, lookupKeyField);
      this.distinctValues = new Set<Object>();
      if (this.returnVal != RollupFieldInitializer.Current.getDefaultValue(opFieldOnLookupObject)) {
        this.distinctValues.add(this.returnVal);
      }
    }

    protected override void setReturnValue() {
      this.returnVal = this.distinctValues.size();
    }

    protected override void handleShortCircuit(SObject calcItem) {
      Object currentVal = calcItem.get(this.opFieldOnCalcItem);
      if (currentVal != null) {
        this.distinctValues.add(currentVal);
      }
    }

    public override void handleCountDistinct(SObject calcItem) {
      Object potentiallyNullValue = calcItem.get(this.opFieldOnCalcItem);
      if (this.op != Rollup.Op.DELETE_COUNT_DISTINCT && potentiallyNullValue != null) {
        this.distinctValues.add(potentiallyNullValue);
      } else if (this.op == Rollup.Op.DELETE_COUNT_DISTINCT) {
        this.distinctValues.clear();
      }
      this.shouldShortCircuit = true;
      this.calculateNewAggregateValue(this.op, new Set<Id>{ calcItem.Id }, calcItem.getSObjectType());
    }

    public override void handleUpdateCountDistinct(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      SObject oldCalcItem = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem;

      Object currentVal = calcItem.get(this.opFieldOnCalcItem);
      Object priorCalcVal = oldCalcItem.get(this.opFieldOnCalcItem);

      if (currentVal != priorCalcVal || this.isReparented(calcItem, oldCalcItem)) {
        this.distinctValues.add(currentVal);
        this.shouldShortCircuit = true;
        this.calculateNewAggregateValue(this.op, oldCalcItems.keySet(), calcItem.getSObjectType());
      }
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, Set<Id> objIds, SObjectType sObjectType) {
      if (this.shouldTriggerFullRecalc == true) {
        this.distinctValues.clear();
      }
      Boolean isArchivable = sObjectType == Task.SObjectType || sObjectType == Event.SObjectType;
      Boolean isGroupable = isArchivable == false && this.opFieldOnCalcItem.getDescribe().isGroupable();
      List<String> queryFields = new List<String>{ String.valueOf(this.opFieldOnCalcItem) };
      if (isGroupable) {
        queryFields.add('COUNT(Id)');
      }
      String query =
        RollupQueryBuilder.Current.getQuery(sObjectType, queryFields, 'Id', '!=', this.lookupKeyQuery) +
        (isGroupable ? (' GROUP BY ' + this.opFieldOnCalcItem) : '');
      List<SObject> results = Database.query(query);
      for (SObject res : results) {
        // have to use the String representation of the this.opFieldOnCalcItem to avoid:
        // System.SObjectException: SObject.FieldName does not belong to SObject type AggregateResult
        this.distinctValues.add(res.get(this.opFieldOnCalcItem.getDescribe().getName()));
      }
      return this.distinctValues.size();
    }
  }

  private virtual class DecimalRollupCalculator extends RollupCalculator {
    private Decimal returnDecimal;
    public DecimalRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata.FullRecalculationDefaultNumberValue__c, metadata, lookupRecordKey, lookupKeyField);
      this.returnDecimal = (Decimal) this.returnVal;
    }

    protected virtual Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      if (potentiallyUnitializedDecimal instanceof Decimal) {
        return (Decimal) potentiallyUnitializedDecimal;
      } else {
        return potentiallyUnitializedDecimal == null ? 0 : 1;
      }
    }

    protected virtual Decimal getNumericValue(SObject calcItem) {
      return this.getDecimalOrDefault(calcItem.get(this.opFieldOnCalcItem));
    }

    protected virtual Decimal getNumericChangedValue(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      SObject oldCalcItem = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem;

      Decimal newVal = this.getNumericValue(calcItem);

      if (this.isReparented(calcItem, oldCalcItem)) {
        return newVal;
      } else if (this.eval?.matches(calcItem) == true && this.eval?.matches(oldCalcItem) == false) {
        return newVal;
      }

      Decimal oldVal = this.getNumericValue(oldCalcItem);
      // could be negative, could be positive ... could be 0!
      return newVal - oldVal;
    }

    public virtual override Object getReturnValue() {
      if (this.returnVal == RollupFieldInitializer.Current.maximumLongValue || this.returnVal == RollupFieldInitializer.Current.minimumLongValue) {
        this.returnVal = 0;
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
        (this.op.name().contains(Rollup.Op.MAX.name()) && thisPriorVal != 0 && thisPriorVal == this.returnDecimal && newVal <= thisPriorVal) ||
        (this.op.name().contains(Rollup.Op.MIN.name()) &&
        thisPriorVal != 0 &&
        thisPriorVal == this.returnDecimal &&
        newVal >= thisPriorVal)
      ) {
        this.shouldShortCircuit = true;
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, oldCalcItems.keySet(), calcItem.getSObjectType());
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

    protected virtual override Object calculateNewAggregateValue(Rollup.Op op, Set<Id> objIds, SObjectType sObjectType) {
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
      }
      return aggregate;
    }
  }

  private virtual class DatetimeRollupCalculator extends DecimalRollupCalculator {
    public DatetimeRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(((Datetime) priorVal).getTime(), op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
    }

    public virtual override Object getReturnValue() {
      Object superReturnVal = super.getReturnValue();
      if (superReturnVal instanceof Decimal && superReturnVal != 0) {
        superReturnVal = Datetime.newInstance(((Decimal) superReturnVal).longValue());
      }
      return superReturnVal;
    }

    protected virtual override Decimal getDecimalOrDefault(Object potentiallyUnitializedDecimal) {
      if (potentiallyUnitializedDecimal == null) {
        return RollupFieldInitializer.Current.defaultDateTime.getTime();
      }
      // one of the worst things about SOQL is that Datetimes retrieved have the millisecond values truncated
      Datetime datetimeWithMs = potentiallyUnitializedDecimal instanceof Decimal
        ? Datetime.newInstance(((Decimal) potentiallyUnitializedDecimal).longValue())
        : ((Datetime) potentiallyUnitializedDecimal);
      return RollupFieldInitializer.Current.getApexCompliantDatetime(datetimeWithMs).getTime();
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, Set<Id> excludedItems, SObjectType sObjectType) {
      Object aggregate = super.calculateNewAggregateValue(op, excludedItems, sObjectType);
      if (aggregate instanceof Datetime) {
        aggregate = ((Datetime) aggregate).getTime();
      }
      return aggregate;
    }
  }

  private class DateRollupCalculator extends DatetimeRollupCalculator {
    // for Date, it's not necessary to override the "getDecimalOrDefault" method in DatetimeRollupCalculator
    // because the conversion only happens in "getReturnValue"
    public DateRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(
        Datetime.newInstanceGmt((Date) priorVal, Time.newInstance(0, 0, 0, 0)),
        op,
        opFieldOnCalcItem,
        opFieldOnLookupObject,
        metadata,
        lookupRecordKey,
        lookupKeyField
      );
    }

    public override Object getReturnValue() {
      Object superReturnVal = super.getReturnValue();
      return superReturnVal == 0 ? null : ((Datetime) superReturnVal).dateGmt();
    }
  }

  private class TimeRollupCalculator extends DatetimeRollupCalculator {
    public TimeRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(
        Datetime.newInstanceGmt(RollupFieldInitializer.Current.defaultDateTime.dateGmt(), (Time) priorVal),
        op,
        opFieldOnCalcItem,
        opFieldOnLookupObject,
        metadata,
        lookupRecordKey,
        lookupKeyField
      );
    }

    public override Object getReturnValue() {
      Object returnValue = super.getReturnValue();
      if (returnValue instanceof Datetime) {
        returnValue = ((Datetime) returnValue).timeGmt();
      } else if (returnValue == 0) {
        returnValue = null;
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

  private class CountRollupCalculator extends DecimalRollupCalculator {
    public CountRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField);
    }

    public override Object getReturnValue() {
      this.setReturnValue();
      // we shouldn't encourage negative counts. it's totally possible as a rollup is implemented and updates happen before
      // inserts or deletes, but it doesn't really make sense in the context of tracking
      Integer potentialReturnVal = ((Decimal) super.getReturnValue()).intValue();
      return potentialReturnVal < 0 ? 0 : potentialReturnVal;
    }

    protected override Decimal getNumericValue(SObject calcItem) {
      return calcItem.get(this.opFieldOnCalcItem) != null ? 1 : 0;
    }

    protected override Decimal getNumericChangedValue(SObject calcItem, Map<Id, SObject> oldCalcItems) {
      SObject oldCalcItem = oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id) : calcItem;

      // for a reparenting, the item counts towards the new record on an update
      if (this.isReparented(calcItem, oldCalcItem)) {
        return 1;
      }

      // for updates, we have to decrement the count if the value has been cleared out
      Decimal retVal = 0;
      Object current = calcItem.get(this.opFieldOnCalcItem);
      Object prior = oldCalcItem.get(this.opFieldOnCalcItem);
      Object defaultVal = RollupFieldInitializer.Current.getDefaultValue(this.opFieldOnCalcItem);
      if (current == null && prior != null) {
        retVal = -1;
      } else if (current != defaultVal && prior == defaultVal) {
        retVal = 1;
      } else if (this.eval?.matches(oldCalcItem) == false && this.eval?.matches(calcItem) == true) {
        retVal = 1;
      } else if (this.eval?.matches(oldCalcItem) == true && this.eval?.matches(calcItem) == false) {
        retVal = -1;
      }
      return retVal;
    }
  }

  private virtual class StringRollupCalculator extends RollupCalculator {
    protected String concatDelimiter = ', ';
    private String stringVal;

    private final Boolean isConcatDistinct;
    private final Set<Id> concatDistinctIds = new Set<Id>();

    public StringRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField,
      String customConcatDelimiter
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata.FullRecalculationDefaultStringValue__c, metadata, lookupRecordKey, lookupKeyField);
      this.stringVal = (String) this.returnVal;
      if (String.isNotBlank(customConcatDelimiter)) {
        this.concatDelimiter = customConcatDelimiter + ' ';
      }
      this.isConcatDistinct = this.op.name().contains(Rollup.Op.CONCAT_DISTINCT.name());
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

        this.stringVal = (possibleReturnValue.startsWith(trimmedDelimiter)
            ? possibleReturnValue.substring(1, possibleReturnValue.length())
            : possibleReturnValue)
          .trim();
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
      String priorString = String.valueOf((oldCalcItems.containsKey(calcItem.Id) ? oldCalcItems.get(calcItem.Id).get(this.opFieldOnCalcItem) : newVal));
      if (this.shouldConcat(newVal)) {
        this.stringVal = this.replaceWithDelimiter(this.stringVal, priorString, newVal);
      }
    }

    public override void handleDeleteConcat(SObject calcItem) {
      String existingVal = String.valueOf(calcItem.get(this.opFieldOnCalcItem));
      if (String.isBlank(existingVal)) {
        return;
      } else if (this.isConcatDistinct) {
        this.shouldShortCircuit = true;
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
        Object potentialReturnValue = this.calculateNewAggregateValue(this.op, oldCalcItems.keySet(), calcItem.getSObjectType());
        this.stringVal = potentialReturnValue == null ? '' : String.valueOf(potentialReturnValue);
      } else if (this.isTrueFor(newVal, this.stringVal)) {
        this.stringVal = newVal;
      }
    }

    protected override Object calculateNewAggregateValue(Rollup.Op op, Set<Id> objIds, SObjectType sObjectType) {
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

    private void sortAndConcat() {
      List<String> values = this.stringVal.split(this.concatDelimiter);
      for (Integer index = values.size() - 1; index >= 0; index--) {
        if (String.isBlank(values[index])) {
          values.remove(index);
        }
      }
      values.sort();
      this.stringVal = String.join(values, this.concatDelimiter);
    }

    private Boolean shouldConcat(String newVal) {
      Boolean shouldConcat = false;
      Boolean hasVal = String.isNotBlank(newVal);
      if (this.isConcatDistinct == false && hasVal) {
        shouldConcat = true;
      } else if (this.isConcatDistinct && hasVal) {
        List<String> existingVals = this.stringVal.split(this.concatDelimiter);
        Boolean matches = false;
        for (String existingVal : existingVals) {
          matches = existingVal == newVal;
          if (matches) {
            break;
          }
        }
        shouldConcat = matches == false;
      }

      return shouldConcat;
    }

    private String concatWithDelimiter(String newVal) {
      if (String.isBlank(this.stringVal) || this.stringVal.endsWith(this.concatDelimiter)) {
        return newVal + this.concatDelimiter;
      } else {
        return this.concatDelimiter + newVal + this.concatDelimiter;
      }
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
        Set<Id> objIds = this.concatDistinctIds;
        String query = RollupQueryBuilder.Current.getQuery(
          calcItem.getSObjectType(),
          new List<String>{ this.opFieldOnCalcItem.getDescribe().getName() },
          'Id',
          '!=',
          this.lookupKeyQuery
        );
        List<SObject> relatedItems = Database.query(query);
        for (SObject relatedItem : relatedItems) {
          this.handleConcat(relatedItem);
        }
      }
    }
  }

  private class PicklistRollupCalculator extends StringRollupCalculator {
    private final RollupFieldInitializer.PicklistController picklistController;
    private final RollupFieldInitializer.PicklistController rollupFieldController;
    public PicklistRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectfield opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField,
      String customConcatDelimiter
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata, lookupRecordKey, lookupKeyField, customConcatDelimiter);
      this.picklistController = new RollupFieldInitializer.PicklistController(opFieldOnCalcItem.getDescribe());
      this.rollupFieldController = new RollupFieldInitializer.PicklistController(opFieldOnLookupObject.getDescribe());
      if (this.rollupFieldController.isMultiSelectPicklist()) {
        this.concatDelimiter = ';';
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
  }

  private class AverageRollupCalculator extends RollupCalculator {
    public AverageRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(priorVal, op, opFieldOnCalcItem, opFieldOnLookupObject, metadata.FullRecalculationDefaultNumberValue__c, metadata, lookupRecordKey, lookupKeyField);
    }
    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      SObjectType sObjectType = this.getCalcItemType();
      Set<Id> objIds = new Map<Id, SObject>(calcItems).keySet();
      Boolean isArchivable = sObjectType == Task.SObjectType || sObjectType == Event.SObjectType;
      String query = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>{ isArchivable ? 'Id' : 'Count()' }, 'Id', '!=', this.lookupKeyQuery);
      Integer countOfPreExistingItems = isArchivable ? Database.query(query).size() : Database.countQuery(query);

      Decimal oldSum = (Decimal) this.calculateNewAggregateValue(Rollup.Op.SUM, objIds, sObjectType);
      if (oldSum == null) {
        oldSum = 0;
      }

      List<SObject> applicableCalcItems = this.op == Rollup.Op.DELETE_AVERAGE ? new List<SObject>() : calcItems;
      applicableCalcItems = this.winnowItems(applicableCalcItems, oldCalcItems);

      Decimal newSum = 0;
      Decimal currentDenominator = 0;
      for (SObject calcItem : applicableCalcItems) {
        Object potentialDecimal = calcItem.get(this.opFieldOnCalcItem);
        newSum += potentialDecimal == null ? 0 : (Decimal) potentialDecimal;
        currentDenominator++;
      }

      Decimal denominator = countOfPreExistingItems + currentDenominator;
      Decimal average = null;
      // We can't do the division if the denominator is 0
      if (denominator != 0) {
        Decimal numerator = oldSum + newSum;
        average = numerator / denominator;
      }
      this.returnVal = average;
    }
  }

  private class FirstLastRollupCalculator extends RollupCalculator {
    public FirstLastRollupCalculator(
      Object priorVal,
      Rollup.Op op,
      SObjectField opFieldOnCalcItem,
      SObjectField opFieldOnLookupObject,
      Rollup__mdt metadata,
      String lookupRecordKey,
      SObjectField lookupKeyField
    ) {
      super(
        priorVal,
        op,
        opFieldOnCalcItem,
        opFieldOnLookupObject,
        // first/last could possibly use either default value
        // we also have to cast to Object to avoid the compilation error:
        // "Incompatible types in ternary operator: String, Decimal"
        (metadata.FullRecalculationDefaultNumberValue__c != null
          ? (Object) metadata.FullRecalculationDefaultNumberValue__c
          : (Object) metadata.FullRecalculationDefaultStringValue__c),
        metadata,
        lookupRecordKey,
        lookupKeyField
      );
      this.metadata.OrderByFirstLast__c = String.isNotBlank(metadata.OrderByFirstLast__c) ? metadata.OrderByFirstLast__c : metadata.RollupFieldOnCalcItem__c;
    }

    public override void performRollup(List<SObject> calcItems, Map<Id, SObject> oldCalcItems) {
      SObjectType sObjectType = this.getCalcItemType();
      Set<Id> objIds = new Map<Id, SObject>(calcItems).keySet();
      Set<String> queryFields = new Set<String>{
        String.valueOf(this.opFieldOnCalcItem),
        this.metadata.OrderByFirstLast__c,
        this.metadata.LookupFieldOnCalcItem__c
      };
      queryFields.addAll(RollupEvaluator.getWhereEval(this.metadata.CalcItemWhereClause__c, sObjectType).getQueryFields());
      // a full-recalc is always necessary because we don't retain the information about the order by field
      String queryString = RollupQueryBuilder.Current.getQuery(sObjectType, new List<String>(queryFields), 'Id', '!=', this.lookupKeyQuery);

      // we have to exclude the current items on delete, otherwise they'll be incorrectly considered
      List<SObject> additionalItems = Database.query(queryString);
      if (this.op.name().contains('DELETE')) {
        calcItems = additionalItems;
      } else {
        calcItems.addAll(additionalItems);
      }

      calcItems = this.winnowItems(calcItems, oldCalcItems);

      new FirstLastSorter(this.op, this.metadata.OrderByFirstLast__c).sort(calcItems);
      this.returnVal = calcItems.isEmpty() ? null : calcItems[0].get(this.opFieldOnCalcItem);
    }
  }

  private class FirstLastSorter {
    private final Boolean isFirst;
    private final String orderByField;

    private final Integer moveTowardFrontOfList = 1;
    private final Integer moveTowardBackOfList = -1;

    public FirstLastSorter(Rollup.Op op, String orderByField) {
      this.isFirst = op.name().contains(Rollup.Op.FIRST.name());
      this.orderByField = orderByField;
    }

    public Integer compare(Object o1, Object o2) {
      Integer returnVal = 0;
      SObject objOne = (SObject) o1;
      SObject objTwo = (SObject) o2;

      Object potentialFirstVal = objOne.get(this.orderByField);
      Object potentialSecondVal = objTwo.get(this.orderByField);

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

    public void sort(Object[] values) {
      ComparableItem[] wrappedItems = new List<ComparableItem>();

      for (Object value : values) {
        wrappedItems.add(new ComparableItem(this, value));
      }

      wrappedItems.sort();

      values.clear();
      for (ComparableItem item : wrappedItems) {
        values.add(item.value);
      }
    }
  }

  private class ComparableItem implements System.Comparable {
    private final FirstLastSorter sorter;
    private final Object value;

    public ComparableItem(FirstLastSorter sorter, Object value) {
      this.sorter = sorter;
      this.value = value;
    }

    public Integer compareTo(Object o) {
      return this.sorter.compare(this.value, ((ComparableItem) o).value);
    }
  }
}
