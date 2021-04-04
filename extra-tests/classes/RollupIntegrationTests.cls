@isTest
private class RollupIntegrationTests {
  // "Integration," in the sense that these include custom fields / objects that shouldn't be installed
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
    upsert new RollupSettings__c(IsEnabled__c = true);
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

  @isTest
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
  @isTest
  static void shouldFindGreatGrandParentRelationshipBetweenCustomObjects() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
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
      new RollupControl__mdt(MaxQueryRows__c = 1000),
      'Application__r.ParentApplication__r.Account__r.Name',
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

  @isTest
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

  @isTest
  static void shouldRunCorrectlyForGrandparentReparenting() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Second grandparent', Account__c = secondGreatGrandparent.Id);
    insert new List<ParentApplication__c>{ grandParent, secondGrandparent };

    Application__c parent = new Application__c(Name = 'Parent-level', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Test Rollup Grandchildren Reparenting');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'Reparenting deux', Application__c = parent.Id);
    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{ child, secondChild };
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
        GrandparentRelationshipFieldPath__c = 'Application__r.ParentApplication__r.Account__r.Name'
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, SObject>{
      child.Id => new ApplicationLog__c(Id = child.Id, Application__c = parent.Id, Name = greatGrandparent.Name),
      secondChild.Id => new ApplicationLog__c(Id = secondChild.Id, Application__c = secondParent.Id, Name = secondGreatGrandparent.Name)
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparent.Name, 'CONCAT_DISTINCT and reparenting should have worked');
    System.assertEquals(child.Name, updatedGreatGrandparentTwo.Name, 'CONCAT_DISTINCT and reparenting should have worked again');
  }

  @isTest
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUpdated() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Second grandparent', Account__c = secondGreatGrandparent.Id);
    List<ParentApplication__c> parentApps = new List<ParentApplication__c>{ grandParent, secondGrandparent };
    insert parentApps;

    Application__c parent = new Application__c(Name = 'Parent-level', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Test Rollup Grandchildren Reparenting');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'Reparenting deux', Application__c = parent.Id);
    insert new List<ApplicationLog__c>{ child, secondChild };

    Rollup.records = parentApps;
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
    Rollup.oldRecordsMap = new Map<Id, SObject>{
      grandParent.Id => new ParentApplication__c(Id = grandParent.Id, Account__c = secondGreatGrandparent.Id),
      secondGrandparent.Id => new ParentApplication__c(Id = secondGrandparent.Id, Account__c = greatGrandparent.Id)
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparent.Name, 'Grandparent record should have retriggered greatgrandparent rollup!');
    System.assertEquals(child.Name, updatedGreatGrandparentTwo.Name, 'Grandparent record should have retriggered greatgrandparent rollup again!');
  }

  @isTest
  static void shouldAllowIntermediateCustomObjectCalcItemWhereClauseFiltering() {
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
    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{ child, secondChild };
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
        CalcItemWhereClause__c = 'Application__r.Name != \'' + secondParent.Name + '\' AND Application__r.ParentApplication__r.Name != \'' +  grandParent.Name + '\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;


    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    System.assertEquals(greatGrandparent.Name, updatedGreatGrandparent.Name);
  }
}
