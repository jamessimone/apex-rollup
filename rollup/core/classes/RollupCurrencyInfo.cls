public without sharing virtual class RollupCurrencyInfo {
  public static final String CURRENCY_ISO_CODE_FIELD_NAME = 'CurrencyIsoCode';

  @TestVisible
  private static List<RollupCurrencyInfo> mockCurrencyData;
  private static final Map<Id, SObject> TRANSFORMED_MULTICURRENCY_CALC_ITEMS = new Map<Id, SObject>();
  private static final Set<String> HASHED_ITEM_VALUES = new Set<String>();
  private static Date minDatedCurrencyLookup = Date.newInstance(System.today().year(), 1, 1).addYears(-1);
  private static Date maxDatedCurrencyLookup = System.today().addYears(1);
  private static Boolean hasLoadedDatedCurrencyInfo = false;

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
  private static Boolean IS_DATED_MULTICURRENCY {
    get {
      if (IS_DATED_MULTICURRENCY == null) {
        IS_DATED_MULTICURRENCY = Type.forName('DatedConversionRate') != null;
      }
      return IS_DATED_MULTICURRENCY;
    }
    set;
  }

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

  // Can't be Schema.SObjectType => Schema.SObjectField because not all orgs have OppLineItems/Splits
  private static final Map<String, List<String>> DATED_MULTICURRENCY_SUPPORTED_OBJECTS = new Map<String, List<String>>{
    'Opportunity' => new List<String>{ 'CloseDate' },
    'OpportunityLineItem' => new List<String>{ 'ServiceDate' },
    'OpportunityLineItemSchedule' => new List<String>{ 'ScheduleDate' },
    'OpportunitySplit' => new List<String>{ 'OpportunityId', 'CloseDate' } // yikes
  };

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

  public static void transform(List<SObject> calcItems, Schema.SObjectField opFieldOnCalcItem, String parentIsoCode, List<RollupOrderBy__mdt> orderBys) {
    if (IS_MULTICURRENCY) {
      loadProperMinMaxDates(calcItems);
      for (SObject calcItem : calcItems) {
        actuallyTransformCurrency(calcItem, opFieldOnCalcItem, parentIsoCode, orderBys);
      }
    }
  }

  public static Boolean isMultiCurrency() {
    return IS_MULTICURRENCY;
  }

  public static SObject getCalcItem(SObject calcItem) {
    return TRANSFORMED_MULTICURRENCY_CALC_ITEMS.containsKey(calcItem.Id) ? TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(calcItem.Id) : calcItem;
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

  private static void loadProperMinMaxDates(List<SObject> calcItems) {
    if (hasLoadedDatedCurrencyInfo) {
      return;
    }
    hasLoadedDatedCurrencyInfo = true;
    for (SObject calcItem : calcItems) {
      if (DATED_MULTICURRENCY_SUPPORTED_OBJECTS.containsKey(calcItem.getSObjectType().getDescribe().getName()) == false) {
        break;
      }
      Date currencyDate = getCurrencyDate(calcItem);
      if (currencyDate == null) {
        continue;
      } else if (currencyDate < minDatedCurrencyLookup) {
        minDatedCurrencyLookup = currencyDate;
      } else if (currencyDate > maxDatedCurrencyLookup) {
        maxDatedCurrencyLookup = currencyDate;
      }
    }
  }

  private static void actuallyTransformCurrency(
    SObject calcItem,
    Schema.SObjectField opFieldOnCalcItem,
    String parentIsoCode,
    List<RollupOrderBy__mdt> orderBys
  ) {
    if (calcItem.getSObjectType().getDescribe().fields.getMap().containsKey(CURRENCY_ISO_CODE_FIELD_NAME)) {
      String calcItemIsoCode = (String) calcItem.get(CURRENCY_ISO_CODE_FIELD_NAME);
      SObject clonedCalcItem = TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(calcItem.Id);
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

      TRANSFORMED_MULTICURRENCY_CALC_ITEMS.put(calcItem.Id, clonedCalcItem);
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
      clonedCalcItem.put(CURRENCY_ISO_CODE_FIELD_NAME, parentIsoCode);
      if (fieldOnCalcItem.getDescribe().isCalculated() == false) {
        clonedCalcItem.put(fieldOnCalcItem, calcItemAmountInParentCurrency);
      } else {
        clonedCalcItem = RollupCalcItemReplacer.replaceReadOnlyField(clonedCalcItem, fieldOnCalcItem.getDescribe().getName(), calcItemAmountInParentCurrency);
      }
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
      if (IS_DATED_MULTICURRENCY) {
        String query = 'SELECT IsoCode, ConversionRate, StartDate, NextStartDate from DatedConversionRate WHERE StartDate >= :minDatedCurrencyLookup AND NextStartDate <= :maxDatedCurrencyLookup';
        List<RollupCurrencyInfo> datedCurrencyInfos = (List<RollupCurrencyInfo>) JSON.deserialize(
          JSON.serialize(Database.query(query)),
          List<RollupCurrencyInfo>.class
        );
        IS_DATED_MULTICURRENCY = datedCurrencyInfos.isEmpty() == false;
        currencyInfos.addAll(datedCurrencyInfos);
      }
      if (IS_MULTICURRENCY) {
        String query = 'SELECT IsoCode, ConversionRate, DecimalPlaces FROM CurrencyType WHERE IsActive = TRUE';
        currencyInfos.addAll((List<RollupCurrencyInfo>) JSON.deserialize(JSON.serialize(Database.query(query)), List<RollupCurrencyInfo>.class));
      }
    }

    for (RollupCurrencyInfo currencyInfo : currencyInfos) {
      if (currencyInfoMap.containsKey(currencyInfo.IsoCode)) {
        currencyInfoMap.get(currencyInfo.IsoCode).addInfo(currencyInfo);
      } else {
        RollupCurrencyInfo mappedInfo = IS_DATED_MULTICURRENCY ? new CurrencyFinder(currencyInfo) : currencyInfo;
        currencyInfoMap.put(currencyInfo.IsoCode, mappedInfo);
      }
    }
    return currencyInfoMap;
  }

  private static Date getCurrencyDate(SObject calcItem) {
    List<String> itemToDateFieldMapping = DATED_MULTICURRENCY_SUPPORTED_OBJECTS.get(calcItem.getSObjectType().getDescribe().getName());
    if (itemToDateFieldMapping?.isEmpty() == false && calcItem.isSet(itemToDateFieldMapping[0])) {
      return itemToDateFieldMapping.size() == 1
        ? (Date) calcItem.get(itemToDateFieldMapping[0])
        : (Date) calcItem.getSObject(itemToDateFieldMapping[0]).get(itemToDateFieldMapping[1]);
    }
    return null;
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
      Date currencyDate = getCurrencyDate(calcItem);
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
