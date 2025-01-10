@IsTest
private class RollupIntegrationTests implements Database.Batchable<SObject> {
  @TestSetup
  static void setup() {
    Rollup.onlyUseMockMetadata = true;
    Account acc = new Account(Name = RollupIntegrationTests.class.getName(), Phone = '9999999999');
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
    Rollup.records = new List<Opportunity>{
      (Opportunity) RollupTestUtils.queryRecord(Opportunity.SObjectType, new List<Schema.SObjectField>{ Opportunity.Amount, Opportunity.AccountIdText__c })
    };
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = Opportunity.AccountIdText__c.toString(),
        LookupFieldOnLookupObject__c = Account.AccountIdText__c.toString(),
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
    Opportunity opp = (Opportunity) RollupTestUtils.queryRecord(
      Opportunity.SObjectType,
      new List<Schema.SObjectField>{ Opportunity.AmountFormula__c, Opportunity.AccountId }
    );
    System.assertEquals(1, opp.AmountFormula__c, 'Test has started with wrong opp conditions!');
    Rollup.records = new List<Opportunity>{ opp };
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = Opportunity.AmountFormula__c.toString(),
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
    System.assertEquals(0, acc.AnnualRevenue, 'Formula field failed to be used correctly!');
  }

  @IsTest
  static void shouldSupportCustomObjectsReferencedViaCustomMetadata() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
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
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
    ParentApplication__c parentApp = new ParentApplication__c(Name = 'Hi');
    insert parentApp;

    String baseId = Application__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '0'.repeat(11);
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
    input.lookupFieldOnCalcItem = Application__c.ParentApplication__c.toString();
    input.lookupFieldOnOpObject = 'Id';
    input.recordsToRollup = applications;
    input.rollupContext = 'INSERT';
    input.rollupFieldOnCalcItem = Application__c.Engagement_Score__c.toString();
    input.rollupFieldOnOpObject = ParentApplication__c.Engagement_Rollup__c.toString();
    input.rollupOperation = 'AVERAGE';
    input.rollupSObjectName = ParentApplication__c.SObjectType.toString();
    input.calcItemWhereClause = Application__c.Something_With_Underscores__c.toString() + ' != \'' + applications[0].Something_With_Underscores__c + '\'';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ input });
    Test.stopTest();

    ParentApplication__c updatedParent = [SELECT Engagement_Rollup__c FROM ParentApplication__c];
    System.assertEquals(45 / 3, updatedParent.Engagement_Rollup__c, 'Average should be calculated based off of matching items');
  }

  @IsTest
  static void shouldSupportCustomObjectsWhenRollupTriggeredFromParent() {
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
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
    input.lookupFieldOnCalcItem = Application__c.ParentApplication__c.toString();
    input.lookupFieldOnOpObject = 'Id';
    input.recordsToRollup = new List<ParentApplication__c>{ parentApp };
    input.rollupContext = 'INSERT';
    input.rollupFieldOnCalcItem = Application__c.Engagement_Score__c.toString();
    input.rollupFieldOnOpObject = ParentApplication__c.Engagement_Rollup__c.toString();
    input.rollupOperation = 'SUM';
    input.rollupSObjectName = ParentApplication__c.SObjectType.toString();
    input.isRollupStartedFromParent = true;
    input.calcItemTypeWhenRollupStartedFromParent = Application__c.SObjectType.toString();

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

    Set<String> childrenFieldsToSelect = new Set<String>{ String.valueOf(ApplicationLog__c.Id), String.valueOf(ApplicationLog__c.Name) };
    Set<String> parentFieldsToSelect = new Set<String>{ 'Id', 'Name' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1000),
      new Rollup__mdt(
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
      ),
      childrenFieldsToSelect,
      parentFieldsToSelect,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(appLogs);
    System.assertEquals(true, traversal.getIsFinished(), 'Traversal should not have aborted early');
    System.assertEquals(greatGrandparent, traversal.retrieveParents(child.Id)[0], 'Account should match!');

    System.assertEquals(
      null,
      traversal.retrieveParents(nonMatchingChild.Id),
      'No matching records should be returned for relationship that does not go fully up the chain'
    );

    // ok, and can we access the great-grandparent if the lookup field is populated?
    nonMatchingGrandParent.Account__c = secondGreatGrandparent.Id;
    update nonMatchingGrandParent;

    // this also validates that the internal state of the finder is resilient; that it can be called more than once
    traversal = finder.getParents(appLogs);
    System.assertEquals(greatGrandparent, traversal.retrieveParents(child.Id)[0], 'Should still match!');
    System.assertEquals(secondGreatGrandparent, traversal.retrieveParents(nonMatchingChild.Id)[0], 'Should now match!');
  }

  @IsTest
  static void shouldNotBlowUpIfGrandparentsDontExist() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    Application__c app = new Application__c(Name = 'No grandparent app');
    insert app;

    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Lead'),
      new ApplicationLog__c(Application__c = app.Id, Object__c = 'Account')
    };

    Rollup.records = appLogs;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = ApplicationLog__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = ApplicationLog__c.Object__c.toString(),
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
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
  static void fullRecalculationStartsProperlyOnUpdateWhenOverQueryLimit() {
    Rollup.defaultControl = new RollupControl__mdt(MaxQueryRows__c = 2, MaxRollupRetries__c = 1);
    Rollup.onlyUseMockMetadata = true;
    Account acc = [SELECT Id FROM Account];
    Opportunity priorOpp = [SELECT Amount, StageName FROM Opportunity];
    Opportunity opp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Prospecting', Amount = 5, Name = 'One');
    Opportunity secondOpp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Something', Amount = 5, Name = 'Two');
    insert new List<Opportunity>{ opp, secondOpp };

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnLookupObject__c = 'Id',
        IsFullRecordSet__c = true
      ),
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        RollupOperation__c = 'CONCAT',
        RollupFieldOnLookupObject__c = 'Description',
        RollupFieldOnCalcItem__c = 'StageName',
        LookupFieldOnLookupObject__c = 'Id',
        IsFullRecordSet__c = true
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.records = new List<Opportunity>{ opp };
    Rollup.oldRecordsMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, AccountId = acc.Id) };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAccount = [SELECT Id, AnnualRevenue, Description FROM Account WHERE Id = :acc.Id];
    System.assertEquals(priorOpp.Amount + opp.Amount + secondOpp.Amount, updatedAccount.AnnualRevenue, 'SUM should have fully rolled up');
    System.assertEquals(
      opp.StageName + ', ' + secondOpp.StageName + ', ' + priorOpp.StageName,
      updatedAccount.Description,
      'CONCAT should have fully rolled up'
    );
  }

  @IsTest
  static void performsRollupWhenIntermediateOneToManyChildrenUpdated() {
    Rollup.onlyUseMockMetadata = true;
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 47;
    update acc;
    Account initialParent = new Account(Name = 'Initial', AnnualRevenue = acc.AnnualRevenue);
    insert initialParent;

    Individual indy = new Individual(LastName = 'Indy');
    insert indy;
    Contact con = new Contact(LastName = 'One To Many Child', AccountId = acc.Id, IndividualId = indy.Id);
    insert con;

    Rollup.shouldFlattenAsyncProcesses = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Account',
        LookupObject__c = 'Individual',
        LookupFieldOnCalcItem__c = 'Id',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'ConsumerCreditScore',
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupFieldOnLookupObject__c = 'Id',
        GrandparentRelationshipFieldPath__c = 'Contacts.Individual.ConsumerCreditScore',
        OneToManyGrandparentFields__c = 'Contact.AccountId'
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.records = new List<Contact>{ con };
    Rollup.oldRecordsMap = new Map<Id, Contact>{ con.Id => new Contact(Id = con.Id, AccountId = initialParent.Id) };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Individual updatedIndy = [SELECT Id, ConsumerCreditScore FROM Individual WHERE Id = :indy.Id];
    System.assertEquals(
      acc.AnnualRevenue,
      updatedIndy.ConsumerCreditScore,
      'Apex grandparent rollup should run with reparenting change to intermediate records'
    );
  }

  @IsTest
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUpdatedFromApex() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }

    Rollup.onlyUseMockMetadata = true;
    Rollup.shouldFlattenAsyncProcesses = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = ApplicationLog__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
      )
    };

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
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUndeletedFromApex() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }

    Rollup.onlyUseMockMetadata = true;
    Rollup.shouldFlattenAsyncProcesses = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = ApplicationLog__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
      )
    };

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

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'child one');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'child two', Application__c = parent.Id);
    insert new List<ApplicationLog__c>{ child, secondChild };

    Test.startTest();
    delete parentApps;
    undelete parentApps;
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparentTwo.Name);
    System.assertEquals(child.Name, updatedGreatGrandparent.Name);
  }

  @IsTest
  static void shouldNotRunGrandparentRollupForIntermediateRecordsWhenLookupsAreNotUpdated() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }

    Rollup.onlyUseMockMetadata = true;

    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    List<Account> greatGrandparents = new List<Account>{ greatGrandparent, secondGreatGrandparent };
    insert greatGrandparents;

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
        CalcItem__c = ApplicationLog__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
      )
    };
    RollupAsyncProcessor.stubParentRecords = greatGrandparents;

    Test.startTest();
    parentApps[0].Name = 'Grandparent rename';
    parentApps[1].Name = 'Second grandparent rename';
    update parentApps;
    Test.stopTest();

    System.assertEquals('Great-grandparent', greatGrandparent.Name, 'Great grandparent name should not have been updated');
    System.assertEquals('Second great-grandparent', secondGreatGrandparent.Name);
  }

  @IsTest
  static void shouldRunGrandparentRollupsWhenIntermediateObjectsAreUpdatedFromFlow() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
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
    input.calcItemTypeWhenRollupStartedFromParent = ApplicationLog__c.SObjectType.toString();
    input.rollupFieldOnCalcItem = ApplicationLog__c.Name.toString();
    input.lookupFieldOnCalcItem = ApplicationLog__c.Application__c.toString();
    input.rollupSObjectName = 'Account';
    input.lookupFieldOnOpObject = 'Id';
    input.rollupFieldOnOpObject = 'Name';
    input.rollupOperation = 'CONCAT_DISTINCT';
    input.rollupContext = 'UPDATE';
    String relName = RollupTestUtils.getRelationshipPath(
      new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
    );
    input.grandparentRelationshipFieldPath = relName;
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
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
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
        CalcItem__c = ApplicationLog__c.getSObjectType().toString(),
        RollupFieldOnCalcItem__c = ApplicationLog__c.Name.toString(),
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        ),
        CalcItemWhereClause__c = RollupTestUtils.getRelationshipPath(new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.Name }) +
          ' != \'' +
          secondParent.Name +
          '\' AND ' +
          RollupTestUtils.getRelationshipPath(
            new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Name }
          ) +
          ' != \'' +
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
  static void shouldCountDistinctForGrandparentDeletes() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }

    Rollup.onlyUseMockMetadata = true;
    Rollup.shouldFlattenAsyncProcesses = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = ApplicationLog__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = ApplicationLog__c.Application__c.toString(),
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ ApplicationLog__c.Application__c, Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.Name }
        )
      )
    };

    Account greatGrandparent = new Account(Name = 'Great-grandparent 1');
    insert greatGrandparent;

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent 1', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Grandparent 2', Account__c = greatGrandparent.Id);
    List<ParentApplication__c> parentApps = new List<ParentApplication__c>{ grandParent, secondGrandparent };
    insert parentApps;

    Application__c parent = new Application__c(Name = 'Parent 1', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Parent 2', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = secondParent.Id, Name = 'Will Still Exist');
    ApplicationLog__c secondChild = new ApplicationLog__c(Name = 'To be deleted', Application__c = parent.Id);
    insert new List<ApplicationLog__c>{ child, secondChild };

    Test.startTest();
    delete secondChild;
    Test.stopTest();

    greatGrandparent = [SELECT AnnualRevenue FROM Account WHERE Id = :greatGrandparent.Id];
    Assert.areEqual(1, greatGrandparent.AnnualRevenue, 'Should still count non-deleted great-grandchild');
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
        RollupOperation__c = 'CONCAT',
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
    System.assertEquals(matchingTask.Subject, updatedAcc.Name, 'Only matching task subject should have been appended via What.Type');
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
    System.assertEquals(matchingTask.Subject, updatedAcc.Name, 'Only matching task subject should have been appended via Who.Type requerying');
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
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = 'Who.Type = \'Lead\''
      )
    };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Lead updatedLead = [SELECT LastName FROM Lead WHERE Id = :lead.Id];
    System.assertEquals(matchingTask.Subject, updatedLead.LastName, 'Only matching task should have been appended via Who.Type');
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
        RollupFieldOnCalcItem__c = Opportunity.AmountFormula__c.toString(),
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
        RollupFieldOnCalcItem__c = Opportunity.AmountFormula__c.toString(),
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
    String whereClause = String.valueOf(Account.NameFormula__c) + ' = \'GermanyFormula\'';

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

    List<SObject> rollupChildren = new List<SObject>{
      new ContactPointAddress(Name = 'Child one', ParentId = parent.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'Child two', ParentId = parentToMerge.Id, PreferenceRank = 2),
      new Opportunity(Name = 'opp', AccountId = parentToMerge.Id, Amount = 50, StageName = 'test', CloseDate = System.today())
    };
    Decimal expectedAmount = ((Decimal) rollupChildren[2].get('Amount')) + 1; // another opp is inserted in test setup

    // we don't even need the parent account's rollup fields to be pre-set to anything
    // we need to validate that post merge, each rollup has been recalculated correctly
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
        // validate child object where clause works
        CalcItemWhereClause__c = 'Parent.Name = \'' + parent.Name + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = 'PreferenceRank = 1 OR PreferenceRank = 2'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'SUM'
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

    parent = [SELECT Id, Description, AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :parent.Id];
    System.assertEquals(2, parent.AnnualRevenue, 'Merge should have triggered rollup');
    System.assertEquals(rollupChildren[0].get('Name') + ', ' + rollupChildren[1].get('Name'), parent.Description, 'Second rollup should also have run');
    System.assertEquals(expectedAmount, parent.NumberOfEmployees, 'opp rollup shold have run');
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
        // validate polymorphic child object where clause works
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
      cpa.Name + ', ' + acc.AccountNumber,
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
        CalcItemWhereClause__c = '(NOT Name LIKE \'' + cpa.Name.substring(0, 6) + '%\')'
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
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(PreferenceRank = 10, Id = cpa.Id, ParentId = acc.Id) };
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
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items');
  }

  @IsTest
  static void recursivelyUpdatesEntireHierarchy() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);
    Rollup.shouldFlattenAsyncProcesses = true;
    Rollup.onlyUseMockMetadata = true;
    RollupLimits.stubAsyncTimeoutInterval = 1;
    Account ultimateParent = [SELECT Id FROM Account];

    Account penultimateChildOne = new Account(Name = 'Penultimate Child 1', ParentId = ultimateParent.Id);
    Account penultimateChildTwo = new Account(Name = 'Penultimate Child 2', ParentId = ultimateParent.Id);
    insert new List<Account>{ penultimateChildOne, penultimateChildTwo };

    Account ultimateChildOne = new Account(Name = 'Ultimate child 1', ParentId = penultimateChildOne.Id, AnnualRevenue = 3);
    Account ultimateChildTwo = new Account(Name = 'Ultimate child 2', ParentId = penultimateChildOne.Id, AnnualRevenue = 2);
    Account ultimateChildThree = new Account(Name = 'Ultimate child 3', ParentId = penultimateChildTwo.Id, AnnualRevenue = 5);
    Account ultimateChildFour = new Account(Name = 'Ultimate child 4', ParentId = penultimateChildTwo.Id, AnnualRevenue = 5);
    List<Account> accounts = new List<Account>{ ultimateChildOne, ultimateChildTwo, ultimateChildThree, ultimateChildFour };
    insert accounts;

    Rollup.records = accounts;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'Account'
      )
    };

    // don't wrap in start/stopTest to prove this is all capable of running sync
    Rollup.runFromTrigger();

    penultimateChildOne = [SELECT AnnualRevenue FROM Account WHERE Id = :penultimateChildOne.Id];
    Assert.areEqual(5, penultimateChildOne.AnnualRevenue);
    penultimateChildTwo = [SELECT AnnualRevenue FROM Account WHERE Id = :penultimateChildTwo.Id];
    Assert.areEqual(10, penultimateChildTwo.AnnualRevenue);
    ultimateParent = [SELECT AnnualRevenue FROM Account WHERE Id = :ultimateParent.Id];
    Assert.areEqual(15, ultimateParent.AnnualRevenue);
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
      MaxNumberOfQueries__c = 1,
      MaxRollupRetries__c = 1,
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
      MaxNumberOfQueries__c = 7,
      MaxRollupRetries__c = 1,
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
    System.assertEquals('Two', indy.LastName, 'LastName should have been concat properly');
  }

  @IsTest
  static void shouldRunDirectlyFromApex() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 5),
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 10)
    };

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
  static void shouldRunWithOldRecordsDirectlyFromApex() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 5),
      new ContactPointAddress(Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), ParentId = acc.Id, PreferenceRank = 10)
    };

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
    Rollup.runFromApex(
      cpas,
      new Map<Id, SObject>{
        cpas[0].Id => new ContactPointAddress(Id = cpas[0].Id, ParentId = acc.Id, PreferenceRank = 0),
        cpas[1].Id => new ContactPointAddress(Id = cpas[1].Id, ParentId = acc.Id, PreferenceRank = 0)
      },
      TriggerOperation.AFTER_UPDATE
    );
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
    Rollup.defaultControl = new RollupControl__mdt(MaxParentRowsUpdatedAtOnce__c = 0);

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(50, acc.AnnualRevenue, 'Account should have been updated since the mock is not used async');
  }

  @IsTest
  static void limitsCorrectlyOnInsert() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50, Name = 'One');
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 25, Name = 'Two');
    insert new List<ContactPointAddress>{ cpa, two };

    Rollup.records = new List<ContactPointAddress>{ two };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
      .addLimit(1, ContactPointAddress.PreferenceRank)
      .addOrderBys(new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Name') }, ContactPointAddress.PreferenceRank)
      .runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(cpa.PreferenceRank, acc.AnnualRevenue, 'First inserted cpa amount should have been used');
  }

  @IsTest
  static void limitsCorrectlyOnUpdate() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50, Name = 'A');
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 25, Name = 'B');
    insert new List<ContactPointAddress>{ cpa, two };

    Rollup.records = new List<ContactPointAddress>{ two };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.oldRecordsMap = new Map<Id, SObject>{ two.Id => new ContactPointAddress(Id = two.Id, PreferenceRank = 1) };

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
      .addLimit(1, ContactPointAddress.PreferenceRank)
      .addOrderBys(new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'Name', Ranking__c = 1) }, ContactPointAddress.PreferenceRank)
      .runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(cpa.PreferenceRank, acc.AnnualRevenue, 'First inserted cpa amount should have been used');
  }

  @IsTest
  static void limitsCorrectlyOnDelete() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50, Name = 'One');
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 25, Name = 'Two');
    insert new List<ContactPointAddress>{ cpa, two };

    Rollup.records = new List<ContactPointAddress>{ two };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.BEFORE_DELETE;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
      .addLimit(1, ContactPointAddress.PreferenceRank)
      .runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(cpa.PreferenceRank, acc.AnnualRevenue, 'First inserted cpa amount should have been used');
  }

  @IsTest
  static void distinctCorrectlyQueriesAdditionalChildren() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress one = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'One');
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'Two');
    ContactPointAddress three = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 2, Name = 'Three');
    insert new List<ContactPointAddress>{ one, two, three };

    Rollup.records = new List<ContactPointAddress>{ one };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.Name, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
      .modifyMetadata(new Rollup__mdt(IsDistinct__c = true))
      .runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    Assert.areEqual(3, acc.AnnualRevenue);
  }

  @IsTest
  static void allowsMultipleRollupsToOperateOnSameParentFieldWithRollupGrouping() {
    Account acc = [SELECT Id, Phone, OwnerId FROM Account];
    Assert.areEqual('9999999999', acc.Phone, 'Test has started under the wrong conditions!');
    String winningPhone = '5555555555';
    insert new List<Contact>{
      new Contact(LastName = 'Second child object', Phone = winningPhone, OwnerId = acc.OwnerId),
      new Contact(LastName = 'Losing child', Phone = '333', OwnerId = acc.OwnerId)
    };
    RollupGrouping__mdt parentGrouping = new RollupGrouping__mdt(Id = RollupTestUtils.createId(RollupGrouping__mdt.SObjectType), RollupOperation__c = 'MAX');

    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Phone',
        LookupObject__c = 'User',
        LookupFieldOnCalcItem__c = 'OwnerId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'MAX',
        CalcItem__c = 'Account',
        RollupGrouping__r = parentGrouping
      ),
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Phone',
        LookupObject__c = 'User',
        LookupFieldOnCalcItem__c = 'OwnerId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'MAX',
        CalcItem__c = 'Contact',
        RollupGrouping__r = parentGrouping
      )
    };

    Test.startTest();
    acc.Phone = '0';
    update acc;
    Test.stopTest();

    User updatedUser = [SELECT AboutMe FROM User WHERE Id = :acc.OwnerId];
    Assert.isNotNull(updatedUser.AboutMe);
    Assert.areEqual(winningPhone, updatedUser.AboutMe);
  }

  @IsTest
  static void shouldThrowExceptionWhenTryingToOperateOnDisallowedFieldTypes() {
    Account acc = [SELECT Id FROM Account];
    Rollup.records = new List<Task>{ new Task(ActivityDate = System.today(), WhatId = acc.Id) };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    try {
      Test.startTest();
      Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, Account.Id, Account.BillingAddress, Account.SObjectType).runCalc();
      Test.stopTest();
      Assert.fail('Exception should be thrown above');
    } catch (Exception ex) {
      System.assertEquals('Calculation not defined for parent field: BillingAddress and op: MAX', ex.getMessage());
    }
  }

  @IsTest
  static void throwsExceptionWhenSuppliedRollupFieldIsInvalid() {
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    try {
      Rollup.runFromApex(
          new List<Rollup__mdt>{
            new Rollup__mdt(
              CalcItem__c = 'Task',
              RollupFieldOnCalcItem__c = 'CreatedDate',
              LookupFieldOnCalcItem__c = 'WhatId',
              LookupObject__c = 'Account',
              LookupFieldOnLookupObject__c = 'Id',
              RollupFieldOnLookupObject__c = 'Typo__c ',
              RollupOperation__c = 'MAX'
            )
          },
          null,
          new List<Task>{ new Task(ActivityDate = System.today()) },
          new Map<Id, SObject>()
        )
        .runCalc();
      Assert.fail('Exception should be thrown above');
    } catch (Exception ex) {
      System.assertEquals(
        true,
        ex.getMessage().contains('At least one of the following values is null when it should not be. Check your rollup configs for possible misspellings')
      );
    }
  }

  @IsTest
  static void shouldFilterNonMatchingRollupsOutOfBatch() {
    Contact con = new Contact(FirstName = 'Something', LastName = 'Required');
    insert con;

    Rollup.FilterResults results = new Rollup.FilterResults();
    results.matchingItemIds.add(con.Id);
    RollupAsyncProcessor batchProcessor = new RollupAsyncProcessor(
      results,
      Contact.FirstName,
      Contact.Id,
      Contact.AccountId,
      Contact.FirstName,
      Campaign.SObjectType,
      Contact.SObjectType,
      Rollup.Op.CONCAT,
      Rollup.InvocationPoint.FROM_APEX,
      RollupControl__mdt.getInstance(Rollup.CONTROL_ORG_DEFAULTS).clone(),
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
  static void shouldWorkMultipleOrInWhereClause() {
    Account acc = [SELECT Id, Name FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'b', CloseDate = System.today(), AccountId = acc.Id, Name = 'a', Amount = 2),
      new Opportunity(StageName = 'a', CloseDate = System.today(), AccountId = acc.Id, Name = 'b', Amount = 2),
      new Opportunity(StageName = 'c', CloseDate = System.today().addDays(-2), AccountId = acc.Id, Name = 'c', Amount = 2),
      new Opportunity(StageName = 'd', CloseDate = System.today().addDays(2), AccountId = acc.Id, Name = 'd', Amount = 2)
    };

    Test.startTest();
    Rollup__mdt mdt = new Rollup__mdt(
      CalcItem__c = 'Opportunity',
      LookupObject__c = 'Account',
      RollupFieldOnCalcItem__c = 'StageName',
      LookupFieldOnCalcItem__c = 'AccountId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'SicDesc',
      RollupOperation__c = 'LAST',
      CalcItemWhereClause__c = '(StageName IN (\'a\', \'b\') AND CloseDate = TODAY) OR (StageName = \'d\' AND CloseDate = TODAY)'
    );
    Rollup.performFullRecalculation(mdt);
    Test.stopTest();

    acc = [SELECT SicDesc FROM Account];
    System.assertEquals('b', acc.SicDesc);
    // Validate that job ran as queueable - that the where clause was formatted correctly, in other words
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  /** Schedulable tests */
  @IsTest
  static void shouldThrowExceptionForBadQuery() {
    // it's a date field - you tell ME why this query is invalid!
    String veryBadQuery = 'SELECT MAX(ActivityDate) FROM Task';

    try {
      Rollup.schedule('Test bad query', '0 0 0 0 0', veryBadQuery, 'Account', null);
      Assert.fail('Exception should be thrown above');
    } catch (Exception ex) {
      Assert.isTrue(ex.getMessage().containsIgnoreCase('field ActivityDate does not support aggregate operator MAX'), ex.getMessage());
    }
  }

  @IsTest
  static void shouldScheduleSuccessfullyForGoodQuery() {
    String goodQuery = 'SELECT Id, Name FROM ContactPointAddress WHERE CreatedDate > YESTERDAY';

    String jobId = Rollup.schedule('Test good query' + System.now(), '0 0 0 * * ?', goodQuery, 'ContactPointAddress', null);

    System.assertNotEquals(null, jobId);
  }

  @IsTest
  static void usesFullBatchRecalculatorForLargerQueries() {
    List<Account> accounts = [SELECT Id FROM Account];
    RollupAsyncProcessor.stubParentRecords = accounts;
    Rollup.defaultControl = new RollupControl__mdt(MaxQueryRows__c = 0);
    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Contact'
      )
    };
    insert new Contact(AccountId = accounts[0].Id, LastName = 'Does Not Reset');

    String jobId = Rollup.schedule('Does not Reset ' + System.now(), '0 0 0 * * ?', 'SELECT Id, AccountId FROM Contact', 'Account', null);

    CronTrigger job = [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId];
    Assert.isTrue(job.CronJobDetail.Name.contains(RollupFullBatchRecalculator.class.getName()));
  }

  @IsTest
  static void doesNotResetParentRecordValuesForLargeScheduledQueries() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Contact'
      )
    };
    insert new Contact(AccountId = acc.Id, LastName = 'Does Not Reset');

    Test.startTest();
    new RollupFullBatchRecalculator.NonResettingBulkFullRecalc(
        'SELECT Id, AccountId\nFROM Contact',
        Rollup.InvocationPoint.FROM_SCHEDULED,
        new List<Rollup__mdt>{
          new Rollup__mdt(
            RollupFieldOnCalcItem__c = 'Id',
            LookupObject__c = 'Account',
            LookupFieldOnCalcItem__c = 'AccountId',
            LookupFieldOnLookupObject__c = 'Id',
            RollupFieldOnLookupObject__c = 'AnnualRevenue',
            RollupOperation__c = 'COUNT',
            CalcItem__c = 'Contact',
            CalcItemWhereClause__c = RollupCurrencyInfo.isMultiCurrency() ? RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME + ' != null' : null
          )
        },
        Contact.SObjectType
      )
      .runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id LIMIT 1];
    Assert.areEqual(2, acc.AnnualRevenue);
  }

  @IsTest
  static void startingFromBatchDoesNotBlowUpCursorBasedFullRecalc() {
    Test.startTest();
    Database.executeBatch(new RollupIntegrationTests());
    Test.stopTest();

    Assert.areEqual(1, [SELECT AnnualRevenue FROM Account].AnnualRevenue);
  }

  public List<SObject> start(Database.BatchableContext bc) {
    return [SELECT Id FROM Organization LIMIT 1];
  }

  public void execute(Database.BatchableContext bc, List<SObject> records) {
    Rollup.defaultControl = new RollupControl__mdt(
      BatchChunkSize__c = 1,
      MaxLookupRowsBeforeBatching__c = 0,
      IsRollupLoggingEnabled__c = true,
      MaxRollupRetries__c = 1
    );
    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Id',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'REFRESH_COUNT',
        CalcItem__c = 'ContactPointAddress'
      )
    };
    ContactPointAddress con = new ContactPointAddress(ParentId = [SELECT Id FROM Account LIMIT 1].Id, Name = 'Child');
    insert con;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    rollup.records = new List<ContactPointAddress>{ con };
    rollup.shouldRun = true;
    Rollup.runFromTrigger();
  }

  public void finish(Database.BatchableContext bc) {
  }
}
