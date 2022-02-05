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
  static void shouldReturnSafeFallbackForCurrencyInfo() {
    RollupCurrencyInfo.IS_MULTICURRENCY = false;

    RollupCurrencyInfo fallbackInfo = RollupCurrencyInfo.getCurrencyInfo('USD');

    System.assertNotEquals(null, fallbackInfo);
  }
}
