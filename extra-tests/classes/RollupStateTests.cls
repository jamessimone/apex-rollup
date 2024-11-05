@IsTest
private class RollupStateTests {
  @IsTest
  static void commitsAndLoadsStateProperly() {
    RollupState state = new RollupState();
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    RollupState.GenericInfo info = (RollupState.GenericInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'SUM'),
      RollupState.GenericInfo.class
    );
    info.value = 5;
    RollupState.AverageInfo averageInfo = (RollupState.AverageInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'CONCAT'),
      RollupState.AverageInfo.class
    );
    averageInfo.increment(10);
    RollupState.SObjectInfo sObjectInfo = (RollupState.SObjectInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'FIRST'),
      RollupState.SObjectInfo.class
    );
    sObjectInfo.setItem(new Account(AnnualRevenue = 1000));
    String secondStubId = RollupTestUtils.createId(Contact.SObjectType);
    RollupState.MostInfo mostInfo = (RollupState.MostInfo) state.getState(
      secondStubId,
      new Rollup__mdt(RollupOperation__c = 'MOST'),
      RollupState.MostInfo.class
    );
    mostInfo.setValues(5, 'some string');
    // populate a null state value to be sure if the last iteration is "empty" the body is still properly committed
    state.getState(secondStubId, new Rollup__mdt(RollupOperation__c = 'LAST'), RollupState.GenericInfo.class);
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    Set<String> relatedRecordKeys = new Set<String>{ '%' + stubAccountId + '%', '%' + secondStubId + '%' };

    state.commitState(stubJobId);
    state.loadState(stubJobId, new Set<String>{ stubAccountId, secondStubId });
    info = (RollupState.GenericInfo) state.getState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), RollupState.GenericInfo.class);
    info.value = 6;
    state.commitState(stubJobId);

    RollupState__c insertedState = [
      SELECT Id, Body0__c
      FROM RollupState__c
      WHERE RelatedRecordKeys0__c LIKE :relatedRecordKeys
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
    RollupState state = new RollupState();
    RollupState.AverageInfo averageInfo = (RollupState.AverageInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'AVERAGE'),
      RollupState.AverageInfo.class
    );
    averageInfo.increment(10);
    RollupState.GenericInfo info = (RollupState.GenericInfo) state.getState(
      stubAccountId,
      new Rollup__mdt(RollupOperation__c = 'SUM'),
      RollupState.GenericInfo.class
    );

    RollupState__c existingAverageState = new RollupState__c(
      RelatedJobId__c = stubJobId,
      RelatedRecordKeys0__c = stubAccountId,
      Body0__c = JSON.serialize(averageInfo.getUntypedState())
    );
    insert new List<RollupState__c>{
      existingAverageState,
      new RollupState__c(RelatedJobId__c = stubJobId, RelatedRecordKeys0__c = stubAccountId, Body0__c = JSON.serialize(info.getUntypedState()))
    };

    state = new RollupState();
    state.loadState(stubJobId, new Set<String>{ stubAccountId });
    info = (RollupState.GenericInfo) state.getState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'SUM'), RollupState.GenericInfo.class);
    info.value = 5;
    averageInfo = (RollupState.AverageInfo) state.getState(stubAccountId, new Rollup__mdt(RollupOperation__c = 'AVERAGE'), RollupState.AverageInfo.class);
    averageInfo.increment(20);

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
    // the type names take up a bit more space during namespaced packaging
    RollupState.maxBodyLength = RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG ? 20000 : 18000;
    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    String stubAccountId = RollupTestUtils.createId(Account.SObjectType);
    Rollup__mdt template = new Rollup__mdt(DeveloperName = 'exampleUnique40CharacterLimit');
    RollupState state = new RollupState();

    List<Map<String, Object>> statesToSample = new List<Map<String, Object>>();
    for (Integer index = 0; index < 400; index++) {
      Rollup__mdt clonedMeta = template.clone();
      clonedMeta.DeveloperName += '' + index;
      RollupState.GenericInfo info = (RollupState.GenericInfo) state.getState(stubAccountId, clonedMeta, RollupState.GenericInfo.class);
      info.value = index;
      if (index < 20) {
        statesToSample.add(info.getUntypedState());
      }
    }
    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT Body0__c, RelatedRecordKeys0__c
      FROM RollupState__c
    ];

    Assert.areEqual(3, committedStates.size());
    Boolean body0Filled = false;
    Boolean sampleStatesFilled = false;
    for (Integer index = 0; index < committedStates.size(); index++) {
      RollupState__c committedState = committedStates[index];
      body0Filled = body0Filled || committedState.Body0__c != null;
      Assert.areEqual(stubAccountId, committedState.RelatedRecordKeys0__c, 'State was missing key at index: ' + index);
      if (sampleStatesFilled) {
        Boolean isDuplicate = committedState.Body0__c.contains(JSON.serialize(statesToSample).removeStart('[').removeEnd(']'));
        if (isDuplicate) {
          throw new IllegalArgumentException('Body0__c should not match for both states');
        }
      } else {
        sampleStatesFilled = committedState.Body0__c?.contains(JSON.serialize(statesToSample).removeStart('[').removeEnd(']')) == true;
      }
    }

    Assert.isTrue(body0Filled);
    Assert.isTrue(sampleStatesFilled, committedStates[0].Body0__c?.substring(0, 50));
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
    List<String> secondFieldKeys0 = new List<String>();
    String firstAccountId = RollupTestUtils.createId(Account.SObjectType) + 'aaa';
    // 255 / 18 characters ~= 13 records per field (accounting for commas)
    // 12 because with 11 fields, we want to "overflow" to the second RelatedRecordKeys0__c
    for (Integer index = 0; index < 13 * 12; index++) {
      String stubAccountId = index == 0 ? firstAccountId : RollupTestUtils.createId(Account.SObjectType) + 'aaa';
      RollupState.GenericInfo info = (RollupState.GenericInfo) state.getState(stubAccountId, template, RollupState.GenericInfo.class);
      info.value = index;
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
        keys = secondFieldKeys0;
      }
      keys?.add(stubAccountId);
      fullKeys.add(stubAccountId);
    }

    Id stubJobId = RollupTestUtils.createId(AsyncApexJob.SObjectType);
    state.commitState(stubJobId);

    List<RollupState__c> committedStates = [
      SELECT
        RelatedRecordKeys0__c,
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
      WHERE RelatedJobId__c = :stubJobId
    ];
    // ensure that loadState can be called with the full spread of keys
    state.loadState(stubJobId, fullKeys);

    Assert.areEqual(2, committedStates.size());
    RollupState__c firstState = committedStates.get(0);
    RollupState__c secondState = committedStates.get(1);
    // swap out for the correct "first" state - since they're inserted at the same time
    // there's no deterministic way to order them
    if (firstState.RelatedRecordKeys0__c.startsWith(firstAccountId) == false) {
      secondState = firstState;
      firstState = committedStates.get(1);
    }
    Assert.isNotNull(firstState.RelatedRecordKeys0__c, 'RelatedRecordKeys0__c should have been filled out');
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
    Assert.isNotNull(secondState.RelatedRecordKeys0__c, 'Second RelatedRecordKeys0__c should have been filled out');

    Assert.areEqual(String.join(fieldKeys0, ','), firstState.RelatedRecordKeys0__c, 'fieldKeys0');
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
    Assert.areEqual(String.join(secondFieldKeys0, ','), secondState.RelatedRecordKeys0__c, 'secondFieldKeys0');
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
      new RollupState__c(RelatedJobId__c = stubJobId, RelatedRecordKeys0__c = stubAccountId)
    };

    RollupState state = new RollupState();
    state.loadState(stubJobId, new Set<String>{ stubAccountId });
    state.loadState(stubJobId, new Set<String>{ stubAccountId });

    Assert.areEqual(1, Limits.getQueryRows());
    Assert.areEqual(1, Limits.getQueries());
  }

  @IsTest
  static void alwaysTracksRelatedRecordKeys() {
    String firstId = RollupTestUtils.createId(Account.SObjectType) + 'aaa';
    RollupState.maxRelatedKeysLength = firstId.length();
    Rollup__mdt template = new Rollup__mdt(DeveloperName = 'unique');
    RollupState state = new RollupState();
    List<String> range = new String[14];
    String serializedLastState;
    String thirdToLastKey;
    String secondToLastKey;
    String lastKey;
    for (Integer index = 0; index <= range.size(); index++) {
      String stubAccountId = index == 0 || index == 12 ? firstId : RollupTestUtils.createId(Account.SObjectType) + 'bbb';
      RollupState.GenericInfo info = (RollupState.GenericInfo) state.getState(stubAccountId, template, RollupState.GenericInfo.class);
      info.value = index;
      switch on index {
        when 11 {
          thirdToLastKey = stubAccountId;
        }
        when 13 {
          secondToLastKey = stubAccountId;
        }
        when 14 {
          lastKey = stubAccountId;
          serializedLastState = JSON.serialize(info.getUntypedState());
        }
      }
    }

    state.commitState(RollupTestUtils.createId(AsyncApexJob.SObjectType));

    List<RollupState__c> committedStates = [
      SELECT
        Body0__c,
        RelatedRecordKeys0__c,
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
    Assert.areEqual(2, committedStates.size());
    for (RollupState__c committedState : committedStates) {
      if (committedState.RelatedRecordKeys3__c == null) {
        Assert.isTrue(committedState.Body0__c.contains(serializedLastState));
        Assert.areEqual(thirdToLastKey, committedState.RelatedRecordKeys0__c);
        Assert.areEqual(secondToLastKey, committedState.RelatedRecordKeys1__c);
        Assert.areEqual(lastKey, committedState.RelatedRecordKeys2__c);
      } else {
        Assert.areEqual(firstId, committedState.RelatedRecordKeys0__c);
      }
    }
  }
}
