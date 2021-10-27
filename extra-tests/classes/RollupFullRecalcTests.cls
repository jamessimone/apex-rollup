@IsTest
private class RollupFullRecalcTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupFullRecalcTests.class.getName());
    insert acc;

    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void shouldSortFullRecalcsToEnd() {
    RollupAsyncProcessor actualProcessor = RollupAsyncProcessor.getProcessor(
      new Rollup.FilterResults(),
      Contact.Id,
      Contact.AccountId,
      Account.Id,
      Account.Name,
      Account.SObjectType,
      Contact.SObjectType,
      Rollup.Op.SUM,
      Rollup.InvocationPoint.FROM_APEX,
      null,
      null
    );
    List<RollupAsyncProcessor> processors = new List<RollupAsyncProcessor>{
      actualProcessor,
      new RollupDeferredFullRecalcProcessor(null, null, null, null, null),
      actualProcessor
    };
    processors.sort();

    System.assertEquals(true, processors[2] instanceof RollupDeferredFullRecalcProcessor, processors);
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowChildren() {
    Account acc = [SELECT Id FROM Account];
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two') };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
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
  static void shouldPerformFullRecalcWithGrandparentHierarchy() {
    Rollup.onlyUseMockMetadata = true;
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
    flowInputs[0].lookupFieldOnCalcItem = 'ParentApplication__c';
    flowInputs[0].rollupFieldOnCalcItem = 'Engagement_Score__c';
    flowInputs[0].grandparentRelationshipFieldPath = 'ParentApplication__r.Account__r.AnnualRevenue';

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
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 1, IsRollupLoggingEnabled__c = true, BatchChunkSize__c = 2);
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
    System.assertEquals(0, reparentedAccount.AnnualRevenue, 'Reparenting with REFRESH should run decrement logic on old parent');
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
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
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
  static void shouldProperlyBulkifyApexFullRecalcs() {
    // cheating, but we'll use REFRESH_ rollup operations to reproduce this issue (REFRESH is typically only available in Flow)
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60),
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = events;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'REFRESH_CONCAT'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'REFRESH_COUNT',
        CalcItemWhereClause__c = 'WhatId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'DurationInMinutes',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'REFRESH_SUM'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_DELETE;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'No updates should have been made for non-merge delete');
  }

  @IsTest
  static void shouldAllowGrandparentRollupsFromParent() {
    // also an integration test for having an ORDER BY statement
    // in RollupFullBatchRecalculator
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60),
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = [SELECT Id, AboutMe FROM User WHERE Id = :acc.OwnerId];
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'What.Owner.AboutMe',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'What.Type = \'Account\''
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(events[0].Subject + ', ' + events[1].Subject, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  @IsTest
  static void shouldAllowGrandparentRollupFromParentWithPolymorphicFields() {
    // technically shouldAllowGrandparentRollupsFromParent also tests polymorphic fields
    // this test does that in conjunction with a more complicated where clause
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = [SELECT Id, AboutMe FROM User WHERE Id = :acc.OwnerId];
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable,
      BatchChunkSize__c = 100,
      IsRollupLoggingEnabled__c = true
    );
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'Parent.Owner.AboutMe',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'ParentId = \'' + acc.Id + '\' OR Parent.Type = \'Account\''
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(cpas[0].Name + ', ' + cpas[1].Name, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  /** Parent-initiated rollups */
  @IsTest
  static void shouldAllowRollupToBeInitiatedFromTheParent() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Asset asset = new Asset(AccountId = acc.Id, Name = 'Rollup initiated from parent', Quantity = 500);
    insert asset;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Quantity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Asset',
        IsRollupStartedFromParent__c = true
      ),
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT',
        CalcItem__c = 'Asset',
        IsRollupStartedFromParent__c = true
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.records = new List<Account>{ acc };
    Rollup.oldRecordsMap = new Map<Id, Account>{ acc.Id => new Account(Id = acc.Id, AnnualRevenue = 0) };
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been updated based on parent metadata AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertNotEquals(acc.AnnualRevenue, updatedAcc.AnnualRevenue, 'Account should now have been updated');
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'Account should have been updated with asset count');
    System.assertEquals(asset.Name, updatedAcc.Name);
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
  static void shouldNotFailForTruncatedTextFields() {
    Account acc = [SELECT Id FROM Account];
    Integer maxAccountNameLength = Account.Name.getDescribe().getLength();
    Contact con = new Contact(AccountId = acc.Id, Description = '0'.repeat(maxAccountNameLength + 1), LastName = 'Truncate', Email = 'rollup@gmail.com');
    insert con;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'Contact',
      RollupFieldOnCalcItem__c = 'Description',
      LookupFieldOnCalcItem__c = 'AccountId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'Name',
      LookupObject__c = 'Account',
      RollupOperation__c = 'CONCAT'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT Name FROM Account];
    System.assertEquals(maxAccountNameLength, acc.Name.length(), acc.Name);
  }

  @IsTest
  static void shouldEnqueueCMDTRecalcWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDT', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    Test.startTest();
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldRunRollupSyncWhenFiredFromParentRecalcInvocation() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDTSync', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank + ' ||| ParentId = \'' + acc.Id + '\''
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    // specifically don't wrap in start/stopTest to prove it ran sync
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldCorrectlyQueryOrderByFieldForBulkRecalc() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneLast', ParentId = acc.Id, PreferenceRank = 2),
      new ContactPointAddress(Name = 'twoLast', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'LAST',
        OrderByFirstLast__c = 'PreferenceRank',
        CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    // specifically don't wrap in start/stopTest to prove it ran sync
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT Name FROM Account];
    System.assertEquals(cpas[0].Name, acc.Name, 'Last should have been selected based on order field');
  }

  @IsTest
  static void shouldCorrectlyBulkRecalcWhenParentObjectsDiffer() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneLast', ParentId = acc.Id, PreferenceRank = 2),
      new ContactPointAddress(Name = 'twoLast', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    insert new Task(Subject = 'Task rollup', WhatId = acc.Id);

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'LAST',
        OrderByFirstLast__c = 'PreferenceRank',
        CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT Name, AccountNumber FROM Account];
    System.assertEquals(cpas[0].Name, acc.Name, 'Last should have been selected based on order field');
    System.assertEquals('Task rollup', acc.AccountNumber);
  }

  @IsTest
  static void shouldCorrectlyHandleNotLikeInWhereClause() {
    Account acc = [SELECT Id FROM Account];

    insert new Task(Subject = 'Task rollup', WhatId = acc.Id);

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = 'Subject NOT LIKE \'Email\' ||| WhatId = \'' + acc.Id + '\''
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT AccountNumber FROM Account];
    System.assertEquals('Task rollup', acc.AccountNumber);
  }

  @IsTest
  static void shouldEnqueueFullRecalculationWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'one', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'two', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'three', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'four', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'five', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'six', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldBatchForFullRecalcWhenOverLimits() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 5; // validate that the pre-existing value is cleared
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixBatch', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 1,
      BatchChunkSize__c = 10,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable, // validate that it still batches
      IsRollupLoggingEnabled__c = true
    );

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'Name != \'\''
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @IsTest
  static void shouldUseSmallerBatchSizeWhenSpecificRollupControlLowerThanOrgDefaults() {
    Account acc = [SELECT Id FROM Account];
    Account secondAccount = new Account(Name = 'Second');
    insert secondAccount;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'secondAccount', ParentId = secondAccount.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 1,
      BatchChunkSize__c = 100,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable, // validate that it still batches
      IsRollupLoggingEnabled__c = true
    );
    Rollup.specificControl = new RollupControl__mdt(BatchChunkSize__c = 1);

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'Name != \'\''
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    List<AsyncApexJob> jobs = [SELECT Status, JobItemsProcessed FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'];
    System.assertEquals(false, jobs.isEmpty());
    for (AsyncApexJob job : jobs) {
      System.assertEquals('Completed', job.Status);
      System.assertEquals(1, job.JobItemsProcessed);
    }
  }

  @IsTest
  static void shouldNotBatchForFullRecalcWhenWhereClausePlacesItemsUnderneathThreshold() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixQueue', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 2, // this is the important part; that only the qualified cpa ends up counting
      MaxNumberOfQueries__c = 5,
      BatchChunkSize__c = 10,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      IsRollupLoggingEnabled__c = true,
      MaxParentRowsUpdatedAtOnce__c = 2,
      MaxRollupRetries__c = 1
    );

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable'].Status);
  }

  @IsTest
  static void shouldAllowForMutuallyExclusiveWhereClausesOnBulkFullRecalc() {
    Account acc = [SELECT Id, Name FROM Account];

    Task appliesToFirst = new Task(Subject = 'Task for first CMDT', WhatId = acc.Id);
    Task appliesToSecond = new Task(Subject = 'Task for second CMDT', WhatId = acc.Id);
    insert new List<Task>{ appliesToFirst, appliesToSecond };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = 'Subject = \'' + appliesToFirst.Subject + '\' ||| WhatId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItemWhereClause__c = 'Subject = \'' + appliesToSecond.Subject + '\''
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT AccountNumber, Name FROM Account WHERE Id = :acc.Id];

    System.assertEquals(appliesToFirst.Subject, acc.AccountNumber);
    System.assertEquals(appliesToSecond.Subject, acc.Name);
  }

  @IsTest
  static void shouldNotBlowUpOnMassiveQuery() {
    String endOfWhereClause = '2'.repeat(100001);
    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'PreferenceRank = ' + endOfWhereClause
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    System.assert(true, 'Should make it here without exception being thrown');
  }

  @IsTest
  static void shouldNotAddToExistingAmountForFullRecalc() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 60;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneExisting', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoExisting', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  // also an integration test for querying relationship names
  // on CalcItemWhereClause__c Rollup__mdt field
  @IsTest
  static void shouldSuccessfullyExcludeBasedOnWhereCriteriaDuringFullRecalc() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'Parent.Name != \'' + acc.Name + '\''
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'Account should not have been updated based on exclusion criteria');
  }

  @IsTest
  static void shouldCorrectlyQueryOrderByFieldForFullRecalcFirst() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 3),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'Name',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'Name',
      LookupObject__c = 'Account',
      RollupOperation__c = 'FIRST',
      OrderByFirstLast__c = 'PreferenceRank'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT Name FROM Account];
    System.assertEquals(cpas[1].Name, updatedAcc.Name, 'Should have taken first based on PreferenceRank');
  }

  @IsTest
  static void shouldRetainFullRecalcValuesForMutuallyExclusiveRollupsToSameField() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 3),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeName', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Name != \'' + cpas[0].Name + '\''
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(6, acc.AnnualRevenue, 'Full child amount should be included');
  }

  @IsTest
  static void shouldCorrectlyResetParentValueFromSingularRecalcWithNoChildren() {
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    insert new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 0, Name = 'Should not match');

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0 ||| ParentId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT AccountNumber, AnnualRevenue FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'AnnualRevenue should have been reset');
    // seems like some standard fields default to null when you save an empty string to them, even if they have no default value 🙄
    System.assertEquals(null, acc.AccountNumber, 'AccountNumber should have been reset');
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteUnderQueryLimit() {
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    List<Account> accounts = [SELECT AccountNumber, AnnualRevenue, Name FROM Account];
    for (Account updatedAcc : accounts) {
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
      System.assertEquals(null, updatedAcc.AccountNumber, 'AccountNumber should have been reset: ' + updatedAcc);
    }
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteOverQueryLimit() {
    RollupParentResetProcessor.maxQueryRows = 0;
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      BatchChunkSize__c = 3,
      IsRollupLoggingEnabled__c = true
    );
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    List<Account> accounts = [SELECT AccountNumber, AnnualRevenue, Name FROM Account];
    for (Account updatedAcc : accounts) {
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
      System.assertEquals(null, updatedAcc.AccountNumber, 'AccountNumber should have been reset: ' + updatedAcc);
    }
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteOverLimitWithBatching() {
    RollupParentResetProcessor.maxQueryRows = 0;
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Batchable,
      BatchChunkSize__c = 3,
      IsRollupLoggingEnabled__c = true
    );
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    List<Account> accounts = [SELECT AnnualRevenue, Name FROM Account];
    for (Account updatedAcc : accounts) {
      // for this set of tests, since we can't add more than one queueable job to the stack in a test context
      // and because each full reset is processor separately, we can only validate that the first Rollup__mdt record
      // had the parents associated with it reset. It's possible that this will be revisited in the future to consolidate full
      // resets into singular jobs
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
    }
  }

  @IsTest
  static void shouldCacheRetrievedCalcItemsBetweenFullRecalcRuns() {
    // since we can't have more than one batch chunk run in the tests, but we need to test logic in the execute method
    // we'll call that method twice directly
    Rollup.defaultControl = new RollupControl__mdt(
      BatchChunkSize__c = 1,
      MaxNumberOfQueries__c = 4,
      IsRollupLoggingEnabled__c = true,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous
    );
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 2, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 3, Name = 'Two')
    };
    insert cpas;

    RollupFullBatchRecalculator fullRecalc = new RollupFullBatchRecalculator(
      'SELECT Id, PreferenceRank FROM ContactPointAddress',
      Rollup.InvocationPoint.FROM_APEX,
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'SUM'
        )
      },
      ContactPointAddress.SObjectType,
      new Set<Id>()
    );

    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[0] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[1] });

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(5, acc.AnnualRevenue, 'Should have included all calc items in both runs without double-counting or incorrectly summing');
  }

  @IsTest
  static void shouldFullRecalcWithInWhereClauses() {
    RollupParentResetProcessor.maxQueryRows = 0;
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Batchable,
      BatchChunkSize__c = 3,
      IsRollupLoggingEnabled__c = true
    );
    Account acc = [SELECT Id FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 1)
    };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'StageName IN (\'firstName\', \'secondName\')'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldNotBlowUpWithDateFunctionInWhereClause() {
    Account acc = [SELECT Id FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 1)
    };

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'Opportunity',
      RollupFieldOnCalcItem__c = 'Amount',
      LookupFieldOnCalcItem__c = 'AccountId',
      LookupObject__c = 'Account',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'CALENDAR_YEAR(CreatedDate) = ' + System.today().year()
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }
}
