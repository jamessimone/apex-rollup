@IsTest
private class RollupCurrencyInfoTests {
  @IsTest
  static void shouldNotHitDivideByZeroError() {
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 0;
    mockUsdInfo.DecimalPlaces = 2;
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = 0;
    mockEurInfo.DecimalPlaces = 2;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };
    Opportunity opp = new Opportunity(Amount = 0);

    RollupCurrencyInfo.setCurrencyIsoCode(opp, mockUsdInfo.IsoCode);
    RollupCurrencyInfo.transform(new List<SObject>{ opp }, Opportunity.Amount, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    opp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp, mockEurInfo.IsoCode);
    System.assertEquals(0, opp.Amount, 'Should make it here without divide by zero error!');
  }

  @IsTest
  static void shouldFallbackToExistingAmountIfFieldIsNull() {
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 0;
    mockUsdInfo.DecimalPlaces = 2;
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = 0;
    mockEurInfo.DecimalPlaces = 2;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

    Opportunity opp = new Opportunity(Amount = null);

    RollupCurrencyInfo.setCurrencyIsoCode(opp, 'USD');
    RollupCurrencyInfo.transform(new List<SObject>{ opp }, Opportunity.Amount, 'EUR', new List<RollupOrderBy__mdt>());

    opp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp, 'EUR');
    System.assertEquals(null, opp.Amount, 'Should make it here without NPE!');
  }

  @IsTest
  static void shouldReturnSafeFallbackForCurrencyInfo() {
    RollupCurrencyInfo.IS_MULTICURRENCY = false;

    RollupCurrencyInfo fallbackInfo = RollupCurrencyInfo.getCurrencyInfo('USD');

    System.assertNotEquals(null, fallbackInfo);
  }

  @IsTest
  static void convertsMultipleFieldsCorrectly() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 1;
    mockUsdInfo.DecimalPlaces = 2;
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = .75;
    mockEurInfo.DecimalPlaces = 2;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

    Campaign camp = new Campaign(Id = RollupTestUtils.createId(Campaign.SObjectType), BudgetedCost = 5, ActualCost = 6);

    RollupCurrencyInfo.setCurrencyIsoCode(camp, mockUsdInfo.IsoCode);
    RollupCurrencyInfo.transform(new List<SObject>{ camp }, Campaign.BudgetedCost, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    Campaign updatedCamp = (Campaign) RollupCurrencyInfo.getCalcItem(camp, mockEurInfo.IsoCode);
    System.assertEquals(mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.BudgetedCost), updatedCamp.BudgetedCost);

    // now for the second field update
    RollupCurrencyInfo.transform(new List<SObject>{ camp }, Campaign.ActualCost, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());
    updatedCamp = (Campaign) RollupCurrencyInfo.getCalcItem(camp, mockEurInfo.IsoCode);
    System.assertEquals((mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.ActualCost)).doubleValue(), updatedCamp.ActualCost);
    // sanity check that updates on previously transformed fields still calculate correctly
    camp.BudgetedCost = 6;
    RollupCurrencyInfo.transform(new List<SObject>{ camp }, Campaign.BudgetedCost, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());
    Campaign again = (Campaign) RollupCurrencyInfo.getCalcItem(camp, mockEurInfo.IsoCode);
    System.assertEquals(
      (mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.BudgetedCost)).setScale(mockEurInfo.DecimalPlaces),
      again.BudgetedCost
    );
  }

  @IsTest
  static void convertsFormulaCurrencyFields() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 1;
    mockUsdInfo.DecimalPlaces = 2;
    mockUsdInfo.IsoCode = 'USD';
    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = .75;
    mockEurInfo.DecimalPlaces = 2;
    mockEurInfo.IsoCode = 'EUR';
    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

    Opportunity opp = new Opportunity(Amount = 50, StageName = 'formula', CloseDate = System.today(), Name = 'Hi');
    insert opp;
    Schema.SObjectfield currencyFormulaToken = Opportunity.AmountFormula__c;
    opp = (Opportunity) RollupTestUtils.queryRecord(opp.Id, new List<Schema.SObjectField>{ currencyFormulaToken, Opportunity.CloseDate });

    RollupCurrencyInfo.transform(new List<SObject>{ opp }, currencyFormulaToken, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    Opportunity updatedOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp, mockEurInfo.IsoCode);
    System.assertEquals((mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / opp.AmountFormula__c)).doubleValue(), updatedOpp.AmountFormula__c);
  }

  @IsTest
  static void retrievesCorrectExchangeRateForDatedCurrency() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    RollupCurrencyInfo.IS_DATED_MULTICURRENCY = true;

    RollupCurrencyInfo usdInfo = new RollupCurrencyInfo();
    usdInfo.ConversionRate = 1;
    usdInfo.IsoCode = 'USD';
    // default dated currency range - all time
    usdInfo.StartDate = Date.newInstance(0, 12, 30);
    usdInfo.NextStartDate = Date.newInstance(9999, 12, 31);

    RollupCurrencyInfo eurPeriodOne = new RollupCurrencyInfo();
    eurPeriodOne.ConversionRate = 1.1;
    eurPeriodOne.IsoCode = 'EUR';
    eurPeriodOne.StartDate = System.today().addDays(-10);
    eurPeriodOne.NextStartDate = System.today().addDays(-5);

    RollupCurrencyInfo eurPeriodTwo = new RollupCurrencyInfo();
    eurPeriodTwo.ConversionRate = 1.2;
    eurPeriodTwo.IsoCode = 'EUR';
    eurPeriodTwo.StartDate = eurPeriodOne.NextStartDate;
    eurPeriodTwo.NextStartDate = System.today().addDays(1);

    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne, eurPeriodTwo };

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, StageName = 'dated currency', CloseDate = System.today().addDays(-7), Name = 'One'),
      new Opportunity(Amount = 100, StageName = 'dated currency', CloseDate = System.today(), Name = 'Two')
    };
    insert opps;
    List<Schema.SObjectField> queryFields = new List<Schema.SObjectField>{ Opportunity.Amount, Opportunity.CloseDate };
    Opportunity firstOpp = (Opportunity) RollupTestUtils.queryRecord(opps[0].Id, queryFields);
    Opportunity secondOpp = (Opportunity) RollupTestUtils.queryRecord(opps[1].Id, queryFields);
    opps.clear();
    opps.add(firstOpp);
    opps.add(secondOpp);

    // quite a bit of ceremony to get here - but finally the method under test
    RollupCurrencyInfo.transform(opps, Opportunity.Amount, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());

    firstOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opps.get(0), eurPeriodOne.IsoCode);
    secondOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opps.get(1), eurPeriodOne.IsoCode);
    System.assertEquals(eurPeriodOne.ConversionRate / (usdInfo.ConversionRate / opps[0].Amount), firstOpp.Amount);
    System.assertEquals(eurPeriodTwo.ConversionRate / (usdInfo.ConversionRate / opps[1].Amount), secondOpp.Amount);
  }

  @IsTest
  static void usesConfiguredDateFieldForAdvancedCurrencyManagement() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    RollupCurrencyInfo.IS_DATED_MULTICURRENCY = true;

    RollupCurrencyInfo usdInfo = new RollupCurrencyInfo();
    usdInfo.ConversionRate = 1;
    usdInfo.IsoCode = 'USD';
    // default dated currency range - all time
    usdInfo.StartDate = Date.newInstance(0, 12, 30);
    usdInfo.NextStartDate = Date.newInstance(9999, 12, 31);

    RollupCurrencyInfo eurPeriodOne = new RollupCurrencyInfo();
    eurPeriodOne.ConversionRate = 1.1;
    eurPeriodOne.IsoCode = 'EUR';
    eurPeriodOne.StartDate = System.today().addDays(-10);
    eurPeriodOne.NextStartDate = System.today().addDays(-5);

    RollupCurrencyInfo eurPeriodTwo = new RollupCurrencyInfo();
    eurPeriodTwo.ConversionRate = 1.2;
    eurPeriodTwo.IsoCode = 'EUR';
    eurPeriodTwo.StartDate = eurPeriodOne.NextStartDate;
    eurPeriodTwo.NextStartDate = System.today().addDays(1);

    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne, eurPeriodTwo };

    // somewhere within eurPeriodOne
    Opportunity firstOpp = new Opportunity(StageName = 'dated currency', CloseDate = System.today().addDays(-7), Name = 'One');
    OpportunityLineItem oliToUpdate = (OpportunityLineItem) RollupCalcItemReplacer.replaceField(
      //                                                            within eurPeriodTwo 👇
      new OpportunityLineItem(Opportunity = firstOpp, Quantity = 1, ServiceDate = System.today(), TotalPrice = 5),
      OpportunityLineItem.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME),
      usdInfo.IsoCode
    );
    List<OpportunityLineItem> olis = new List<OpportunityLineItem>{ oliToUpdate };

    RollupCurrencyInfo.overrideDatedMultiCurrency(olis.getSObjectType().toString(), new List<String>{ 'Opportunity', 'CloseDate' });
    RollupCurrencyInfo.transform(olis, OpportunityLineItem.TotalPrice, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());

    OpportunityLineItem oli = (OpportunityLineItem) RollupCurrencyInfo.getCalcItem(oliToUpdate, eurPeriodOne.IsoCode);
    System.assertEquals(eurPeriodOne.ConversionRate / (usdInfo.ConversionRate / oliToUpdate.TotalPrice), oli.TotalPrice);
  }
}
