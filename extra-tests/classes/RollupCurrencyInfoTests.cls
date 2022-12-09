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
    RollupCurrencyInfo.transformForMultiCurrencyOrgs(opp, Opportunity.Amount, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    opp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp);
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
    RollupCurrencyInfo.transformForMultiCurrencyOrgs(opp, Opportunity.Amount, 'EUR', new List<RollupOrderBy__mdt>());

    opp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp);
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
    RollupCurrencyInfo.transformForMultiCurrencyOrgs(camp, Campaign.BudgetedCost, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    Campaign updatedCamp = (Campaign) RollupCurrencyInfo.getCalcItem(camp);
    System.assertEquals(mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.BudgetedCost), updatedCamp.BudgetedCost);

    // now for the second field update
    RollupCurrencyInfo.transformForMultiCurrencyOrgs(camp, Campaign.ActualCost, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());
    updatedCamp = (Campaign) RollupCurrencyInfo.getCalcItem(camp);
    System.assertEquals(mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.ActualCost), updatedCamp.ActualCost);
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
    opp = (Opportunity) RollupTestUtils.queryRecord(opp.Id, new List<Schema.SObjectField>{ currencyFormulaToken });

    RollupCurrencyInfo.transformForMultiCurrencyOrgs(opp, currencyFormulaToken, mockEurInfo.IsoCode, new List<RollupOrderBy__mdt>());

    Opportunity updatedOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp);
    System.assertEquals(mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / opp.AmountFormula__c), updatedOpp.AmountFormula__c);
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
    RollupCurrencyInfo.loadChildItemInfo(opps, Opportunity.Amount, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());

    firstOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opps.get(0));
    secondOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(opps.get(1));

    // TODO finish me
    System.assert(false, firstOpp.Amount);
  }
}
