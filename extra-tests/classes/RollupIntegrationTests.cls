@isTest
private class RollupIntegrationTests {
  // "Integration," in the sense that these include custom fields that shouldn't be installed
  // we still don't need to actually update the records to prove the point
  @TestSetup
  static void setup() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = new Account(Name = 'RollupIntegrationTests');
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
    insert opp;
  }

  @isTest
  static void shouldWorkUsingCustomFieldWithCmdt() {
    Account prior = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, prior.AnnualRevenue, 'Test has started under the wrong conditions!');
    Rollup.records = [SELECT Id, Amount, AccountIdText__c FROM Opportunity];
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountIdText__c',
        LookupFieldOnLookupObject__c = 'AccountIdText__c',
        RollupFieldOnLookupObject__c = 'Account.AnnualRevenue',
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

  @isTest
  static void shouldSupportFormulaFieldsOnChildObjectsOnFullRecordSet() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under the wrong conditions!');
    List<Opportunity> opps = [SELECT Id, Name, AmountFormula__c, AccountId FROM Opportunity];
    System.assertEquals(1, opps[0].AmountFormula__c, 'Test has started with wrong opp conditions!');
    Rollup.records = opps;
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
        CalcItemWhereClause__c = 'Name != \'' + opps[0].Name + '\'',
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

  @isTest
  static void shouldSupportCustomObjectsReferencedViaCustomMetadata() {
    Application__c app = new Application__c(Name = 'RollupIntegrationTests App');
    insert app;

    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Lead'),
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Account')
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
    System.assertEquals('Lead, Account', app.Objects__c);
  }

  @isTest
  static void shouldProperlyAverageWithSpecialFieldNamesAndFilteredItems() {
    ParentApplication__c parentApp = new ParentApplication__c(Name = 'Hi');
    insert parentApp;

    String baseId = Application__c.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(11);
    List<Application__c> applications = new List<Application__c>{
      new Application__c(Id = baseId + 1, Something_With_Underscores__c = 'We have and in the name', ParentApplication__c = parentApp.Id, Engagement_Score__c = 40),
      new Application__c(Id = baseId + 2, Something_With_Underscores__c = 'We have and in the name', ParentApplication__c = parentApp.Id, Engagement_Score__c = 40),
      new Application__c(Id = baseId + 3, Something_With_Underscores__c = 'Financial Services', ParentApplication__c = parentApp.Id, Engagement_Score__c = 30),
      new Application__c(Id = baseId + 4, Something_With_Underscores__c = 'Backslashes/Too', ParentApplication__c = parentApp.Id, Engagement_Score__c = 5),
      new Application__c(Id = baseId + 5, Something_With_Underscores__c = 'Something & Something Else', ParentApplication__c = parentApp.Id, Engagement_Score__c = 10)
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
    Rollup.performRollup(new List<Rollup.FlowInput>{
      input
    });
    Test.stopTest();

    ParentApplication__c updatedParent = [SELECT Engagement_Rollup__c FROM ParentApplication__c];
    System.assertEquals(45/3, updatedParent.Engagement_Rollup__c, 'Average should be calculated based off of matching items'); 
  }
}
