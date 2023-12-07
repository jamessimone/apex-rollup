@IsTest
private class RollupMultiCurrencyTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupMultiCurrencyTests.class.getName());
    insert acc;

    Opportunity opp = new Opportunity(
      Name = 'Rollup Multicurrency',
      StageName = 'One',
      CloseDate = System.today(),
      Amount = 1,
      AccountIdText__c = acc.Id,
      AccountId = acc.Id
    );
    RollupCurrencyInfo.setCurrencyIsoCode(opp, 'USD');

    insert opp;
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void doesNotQueryDatedCurrenciesForNonMatchingObject() {
    Integer currentQueryCount = Limits.getQueries();
    Account acc = new Account();

    RollupCurrencyInfo.transform(new List<Account>{ acc }, Account.AnnualRevenue, getCurrencyIsoCode(acc), new List<RollupOrderBy__mdt>());

    Assert.areEqual(currentQueryCount + 1, Limits.getQueries());
  }

  @IsTest
  static void shouldCorrectlyRollupMaxForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MAX',
        CalcItem__c = 'Opportunity'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<Schema.SObjectField>{ Account.AnnualRevenue, Account.MaxAmountRollupSummary__c });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.MaxAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency MAX rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupMinForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MIN',
        IsFullRecordSet__c = true,
        CalcItem__c = 'Opportunity'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<Schema.SObjectField>{ Account.AnnualRevenue, Account.MinAmountRollupSummary__c });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.MinAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency MIN rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupSumForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        IsFullRecordSet__c = true,
        CalcItem__c = 'Opportunity'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;
    Rollup.onlyUseMockMetadata = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<Schema.SObjectField>{ Account.AnnualRevenue, Account.SumAmountRollupSummary__c });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.SumAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency SUM rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupAverageForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'AVERAGE',
        CalcItem__c = 'Opportunity'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    List<SObject> opportunities = UserInfo.isMultiCurrencyOrganization()
      ? Database.query('SELECT Id, convertCurrency(Amount) ConvertedAmount FROM Opportunity')
      : [SELECT MAX(Amount) ConvertedAmount, Id FROM Opportunity GROUP BY Id];
    Decimal convertedAmountSum = 0;
    for (SObject opp : opportunities) {
      convertedAmountSum += (Decimal) opp.get('ConvertedAmount');
    }
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    Decimal expectedAverage = (convertedAmountSum / opportunities.size()) * currencyInfo.ConversionRate;

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(
      expectedAverage.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency AVERAGE rollup not calculated correctly! Records: ' + opportunities
    );
  }

  @IsTest
  static void shouldCorrectlyRollupFirstForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'FIRST',
        CalcItem__c = 'Opportunity'
      ),
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Amount') }
    );
    Rollup.rollupMetadata = new List<Rollup__mdt>{ meta };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Decimal firstAmount;
    Id firstOpportunityId;
    List<SObject> opportunities = UserInfo.isMultiCurrencyOrganization()
      ? Database.query('SELECT Id, convertCurrency(Amount) ConvertedAmount FROM Opportunity')
      : [SELECT MAX(Amount) ConvertedAmount, Id FROM Opportunity GROUP BY Id];
    for (SObject opp : opportunities) {
      Decimal oppConvertedAmount = (Decimal) opp.get('ConvertedAmount');
      if (firstAmount == null || oppConvertedAmount < firstAmount) {
        firstAmount = oppConvertedAmount;
        firstOpportunityId = opp.Id;
      }
    }

    acc = [SELECT Id, Name FROM Account];
    System.assertEquals(firstOpportunityId, acc.Name, 'Should have taken first based on multi-currency Amount! Records: ' + opportunities);
  }

  @IsTest
  static void shouldCorrectlyRollupLastForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.StageName, Opportunity.CloseDate, Opportunity.Amount, Opportunity.AccountId }
    );

    Opportunity eurOpp = usdOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'LAST',
        CalcItem__c = 'Opportunity'
      ),
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Amount') }
    );
    Rollup.rollupMetadata = new List<Rollup__mdt>{ meta };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.records = new List<Opportunity>{ usdOpp, eurOpp, jpyOpp };
    Rollup.shouldRun = true;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Decimal lastAmount;
    Id lastOpportunityId;
    List<SObject> opportunities = UserInfo.isMultiCurrencyOrganization()
      ? Database.query('SELECT Id, convertCurrency(Amount) ConvertedAmount FROM Opportunity')
      : [SELECT MAX(Amount) ConvertedAmount, Id FROM Opportunity GROUP BY Id];
    for (SObject opp : opportunities) {
      Decimal oppConvertedAmount = (Decimal) opp.get('ConvertedAmount');
      if (lastAmount == null || oppConvertedAmount > lastAmount) {
        lastAmount = oppConvertedAmount;
        lastOpportunityId = opp.Id;
      }
    }

    acc = [SELECT Id, Name FROM Account];
    System.assertEquals(lastOpportunityId, acc.Name, 'Should have taken last based on multi-currency Amount! Records: ' + opportunities);
  }

  private static String getCurrencyIsoCode(SObject record) {
    return UserInfo.isMultiCurrencyOrganization() ? (String) record.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME) : 'USD';
  }
}
