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

    Opportunity opp = new Opportunity(Name = 'Rollup Integration', StageName = 'testInt', CloseDate = System.today(), Amount = 1, AccountIdText__c = acc.Id, AccountId = acc.Id);
    insert opp;
  }

  @isTest
  static void shouldWorkUsingCustomFieldWithCmdt() {
    Account prior = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, prior.AnnualRevenue, 'Test has started under the wrong conditions!');
    Rollup.records = [SELECT Id, Amount, AccountIdText__c FROM Opportunity];
    Rollup.shouldRun = true;

    FieldDefinition oppCustomField = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'AccountIdText__c' AND EntityDefinitionId = 'Opportunity'];
    FieldDefinition accCustomField = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'AccountIdText__c' AND EntityDefinitionId = 'Account'];

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Opportunity.Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = oppCustomField.DurableId,
        LookupFieldOnLookupObject__c = accCustomField.DurableId,
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

    FieldDefinition oppCustomField = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'AmountFormula__c' AND EntityDefinitionId = 'Opportunity'];

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = oppCustomField.DurableId,
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'Opportunity.AccountId',
        LookupFieldOnLookupObject__c = 'Account.Id',
        RollupFieldOnLookupObject__c = 'Account.AnnualRevenue',
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

    EntityDefinition appDefinition = [SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = 'Application__c'];
    EntityDefinition appLogDefinition = [SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = 'ApplicationLog__c'];

    FieldDefinition appObjects = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'Objects__c' AND EntityDefinitionId = :appDefinition.DurableId];
    FieldDefinition appId = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'Id' AND EntityDefinitionId = :appDefinition.DurableId];
    FieldDefinition appLogObject = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'Object__c' AND EntityDefinitionId = :appLogDefinition.DurableId];
    FieldDefinition appLogAppLookup = [SELECT DurableId FROM FieldDefinition WHERE QualifiedApiName = 'Application__c' AND EntityDefinitionId = :appLogDefinition.DurableId];

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = appLogDefinition.DurableId,
        RollupFieldOnCalcItem__c = appLogObject.DurableId,
        LookupFieldOnCalcItem__c = appLogAppLookup.DurableId,
        LookupObject__c = appDefinition.DurableId,
        LookupFieldOnLookupObject__c = appId.DurableId,
        RollupFieldOnLookupObject__c = appObjects.DurableId,
        RollupOperation__c = 'CONCAT_DISTINCT'
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    app = [SELECT Objects__c FROM Application__c WHERE Id = :app.Id];
    System.assertEquals('Lead, Account', app.Objects__c);
  }
}
