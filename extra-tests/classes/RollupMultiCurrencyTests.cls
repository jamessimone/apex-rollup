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
    Account acc = new Account();

    RollupCurrencyInfo.transform(new List<Account>{ acc }, Account.AnnualRevenue, getCurrencyIsoCode(acc), new List<RollupOrderBy__mdt>());

    // this test was flapping when comparing query counts during packaging despite passing in each multi-currency org
    // previously. normally I don't like to resort to exposing @TestVisible properties but that's preferable to a flapping test
    Assert.isFalse(RollupCurrencyInfo.hasLoadedDatedCurrencyInfo);
  }

  @IsTest
  static void shouldCorrectlyRollupMaxForMultiCurrency() {
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    eurOpp.StageName = 'A';
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    eurOpp.Amount = .95;
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.StageName = 'Z';
    jpyOpp.Amount = 100;
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'StageName',
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

    acc = [SELECT Id, Name FROM Account];
    System.assertEquals('A', acc.Name, 'Should have taken first based on multi-currency Amount!');
  }

  @IsTest
  static void shouldCorrectlyRollupLastForMultiCurrency() {
    if (hasCurrencyInfo('EUR') == false) {
      return;
    }
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
    eurOpp.StageName = 'A';
    Opportunity jpyOpp = eurOpp.clone(false, true);
    RollupCurrencyInfo.setCurrencyIsoCode(jpyOpp, 'JPY');
    jpyOpp.Amount = 100;
    jpyOpp.StageName = 'Z';
    insert new List<Opportunity>{ eurOpp, jpyOpp };

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'StageName',
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

    acc = [SELECT Id, Name FROM Account];
    System.assertEquals('Z', acc.Name, 'Should have taken last based on multi-currency Amount!');
  }

  @IsTest
  static void properlyTracksCurrencyItemsForDifferentParentCurrencies() {
    if (hasCurrencyInfo('EUR') == false || hasCurrencyInfo('JPY') == false) {
      return;
    }
    delete [SELECT Id FROM Opportunity];

    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    acc.AnnualRevenue = 100;
    update acc;
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');

    Opportunity eurOpp = new Opportunity(Name = 'First Parent', StageName = 'a', CloseDate = System.today(), AccountId = acc.Id);
    RollupCurrencyInfo.setCurrencyIsoCode(eurOpp, 'EUR');
    Contract contract = new Contract(AccountId = acc.Id, Name = 'Second Parent');
    RollupCurrencyInfo.setCurrencyIsoCode(contract, 'JPY');
    insert new List<SObject>{ eurOpp, contract };

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt firstParent = new Rollup__mdt(
      RollupFieldOnCalcItem__c = 'AnnualRevenue',
      LookupObject__c = 'Opportunity',
      LookupFieldOnCalcItem__c = 'Id',
      LookupFieldOnLookupObject__c = 'AccountId',
      RollupFieldOnLookupObject__c = 'Amount',
      RollupOperation__c = 'SUM',
      CalcItem__c = 'Account'
    );
    Rollup__mdt secondParent = new Rollup__mdt(
      RollupFieldOnCalcItem__c = 'AnnualRevenue',
      LookupObject__c = 'Contract',
      LookupFieldOnCalcItem__c = 'Id',
      LookupFieldOnLookupObject__c = 'AccountId',
      RollupFieldOnLookupObject__c = 'ContractTerm',
      RollupOperation__c = 'SUM',
      CalcItem__c = 'Account'
    );
    Rollup.rollupMetadata = new List<Rollup__mdt>{ firstParent, secondParent };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;
    Rollup.records = new List<Account>{ acc };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    contract = [SELECT ContractTerm FROM Contract WHERE Id = :contract.Id];
    eurOpp = [SELECT Amount FROM Opportunity WHERE Id = :eurOpp.Id];
    System.assertNotEquals(null, contract.ContractTerm, 'Rollup should have occurred');
    System.assertNotEquals(contract.ContractTerm, eurOpp.Amount);
  }

  private static Boolean hasCurrencyInfo(String currencyCode) {
    return RollupCurrencyInfo.getCurrencyInfo(currencyCode).IsoCode != null;
  }

  private static String getCurrencyIsoCode(SObject record) {
    return UserInfo.isMultiCurrencyOrganization() ? (String) record.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME) : 'USD';
  }
}
