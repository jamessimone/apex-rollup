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

    RollupCurrencyInfo.mockCurrencyData = new Map<String, RollupCurrencyInfo>{ mockUsdInfo.IsoCode => mockUsdInfo, mockEurInfo.IsoCode => mockEurInfo };
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

    RollupCurrencyInfo.mockCurrencyData = new Map<String, RollupCurrencyInfo>{ mockUsdInfo.IsoCode => mockUsdInfo, mockEurInfo.IsoCode => mockEurInfo };

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

    RollupCurrencyInfo.mockCurrencyData = new Map<String, RollupCurrencyInfo>{ mockUsdInfo.IsoCode => mockUsdInfo, mockEurInfo.IsoCode => mockEurInfo };

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
}
