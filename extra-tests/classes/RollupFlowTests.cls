@IsTest
private class RollupFlowTests {
  @TestSetup
  static void setup() {
    insert new Account(Name = RollupFlowTests.class.getName());
    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void shouldProperlyShortCircuitWhenOldItemMatchesAndNewOneDoesNotConcatDistinct() {
    Account acc = [SELECT Id, Name FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    insert new ContactPointAddress(Name = 'CDC, GDG', ParentId = acc.Id);

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'GDG', ParentId = acc.Id, PreferenceRank = 5) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'CONCAT_DISTINCT');
    flowInputs[0].oldRecordsToRollup = new List<SObject>{ new ContactPointAddress(Id = cpas[0].Id, ParentId = acc.Id, Name = 'CDC') };
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 5';
    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'CONCAT_DISTINCT AFTER_UPDATE from flow did not update account');
    System.assertEquals('CDC, GDG', acc.Name, 'CONCAT_DISTINCT should have properly pulled all records!');
  }

  @IsTest
  static void shouldSplitConcatCalcItemsFromFlow() {
    Account acc = [SELECT Id FROM Account];
    acc.Name = 'CDC';
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'CDC, GDG', ParentId = acc.Id),
      new ContactPointAddress(Name = 'CDC, GDG', ParentId = acc.Id)
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'CONCAT_DISTINCT');
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';
    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'CONCAT_DISTINCT AFTER_INSERT from flow did not update account');
    System.assertEquals(cpas[0].Name, acc.Name, 'CONCAT_DISTINCT should have split on child object values!');
  }

  @IsTest
  static void shouldBeInvokedRegardlessOfCasingFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'insert', 'sum'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'sum AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'sum AFTER_INSERT from flow should match input PreferenceRank');
  }

  @IsTest
  static void shouldBeInvokedSuccessfullyAfterSaveFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250)
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(750, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @IsTest
  static void shouldAllowForSuccessiveInvocablesToBeCalledInSameTransaction() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'distinct'),
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'again')
    };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Account reparentedAcc = new Account(Name = 'ReparentMultipleDMLInvocableRollup');
    insert reparentedAcc;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].deferProcessing = true;
    Rollup.performRollup(flowInputs);

    Rollup.FlowInput flowInput = flowInputs[0];
    flowInput.rollupFieldOnCalcItem = 'Name';
    flowInput.rollupFieldOnOpObject = 'Description';
    flowInput.rollupOperation = 'CONCAT_DISTINCT';
    Rollup.performRollup(flowInputs);

    // now that the inserts have been queued, let's do the updates
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>(cpas);
    cpas[0].ParentId = reparentedAcc.Id;
    flowInput.rollupContext = 'UPDATE';
    Rollup.performRollup(flowInputs);
    flowInput.rollupOperation = 'SUM';
    flowInput.rollupFieldOnCalcItem = 'PreferenceRank';
    flowInput.rollupFieldOnOpObject = 'Description';
    Rollup.performRollup(flowInputs);

    // simulate multiple DML situations
    Test.startTest();
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    System.assertEquals(2, mock.Records.size(), 'Enqueued rollups did not properly update old account and reparented Account');
    Account updatedReparentAcc = (Account) mock.Records[0];
    System.assertEquals(cpas[0].Name, updatedReparentAcc.Description);
    System.assertEquals(cpas[0].PreferenceRank, updatedReparentAcc.AnnualRevenue);

    Account updatedAcc = (Account) mock.Records[1];
    System.assertNotEquals(updatedAcc.Id, reparentedAcc.Id);
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
    System.assertEquals(cpas[1].Name, updatedAcc.Description, 'CONCAT_DISTINCT AFTER_UPDATE from flow should match diff for reparented Name');
  }

  @IsTest
  static void shouldBeInvokedSuccessfullyAfterInsertFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1000, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank');
  }

  @IsTest
  static void flattensMultipleDeferredRollupsProperly() {
    List<ContactPointAddress> firstList = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'again'),
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'again')
    };
    List<ContactPointAddress> secondList = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'distinct'),
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType), Name = 'distinct')
    };

    RollupTestUtils.loadAccountIdMock(firstList);
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(secondList);
    Rollup.records = null;

    List<Rollup.FlowInput> firstFlowInputs = RollupTestUtils.prepareFlowTest(firstList, 'INSERT', 'SUM');
    Rollup.FlowInput firstInput = firstFlowInputs[0];
    firstInput.deferProcessing = true;
    List<Rollup.FlowInput> secondFlowInputs = RollupTestUtils.prepareFlowTest(secondList, 'INSERT', 'SUM');
    Rollup.FlowInput secondInput = secondFlowInputs[0];
    secondInput.deferProcessing = true;
    Rollup.performRollup(firstFlowInputs);
    Rollup.performRollup(secondFlowInputs);

    firstInput.rollupFieldOnCalcItem = 'Name';
    firstInput.rollupFieldOnOpObject = 'Description';
    firstInput.rollupOperation = 'CONCAT_DISTINCT';
    secondInput.rollupFieldOnCalcItem = firstInput.rollupFieldOnCalcItem;
    secondInput.rollupFieldOnOpObject = firstInput.rollupFieldOnOpObject;
    secondInput.rollupOperation = firstInput.rollupOperation;
    Rollup.performRollup(firstFlowInputs);
    Rollup.performRollup(secondFlowInputs);

    // now that the inserts have been queued, let's do the updates
    firstInput.oldRecordsToRollup = firstList;
    firstInput.recordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(Id = firstList[0].Id, PreferenceRank = 1200, Name = 'again', ParentId = firstList[0].ParentId),
      new ContactPointAddress(Id = firstList[1].Id, PreferenceRank = 1200, Name = 'anew', ParentId = firstList[0].ParentId)
    };
    firstInput.rollupContext = 'UPDATE';
    Rollup.performRollup(firstFlowInputs);
    firstInput.rollupOperation = 'SUM';
    firstInput.rollupFieldOnCalcItem = 'PreferenceRank';
    firstInput.rollupFieldOnOpObject = 'AnnualRevenue';
    Rollup.performRollup(firstFlowInputs);

    secondInput.oldRecordsToRollup = secondList;
    secondInput.recordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(Id = secondList[0].Id, PreferenceRank = 1200, Name = 'distinct', ParentId = firstList[0].ParentId),
      new ContactPointAddress(Id = secondList[1].Id, PreferenceRank = 1200, Name = 'anew', ParentId = firstList[0].ParentId)
    };
    secondInput.rollupContext = 'UPDATE';
    Rollup.performRollup(secondFlowInputs);
    secondInput.rollupOperation = 'SUM';
    secondInput.rollupFieldOnCalcItem = 'PreferenceRank';
    secondInput.rollupFieldOnOpObject = 'AnnualRevenue';
    Rollup.performRollup(secondFlowInputs);

    // simulate multiple DML situations
    Test.startTest();
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'All records share the same account for update');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(4800, updatedAcc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match');
    System.assertEquals('again, anew, distinct', updatedAcc.Description, 'CONCAT_DISTINCT AFTER_UPDATE from flow should match');
  }

  @IsTest
  static void shouldThrowValidationErrorOnUpdateFromFlowIfNoOldCalcItems() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Prior records to rollup collection required for rollup context: UPDATE', ex.getMessage());
  }

  @IsTest
  static void shouldThrowValidationErrorOnUpsertFromFlowIfNoOldCalcItems() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPSERT', 'SUM');

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Prior records to rollup collection required for rollup context: UPSERT', ex.getMessage());
  }

  @IsTest
  static void validatesCorrectSetupForGroupByRowDelimiter() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].groupByRowStartDelimiter = '\t';

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('You must set group by fields when supplying a group by delimiter', ex?.getMessage());
  }

  @IsTest
  static void shouldGracefullyExitIfCalcItemsAreNull() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(null, 'INSERT', 'CONCAT');

    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);

    System.assertEquals(1, flowOutputs.size());
    System.assertEquals('No records to rollup, returning early', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotCount() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 2;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'Count Non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 1, Name = 'Count match', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, matchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'COUNT');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(1, acc.AnnualRevenue, 'COUNT AFTER_UPDATE from flow should correctly perform full recalc');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotCountDistinct() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 3;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'Count Non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 1, Name = 'Count distinct match', ParentId = acc.Id);
    ContactPointAddress secondMatchingCpa = matchingCpa.clone();
    secondMatchingCpa.Name = 'Second Count Distinct Match';
    insert new List<ContactPointAddress>{ cpa, matchingCpa, secondMatchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'COUNT_DISTINCT');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpa.ParentId, Id = cpa.Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT_DISTINCT AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(1, acc.AnnualRevenue, 'COUNT_DISTINCT AFTER_UPDATE from flow should correctly perform full recalc');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotSum() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 18;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 2, Name = 'Sum non-match', ParentId = acc.Id);
    ContactPointAddress matchingCpa = new ContactPointAddress(PreferenceRank = 15, Name = 'sum match', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, matchingCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 3)
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(matchingCpa.PreferenceRank, acc.AnnualRevenue, 'SUM AFTER_UPDATE from flow should match diff for PreferenceRank');
  }

  @IsTest
  static void shouldUpdateProperlyAfterSaveIfCurrentItemWouldBeExcludedButOldItemWouldNotFirst() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'First', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'FIRST');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(null, acc.AnnualRevenue, 'FIRST AFTER_UPDATE from flow should get nulled out if no other matching items');
  }

  @IsTest
  static void shouldUpdateToActualFirstIfCurrentItemShouldBeExcludedAndOldOneWouldNot() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress nullPrefRankCpa = new ContactPointAddress(PreferenceRank = null, Name = 'Null pref', ParentId = acc.Id);
    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, Name = 'First', ParentId = acc.Id);
    ContactPointAddress cpaTwo = new ContactPointAddress(PreferenceRank = 1, Name = 'Second', ParentId = acc.Id);
    insert new List<ContactPointAddress>{ cpa, cpaTwo, nullPrefRankCpa };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa }; // only pass cpa, which would be excluded normally (except for the PreferenceRank being set below to another val)
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'FIRST');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = acc.AnnualRevenue.intValue())
    };
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'Name descending nulls last, PreferenceRank';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(cpaTwo.PreferenceRank, acc.AnnualRevenue, 'FIRST AFTER_UPDATE from flow should correctly recalculate and exclude current item');
  }

  @IsTest
  static void shouldProperlyDeleteFirstIfCurrentItemIsOnlyItemAndItIsExcluded() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'First Delete', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank.format();
    flowInputs[0].orderByFirstLast = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'FIRST BEFORE_DELETE from flow did not update accounts');
    System.assertEquals(null, acc.AnnualRevenue, 'FIRST BEFORE_DELETE from flow should correctly null out');
  }

  @IsTest
  static void shouldProperlyDeleteForAverageIfCurrentItemIsOnlyItemAndItIsExcluded() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 250;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = acc.AnnualRevenue.intValue(), Name = 'Average Delete', ParentId = acc.Id);
    insert cpa;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'AVERAGE');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != ' + cpa.PreferenceRank.format();

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'AVERAGE AFTER_UPDATE from flow did not update accounts');
    System.assertEquals(null, acc.AnnualRevenue, 'AVERAGE BEFORE_DELETE from flow should correctly null out');
  }

  @IsTest
  static void shouldBeInvokedSuccessfullyBeforeDeleteFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM BEFORE_DELETE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1000, updatedAcc.AnnualRevenue, 'SUM BEFORE_DELETE from flow should subtract PreferenceRank from Account');
  }

  @IsTest
  static void shouldExcludeNonLinkedItemsAndUseCalcItemWhereClause() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    Date today = System.today();
    insert new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1, ActiveFromDate = today.addDays(-1), Name = 'non-match on account'),
      new ContactPointAddress(PreferenceRank = 0, ActiveFromDate = today.addDays(-1), ParentId = acc.Id, Name = 'Non match on where clause')
    };

    ContactPointAddress cpa = new ContactPointAddress(
      PreferenceRank = 5,
      ActiveFromDate = today,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'ActiveFromDate';

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Updated account should have been loaded FIRST AFTER_INSERT');
    System.assertEquals(cpa.PreferenceRank, acc.AnnualRevenue, 'Only linked items should be used');
  }

  @IsTest
  static void shouldReportErrorWhenUltimateParentRollupAndNoLookupField() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].rollupToUltimateParent = true;

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Rollup To Ultimate Parent and Ultimate Parent Lookup must both be set for hierarchical rollups', ex?.getMessage());
  }

  @IsTest
  static void shouldReportErrorWhenConcatDelimiterSetAndNotConcat() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].concatDelimiter = ';';
    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(
      'Concat delimiter should only be supplied for CONCAT-based rollups. Concat options should only be set for CONCAT_DISTINCT operations',
      ex?.getMessage()
    );
  }

  @IsTest
  static void shouldReportErrorWhenConcatOptionSetAndNotConcat() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].splitConcatDelimiterOnCalcItem = true;

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Concat options should only be set for CONCAT_DISTINCT operations', ex?.getMessage());
  }

  @IsTest
  static void shouldReportErrorWhenBothOverridesSet() {
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(
      new List<ContactPointAddress>{
        new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = System.today(), Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
      },
      'INSERT',
      'MAX'
    );

    flowInputs[0].fullRecalculationDefaultNumberValue = 1;
    flowInputs[0].fullRecalculationDefaultStringValue = 'someValue';

    Exception ex;
    try {
      Rollup.performRollup(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Only one override - the default string value or number value - can be supplied for each rollup', ex?.getMessage());
  }

  @IsTest
  static void shouldStillPerformRollupForFirstLastEvenIfCurrentCalcItemsDoNotMatch() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };
    Date today = System.today();

    // the important part here is that this one SHOULDN'T be first if the passed in child object is not winnowed properly
    insert new ContactPointAddress(PreferenceRank = 5, ActiveFromDate = today.addDays(1), ParentId = acc.Id, Name = 'match on where clause');

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 0, ActiveFromDate = today);
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'FIRST');
    flowInputs[0].calcItemWhereClause = 'PreferenceRank != 0';
    flowInputs[0].orderByFirstLast = 'ActiveFromDate';

    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Updated account should have been loaded FIRST AFTER_INSERT');
    System.assertEquals(5, acc.AnnualRevenue, 'Queried item should be found and used even if child object where clause filters out current iterations');
  }

  // integration test for "ChangedFieldsOnCalcItem__c" being properly constructed
  @IsTest
  static void shouldOnlyIncludeObjectChangedFieldsWhenSuppliedFromFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, Name = 'Acme cpa', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)),
      new ContactPointAddress(PreferenceRank = 500, Name = 'Test name changed cpa', Id = RollupTestUtils.createId(ContactPointAddress.SObjectType))
    };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPDATE', 'SUM');
    flowInputs[0].calcItemChangedFields = 'Name, IsDefault';
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = cpas[0].ParentId, Id = cpas[0].Id, PreferenceRank = 250, Name = cpas[0].Name),
      new ContactPointAddress(ParentId = cpas[1].ParentId, Id = cpas[1].Id, PreferenceRank = 200, Name = 'Name that does not match')
    };

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_UPDATE from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(
      300,
      updatedAcc.AnnualRevenue,
      'SUM AFTER_UPDATE from flow with changed fields should match diff for PreferenceRank based off of the CPA with Name changes'
    );
  }

  @IsTest
  static void shouldReportSuccessWhenFlowPassesNoRecords() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>();
    Rollup.shouldRun = true;
    Rollup.records = cpas;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldReportFailureWhenExceptionIsThrown() {
    List<ContactPointAddressHistory> history = new List<ContactPointAddressHistory>{ new ContactPointAddressHistory() };
    Rollup.shouldRun = true;

    Exception ex;
    Test.startTest();
    // RollupTestUtils.prepareFlowTest sets us up for a failure with a field that doesn't exist on ContactPointAddressHistory
    try {
      Rollup.performRollup(RollupTestUtils.prepareFlowTest(history, 'INSERT', 'SUM'));
    } catch (Exception e) {
      ex = e;
    }
    Test.stopTest();

    System.assertEquals('Invalid field PreferenceRank for ContactPointAddressHistory', ex.getMessage(), ex.getMessage() + '\n' + ex.getStacktraceString());
  }

  @IsTest
  static void shouldNotThrowErrorEvenIfNoRollupsPerformedDuringInvocable() {
    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(RollupTestUtils.prepareFlowTest(new List<SObject>(), 'INSERT', 'SUM'));
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size());
    System.assertEquals(true, flowOutputs[0].isSuccess);
  }

  @IsTest
  static void shouldCountOnNonIdField() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'Test') };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'COUNT');
    flowInputs[0].rollupFieldOnCalcItem = 'Name';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(1, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void shouldOverrideNumberBasedDefaultBasedOnMetadataForFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 1000) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultNumberValue = -1001;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals(-1, updatedAcc.AnnualRevenue, 'SUM AFTER_INSERT from flow should match input PreferenceRank + number override');
  }

  @IsTest
  static void shouldOverrideDateUsingNumberBasedDefaultForFlow() {
    Datetime nowish = System.now();
    Contract con = new Contract(Id = RollupTestUtils.createId(Contract.SObjectType), ActivatedDate = nowish.addSeconds(5));
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ con };

    // it only matters that the amount below is LESS than the above value, and that "nowish" is assigned to the fullRecalculationDefaultNumberValue flow input value
    List<Event> events = new List<Event>{ new Event(WhatId = con.Id) };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(events);
    Rollup.records = null;

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = events;
    flowInput.lookupFieldOnCalcItem = 'WhatId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = 'INSERT';
    flowInput.rollupFieldOnCalcItem = 'ActivityDateTime';
    flowInput.rollupFieldOnOpObject = 'ActivatedDate';
    flowInput.rollupSObjectName = 'Contract';
    flowInput.rollupOperation = 'MAX';
    flowInput.fullRecalculationDefaultNumberValue = nowish.getTime();
    flowInput.isFullRecordSet = true;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput });
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'MAX AFTER_INSERT from flow with override date did not update accounts');
    System.assertEquals(nowish, con.ActivatedDate, 'MAX AFTER_INSERT from flow should match override date');
  }

  @IsTest
  static void shouldOverrideStringBasedDefaultForFlow() {
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(Name = 'A') };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadAccountIdMock(cpas);
    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'INSERT', 'SUM');
    flowInputs[0].fullRecalculationDefaultStringValue = 'Z';
    flowInputs[0].rollupFieldOnOpObject = 'Name';
    flowInputs[0].rollupFieldOnCalcItem = 'Name';
    flowInputs[0].isFullRecordSet = true;

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'SUM AFTER_INSERT from flow did not update accounts');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertEquals('Z', updatedAcc.Name, 'SUM AFTER_INSERT from flow should match string override when it is greater than supplied calc values');
  }

  @IsTest
  static void shouldNotWriteToNonUpdateableFieldsForOldFlowRecords() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    Event ev = new Event(ActivityDateTime = System.now().addDays(-2), WhatId = acc.Id);

    // a useful hack for assigning values to unwriteable fields ...
    Map<String, Object> deserializedEvent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(ev));
    deserializedEvent.put('AccountId', null);
    ev = (Event) JSON.deserialize(JSON.serialize(deserializedEvent), Event.class);

    List<Event> events = new List<Event>{ ev };
    RollupTestUtils.DMLMock mock = RollupTestUtils.loadMock(events);
    Rollup.records = null;

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = events;
    flowInput.lookupFieldOnCalcItem = 'WhatId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = 'INSERT';
    flowInput.rollupFieldOnCalcItem = 'ActivityDateTime';
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupSObjectName = 'Account';
    flowInput.rollupOperation = 'COUNT';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput });
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    System.assertEquals(1, mock.Records.size(), 'COUNT AFTER_INSERT from flow did not update accounts');
    System.assertEquals(1, acc.AnnualRevenue, 'COUNT AFTER_INSERT from flow should not fail when non-writeable fields are present');
  }

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

    List<Contact> cons = new List<Contact>{ new Contact(LastName = 'somethingElse', AccountId = acc.Id, Phone = '617619111') };
    insert cons;
    Rollup.shouldRefreshCachedControl = true;

    Contact oldContact = cons[0].clone(true, true);
    cons[0].LastName = 'soloAdmin'; // simulating an update which has not yet been reflected in the database

    Rollup.FlowInput flowInput = RollupTestUtils.prepareFlowTest(cons, 'UPSERT', 'SUM')[0];
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupFieldOnCalcItem = 'Id';
    flowInput.lookupFieldOnCalcItem = 'AccountId';
    flowInput.calcItemWhereClause = 'LastName != \'soloAdmin\' AND Account.Name = \'' + acc.Name + '\'';
    flowInput.oldRecordsToRollup = new List<Contact>{ oldContact };
    Rollup.FlowInput secondInput = (Rollup.FlowInput) JSON.deserialize(JSON.serialize(flowInput), Rollup.FlowInput.class);
    secondInput.recordsToRollup = flowInput.recordsToRollup; // lost in deserialization
    secondInput.oldRecordsToRollup = flowInput.oldRecordsToRollup; // lost in deserialization
    secondInput.rollupOperation = 'COUNT';
    secondInput.calcItemWhereClause = 'LastName != \'soloAdmin\'';
    secondInput.rollupFieldOnOpObject = 'NumberOfEmployees';
    // also validate that a matching clause does NOT get reset
    Rollup.FlowInput matchingInput = (Rollup.FlowInput) JSON.deserialize(JSON.serialize(flowInput), Rollup.FlowInput.class);
    matchingInput.recordsToRollup = flowInput.recordsToRollup; // lost in deserialization
    matchingInput.oldRecordsToRollup = flowInput.oldRecordsToRollup; // lost in deserialization
    matchingInput.rollupOperation = 'MAX';
    matchingInput.rollupFieldOnCalcItem = 'Phone';
    matchingInput.calcItemWhereClause = 'LastName = \'soloAdmin\' AND Account.Name = \'' + acc.Name + '\'';
    matchingInput.rollupFieldOnOpObject = 'Phone';

    Test.startTest();
    Rollup.performRollup(new List<Rollup.FlowInput>{ flowInput, secondInput, matchingInput });
    Test.stopTest();

    Account updatedAccount = [SELECT AnnualRevenue, NumberOfEmployees, Phone FROM Account];
    System.assertEquals(null, updatedAccount.NumberOfEmployees, 'COUNT should be cleared now that child object no longer matches');
    System.assertEquals(null, updatedAccount.AnnualRevenue, 'SUM should be cleared now that child object no longer matches');
    System.assertEquals(cons[0].Phone, updatedAccount.Phone, 'MAX should not be cleared since child object matches');
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
      'Child object where clause with parent filtering should decrement on update when old item matches and new item does not'
    );
    System.assertEquals(250, updatedAcc.NumberOfEmployees, 'Number of employees should also have been decremented');
  }

  @IsTest
  static void excludesDeletedItemsForMost() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1, ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(PreferenceRank = 1, ParentId = acc.Id, Name = 'Two'),
      new ContactPointAddress(PreferenceRank = 2, ParentId = acc.Id, Name = 'Three')
    };
    insert cpas;
    ContactPointAddress expectedMost = cpas.remove(2);

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'MOST');

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(expectedMost.PreferenceRank, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void runsWithoutChildrenWhenFlagged() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 50;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(new List<SObject>(), 'REFRESH', 'SUM');
    flowInputs[0].recordsToRollup = null; // Get Records passes null for something that doesn't match
    flowInputs[0].parentRecordIdForEmptyChildrenCollections = acc.Id;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertNotEquals('No records to rollup, returning early', flowOutputs[0].message);
    System.assertEquals(null, acc.AnnualRevenue);
  }

  @IsTest
  static void worksWithMultipleDmlWithDeletes() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 1;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1, ParentId = acc.Id, Name = 'Non-match 1'),
      new ContactPointAddress(PreferenceRank = 2, ParentId = acc.Id, Name = 'Match to be deleted')
    };
    insert cpas;

    ContactPointAddress toDelete = cpas.remove(1);
    List<ContactPointAddress> deletedCpas = new List<ContactPointAddress>{ toDelete };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(deletedCpas, 'UPDATE', 'COUNT');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>(deletedCpas);
    flowInputs[0].isFullRecordSet = true;
    flowInputs[0].calcItemWhereClause = 'PreferenceRank = 2';
    flowInputs.addAll(RollupTestUtils.prepareFlowTest(deletedCpas, 'DELETE', 'COUNT'));
    flowInputs[1].calcItemWhereClause = 'PreferenceRank = 2';
    flowInputs[1].isFullRecordSet = true;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(null, updatedAcc.AnnualRevenue);
  }

  @IsTest
  static void shouldCorrectlyDecrementOnRollupsToMultipleParentsDelete() {
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Parent 1', AnnualRevenue = 1),
      new Account(Name = 'Parent 2', AnnualRevenue = 2),
      new Account(Name = 'Parent 3', AnnualRevenue = 3),
      new Account(Name = 'Parent 4', AnnualRevenue = 4)
    };
    insert accounts;
    Individual bParentOne = new Individual(LastName = 'B1', ConsumerCreditScore = 3, ConvictionsCount = 2);
    Individual bParentTwo = new Individual(LastName = 'B2', ConsumerCreditScore = 7, ConvictionsCount = 2);
    insert new List<Individual>{ bParentOne, bParentTwo };
    List<ContactPointAddress> childrenToInsert = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = accounts[0].AnnualRevenue.intValue(), ParentId = accounts[0].Id, Name = bParentOne.Id),
      new ContactPointAddress(PreferenceRank = accounts[1].AnnualRevenue.intValue(), ParentId = accounts[1].Id, Name = bParentOne.Id),
      new ContactPointAddress(PreferenceRank = accounts[2].AnnualRevenue.intValue(), ParentId = accounts[2].Id, Name = bParentTwo.Id),
      new ContactPointAddress(PreferenceRank = accounts[3].AnnualRevenue.intValue(), ParentId = accounts[3].Id, Name = bParentTwo.Id)
    };
    insert childrenToInsert;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ childrenToInsert[0], childrenToInsert[2] };

    Rollup.FlowInput firstInput = RollupTestUtils.prepareFlowTest(cpas, 'DELETE', 'SUM')[0];
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
    System.assertEquals(3, Rollup.CACHED_ROLLUPS.size());
    Rollup.processStoredFlowRollups();
    Test.stopTest();

    Map<Id, Decimal> accountToExpectedAmount = new Map<Id, Decimal>{
      accounts[0].Id => null,
      accounts[1].Id => accounts[1].AnnualRevenue,
      accounts[2].Id => null,
      accounts[3].Id => accounts[3].AnnualRevenue
    };
    for (Account updatedAcc : [SELECT Id, Name, AnnualRevenue FROM Account WHERE Id = :accounts]) {
      System.assertEquals(accountToExpectedAmount.get(updatedAcc.Id), updatedAcc.AnnualRevenue, updatedAcc);
    }
    bParentOne = [SELECT Id, ConsumerCreditScore, ConvictionsCount FROM Individual WHERE Id = :bParentOne.Id];
    System.assertEquals(2, bParentOne.ConsumerCreditScore);
    System.assertEquals(1, bParentOne.ConvictionsCount);
    bParentTwo = [SELECT Id, ConsumerCreditScore, ConvictionsCount FROM Individual WHERE Id = :bParentTwo.Id];
    System.assertEquals(4, bParentTwo.ConsumerCreditScore);
    System.assertEquals(1, bParentTwo.ConvictionsCount);
  }
}
