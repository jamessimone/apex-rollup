@IsTest
private class RollupStateTests {
  @IsTest
  static void commitsAndLoadsStateProperly() {
    RollupState state = new RollupState();
    RollupState.GenericInfo info = new RollupState.GenericInfo();
    info.value = 5;
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    String secondStubId = RollupTestUtils.createId(Contact.SObjectType);

    RollupState.AverageInfo averageInfo = new RollupState.AverageInfo();
    averageInfo.increment(10);
    RollupState.SObjectInfo sObjectInfo = new RollupState.SObjectInfo();
    sObjectInfo.setItem(new Account(AnnualRevenue = 1000));
    RollupState.MostInfo mostInfo = new RollupState.MostInfo();
    mostInfo.setValues(5, 'some string');
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'CONCAT'), averageInfo);
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'FIRST'), sObjectInfo);
    state.setState(secondStubId, new Rollup__mdt(RollupOperation__c = 'MOST'), mostInfo);
    state.setState(secondStubId, new Rollup__mdt(RollupOperation__c = 'LAST'), new RollupState.GenericInfo());

    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);

    Set<String> relatedRecordKeys = new Set<String>{ '%' + stubAccountId + '%', '%' + secondStubId + '%' };
    Test.startTest();
    state.commitState(stubJobId);
    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    info.value = 6;
    state.commitState(stubJobId);
    Test.stopTest();

    RollupState__c insertedState = [
      SELECT Id, Body0__c, Body1__c, Body2__c, Body3__c, Body4__c
      FROM RollupState__c
      WHERE RelatedRecordKeysIndex__c LIKE :relatedRecordKeys
    ];
    Assert.isNotNull(insertedState.Body0__c, 'Serialized representation of generic state should be present');

    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    Set<Object> actual = ((RollupState.AverageInfo) state.getState(
        stubAccountId,
        new Rollup__mdt(RollupOperation__c = 'CONCAT'),
        RollupState.AverageInfo.class
      ))
      .distinctNumerators;

    Assert.areEqual(averageInfo.distinctNumerators.size(), actual.size());
    Assert.areEqual(averageInfo.distinctNumerators.contains(10.00), actual.contains(10.00));
    RollupState.GenericInfo updatedInfo = ((RollupState.GenericInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'SUM'),
      RollupState.GenericInfo.class
    ));
    Assert.areEqual(info.value, updatedInfo.value);
  }

  @IsTest
  static void handlesMultipleExistingStateValues() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    RollupState.AverageInfo averageInfo = new RollupState.AverageInfo();
    averageInfo.increment(10);
    RollupState.GenericInfo info = new RollupState.GenericInfo();
    info.value = 5;
    RollupState state = new RollupState();
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'AVERAGE'), averageInfo);
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    RollupState__c existingAverageState = new RollupState__c(
      RelatedJobId__c = stubJobId,
      RelatedRecordKeys__c = stubAccountId,
      Body0__c = JSON.serialize(averageInfo.getUntypedState())
    );
    insert new List<RollupState__c>{
      existingAverageState,
      new RollupState__c(RelatedJobId__c = stubJobId, RelatedRecordKeys__c = stubAccountId, Body0__c = JSON.serialize(info.getUntypedState()))
    };

    state = new RollupState();
    averageInfo.increment(20);
    state.loadState(stubJobId, new Set<String>{ stubAccountId });
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'AVERAGE'), averageInfo);

    Test.startTest();
    state.commitState(stubJobId);
    Assert.areEqual(1, Limits.getDmlRows());
    Test.stopTest();

    Boolean hasCorrectAverageInfo = false;
    Boolean hasCorrectGenericInfo = false;
    for (RollupState__c createdState : [SELECT Body0__c FROM RollupState__c]) {
      hasCorrectAverageInfo = hasCorrectAverageInfo || createdState.Body0__c.contains(JSON.serialize(averageInfo.getUntypedState()));
      hasCorrectGenericInfo = hasCorrectGenericInfo || createdState.Body0__c.contains(JSON.serialize(info.getUntypedState()));
    }
    Assert.isTrue(hasCorrectAverageInfo, 'new average state should have been updated');
    Assert.isTrue(hasCorrectGenericInfo, 'Generic info should not be wiped out');
  }

  @IsTest
  static void splitsReallyLongStatesForTheSameRecord() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    Rollup__mdt template = new Rollup__mdt(DeveloperName = 'exampleUnique40CharacterLimit');
    RollupState state = new RollupState();

    List<Map<String, Object>> statesToSample = new List<Map<String, Object>>();
    for (Integer index = 0; index < 6000; index++) {
      Rollup__mdt clonedMeta = template.clone();
      clonedMeta.DeveloperName += '' + index;
      RollupState.GenericInfo info = new RollupState.GenericInfo();
      info.value = index;
      state.setState(stubAccountId, clonedMeta, info);
      if (index < 20) {
        statesToSample.add(info.getUntypedState());
      }
    }
    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT Body0__c, Body1__c, Body2__c, Body3__c, Body4__c
      FROM RollupState__c
    ];

    Assert.areEqual(2, committedStates.size());
    Boolean body0Filled = false;
    Boolean body1Filled = false;
    Boolean body2Filled = false;
    Boolean body3Filled = false;
    Boolean body4Filled = false;
    Boolean sampleStatesFilled = false;
    for (RollupState__c committedState : committedStates) {
      body0Filled = body0Filled || committedState.Body0__c != null;
      body1Filled = body1Filled || committedState.Body1__c != null;
      body2Filled = body2Filled || committedState.Body2__c != null;
      body3Filled = body3Filled || committedState.Body3__c != null;
      body4Filled = body4Filled || committedState.Body4__c != null;
      if (sampleStatesFilled) {
        Boolean isDuplicate = committedState.Body0__c.contains(JSON.serialize(statesToSample).removeStart('[').removeEnd(']'));
        if (isDuplicate) {
          throw new IllegalArgumentException('Body0__c should not match for both states');
        }
      } else {
        sampleStatesFilled = committedState.Body0__c.contains(JSON.serialize(statesToSample).removeStart('[').removeEnd(']'));
      }
    }

    Assert.isTrue(body0Filled);
    Assert.isTrue(body1Filled);
    Assert.isTrue(body2Filled);
    Assert.isTrue(body3Filled);
    Assert.isTrue(body4Filled);
    Assert.isTrue(sampleStatesFilled);
    /**
     * ensure that we don't exceed the DataWeave heap:
     * System.DataWeaveScriptException: turtles.api.SandboxedLimitException - Heap limit exceeded 6004410 > 6000000
     */
    state.loadState(stubJobId, new Set<String>{ stubAccountId });
  }

  @IsTest
  static void splitsRelatedRecordKeysIntoDifferentTextFields() {
    Rollup__mdt template = new Rollup__mdt(DeveloperName = 'one rollup');
    RollupState state = new RollupState();
    Set<String> fullKeys = new Set<String>();

    List<String> fieldKeys0 = new List<String>();
    List<String> fieldKeys1 = new List<String>();
    List<String> fieldKeys2 = new List<String>();
    List<String> fieldKeys3 = new List<String>();
    List<String> fieldKeys4 = new List<String>();
    List<String> fieldKeys5 = new List<String>();
    List<String> fieldKeys6 = new List<String>();
    List<String> fieldKeys7 = new List<String>();
    List<String> fieldKeys8 = new List<String>();
    List<String> fieldKeys9 = new List<String>();
    List<String> fieldKeys10 = new List<String>();
    List<String> fieldKeys0_1 = new List<String>();
    // 255 / 18 characters ~= 13 records per field (accounting for commas)
    for (Integer index = 0; index < 17 * 15; index++) {
      String stubAccountId = RollupTestUtils.createId(Account.SObjectType) + 'aaa';
      RollupState.GenericInfo info = new RollupState.GenericInfo();
      info.value = index;
      state.setState(stubAccountId, template, info);
      List<String> keys;
      if (index < 13) {
        keys = fieldKeys0;
      } else if (index < 13 * 2) {
        keys = fieldKeys1;
      } else if (index < 13 * 3) {
        keys = fieldKeys2;
      } else if (index < 13 * 4) {
        keys = fieldKeys3;
      } else if (index < 13 * 5) {
        keys = fieldKeys4;
      } else if (index < 13 * 6) {
        keys = fieldKeys5;
      } else if (index < 13 * 7) {
        keys = fieldKeys6;
      } else if (index < 13 * 8) {
        keys = fieldKeys7;
      } else if (index < 13 * 9) {
        keys = fieldKeys8;
      } else if (index < 13 * 10) {
        keys = fieldKeys9;
      } else if (index < 13 * 11) {
        keys = fieldKeys10;
      } else if (index < 13 * 12) {
        keys = fieldKeys0_1;
      }
      keys?.add(stubAccountId);
      fullKeys.add(stubAccountId);
    }

    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT
        RelatedRecordKeys__c,
        RelatedRecordKeys1__c,
        RelatedRecordKeys2__c,
        RelatedRecordKeys3__c,
        RelatedRecordKeys4__c,
        RelatedRecordKeys5__c,
        RelatedRecordKeys6__c,
        RelatedRecordKeys7__c,
        RelatedRecordKeys8__c,
        RelatedRecordKeys9__c,
        RelatedRecordKeys10__c
      FROM RollupState__c
    ];
    // ensure that loadState can be called with the full spread of keys
    state.loadState(stubJobId, fullKeys);

    Assert.areEqual(2, committedStates.size());
    RollupState__c firstState = committedStates.get(0);
    RollupState__c secondState = committedStates.get(1);
    // swap out for the correct "first" state - since they're inserted at the same time
    // there's no deterministic way to order them
    if (firstState.RelatedRecordKeys__c.startsWith('001000000000001') == false) {
      secondState = firstState;
      firstState = committedStates.get(1);
    }
    Assert.isNotNull(firstState.RelatedRecordKeys__c, 'RelatedRecordKeys__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys1__c, 'RelatedRecordKeys1__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys2__c, 'RelatedRecordKeys2__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys3__c, 'RelatedRecordKeys3__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys4__c, 'RelatedRecordKeys4__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys5__c, 'RelatedRecordKeys5__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys6__c, 'RelatedRecordKeys6__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys7__c, 'RelatedRecordKeys7__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys8__c, 'RelatedRecordKeys8__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys9__c, 'RelatedRecordKeys9__c should have been filled out');
    Assert.isNotNull(firstState.RelatedRecordKeys10__c, 'RelatedRecordKeys10__c should have been filled out');

    Assert.areEqual(String.join(fieldKeys0, ','), firstState.RelatedRecordKeys__c, 'fieldKeys0');
    Assert.areEqual(String.join(fieldKeys1, ','), firstState.RelatedRecordKeys1__c, 'fieldKeys1');
    Assert.areEqual(String.join(fieldKeys2, ','), firstState.RelatedRecordKeys2__c, 'fieldKeys2');
    Assert.areEqual(String.join(fieldKeys3, ','), firstState.RelatedRecordKeys3__c, 'fieldKeys3');
    Assert.areEqual(String.join(fieldKeys4, ','), firstState.RelatedRecordKeys4__c, 'fieldKeys4');
    Assert.areEqual(String.join(fieldKeys5, ','), firstState.RelatedRecordKeys5__c, 'fieldKeys5');
    Assert.areEqual(String.join(fieldKeys6, ','), firstState.RelatedRecordKeys6__c, 'fieldKeys6');
    Assert.areEqual(String.join(fieldKeys7, ','), firstState.RelatedRecordKeys7__c, 'fieldKeys7');
    Assert.areEqual(String.join(fieldKeys8, ','), firstState.RelatedRecordKeys8__c, 'fieldKeys8');
    Assert.areEqual(String.join(fieldKeys9, ','), firstState.RelatedRecordKeys9__c, 'fieldKeys9');
    Assert.areEqual(String.join(fieldKeys10, ','), firstState.RelatedRecordKeys10__c, 'fieldKeys10');
    Assert.areEqual(String.join(fieldKeys0_1, ','), secondState.RelatedRecordKeys__c, 'fieldKeys0_1');
  }

  @IsTest
  static void clearsStateProperly() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    insert new RollupState__c(RelatedJobId__c = stubJobId);

    Test.startTest();
    new RollupState().cleanup(new Set<String>{ stubJobId });
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM RollupState__c]);
  }

  @IsTest
  static void onlyLoadsStateForRelatedRecords() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    insert new List<RollupState__c>{
      new RollupState__c(RelatedJobId__c = stubJobId),
      new RollupState__c(RelatedJobId__c = stubJobId, RelatedRecordKeys__c = stubAccountId)
    };

    RollupState state = new RollupState();
    state.loadState(stubJobId, new Set<String>{ stubAccountId });
    state.loadState(stubJobId, new Set<String>{ stubAccountId });

    Assert.areEqual(1, Limits.getQueryRows());
    Assert.areEqual(1, Limits.getQueries());
  }
}
