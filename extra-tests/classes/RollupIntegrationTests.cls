@IsTest
private class RollupIntegrationTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupIntegrationTests.class.getName());
    insert acc;

    acc.AccountIdText__c = acc.Id;
    update acc;

    Opportunity opp = new Opportunity(
      Name = 'Rollup Integration',
      StageName = 'testInt',
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
  static void shouldWorkUsingCustomFieldWithCmdt() {
    Account prior = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, prior.AnnualRevenue, 'Test has started under the wrong conditions!');
    Rollup.records = new List<Opportunity>{ (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'Amount', 'AccountIdText__c' }) };
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountIdText__c',
        LookupFieldOnLookupObject__c = 'AccountIdText__c',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MAX',
        CalcItem__c = 'Opportunity'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1, acc.AnnualRevenue, 'Custom metadata mapping failed!');
  }

  @IsTest
  static void shouldSupportFormulaFieldsOnChildObjectsOnFullRecordSet() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    Opportunity opp = (Opportunity) RollupTestUtils.queryrecord('Opportunity', new List<String>{ 'AmountFormula__c', 'AccountId' });
    System.assertEquals(1, opp.AmountFormula__c, 'Test has started with wrong opp conditions!');
    Rollup.records = new List<Opportunity>{ opp };
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'AmountFormula__c',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        IsFullRecordSet__c = true,
        CalcItemWhereClause__c = 'Name != \'' + opp.Name + '\'',
        FullRecalculationDefaultNumberValue__c = 0,
        CalcItem__c = 'Opportunity'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'Formula field failed to be used correctly!');
  }

  @IsTest
  static void shouldSupportCustomObjectsReferencedViaCustomMetadata() {
    Application__c app = new Application__c(Name = 'RollupIntegrationTests App');
    insert app;

    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{
      new ApplicationLog__c(Id = RollupTestUtils.createId(ApplicationLog__c.SObjectType), Application__c = app.Id, Object__c = 'Lead'),
      new ApplicationLog__c(Id = RollupTestUtils.createId(ApplicationLog__c.SObjectType), Application__c = app.Id, Object__c = 'Account')
    };

    Rollup.records = appLogs;
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    // the CMDT record actually exists and is queried for; this test is to ensure that the custom object/field references
    // get updated correctly in Rollup

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    app = [SELECT Objects__c FROM Application__c WHERE Id = :app.Id];
    System.assertEquals('Account, Lead', app.Objects__c);
  }

  @IsTest
  static void shouldProperlyAverageWithSpecialFieldNamesAndFilteredItems() {
    Rollup.onlyUseMockMetadata = true;
    ParentApplication__c parentApp = new ParentApplication__c(Name = 'Hi');
    insert parentApp;

    String baseId = Application__c.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(11);
    List<Application__c> applications = new List<Application__c>{
      new Application__c(
        Id = baseId + 1,
        Something_With_Underscores__c = 'We have and in the name',
        ParentApplication__c = parentApp.Id,
        Engagement_Score__c = 40
      ),
      new Application__c(
        Id = baseId + 2,
        Something_With_Underscores__c = 'We have and in the name',
        ParentApplication__c = parentApp.Id,
        Engagement_Score__c = 40
      ),
      new Application__c(Id = baseId + 3, Something_With_Underscores__c = 'Financial Services', ParentApplication__c = parentApp.Id, Engagement_Score__c = 30),
      new Application__c(Id = baseId + 4, Something_With_Underscores__c = 'Backslashes/Too', ParentApplication__c = parentApp.Id, Engagement_Score__c = 5),
      new Application__c(
        Id = baseId + 5,
        Something_With_Underscores__c = 'Something & Something Else',
        ParentApplication__c = parentApp.Id,
        Engagement_Score__c = 10
      )
    };
    Rollup.records = applications;

    Rollup.FlowInput input = new Rollup.FlowInput();
    input.lookupFieldOnCalcItem = 'ParentApplication__c';
    input.lookupFieldOnOpObject = 'Id';
    input.recordsToRollup = applications;
    input.rollupContext = 'INSERT';
    input.rollupFieldOnCalcItem = 'Engagement_Score__c';
    input.rollupFieldOnOpObject = 'Engagement_Rollup__c';
    input.rollupOperation = 'AVERAGE';
    input.rollupSObjectName = 'ParentApplication__c';
    input.calcItemWhereClause = 'Something_With_Underscores__c != \'' + applications[0].Something_With_Underscores__c + '\'';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ input });
    Test.stopTest();

    ParentApplication__c updatedParent = [SELECT Engagement_Rollup__c FROM ParentApplication__c];
    System.assertEquals(45 / 3, updatedParent.Engagement_Rollup__c, 'Average should be calculated based off of matching items');
  }

  @IsTest
  static void shouldCorrectlyRollupMaxForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<String>{ 'AnnualRevenue', 'MaxAmountRollupSummary__c' });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.MaxAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency MAX rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupMinForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<String>{ 'AnnualRevenue', 'MinAmountRollupSummary__c' });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.MinAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency MIN rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupSumForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<String>{ 'AnnualRevenue', 'SumAmountRollupSummary__c' });
    RollupCurrencyInfo currencyInfo = RollupCurrencyInfo.getCurrencyInfo(getCurrencyIsoCode(acc));
    System.assertEquals(
      acc.SumAmountRollupSummary__c.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency SUM rollup not calculated correctly!'
    );
  }

  @IsTest
  static void shouldCorrectlyRollupAverageForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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

    acc = (Account) RollupTestUtils.queryRecord(acc.Id, new List<String>{ 'AnnualRevenue' });
    System.assertEquals(
      expectedAverage.setScale(currencyInfo.DecimalPlaces),
      acc.AnnualRevenue.setScale(currencyInfo.DecimalPlaces),
      'Multi-currency AVERAGE rollup not calculated correctly! Records: ' + opportunities
    );
  }

  @IsTest
  static void shouldCorrectlyRollupFirstForMultiCurrency() {
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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
    Account acc = (Account) RollupTestUtils.queryRecord('Account', new List<String>{ 'AnnualRevenue' });
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    System.assertEquals('USD', getCurrencyIsoCode(acc), 'Test has started under the wrong conditions!');
    RollupCurrencyInfo.setCurrencyIsoCode(acc, 'EUR');
    update acc;

    Opportunity usdOpp = (Opportunity) RollupTestUtils.queryRecord('Opportunity', new List<String>{ 'StageName', 'CloseDate', 'Amount', 'AccountId' });

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

  @IsTest
  static void shouldSupportCustomObjectsWhenRollupTriggeredFromParent() {
    ParentApplication__c parentApp = new ParentApplication__c(Name = 'Custom Object Parent App');
    insert parentApp;

    List<Application__c> apps = new List<Application__c>{
      new Application__c(Something_With_Underscores__c = 'We have and in the name', ParentApplication__c = parentApp.Id, Engagement_Score__c = 40),
      new Application__c(Something_With_Underscores__c = 'We have and in the name', ParentApplication__c = parentApp.Id, Engagement_Score__c = 40),
      new Application__c(Something_With_Underscores__c = 'Financial Services', ParentApplication__c = parentApp.Id, Engagement_Score__c = 30),
      new Application__c(Something_With_Underscores__c = 'Backslashes/Too', ParentApplication__c = parentApp.Id, Engagement_Score__c = 5),
      new Application__c(Something_With_Underscores__c = 'Something & Something Else', ParentApplication__c = parentApp.Id, Engagement_Score__c = 10)
    };
    insert apps;

    Rollup.FlowInput input = new Rollup.FlowInput();
    input.lookupFieldOnCalcItem = 'ParentApplication__c';
    input.lookupFieldOnOpObject = 'Id';
    input.recordsToRollup = new List<ParentApplication__c>{ parentApp };
    input.rollupContext = 'INSERT';
    input.rollupFieldOnCalcItem = 'Engagement_Score__c';
    input.rollupFieldOnOpObject = 'Engagement_Rollup__c';
    input.rollupOperation = 'SUM';
    input.rollupSObjectName = 'ParentApplication__c';
    input.isRollupStartedFromParent = true;
    input.calcItemTypeWhenRollupStartedFromParent = 'Application__c';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ input });
    Test.stopTest();

    ParentApplication__c updatedParent = [SELECT Engagement_Rollup__c FROM ParentApplication__c];
    System.assertEquals(125, updatedParent.Engagement_Rollup__c, 'Custom fields should work when rollup started from parent!');
  }

  /** grandparent rollup tests */
  @IsTest
  static void shouldFindGreatGrandParentRelationshipBetweenCustomObjects() {
    // The CurrencyIsoCode field isn't directly used here, but the field will be automatically included by Rollup's queries,
    // so include it on the accounts so the asserts below show that the accounts do, in fact, match
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    RollupCurrencyInfo.setCurrencyIsoCode(greatGrandparent, 'USD');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    RollupCurrencyInfo.setCurrencyIsoCode(secondGreatGrandparent, 'USD');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = greatGrandparent.Id);
    ParentApplication__c nonMatchingGrandParent = new ParentApplication__c(Name = 'Non-matching grandparent');
    insert new List<ParentApplication__c>{ grandParent, nonMatchingGrandParent };

    Application__c parent = new Application__c(Name = 'Parent', ParentApplication__c = grandParent.Id);
    Application__c nonMatchingParent = new Application__c(Name = 'Non matching parent', ParentApplication__c = nonMatchingGrandParent.Id);
    insert new List<Application__c>{ parent, nonMatchingParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = parent.Id, Name = 'Test Rollup Grandchildren');
    ApplicationLog__c nonMatchingChild = new ApplicationLog__c(Name = 'Non matching child', Application__c = nonMatchingParent.Id);
    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{ child, nonMatchingChild };
    insert appLogs;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1000),
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Application__r.ParentApplication__r.Account__r.Name'),
      new Set<String>{ 'Id', 'Name' },
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(appLogs);
    System.assertEquals(true, traversal.getIsFinished(), 'Traversal should not have aborted early');
    System.assertEquals(greatGrandparent, traversal.retrieveParent(child.Id), 'Account should match!');

    System.assertEquals(
      null,
      traversal.retrieveParent(nonMatchingChild.Id),
      'No matching records should be returned for relationship that does not go fully up the chain'
    );

    // ok, and can we access the great-grandparent if the lookup field is populated?
    nonMatchingGrandParent.Account__c = secondGreatGrandparent.Id;
    update nonMatchingGrandParent;

    // this also validates that the internal state of the finder is resilient; that it can be called more than once
    traversal = finder.getParents(appLogs);
    System.assertEquals(greatGrandparent, traversal.retrieveParent(child.Id), 'Should still match!');
    System.assertEquals(secondGreatGrandparent, traversal.retrieveParent(nonMatchingChild.Id), 'Should now match!');
  }

  @IsTest
  static void shouldNotBlowUpIfGrandparentsDontExist() {
    Application__c app = new Application__c(Name = 'No grandparent app');
    insert app;

    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Lead'),
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Account')
    };

    Rollup.records = appLogs;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ApplicationLog__c',
        RollupFieldOnCalcItem__c = 'Object__c',
        LookupFieldOnCalcItem__c = 'Application__c',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'Application__r.ParentApplication__r.Account__r.Name'
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    // basically validates that traversal.isAbortedEarly correctly does its job in RollupRleationshipFieldFinder.cls
    System.assert(true, 'Should make it here without exception being thrown');
  }

  @IsTest
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUpdatedFromApex() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = secondGreatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Second grandparent', Account__c = greatGrandparent.Id);
    List<ParentApplication__c> parentApps = new List<ParentApplication__c>{ grandParent, secondGrandparent };
    insert parentApps;

    Application__c parent = new Application__c(Name = 'Parent-level', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Test Rollup Grandchildren Reparenting');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'Reparenting deux', Application__c = parent.Id);
    insert new List<ApplicationLog__c>{ child, secondChild };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ApplicationLog__c',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'Application__c',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = 'Application__r.ParentApplication__r.Account__r.Name'
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Test.startTest();
    parentApps[0].Account__c = greatGrandparent.Id;
    parentApps[1].Account__c = secondGreatGrandparent.Id;
    update parentApps;
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparent.Name, 'Grandparent record should have retriggered greatgrandparent rollup! - apex');
    System.assertEquals(child.Name, updatedGreatGrandparentTwo.Name, 'Grandparent record should have retriggered greatgrandparent rollup again! - apex');
  }

  @IsTest
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUpdatedFromFlow() {
    Rollup.onlyUseMockMetadata = true;
    Account greatGrandparent = new Account(Name = 'Great-grandparent Flow');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent Flow');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent Flow', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Second grandparent Flow', Account__c = secondGreatGrandparent.Id);
    List<ParentApplication__c> parentApps = new List<ParentApplication__c>{ grandParent, secondGrandparent };
    insert parentApps;

    Application__c parent = new Application__c(Name = 'Parent-level Flow', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level Flow', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Test Rollup Grandchildren Reparenting Flow');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'Reparenting deux Flow', Application__c = parent.Id);
    insert new List<ApplicationLog__c>{ child, secondChild };

    Rollup.shouldRun = true;
    Rollup.FlowInput input = new Rollup.FlowInput();
    input.recordsToRollup = parentApps;
    input.calcItemTypeWhenRollupStartedFromParent = 'ApplicationLog__c';
    input.rollupFieldOnCalcItem = 'Name';
    input.lookupFieldOnCalcItem = 'Application__c';
    input.rollupSObjectName = 'Account';
    input.lookupFieldOnOpObject = 'Id';
    input.rollupFieldOnOpObject = 'Name';
    input.rollupOperation = 'CONCAT_DISTINCT';
    input.rollupContext = 'UPDATE';
    input.grandparentRelationshipFieldPath = 'Application__r.ParentApplication__r.Account__r.Name';
    input.oldRecordsToRollup = new List<ParentApplication__c>{
      new ParentApplication__c(Id = grandParent.Id, Account__c = secondGreatGrandparent.Id),
      new ParentApplication__c(Id = secondGrandparent.Id, Account__c = greatGrandparent.Id)
    };

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ input });
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparent.Name, 'Grandparent record should have retriggered greatgrandparent rollup! - flow');
    System.assertEquals(child.Name, updatedGreatGrandparentTwo.Name, 'Grandparent record should have retriggered greatgrandparent rollup again! - flow');
  }

  @IsTest
  static void shouldAllowIntermediateCustomObjectCalcItemWhereClauseFiltering() {
    Rollup.onlyUseMockMetadata = true;
    Account greatGrandparent = new Account(Name = 'Great-grandparent NonFiltered');
    insert greatGrandparent;

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent NonFiltered', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Should be filtered grandparent', Account__c = greatGrandparent.Id);
    insert new List<ParentApplication__c>{ grandParent, secondGrandparent };

    Application__c parent = new Application__c(Name = 'Parent-level NonFiltered', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level filtered', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Should not be appended since application should be filtered');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'Should correctly be appended', Application__c = parent.Id);
    ApplicationLog__c nonMatchChild = new ApplicationLog__c(Name = 'nonmatch', Application__c = parent.Id);
    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{ child, secondChild, nonMatchChild };
    insert appLogs;

    Rollup.records = appLogs;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ApplicationLog__c',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'Application__c',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = 'Application__r.ParentApplication__r.Account__r.Name',
        CalcItemWhereClause__c = 'Application__r.Name != \'' +
          secondParent.Name +
          '\' AND Application__r.ParentApplication__r.Name != \'' +
          grandParent.Name +
          '\' AND Name != \'' +
          nonMatchChild.Name +
          '\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    System.assertEquals(greatGrandparent.Name, updatedGreatGrandparent.Name, 'Great-grandparent name should not have been appended based on exclusions');
  }

  @IsTest
  static void shouldProperlyFilterPolymorphicWhatFields() {
    Account acc = new Account(Name = 'Matching type');
    Case cas = new Case();
    insert new List<SObject>{ acc, cas };

    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'Prospecting', Name = 'parent opp', AccountId = acc.Id);
    insert opp;

    Task matchingTask = new Task(ActivityDate = System.today(), WhatId = opp.Id, Subject = 'Match');
    Task nonMatchingTask = new Task(ActivityDate = System.today(), WhatId = cas.Id, Subject = 'Non match');
    List<Task> tasks = new List<Task>{ matchingTask, nonMatchingTask };
    insert tasks;

    // things like What.Type aren't included by default in updates made within Triggers/Flows
    // specifically NOT requerying here validates that Rollup can handle a polymorphic where clause
    Rollup.records = tasks;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = 'What.Account.Name',
        CalcItemWhereClause__c = 'What.Type = \'Opportunity\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT Name FROM Account WHERE Id = :acc.Id];
    System.assertEquals(matchingTask.Subject + ', ' + acc.Name, updatedAcc.Name, 'Only matching task subject should have been appended via What.Type');
  }

  @IsTest
  static void shouldWorkEvenIfPolymorphicFieldsAreIncluded() {
    Account acc = new Account(Name = 'Matching type');
    insert acc;

    Opportunity opp = new Opportunity(CloseDate = System.today(), StageName = 'Prospecting', Name = 'parent opp', AccountId = acc.Id);
    insert opp;

    Task matchingTask = new Task(ActivityDate = System.today(), WhatId = opp.Id, Subject = 'Match');
    insert matchingTask;

    Rollup.records = [SELECT Id, Subject, What.Type, WhatId FROM Task];
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = 'What.Account.Name',
        CalcItemWhereClause__c = 'What.Type = \'Opportunity\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT Name FROM Account WHERE Id = :acc.Id];
    System.assertEquals(
      matchingTask.Subject +
      ', ' +
      acc.Name,
      updatedAcc.Name,
      'Only matching task subject should have been appended via Who.Type requerying'
    );
  }

  @IsTest
  static void shouldProperlyFilterPolymorphicWhoFields() {
    Contact con = new Contact(LastName = 'Polly', Email = 'polly@morhpism.com');
    Lead lead = new Lead(LastName = 'Morphism', Email = 'morphism@polly.com', Company = 'PollyMorphism');
    insert new List<SObject>{ con, lead };

    Task matchingTask = new Task(ActivityDate = System.today(), WhoId = lead.Id, Subject = 'Match');
    Task nonMatchingTask = new Task(ActivityDate = System.today(), WhoId = con.Id, Subject = 'Not a Match');
    List<Task> tasks = new List<Task>{ matchingTask, nonMatchingTask };
    insert tasks;

    Rollup.records = tasks;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhoId',
        LookupObject__c = 'Lead',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'LastName',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItemWhereClause__c = 'Who.Type = \'Lead\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Lead updatedLead = [SELECT LastName FROM Lead WHERE Id = :lead.Id];
    System.assertEquals(matchingTask.Subject + ', ' + lead.LastName, updatedLead.LastName, 'Only matching task should have been appended via Who.Type');
  }

  @IsTest
  static void shouldProperlyFilterPolymorphicOwnerFields() {
    User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId()];
    Lead matchingLead = new Lead(Company = 'Matching polymorphic', LastName = 'Polly', OwnerId = currentUser.Id);
    insert matchingLead;

    Event nonMatchingEvent = new Event(
      ActivityDateTime = System.now(),
      WhoId = matchingLead.Id,
      OwnerId = currentUser.Id,
      Subject = 'Not a Match',
      DurationInMinutes = 30
    );
    List<Event> events = new List<Event>{ nonMatchingEvent };
    insert events;

    Rollup.records = events;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhoId',
        LookupObject__c = 'Lead',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'LastName',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItemWhereClause__c = 'Owner.Name != \'' + currentUser.Name + '\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Lead updatedLead = [SELECT LastName FROM Lead WHERE Id = :matchingLead.Id];
    System.assertEquals(matchingLead.LastName, updatedLead.LastName, 'Lead last name should not have been updated');
  }

  @IsTest
  static void shouldProperlyFilterParentFields() {
    Account acc = [SELECT Id, Name FROM Account];
    Account matchingAccount = new Account(Name = 'Matching');
    insert matchingAccount;

    List<SObject> opps = new List<Opportunity>{
      new Opportunity(Name = 'Non Match 0', AccountId = acc.Id, Amount = 500, StageName = 'hi', CloseDate = System.today()),
      new Opportunity(Name = 'Non Match 1', AccountId = acc.Id, Amount = 500, StageName = 'hi', CloseDate = System.today()),
      new Opportunity(Name = 'Match 0', AccountId = matchingAccount.Id, Amount = 500, StageName = 'hi', CloseDate = System.today()),
      new Opportunity(Name = 'Match 1', AccountId = matchingAccount.Id, Amount = 500, StageName = 'hi', CloseDate = System.today()),
      new Opportunity(Name = 'Match 2', AccountId = matchingAccount.Id, Amount = 500, StageName = 'hi', CloseDate = System.today())
    };
    insert opps;

    Rollup.records = opps;
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Account.Name != \'' + acc.Name + '\''
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(null, acc.AnnualRevenue, 'Calc item where clause should have prevented account from being updated');
    matchingAccount = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :matchingAccount.Id];
    System.assertEquals(1500, matchingAccount.AnnualRevenue);
  }

  @IsTest
  static void shouldNotBlowUpForRecursiveCheckOnFormulaFields() {
    String oppId = RollupTestUtils.createId(Opportunity.SObjectType);
    Opportunity opp = new Opportunity(Amount = 15, AccountId = RollupTestUtils.createId(Account.SObjectType), Id = oppId);
    List<Opportunity> opps = new List<Opportunity>{ opp };
    Formula.recalculateFormulas(opps); // sets the AmountFormula__c field on the opp

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'AmountFormula__c',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match when not recursive');

    RollupEvaluator.stubRequestId = 'somethingElse';
    // re-initialize to trigger recursion detection
    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'AmountFormula__c',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(false, eval.matches(opp), 'Should not match when recursive!');

    opp.Id = oppId.substring(0, oppId.length() - 1) + 'Y';

    System.assertEquals(true, eval.matches(opp), 'Should match recursively if values do not match');
  }

  @IsTest
  static void shouldEvaluateCorrectlyForCustomParentFields() {
    String whereClause = 'RollupParent__r.NumberField__c = 1';
    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupParent__c.SObjectType);
    System.assertEquals(true, eval.matches(new RollupParent__c(NumberField__c = 1)));
  }

  @IsTest
  static void shouldFilterOnFormulaText() {
    String whereClause = 'NameFormula__c = \'GermanyFormula\'';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Account.SObjectType);

    Account acc = new Account(Name = 'Germany');

    System.assertNotEquals(true, eval.matches(acc));

    Formula.recalculateFormulas(new List<Account>{ acc });

    System.assertEquals(true, eval.matches(acc));
  }

  @IsTest
  static void shouldCorrectlyRollupFromTriggerOnMerge() {
    Account parent = [SELECT Id, Name FROM Account];

    // you can only merge contacts / accounts / leads / cases
    Account parentToMerge = new Account(Name = 'Second parent');
    insert parentToMerge;

    List<ContactPointAddress> rollupChildren = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'Child one', ParentId = parent.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'Child two', ParentId = parentToMerge.Id, PreferenceRank = 2)
    };

    // we don't even need the parent account's annual revenue to be set; rather
    // we need to validate that post merge, the rollup is recalculated correctly
    insert rollupChildren;

    // this test relies on AccountTrigger.trigger having AFTER DELETE set up
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MAX',
        // validate calc item where clause works
        CalcItemWhereClause__c = 'Parent.Name = \'' + parent.Name + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'CONCAT'
      ),
      // should be filtered out
      new Rollup__mdt(
        CalcItem__c = 'Account',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'User',
        LookupFieldOnCalcItem__c = 'OwnerId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Username',
        RollupOperation__c = 'CONCAT'
      )
    };

    Test.startTest();
    Database.merge(parent, parentToMerge.Id, true);
    Test.stopTest();

    parent = [SELECT Id, Description, AnnualRevenue FROM Account WHERE Id = :parent.Id];
    System.assertEquals(2, parent.AnnualRevenue, 'Merge should have triggered rollup');
    System.assertEquals(rollupChildren[0].Name + ', ' + rollupChildren[1].Name, parent.Description, 'Second rollup should also have run');
  }

  @IsTest
  static void shouldNotBlowUpIfSomeMergeMetadataHasNoMatchingRecords() {
    Account parent = [SELECT Id, Name FROM Account];

    // this test relies on AccountTrigger.trigger having AFTER DELETE set up
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MAX',
        // validate polymorphic calc item where clause works
        CalcItemWhereClause__c = 'Parent.Name = \'' + parent.Name + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'CONCAT'
      ),
      // should be filtered out
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'COUNT'
      )
    };

    // you can only merge contacts / accounts / leads / cases
    Account parentToMerge = new Account(Name = 'Second parent');
    insert parentToMerge;

    List<ContactPointAddress> rollupChildren = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'Child one', ParentId = parent.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'Child two', ParentId = parentToMerge.Id, PreferenceRank = 2)
    };

    // we don't even need the parent account's annual revenue to be set; rather
    // we need to validate that post merge, the rollup is recalculated correctly
    insert rollupChildren;

    Test.startTest();
    Database.merge(parent, parentToMerge.Id, true);
    Test.stopTest();

    parent = [SELECT Id, Description, AnnualRevenue FROM Account WHERE Id = :parent.Id];
    System.assertEquals(2, parent.AnnualRevenue, 'Merge should have triggered rollup');
    System.assertEquals(rollupChildren[0].Name + ', ' + rollupChildren[1].Name, parent.Description, 'Second rollup should also have run');
  }

  @IsTest
  static void shouldNotCrashForFalseMergePositive() {
    Account acc = [SELECT Id, Name, Description, AnnualRevenue FROM Account];

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'MAX',
        CalcItemWhereClause__c = 'Parent.Name = \'' + acc.Name + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'CONCAT'
      ),
      // should be filtered out
      new Rollup__mdt(
        CalcItem__c = 'Account',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'User',
        LookupFieldOnCalcItem__c = 'OwnerId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Username',
        RollupOperation__c = 'CONCAT'
      )
    };

    Test.startTest();
    delete acc;
    Test.stopTest();

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void shouldConcatDistinctOnUpdateEvenIfNewItemDoesNotMatch() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'test update';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = acc.AccountNumber);
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, Name = 'something else') };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'Name != \'' + acc.AccountNumber + '\''
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AccountNumber FROM Account];
    System.assertEquals(null, updatedAcc.AccountNumber, 'CONCAT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items');
  }

  @IsTest
  static void shouldRetrieveAllCalcItemsOnUpdateConcatDistinct() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'test update';
    update acc;

    ContactPointAddress firstCpa = new ContactPointAddress(ParentId = acc.Id, Name = acc.AccountNumber);
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'something else');
    insert new List<ContactPointAddress>{ firstCpa, cpa };

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, Name = acc.AccountNumber) };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AccountNumber FROM Account];
    System.assertEquals(
      cpa.Name +
      ', ' +
      acc.AccountNumber,
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should have both values when another matching item present'
    );
  }

  @IsTest
  static void shouldProperlyQueryNotLikeCountDistinct() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Testing CPA COUNT_DISTINCT not like');
    insert new List<ContactPointAddress>{ cpa, new ContactPointAddress(ParentId = acc.Id, Name = 'Some other thing') };

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>();
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'Name NOT LIKE \'' + cpa.Name.substring(0, 6) + '%\''
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT should work with NOT LIKE');
  }

  @IsTest
  static void shouldNotIncludeNullForCountDistinct() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Testing CPA COUNT_DISTINCT null PreferenceRank');
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>();
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT should ignore nulls');

    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(PreferenceRank = 10, Id = cpa.Id) };
    Rollup.runFromTrigger();

    updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT on update should ignore nulls');
  }

  @IsTest
  static void shouldNotIncludePriorValueForCountDistinctId() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 5;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Testing CPA COUNT_DISTINCT update');
    insert new List<ContactPointAddress>{ cpa, new ContactPointAddress(ParentId = acc.Id, Name = 'Some other thing') };

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>();
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should not overcount items');
  }

  @IsTest
  static void shouldNotDoubleCountOldParentValueOnUpdate() {
    Account acc = [SELECT Id, Name FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'something else');
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, Name = acc.Name) };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items');
  }

  @IsTest
  static void shouldClearParentValueIfNothingMatchesCountDistinct() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 5;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Testing CPA COUNT_DISTINCT update');
    insert new List<ContactPointAddress>{ cpa, new ContactPointAddress(ParentId = acc.Id, Name = 'Some other thing') };

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>();
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_INSERT should not overcount items');
  }

  @IsTest
  static void shouldCountDistinctOnUpdateEvenIfNewItemDoesNotMatch() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Testing CPA COUNT_DISTINCT update', PreferenceRank = 0);
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, PreferenceRank = 1) };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(0, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items');
  }

  @IsTest
  static void shouldRunSyncWhenFlaggedOnRollupLimit() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'oneCpa'),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'twoCpa')
    };
    insert cpas;

    Rollup.records = cpas;
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);

    // specifically do NOT wrap in Test.startTest() / Test.stopTest() - we need to ensure this happened synchronously
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated sync calc');
  }

  @IsTest
  static void shouldPartiallyDeferRollupCalculationWhenOverLimits() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    Account secondParent = new Account(Name = 'Second parent');
    insert secondParent;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One', PreferenceRank = 1),
      new ContactPointAddress(ParentId = secondParent.Id, Name = 'Two', PreferenceRank = 1)
    };
    insert cpas;

    // start as synchronous rollup to allow for one deferral
    Rollup.defaultControl = new RollupControl__mdt(
      BatchChunkSize__c = 1,
      MaxRollupRetries__c = 1,
      MaxNumberOfQueries__c = 3,
      IsRollupLoggingEnabled__c = true,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous
    );
    Rollup.shouldRun = true;
    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        // use one of the full recalc operations - one SOQL per parent object will get us to defer
        // between lookup items
        RollupOperation__c = 'AVERAGE'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    // validate that queueable ran in addition to sync job
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
    List<Account> updatedAccounts = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, updatedAccounts.size(), 'Both parent items should have been updated!');

    for (Account updatedAcc : updatedAccounts) {
      System.assertEquals(1, updatedAcc.AnnualRevenue, 'Average annual revenue should have been set for both records!');
    }
  }

  @IsTest
  static void shouldNotBlowUpWhenDeferralLeadsToMultipleSObjectsBeingPresent() {
    Account acc = [SELECT Id, OwnerId FROM Account];

    Individual indy = new Individual(LastName = 'Indy');
    insert indy;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One', PreferenceRank = 1),
      new ContactPointAddress(ParentId = indy.Id, Name = 'Two', PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      BatchChunkSize__c = 2,
      MaxRollupRetries__c = 1,
      MaxNumberOfQueries__c = 4,
      IsRollupLoggingEnabled__c = true,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous
    );
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Rollup.shouldRun = true;
    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'AVERAGE'
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Individual',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'ChildrenCount',
        RollupOperation__c = 'COUNT'
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Individual',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'LastName',
        RollupOperation__c = 'CONCAT'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    indy = [SELECT LastName, ChildrenCount FROM Individual];
    System.assertEquals(1, acc.AnnualRevenue, 'Annual revenue should have been averaged properly');
    System.assertEquals(1, indy.ChildrenCount, 'Children count should have been counted correctly');
    System.assertEquals('Indy, Two', indy.LastName, 'LastName should have been concat properly');
  }

  @IsTest
  static void shouldRunDirectlyFromApex() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 5),
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 10)
    };

    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromApex(cpas, TriggerOperation.AFTER_INSERT);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(15, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldDeferUpdateWhenMaxParentRowsLessThanCurrentUpdateRows() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50, Name = 'MaxParentRows');
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Rollup.defaultControl = new RollupControl__mdt(MaxParentRowsUpdatedAtOnce__c = 0, BatchChunkSize__c = 1, IsRollupLoggingEnabled__c = true);

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(50, acc.AnnualRevenue, 'Account should have been updated since the mock is not used async');
  }

  @IsTest
  static void shouldThrowExceptionWhenTryingToOperateOnDisallowedFieldTypes() {
    Account acc = [SELECT Id FROM Account];
    Rollup.records = new List<Task>{ new Task(ActivityDate = System.today(), WhatId = acc.Id) };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;
    RollupAsyncProcessor.shouldRunAsBatch = true;

    Exception ex;
    try {
      Test.startTest();
      Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, Account.Id, Account.BillingAddress, Account.SObjectType).runCalc();
      Test.stopTest();
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
    System.assertEquals('Field: BillingAddress of type: ADDRESS specified invalid for rollup operation', ex.getMessage());
  }

  /** Invocable integration tests */

  @IsTest
  static void shouldTryToUpsertFromFlow() {
    Account acc = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'Upsert Flow Test');
    insert cpa; // aping an after-insert action in Flow

    List<ContactPointAddress> cpas = [SELECT Id, ParentId, CreatedDate, LastModifiedDate, PreferenceRank FROM ContactPointAddress];

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPSERT', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{ null }; // sad but true - this is what flow passes for {!$Record__Prior} on upsert

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(cpas[0].PreferenceRank, updatedAcc.AnnualRevenue, 'pseudo-upsert from flow should act like insert for PreferenceRank');
  }

  @IsTest
  static void shouldResetParentFieldsWhenItemsNoLongerMatch() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true, IsRollupLoggingEnabled__c = true, ReplaceCalcItemsAsyncWhenOverCount__c = 1);
    Account acc = [SELECT Id, Name FROM Account];
    acc.AnnualRevenue = 1.0;
    acc.NumberOfEmployees = 1;
    update acc;

    List<Contact> cons = new List<Contact>{ new Contact(LastName = 'somethingElse', AccountId = acc.Id, Number__c = acc.AnnualRevenue, Phone = '617619111') };
    insert cons;
    Rollup.defaultControl = null;

    Contact oldContact = cons[0].clone(true, true);
    cons[0].lastName = 'soloAdmin'; // simulating an update which has not yet been reflected in the database

    Rollup.FlowInput flowInput = RollupTestUtils.prepareFlowTest(cons, 'UPSERT', 'SUM')[0];
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupFieldOnCalcItem = 'Id';
    flowInput.lookupFieldOnCalcItem = 'AccountId';
    flowInput.calcItemWhereClause = 'LastName != \'soloAdmin\' AND Account.Name = \'' + acc.Name + '\'';
    flowInput.oldRecordsToRollup = new List<Contact>{ oldContact };
    Rollup.FlowInput secondInput = (Rollup.FlowInput) JSON.deserialize(JSON.serialize(flowInput), Rollup.FlowInput.class);
    secondInput.oldRecordsToRollup = flowInput.oldRecordsToRollup; // lost in deserialization
    secondInput.rollupOperation = 'COUNT';
    secondInput.calcItemWhereClause = 'LastName != \'soloAdmin\'';
    secondInput.rollupFieldOnOpObject = 'NumberOfEmployees';
    // also validate that a matching clause does NOT get reset
    Rollup.FlowInput matchingInput = (Rollup.FlowInput) JSON.deserialize(JSON.serialize(flowInput), Rollup.FlowInput.class);
    matchingInput.rollupOperation = 'MAX';
    matchingInput.rollupFieldOnCalcItem = 'Phone';
    matchingInput.oldRecordsToRollup = flowInput.oldRecordsToRollup; // lost in deserialization
    matchingInput.calcItemWhereClause = 'LastName = \'soloAdmin\' AND Account.Name = \'' + acc.Name + '\'';
    matchingInput.rollupFieldOnOpObject = 'Phone';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput, secondInput, matchingInput });
    Test.stopTest();

    Account updatedAccount = [SELECT AnnualRevenue, NumberOfEmployees, Phone FROM Account];
    System.assertEquals(0, updatedAccount.NumberOfEmployees, 'COUNT should be cleared now that calc item no longer matches');
    System.assertEquals(0, updatedAccount.AnnualRevenue, 'SUM should be cleared now that calc item no longer matches');
    System.assertEquals(cons[0].Phone, updatedAccount.Phone, 'MAX should not be cleared since calc item matches');
  }

  @IsTest
  static void shouldFilterNonMatchingRollupsOutOfBatch() {
    Contact con = new Contact(FirstName = 'Something', LastName = 'Required');
    insert con;
    RollupControl__mdt control = RollupControl__mdt.getInstance('Org_Defaults');
    Rollup.FilterResults results = new Rollup.FilterResults();
    results.matchingItemIds.add(con.Id);
    RollupAsyncProcessor batchProcessor = new RollupAsyncProcessor(
      results,
      Contact.FirstName,
      Contact.Id,
      Contact.Id,
      Contact.FirstName,
      Campaign.SObjectType,
      Contact.SObjectType,
      Rollup.Op.CONCAT,
      Rollup.InvocationPoint.FROM_APEX,
      control,
      new Rollup__mdt(
        CalcItem__c = 'Contact',
        RollupFieldOnCalcItem__c = 'FirstName',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Campaign',
        RollupFieldOnLookupObject__c = 'FirstName',
        LookupFieldOnLookupObject__c = 'Id'
      )
    );
    RollupAsyncProcessor conductor = new RollupAsyncProcessor(Rollup.InvocationPoint.FROM_APEX, new List<Contact>{ con }, new Map<Id, SObject>());
    conductor.rollups.add(batchProcessor);
    Test.startTest();
    Database.executeBatch(conductor);
    Test.stopTest();

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void shouldDecrementProperlyOnUpdateWithParentFilterFields() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 500;
    acc.NumberOfEmployees = acc.AnnualRevenue.intValue() + 250;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), ParentId = acc.Id, Name = 'Non-match')
    };
    insert cpas;

    List<SObject> oldFlowRecords = new List<SObject>{
      new ContactPointAddress(PreferenceRank = cpas[0].PreferenceRank, ParentId = acc.Id, Name = 'Two', Id = cpas[0].Id)
    };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].rollupFieldOnOpObject = 'NumberOfEmployees';
    flowInputs[0].oldRecordsToRollup = oldFlowRecords;
    flowInputs[0].calcItemWhereClause = 'Name = \'Two\'';
    flowInputs.addAll(RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM'));
    flowInputs[1].calcItemWhereClause = 'Name = \'Two\' AND Parent.Name = \'' + acc.Name + '\'';
    flowInputs[1].oldRecordsToRollup = oldFlowRecords;
    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(2, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    System.assertEquals(
      null,
      updatedAcc.AnnualRevenue,
      'Calc item where clause with parent filtering should decrement on update when old item matches and new item does not'
    );
    System.assertEquals(250, updatedAcc.NumberOfEmployees, 'Number of employees should also have been decremented');
  }

  /** Schedulable tests */
  @IsTest
  static void shouldThrowExceptionForBadQuery() {
    // it's a date field - you tell ME why this query is invalid!
    String veryBadQuery = 'SELECT MAX(ActivityDate) FROM Task';

    Exception ex;
    try {
      Rollup.schedule('Test bad query', '0 0 0 0 0', veryBadQuery, 'Account', null);
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @IsTest
  static void shouldScheduleSuccessfullyForGoodQuery() {
    String goodQuery = 'SELECT Id, Name FROM ContactPointAddress WHERE CreatedDate > YESTERDAY';

    String jobId = Rollup.schedule('Test good query' + System.now(), '0 0 0 * * ?', goodQuery, 'ContactPointAddress', null);

    System.assertNotEquals(null, jobId);
  }

  private static String getCurrencyIsoCode(SObject record) {
    return UserInfo.isMultiCurrencyOrganization() ? (String) record.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME) : 'USD';
  }
}
