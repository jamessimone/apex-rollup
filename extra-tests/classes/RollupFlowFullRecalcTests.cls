@IsTest
private class RollupFlowFullRecalcTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupFlowFullRecalcTests.class.getName());
    insert acc;

    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void shouldPerformFullRecalcWithGrandparentHierarchyFlow() {
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
    Account acc = [SELECT Id FROM Account];
    Account childAccount = new Account(Name = 'Hierarchy child', ParentId = acc.Id);
    insert childAccount;
    ParentApplication__c parentApp = new ParentApplication__c(Account__c = childAccount.Id, Name = 'Link to child account');
    ParentApplication__c secondParentApp = new ParentApplication__c(Account__c = acc.Id, Name = 'Linked directly to parent account');
    insert new List<ParentApplication__c>{ parentApp, secondParentApp };

    // ensure that both a top-level child item linked only to the ultimate parent and one linked to the hierarchy child is included
    List<Application__c> apps = new List<Application__c>{
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = parentApp.Id, Name = 'Linked to Child Parent App'),
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = secondParentApp.Id, Name = 'Linked to Direct Parent App')
    };
    insert apps;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(apps, 'REFRESH', 'SUM');
    flowInputs[0].ultimateParentLookup = 'ParentId';
    flowInputs[0].rollupToUltimateParent = true;
    flowInputs[0].lookupFieldOnCalcItem = Application__c.ParentApplication__c.toString();
    flowInputs[0].rollupFieldOnCalcItem = Application__c.Engagement_Score__c.toString();
    flowInputs[0].grandparentRelationshipFieldPath = RollupTestUtils.getRelationshipPath(
      new List<Schema.SObjectField>{ Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.AnnualRevenue }
    );

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(2000, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
  }

  @IsTest
  static void shouldBulkifyBatchFullRecalcsProperly() {
    RollupAsyncProcessor.additionalCalcItemCount = 1;
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1, IsRollupLoggingEnabled__c = true);
    Account acc = [SELECT Id FROM Account];
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    Rollup.FlowInput secondFlowInput = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'CONCAT')[0];
    secondFlowInput.rollupFieldOnOpObject = 'AccountNumber';
    secondFlowInput.rollupFieldOnCalcItem = 'Name';
    flowInputs.add(secondFlowInput);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(2, flowOutputs.size(), 'Flow outputs were not provided');
    for (Rollup.FlowOutput flowOutput : flowOutputs) {
      System.assertEquals('SUCCESS', flowOutput.message);
      System.assertEquals(true, flowOutput.isSuccess);
    }

    Account updatedAcc = [SELECT Id, AnnualRevenue, AccountNumber FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
    System.assertEquals('One, Two', updatedAcc.AccountNumber);
  }

  @IsTest
  static void shouldBulkifyQueueableFullRecalcsProperly() {
    Account acc = [SELECT Id FROM Account];
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    Rollup.FlowInput secondFlowInput = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'CONCAT')[0];
    secondFlowInput.rollupFieldOnOpObject = 'AccountNumber';
    secondFlowInput.rollupFieldOnCalcItem = 'Name';
    flowInputs.add(secondFlowInput);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(2, flowOutputs.size(), 'Flow outputs were not provided');
    for (Rollup.FlowOutput flowOutput : flowOutputs) {
      System.assertEquals('SUCCESS', flowOutput.message);
      System.assertEquals(true, flowOutput.isSuccess);
    }

    Account updatedAcc = [SELECT Id, AnnualRevenue, AccountNumber FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
    System.assertEquals('One, Two', updatedAcc.AccountNumber);
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowChildrenWithReparenting() {
    Account acc = [SELECT Id FROM Account];
    Account reparentedAccount = new Account(Name = 'Reparented Refresh', AnnualRevenue = 1000);
    insert reparentedAccount;

    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = reparentedAccount.AnnualRevenue.intValue(), ParentId = reparentedAccount.Id, Name = 'Two')
    };
    insert cpas;

    reparentedAccount = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :reparentedAccount.Id];
    System.assertEquals(cpas[0].PreferenceRank, reparentedAccount.AnnualRevenue, 'Reparenting test set up under wrong conditions!');

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    ContactPointAddress clonedCpa = cpas[0].clone(true);
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{ clonedCpa };
    cpas[0].ParentId = acc.Id;
    flowInputs[0].recordsToRollup = cpas;
    update cpas;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1500, acc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
    reparentedAccount = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :reparentedAccount.Id];
    System.assertEquals(null, reparentedAccount.AnnualRevenue, 'Reparenting with REFRESH should run decrement logic on old parent');
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowParent() {
    List<Account> accs = [SELECT Id, AnnualRevenue FROM Account];

    insert new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = accs[0].Id, Name = 'One'),
      new ContactPointAddress(PreferenceRank = 1000, ParentId = accs[0].Id, Name = 'Two')
    };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(accs, 'REFRESH', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow started from parent should fully recalc');
  }

  @IsTest
  static void clearsParentValuesWhenNoRefreshMatches() {
    Account acc = (Account) RollupTestUtils.queryRecord(
      Schema.Account.SObjectType,
      new List<Schema.SObjectField>{ Account.AnnualRevenue, Account.Description }
    );
    acc.AnnualRevenue = 1500;
    acc.Description = 'This is the value that should be persisted';
    update acc;
    // simulate un-related, in-flight update
    acc.Description = 'Something else';

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(new List<Account>{ acc }, 'REFRESH', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue, Description FROM Account];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow started from parent should fully clear');
    System.assertEquals('This is the value that should be persisted', updatedAcc.Description, 'Unrelated field should not be cleared');
  }

  @IsTest
  static void clearsParentValuesWhenNoUpdateMatches() {
    Account acc = (Account) RollupTestUtils.queryRecord(Schema.Account.SObjectType, new List<Schema.SObjectField>{ Account.AnnualRevenue });
    acc.AnnualRevenue = 1500;
    update acc;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(new List<Account>{ acc }, 'UPSERT', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';
    flowInputs[0].oldRecordsToRollup = new List<SObject>{ null };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'SUM from flow started from parent should fully clear');
  }

  @IsTest
  static void properlyPerformsFullRecalcsOnUpdateFromParent() {
    List<Account> accs = [SELECT Id, AnnualRevenue FROM Account];

    insert new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = accs[0].Id, Name = 'One'),
      new ContactPointAddress(PreferenceRank = 1000, ParentId = accs[0].Id, Name = 'Two')
    };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(accs, 'UPDATE', 'COUNT');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';
    flowInputs[0].oldRecordsToRollup = accs;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(2, updatedAcc.AnnualRevenue, 'COUNT UPDATE from flow started from parent should fully recalc');
  }

  @IsTest
  static void shouldFilterOnParentFieldsProperlyWhenInvokedFromParent() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'Test has started under wrong conditions');
    insert new Contact(LastName = 'Parent field test', AccountId = acc.Id);

    List<Account> accs = new List<Account>{ acc };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(accs);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(accs, 'REFRESH', 'COUNT');
    flowInputs[0].lookupFieldOnCalcItem = 'AccountId';
    flowInputs[0].lookupFieldOnOpObject = 'Id';
    flowInputs[0].rollupFieldOnCalcItem = 'Id';
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'Contact';
    flowInputs[0].oldRecordsToRollup = new List<Account>{ new Account(Id = acc.Id, AnnualRevenue = 250) };
    flowInputs[0].calcItemWhereClause = 'Account.AnnualRevenue != 250';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'REFRESH_COUNT from flow did not update account');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'COUNT did not refresh successfully');
  }

  @IsTest
  static void shouldAllowRollupFromParentByInvocable() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'rollup from parent invocable', PreferenceRank = -50);
    insert cpa;

    List<Account> accs = new List<Account>{ acc };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(accs);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(accs, 'INSERT', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(cpa.PreferenceRank, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank');
  }

  @IsTest
  static void multipleIsFullRecordSetsProperlyClearParentFieldsOnce() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    ContactPointAddress one = new ContactPointAddress(ParentId = acc.Id, Name = 'child one', PreferenceRank = 50);
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, Name = 'child two', PreferenceRank = 50);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ one, two };
    insert cpas;
    cpas.remove(1);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].isFullRecordSet = true;
    Rollup.FlowInput secondFullRecalc = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'COUNT')[0];
    secondFullRecalc.isFullRecordSet = true;
    secondFullRecalc.rollupFieldOnCalcItem = 'Name';
    secondFullRecalc.rollupFieldOnOpObject = 'NumberOfEmployees';
    flowInputs.add(secondFullRecalc);

    Test.startTest();
    Rollup.performRollup(flowInputs);
    for (Rollup.FlowInput flowInput : flowInputs) {
      flowInput.recordsToRollup = new List<SObject>{ two };
      flowInput.shouldRunSync = true;
    }
    // same operations, different set of inputs shouldn't add to existing count/sum; they should be reset
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(one.PreferenceRank + two.PreferenceRank, acc.AnnualRevenue);
    System.assertEquals(2, acc.NumberOfEmployees);
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowChildren() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Second', AnnualRevenue = 5);
    insert secondParent;
    insert new List<ContactPointAddress>{
      // ensure another matching item exists outside of the passed in list
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One'),
      // ensure that the PreferenceRank associated with the second parent specifically does NOT match
      // the second parent's existing annual revenue; we want to validate that a constrained full recalc only
      // updates the parents of the records that we've passed in
      new ContactPointAddress(PreferenceRank = secondParent.AnnualRevenue.intValue() * 2, ParentId = secondParent.Id, Name = 'Two')
    };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'First child') };
    insert cpas;
    Rollup.shouldRefreshCachedControl = true;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    Rollup.FlowInput secondInput = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'COUNT')[0];
    secondInput.rollupFieldOnCalcItem = 'Id';
    secondInput.rollupFieldOnOpObject = 'NumberOfEmployees';
    secondInput.rollupOperation = 'COUNT';
    secondInput.calcItemWhereClause = 'PreferenceRank > 0';
    flowInputs.add(secondInput);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(2, flowOutputs.size(), 'Incorrect flow outputs were provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
    Account updatedSecondParent = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :secondParent.Id];
    System.assertEquals(secondParent.AnnualRevenue, updatedSecondParent.AnnualRevenue, 'Out of scope parent values should not have been affected');
  }

  @IsTest
  static void shouldRefreshMultipleBatchFullRecalcs() {
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 0, IsRollupLoggingEnabled__c = true, MaxRollupRetries__c = 3);
    Account acc = [SELECT Id FROM Account];
    Individual secondParent = new Individual(LastName = 'Second');
    insert secondParent;
    List<ContactPointAddress> childrenToInsert = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'A1'),
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'A2'),
      new ContactPointAddress(PreferenceRank = 250, ParentId = secondParent.Id, Name = 'B1'),
      new ContactPointAddress(PreferenceRank = 250, ParentId = secondParent.Id, Name = 'B2')
    };
    insert childrenToInsert;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ childrenToInsert[0], childrenToInsert[2] };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    flowInputs[0].deferProcessing = true;
    flowInputs[0].calcItemWhereClause = 'PreferenceRank > 0';
    List<Rollup.FlowInput> secondInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    secondInputs[0].rollupSObjectName = 'Individual';
    secondInputs[0].rollupFieldOnOpObject = 'ConsumerCreditScore';
    secondInputs[0].rollupOperation = 'SUM';
    secondInputs[0].deferProcessing = true;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Rollup.performRollup(secondInputs);
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1000, updatedAcc.AnnualRevenue);
    Individual updatedSecondParent = [SELECT Id, ConsumerCreditScore FROM Individual WHERE Id = :secondParent.Id];
    System.assertEquals(500, updatedSecondParent.ConsumerCreditScore);
  }

  @IsTest
  static void shouldCorrectlyFilterParentFieldsFromFlowChildren() {
    Account acc = [SELECT Id, Name FROM Account];
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    flowInputs[0].calcItemWhereClause = 'Parent.Name = \'' + acc.Name + '\'';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'Child object where clause with parent filtering should work for REFRESH');
  }

  @IsTest
  static void shouldDecrementProperlyOnRefreshUpdateWithParentFilterFields() {
    Account acc = [SELECT Id, Name FROM Account];
    Account second = new Account(Name = 'Second', AnnualRevenue = 1000);
    insert second;
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = second.AnnualRevenue.intValue(), ParentId = second.Id, Name = 'Two')
    };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    flowInputs[0].calcItemWhereClause = 'Parent.Name = \'' + acc.Name + '\'';
    flowInputs[0].oldRecordsToRollup = new List<SObject>{
      new ContactPointAddress(PreferenceRank = cpas[0].PreferenceRank, ParentId = acc.Id, Name = 'Two', Id = cpas[0].Id)
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(500, updatedAcc.AnnualRevenue, 'Child object where clause with parent filtering should work for REFRESH');
    Account secondUpdatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :second.Id];
    System.assertEquals(null, secondUpdatedAcc.AnnualRevenue, 'Amount should have decremented on update!');
  }

  @IsTest
  static void shouldPerformFullRecalcWithHierarchy() {
    Account acc = [SELECT Id FROM Account];
    Account childAccount = new Account(Name = 'Hierarchy child', ParentId = acc.Id);
    insert childAccount;
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = childAccount.Id, Name = 'One');

    // ensure that a top-level child item linked only to the ultimate parent is included
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    flowInputs[0].ultimateParentLookup = 'ParentId';
    flowInputs[0].rollupToUltimateParent = true;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
  }

  @IsTest
  static void multipleHierarchyRollupsSuccessfullyFullRecalc() {
    Account acc = [SELECT Id FROM Account];
    Account childAccount = new Account(Name = 'Hierarchy child', ParentId = acc.Id);
    insert childAccount;
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = childAccount.Id, Name = 'One');

    // ensure that a top-level child item linked only to the ultimate parent is included
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    Rollup.FlowInput secondInput = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'CONCAT_DISTINCT')[0];
    secondInput.rollupFieldOnOpObject = 'Name';
    secondInput.rollupFieldOnCalcItem = 'Name';
    flowInputs.add(secondInput);

    for (Rollup.FlowInput flowInput : flowInputs) {
      flowInput.ultimateParentLookup = 'ParentId';
      flowInput.rollupToUltimateParent = true;
    }

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    Account updatedAcc = [SELECT Id, AnnualRevenue, Name FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH hierarchy from flow should fully recalc');
    System.assertEquals('One, Two', updatedAcc.Name, 'CONCAT_DISTINCT REFRESH hierarchy from flow should full recalc');
  }

  @IsTest
  static void shouldCorrectlyFindAdjacentChildrenForRollupsToMultipleParents() {
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Parent 1'),
      new Account(Name = 'Parent 2'),
      new Account(Name = 'Parent 3'),
      new Account(Name = 'Parent 4')
    };
    insert accounts;
    Individual bParentOne = new Individual(LastName = 'B1', ConsumerCreditScore = 3, ConvictionsCount = 2);
    Individual bParentTwo = new Individual(LastName = 'B2', ConsumerCreditScore = 7, ConvictionsCount = 2);
    insert new List<Individual>{ bParentOne, bParentTwo };
    List<ContactPointAddress> childrenToInsert = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1, ParentId = accounts[0].Id, Name = bParentOne.Id),
      new ContactPointAddress(PreferenceRank = 2, ParentId = accounts[1].Id, Name = bParentOne.Id),
      new ContactPointAddress(PreferenceRank = 3, ParentId = accounts[2].Id, Name = bParentTwo.Id),
      new ContactPointAddress(PreferenceRank = 4, ParentId = accounts[3].Id, Name = bParentTwo.Id)
    };
    insert childrenToInsert;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ childrenToInsert[0], childrenToInsert[2] };

    Rollup.FlowInput firstInput = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM')[0];
    firstInput.deferProcessing = true;
    Rollup.FlowInput secondInput = firstInput.clone();
    secondInput.lookupFieldOnCalcItem = 'Name';
    secondInput.rollupSObjectName = 'Individual';
    secondInput.rollupFieldOnOpObject = 'ConsumerCreditScore';
    Rollup.FlowInput thirdInput = secondInput.clone();
    thirdInput.calcItemWhereClause = 'PreferenceRank > 0';
    thirdInput.rollupFieldOnOpObject = 'ConvictionsCount';
    thirdInput.rollupOperation = 'COUNT';
    Rollup.FlowInput fourthInput = secondInput.clone();
    fourthInput.rollupSObjectName = 'Task';
    fourthInput.rollupFieldOnOpObject = 'CallDurationInSeconds';
    fourthInput.calcItemWhereClause = '(NOT Name LIKE \'' + bParentOne.Id.toString().substring(0, 3) + '%\')';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ firstInput, secondInput, thirdInput, fourthInput });
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    Map<Id, Decimal> accountToExpectedAmount = new Map<Id, Decimal>{
      accounts[0].Id => childrenToInsert[0].PreferenceRank,
      accounts[1].Id => childrenToInsert[1].PreferenceRank,
      accounts[2].Id => childrenToInsert[2].PreferenceRank,
      accounts[3].Id => childrenToInsert[3].PreferenceRank
    };
    for (Account updatedAcc : [SELECT Id, Name, AnnualRevenue FROM Account WHERE Id = :accounts]) {
      System.assertEquals(accountToExpectedAmount.get(updatedAcc.Id), updatedAcc.AnnualRevenue, updatedAcc);
    }
    bParentOne = [SELECT Id, ConsumerCreditScore, ConvictionsCount FROM Individual WHERE Id = :bParentOne.Id];
    System.assertEquals(3, bParentOne.ConsumerCreditScore);
    System.assertEquals(2, bParentOne.ConvictionsCount);
    bParentTwo = [SELECT Id, ConsumerCreditScore, ConvictionsCount FROM Individual WHERE Id = :bParentTwo.Id];
    System.assertEquals(7, bParentTwo.ConsumerCreditScore);
    System.assertEquals(2, bParentTwo.ConvictionsCount);
  }
}
