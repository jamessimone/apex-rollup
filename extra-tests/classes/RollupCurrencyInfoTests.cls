@IsTest
private class RollupCurrencyInfoTests {
  @IsTest
  static void shouldNotHitDivideByZeroError() {
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 0;
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = 0;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };
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
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = 0;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

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
    mockUsdInfo.IsoCode = 'USD';

    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = .75;
    mockEurInfo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

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
    System.assertEquals((mockEurInfo.ConversionRate / (mockUsdInfo.ConversionRate / camp.BudgetedCost)).doubleValue(), again.BudgetedCost);
  }

  @IsTest
  static void convertsFormulaCurrencyFields() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 1;
    mockUsdInfo.IsoCode = 'USD';
    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = .75;
    mockEurInfo.IsoCode = 'EUR';
    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

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

    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>();
    RollupCurrencyInfo.mockDatedCurrencies = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne, eurPeriodTwo };

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Amount = 100, StageName = 'dated currency', CloseDate = eurPeriodOne.StartDate.addDays(2), Name = 'One'),
      new Opportunity(Amount = 100, StageName = 'dated currency', CloseDate = eurPeriodTwo.StartDate.addDays(2), Name = 'Two')
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

    RollupCurrencyInfo unusedStandardEurPeriod = new RollupCurrencyInfo();
    eurPeriodTwo.ConversionRate = 1.5;
    eurPeriodTwo.IsoCode = 'EUR';

    RollupCurrencyInfo.mockBasicCurrencies = new List<RollupCurrencyInfo>{ unusedStandardEurPeriod };
    RollupCurrencyInfo.mockDatedCurrencies = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne, eurPeriodTwo };

    // somewhere within eurPeriodOne
    Opportunity firstOpp = new Opportunity(StageName = 'dated currency', CloseDate = eurPeriodOne.StartDate.addDays(1), Name = 'One');
    OpportunityLineItem oliToUpdate = (OpportunityLineItem) RollupCalcItemReplacer.replaceField(
      //                                                            within eurPeriodTwo 👇
      new OpportunityLineItem(Opportunity = firstOpp, Quantity = 1, ServiceDate = eurPeriodTwo.StartDate.addDays(1), TotalPrice = 5),
      OpportunityLineItem.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME),
      usdInfo.IsoCode
    );
    List<OpportunityLineItem> olis = new List<OpportunityLineItem>{ oliToUpdate };

    RollupCurrencyInfo.overrideDatedMultiCurrency(olis.getSObjectType().toString(), new List<String>{ 'Opportunity', 'CloseDate' });
    RollupCurrencyInfo.transform(olis, OpportunityLineItem.TotalPrice, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());

    OpportunityLineItem oli = (OpportunityLineItem) RollupCurrencyInfo.getCalcItem(oliToUpdate, eurPeriodOne.IsoCode);
    System.assertEquals(eurPeriodOne.ConversionRate / (usdInfo.ConversionRate / oliToUpdate.TotalPrice), oli.TotalPrice);
  }

  @IsTest
  static void requeriesForBoundedDateRangesWhenChildrenDiffer() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }

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
    eurPeriodTwo.StartDate = Date.newInstance(0, 12, 30);
    eurPeriodTwo.NextStartDate = System.today().addDays(-10);
    RollupCurrencyInfo.mockDatedCurrencies = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne };
    Opportunity opp = new Opportunity(StageName = 'a', CloseDate = System.today().addDays(-7), Name = 'One', Amount = 14);
    Opportunity secondOpp = new Opportunity(StageName = 'a', CloseDate = System.today().addYears(-7), Name = 'One', Amount = 14);
    insert new List<Opportunity>{ opp, secondOpp };
    opp = (Opportunity) RollupTestUtils.queryRecord(opp.Id, new List<Schema.SObjectField>{ Opportunity.Amount, Opportunity.CloseDate });
    secondOpp = (Opportunity) RollupTestUtils.queryRecord(secondOpp.Id, new List<Schema.SObjectField>{ Opportunity.Amount, Opportunity.CloseDate });

    RollupCurrencyInfo.transform(new List<Opportunity>{ opp }, Opportunity.Amount, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());

    opp = (Opportunity) RollupCurrencyInfo.getCalcItem(opp, eurPeriodOne.IsoCode);
    System.assertEquals(15.4, opp.Amount);

    RollupCurrencyInfo.mockDatedCurrencies = new List<RollupCurrencyInfo>{ usdInfo, eurPeriodOne, eurPeriodTwo };
    RollupCurrencyInfo.transform(new List<Opportunity>{ secondOpp }, Opportunity.Amount, eurPeriodOne.IsoCode, new List<RollupOrderBy__mdt>());
    secondOpp = (Opportunity) RollupCurrencyInfo.getCalcItem(secondOpp, eurPeriodOne.IsoCode);
    System.assertEquals(16.8, secondOpp.Amount);
  }
}
