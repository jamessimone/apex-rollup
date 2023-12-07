public without sharing virtual class RollupCurrencyInfo {
  public static final String CURRENCY_ISO_CODE_FIELD_NAME = 'CurrencyIsoCode';

  @TestVisible
  private static List<RollupCurrencyInfo> mockCurrencyData;
  private static final Map<String, SObject> TRANSFORMED_MULTICURRENCY_CALC_ITEMS = new Map<String, SObject>();
  private static final Set<String> HASHED_ITEM_VALUES = new Set<String>();
  private static Date minDatedCurrencyLookup = Date.newInstance(System.today().year(), 1, 1).addYears(-1);
  private static Date maxDatedCurrencyLookup = System.today().addYears(1);
  private static Boolean hasLoadedDatedCurrencyInfo = false;

  // Can't be Schema.SObjectType => Schema.SObjectField because not all orgs have OppLineItems/Splits
  // technically there's a hierarchy for OpportunityLineItem that goes Opportunity.CloseDate > ServiceDate > (ProductDate || ScheduleDate)
  // but because this can be configured on a per-rollup basis, it's fine to leave Opportunity.CloseDate as the default since it can be overridden
  private static final Map<String, List<String>> DATED_MULTICURRENCY_SUPPORTED_OBJECTS = new Map<String, List<String>>{
    'Opportunity' => new List<String>{ 'CloseDate' },
    'OpportunityLineItem' => new List<String>{ 'ServiceDate' },
    'OpportunityLineItemSchedule' => new List<String>{ 'ScheduleDate' },
    'OpportunitySplit' => new List<String>{ 'Opportunity', 'CloseDate' }
  };

  @TestVisible
  private static Boolean IS_MULTICURRENCY {
    get {
      if (IS_MULTICURRENCY == null) {
        IS_MULTICURRENCY = UserInfo.isMultiCurrencyOrganization();
      }
      return IS_MULTICURRENCY;
    }
    set;
  }

  @TestVisible
  private static Boolean IS_DATED_MULTICURRENCY = false;

  private static final RollupCurrencyInfo FALLBACK_INFO {
    get {
      if (FALLBACK_INFO == null) {
        FALLBACK_INFO = new RollupCurrencyInfo();
        FALLBACK_INFO.DecimalPlaces = 2;
        FALLBACK_INFO.ConversionRate = 1;
      }
      return FALLBACK_INFO;
    }
    set;
  }

  private static final Map<String, RollupCurrencyInfo> CURRENCY_ISO_CODE_TO_CURRENCY {
    get {
      if (CURRENCY_ISO_CODE_TO_CURRENCY == null) {
        CURRENCY_ISO_CODE_TO_CURRENCY = getCurrencyMap();
      }
      return CURRENCY_ISO_CODE_TO_CURRENCY;
    }
    set;
  }

  private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> TYPE_TO_FIELDS {
    get {
      if (TYPE_TO_FIELDS == null) {
        TYPE_TO_FIELDS = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();
      }
      return TYPE_TO_FIELDS;
    }
    set;
  }

  public String IsoCode { get; set; }
  public Decimal ConversionRate { get; set; }
  public Integer DecimalPlaces { get; set; }
  // next two fields only available for DatedConversionRate-based RollupCurrencyInfos
  public Date StartDate { get; set; }
  public Date NextStartDate { get; set; }

  protected virtual RollupCurrencyInfo getInfo(SObject calcItem, String isoCode) {
    return this;
  }

  protected virtual void addInfo(RollupCurrencyInfo info) {
  }

  public static List<String> getMultiCurrencyFields(Schema.DescribeSObjectResult objectToken) {
    List<String> fields = new List<String>{ CURRENCY_ISO_CODE_FIELD_NAME };
    List<String> fieldMappings = DATED_MULTICURRENCY_SUPPORTED_OBJECTS.get(objectToken.getName());
    if (fieldMappings != null) {
      String concatenatedName = '';
      for (Integer index = 0; index < fieldMappings.size(); index++) {
        concatenatedName += (index == fieldMappings.size() - 1 ? fieldMappings[index] : fieldMappings[index] + '.');
      }
      fields.add(concatenatedName);
    }
    return fields;
  }

  public static void overrideDatedMultiCurrency(String objectName, List<String> fieldNameOverrides) {
    if (IS_MULTICURRENCY) {
      DATED_MULTICURRENCY_SUPPORTED_OBJECTS.put(objectName, fieldNameOverrides);
    }
  }

  public static void transform(List<SObject> calcItems, Schema.SObjectField opFieldOnCalcItem, String parentIsoCode, List<RollupOrderBy__mdt> orderBys) {
    if (IS_MULTICURRENCY) {
      loadProperMinMaxDates(calcItems, opFieldOnCalcItem);
      for (SObject calcItem : calcItems) {
        actuallyTransformCurrency(calcItem, opFieldOnCalcItem, parentIsoCode, orderBys);
      }
    }
  }

  public static Boolean isMultiCurrency() {
    return IS_MULTICURRENCY;
  }

  public static SObject getCalcItem(SObject calcItem) {
    SObject potentiallyTransformedItem = TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(getKey(calcItem));
    return potentiallyTransformedItem != null ? potentiallyTransformedItem : calcItem;
  }

  public static RollupCurrencyInfo getCurrencyInfo(String currencyIsoCode) {
    return CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(currencyIsoCode) ? CURRENCY_ISO_CODE_TO_CURRENCY.get(currencyIsoCode) : FALLBACK_INFO;
  }

  public static void setCurrencyIsoCode(SObject record, String isoCode) {
    if (IS_MULTICURRENCY) {
      record.put(CURRENCY_ISO_CODE_FIELD_NAME, isoCode);
    }
  }

  public static SObject createNewRecord(SObject originalParent) {
    SObject newParent = originalParent.getSObjectType().newSObject(originalParent.Id);
    if (isMultiCurrency()) {
      newParent.put(CURRENCY_ISO_CODE_FIELD_NAME, originalParent.get(CURRENCY_ISO_CODE_FIELD_NAME));
    }
    return newParent;
  }

  private static String getKey(SObject calcItem) {
    return calcItem.Id + ((Object) calcItem).hashCode().format();
  }

  private static void loadProperMinMaxDates(List<SObject> calcItems, Schema.SObjectField rollupField) {
    if (hasLoadedDatedCurrencyInfo || CURRENCY_ISO_CODE_TO_CURRENCY == null) {
      return;
    }
    for (SObject calcItem : calcItems) {
      if (DATED_MULTICURRENCY_SUPPORTED_OBJECTS.containsKey(calcItem.getSObjectType().getDescribe().getName()) == false) {
        return;
      }
      Datetime currencyDate = getCurrencyDate(calcItem);
      if (currencyDate == null) {
        return;
      }
      if (currencyDate < minDatedCurrencyLookup) {
        minDatedCurrencyLookup = currencyDate.date();
      } else if (currencyDate > maxDatedCurrencyLookup) {
        maxDatedCurrencyLookup = currencyDate.date();
      }
    }

    hasLoadedDatedCurrencyInfo = true;
    String query = 'SELECT IsoCode, ConversionRate, StartDate, NextStartDate from DatedConversionRate WHERE StartDate >= :minDatedCurrencyLookup AND NextStartDate <= :maxDatedCurrencyLookup';
    List<RollupCurrencyInfo> datedCurrencyInfos = (List<RollupCurrencyInfo>) JSON.deserialize(
      JSON.serialize(Database.query(query)),
      List<RollupCurrencyInfo>.class
    );
    IS_DATED_MULTICURRENCY = datedCurrencyInfos.isEmpty() == false;
    mapCurrencies(CURRENCY_ISO_CODE_TO_CURRENCY, datedCurrencyInfos);
    IS_DATED_MULTICURRENCY = false;
  }

  private static void actuallyTransformCurrency(
    SObject calcItem,
    Schema.SObjectField opFieldOnCalcItem,
    String parentIsoCode,
    List<RollupOrderBy__mdt> orderBys
  ) {
    if (calcItem.getSObjectType().getDescribe().fields.getMap().containsKey(CURRENCY_ISO_CODE_FIELD_NAME)) {
      String calcItemIsoCode = (String) calcItem.get(CURRENCY_ISO_CODE_FIELD_NAME);
      String transformKey = getKey(calcItem);
      SObject clonedCalcItem = TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(transformKey);
      String hashKey = getHashKey(calcItem, opFieldOnCalcItem);
      if (
        String.isBlank(parentIsoCode) ||
        String.isBlank(calcItemIsoCode) ||
        calcItemIsoCode == parentIsoCode ||
        HASHED_ITEM_VALUES.contains(hashKey) ||
        CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(calcItemIsoCode) == false ||
        CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(parentIsoCode) == false ||
        calcItem.get(opFieldOnCalcItem) == 0
      ) {
        return;
      }
      // the worst possible scenario has occurred - the currencies differ and we haven't already populated the map
      clonedCalcItem = clonedCalcItem == null ? calcItem.clone(true, true, true, true) : clonedCalcItem;
      clonedCalcItem = convertToParentCurrency(calcItem, clonedCalcItem, opFieldOnCalcItem, calcItemIsoCode, parentIsoCode, hashKey);

      for (RollupOrderBy__mdt orderBy : orderBys) {
        Schema.SObjectField orderByFirstLastField = calcItem.getSObjectType().getDescribe().fields.getMap().get(orderBy.FieldName__c);
        if (orderByFirstLastField != null && orderByFirstLastField != opFieldOnCalcItem) {
          String orderByHashKey = getHashKey(calcItem, orderByFirstLastField);
          clonedCalcItem = convertToParentCurrency(calcItem, clonedCalcItem, orderByFirstLastField, calcItemIsoCode, parentIsoCode, orderByHashKey);
        }
      }

      TRANSFORMED_MULTICURRENCY_CALC_ITEMS.put(transformKey, clonedCalcItem);
    }
  }

  private static SObject convertToParentCurrency(
    SObject calcItem,
    SObject clonedCalcItem,
    SObjectField fieldOnCalcItem,
    String calcItemIsoCode,
    String parentIsoCode,
    String hashKey
  ) {
    if (fieldOnCalcItem.getDescribe().getType() != DisplayType.CURRENCY) {
      return clonedCalcItem;
    }

    Decimal calcItemDenominator = (Decimal) calcItem.get(fieldOnCalcItem);
    if (calcItemDenominator != null) {
      Decimal calcItemAmountInOrgCurrency =
        CURRENCY_ISO_CODE_TO_CURRENCY.get(calcItemIsoCode).getInfo(calcItem, calcItemIsoCode).ConversionRate / calcItemDenominator;
      Double calcItemAmountInParentCurrency = (CURRENCY_ISO_CODE_TO_CURRENCY.get(parentIsoCode).getInfo(calcItem, parentIsoCode).ConversionRate /
        calcItemAmountInOrgCurrency)
        .doubleValue();
      Map<String, Schema.SObjectField> fieldNameToField = TYPE_TO_FIELDS.get(calcItem.getSObjectType());
      if (fieldNameToField == null) {
        fieldNameToField = calcItem.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
        TYPE_TO_FIELDS.put(calcItem.getSObjectType(), fieldNameToField);
      }
      clonedCalcItem = RollupCalcItemReplacer.replaceField(clonedCalcItem, fieldNameToField.get(CURRENCY_ISO_CODE_FIELD_NAME), parentIsoCode);
      clonedCalcItem = RollupCalcItemReplacer.replaceField(clonedCalcItem, fieldOnCalcItem, calcItemAmountInParentCurrency);
      HASHED_ITEM_VALUES.add(hashKey);
    }
    return clonedCalcItem;
  }

  private static String getHashKey(SObject calcItem, Schema.SObjectField opFieldOnCalcItem) {
    return '' + calcItem.Id + opFieldOnCalcItem.getDescribe().getName();
  }

  private static Map<String, RollupCurrencyInfo> getCurrencyMap() {
    List<RollupCurrencyInfo> currencyInfos = new List<RollupCurrencyInfo>();
    Map<String, RollupCurrencyInfo> currencyInfoMap = new Map<String, RollupCurrencyInfo>();
    if (mockCurrencyData != null) {
      currencyInfos.addAll(mockCurrencyData);
    } else {
      if (IS_MULTICURRENCY) {
        String query = 'SELECT IsoCode, ConversionRate, DecimalPlaces FROM CurrencyType WHERE IsActive = TRUE';
        currencyInfos.addAll((List<RollupCurrencyInfo>) JSON.deserialize(JSON.serialize(Database.query(query)), List<RollupCurrencyInfo>.class));
      }
    }
    mapCurrencies(currencyInfoMap, currencyInfos);
    return currencyInfoMap;
  }

  private static void mapCurrencies(Map<String, RollupCurrencyInfo> currencyInfoMap, List<RollupCurrencyInfo> currencyInfos) {
    for (RollupCurrencyInfo currencyInfo : currencyInfos) {
      RollupCurrencyInfo mappedInfo = currencyInfoMap.get(currencyInfo.IsoCode);
      if (mappedInfo == null) {
        mappedInfo = IS_DATED_MULTICURRENCY ? new CurrencyFinder(currencyInfo) : currencyInfo;
        currencyInfoMap.put(currencyInfo.IsoCode, mappedInfo);
      }
      mappedInfo.addInfo(currencyInfo);
    }
  }

  private static Datetime getCurrencyDate(SObject calcItem) {
    List<String> itemToDateFieldMapping = DATED_MULTICURRENCY_SUPPORTED_OBJECTS.get(calcItem.getSObjectType().getDescribe().getName());
    switch on itemToDateFieldMapping?.size() {
      when 1 {
        return calcItem.isSet(itemToDateFieldMapping[0]) ? (Datetime) calcItem.get(itemToDateFieldMapping[0]) : null;
      }
      when 2 {
        SObject parentObject = calcItem.getSObject(itemToDateFieldMapping[0]);
        return parentObject != null ? (Datetime) parentObject.get(itemToDateFieldMapping[1]) : null;
      }
      when else {
        return null;
      }
    }
  }

  private class CurrencyFinder extends RollupCurrencyInfo {
    private final List<RollupCurrencyInfo> currencyInfos = new List<RollupCurrencyInfo>();
    private final Map<Id, RollupCurrencyInfo> cachedItemToInfo = new Map<Id, RollupCurrencyInfo>();
    private RollupCurrencyInfo baseInfo;

    public CurrencyFinder(RollupCurrencyInfo info) {
      this.addInfo(info);
    }

    protected override void addInfo(RollupCurrencyInfo info) {
      if (info.StartDate != null) {
        this.currencyInfos.add(info);
      } else {
        this.baseInfo = info;
      }
    }

    protected override RollupCurrencyInfo getInfo(SObject calcItem, String isoCode) {
      if (cachedItemToInfo.containsKey(calcItem.Id)) {
        return cachedItemToInfo.get(calcItem.Id);
      }
      Datetime currencyDate = getCurrencyDate(calcItem);
      if (this.currencyInfos.isEmpty() == false && currencyDate != null) {
        for (RollupCurrencyInfo info : this.currencyInfos) {
          if (info.IsoCode == isoCode && info.NextStartDate > currencyDate && currencyDate >= info.StartDate) {
            cachedItemToInfo.put(calcItem.Id, info);
            return info;
          }
        }
      }
      cachedItemToInfo.put(calcItem.Id, this.baseInfo);
      return this.baseInfo;
    }
  }
}
