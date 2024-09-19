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

    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);

    Set<String> relatedRecordKeys = new Set<String>{ '%' + stubAccountId + '%', '%' + secondStubId + '%' };
    Test.startTest();
    state.commitState(stubJobId);
    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    info.value = 6;
    state.commitState(stubJobId);
    Test.stopTest();

    RollupState__c insertedState = [SELECT Id, Body0__c FROM RollupState__c WHERE RelatedRecordKeysIndex__c LIKE :relatedRecordKeys];
    Assert.isNotNull(insertedState.Body0__c, 'Serialized representation of generic state should be present');

    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    Set<Object> actual = ((RollupState.AverageInfo) state.getState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'CONCAT'))).distinctNumerators;

    Assert.areEqual(averageInfo.distinctNumerators.size(), actual.size());
    Assert.areEqual(averageInfo.distinctNumerators.contains(10.00), actual.contains(10.00));
    RollupState.GenericInfo updatedInfo = ((RollupState.GenericInfo) state.getState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM')));
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

    for (Integer index = 0; index < 12000; index++) {
      Rollup__mdt clonedMeta = template.clone();
      clonedMeta.DeveloperName += '' + index;
      RollupState.GenericInfo info = new RollupState.GenericInfo();
      info.value = index;
      state.setState(stubAccountId, clonedMeta, info);
    }
    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT Body0__c, Body1__c, Body2__c, Body3__c, Body4__c, Body5__c, Body6__c, Body7__c, Body8__c, Body9__c
      FROM RollupState__c
    ];
    Assert.areEqual(2, committedStates.size());
    Boolean body0Filled = false;
    Boolean body1Filled = false;
    Boolean body2Filled = false;
    Boolean body3Filled = false;
    Boolean body4Filled = false;
    Boolean body5Filled = false;
    Boolean body6Filled = false;
    Boolean body7Filled = false;
    Boolean body8Filled = false;
    Boolean body9Filled = false;
    for (RollupState__c committedState : committedStates) {
      body0Filled = body0Filled || committedState.Body0__c != null;
      body1Filled = body1Filled || committedState.Body1__c != null;
      body2Filled = body2Filled || committedState.Body2__c != null;
      body3Filled = body3Filled || committedState.Body3__c != null;
      body4Filled = body4Filled || committedState.Body4__c != null;
      body5Filled = body5Filled || committedState.Body5__c != null;
      body6Filled = body6Filled || committedState.Body6__c != null;
      body7Filled = body7Filled || committedState.Body7__c != null;
      body8Filled = body8Filled || committedState.Body8__c != null;
      body9Filled = body9Filled || committedState.Body9__c != null;
    }

    Assert.isTrue(body0Filled);
    Assert.isTrue(body1Filled);
    Assert.isTrue(body2Filled);
    Assert.isTrue(body3Filled);
    Assert.isTrue(body4Filled);
    Assert.isTrue(body5Filled);
    Assert.isTrue(body6Filled);
    Assert.isTrue(body7Filled);
    Assert.isTrue(body8Filled);
    Assert.isTrue(body9Filled);
  }

  @IsTest
  static void splitsRelatedRecordKeysIntoDifferentTextFields() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    Rollup__mdt template = new Rollup__mdt(DeveloperName = 'one rollup');
    RollupState state = new RollupState();

    List<String> fieldKeys0 = new List<String>();
    List<String> fieldKeys1 = new List<String>();
    List<String> fieldKeys2 = new List<String>();
    List<String> fieldKeys3 = new List<String>();
    List<String> fieldKeys4 = new List<String>();
    List<String> fieldKeys5 = new List<String>();
    List<String> fieldKeys6 = new List<String>();
    // 255 / 15 characters = 17
    for (Integer index = 0; index < 17 * 6; index++) {
      String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
      RollupState.GenericInfo info = new RollupState.GenericInfo();
      info.value = index;
      state.setState(stubAccountId, template, info);
      List<String> keys;
      if (index < 15) {
        keys = fieldKeys0;
      } else if (index < 30) {
        keys = fieldKeys1;
      } else if (index < 45) {
        keys = fieldKeys2;
      } else if (index < 60) {
        keys = fieldKeys3;
      } else if (index < 75) {
        keys = fieldKeys4;
      } else if (index < 90) {
        keys = fieldKeys5;
      } else if (index < 105) {
        keys = fieldKeys6;
      }
      keys.add(stubAccountId);
    }

    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT
        RelatedRecordKeys__c,
        RelatedRecordKeys1__c,
        RelatedRecordKeys2__c,
        RelatedRecordKeys3__c,
        RelatedRecordKeys4__c,
        RelatedRecordKeys5__c,
        RelatedRecordKeys6__c
      FROM RollupState__c
    ];
    Assert.areEqual(1, committedStates.size(), JSON.serialize(committedStates));
    Assert.areEqual(String.join(fieldKeys0, ','), committedStates.get(0).RelatedRecordKeys__c);
    Assert.areEqual(String.join(fieldKeys1, ','), committedStates.get(0).RelatedRecordKeys1__c);
    Assert.areEqual(String.join(fieldKeys2, ','), committedStates.get(0).RelatedRecordKeys2__c);
    Assert.areEqual(String.join(fieldKeys3, ','), committedStates.get(0).RelatedRecordKeys3__c);
    Assert.areEqual(String.join(fieldKeys4, ','), committedStates.get(0).RelatedRecordKeys4__c);
    Assert.areEqual(String.join(fieldKeys5, ','), committedStates.get(0).RelatedRecordKeys5__c);
    Assert.areEqual(String.join(fieldKeys6, ','), committedStates.get(0).RelatedRecordKeys6__c);
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
