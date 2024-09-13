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
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'CONCAT'), averageInfo);
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'FIRST'), new RollupState.SObjectInfo());
    state.setState(secondStubId, new Rollup__mdt(RollupOperation__c = 'MOST'), new RollupState.MostInfo());

    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);

    Set<String> relatedRecordKeys = new Set<String>{ '%' + stubAccountId + '%', '%' + secondStubId + '%' };
    Test.startTest();
    state.commitState(stubJobId);
    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    state.setState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), info);
    info.value = 6;
    state.commitState(stubJobId);
    Test.stopTest();

    RollupState__c insertedState = [SELECT Id, Body0__c FROM RollupState__c WHERE RelatedRecordKeys__c LIKE :relatedRecordKeys];
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
      Body0__c = averageInfo.toString()
    );
    insert new List<RollupState__c>{
      existingAverageState,
      new RollupState__c(RelatedJobId__c = stubJobId, RelatedRecordKeys__c = stubAccountId, Body0__c = info.toString())
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
      hasCorrectAverageInfo = hasCorrectAverageInfo || createdState.Body0__c.contains(averageInfo.toString());
      hasCorrectGenericInfo = hasCorrectGenericInfo || createdState.Body0__c.contains(info.toString());
    }
    Assert.isTrue(hasCorrectAverageInfo, 'new average state should have been updated');
    Assert.isTrue(hasCorrectGenericInfo, 'Generic info should not be wiped out');
  }

  @IsTest
  static void splitsReallyLongStatesForTheSameRecord() {
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    Rollup__mdt template = new Rollup__mdt(
      RollupOperation__c = Rollup.Op.CONCAT_DISTINCT.name(),
      LookupFieldOnCalcItem__c = 'Some_Long_Value__c',
      LookupFieldOnLookupObject__c = 'Another_Longer_Value__c',
      RollupFieldOnCalcItem__c = 'Long_Value_Again__c',
      RollupFieldOnLookupObject__c = 'Long_Rollup_Value_With_Lots_Of_Spaces__c'
    );
    RollupState state = new RollupState();

    for (Integer index = 0; index < 7000; index++) {
      Rollup__mdt clonedMeta = template.clone();
      clonedMeta.LookupFieldOnCalcItem__c += '' + index;
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
