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
        RollupType__c = 'MAX'
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
        RollupType__c = 'SUM',
        IsFullRecordSet__c = true,
        CalcItemWhereClause__c = 'Name != \'' + opps[0].Name + '\'',
        FullRecalculationDefaultNumberValue__c = 0
      )
    };

    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1, acc.AnnualRevenue, 'Formula field failed to be used correctly!');
  }
}
