@IsTest
private class CustomMetadataDrivenTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new RollupParent__c(Name = CustomMetadataDrivenTests.class.getName());
  }

  @IsTest
  static void shouldRollupFromChildToParentOnInsert() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field, MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id, NumberField__c = 2);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id, NumberField__c = 2);

    Test.startTest();
    insert new List<RollupChild__c>{ childOne, childTwo };
    Test.stopTest();

    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];

    System.assertEquals(childOne.TextField__c, parent.TextField__c);
    System.assertEquals(childOne.NumberField__c, parent.NumberField__c);
  }

  @IsTest
  static void shouldRollupFromChildToParentOnUpdate() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST (with NumberField__c, TextField__c as the Order By fields), MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id, NumberField__c = 1);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id, NumberField__c = 2);
    insert new List<RollupChild__c>{ childOne, childTwo };

    childOne.TextField__c = 'c';
    childOne.NumberField__c = 0;
    // Rollup.RollupIntegrationChildRollupNumber uses RollupControl.Integration_Sync, so the NumberField__c update should happen BEFORE
    // going async
    update childOne;
    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];
    System.assertEquals(childTwo.NumberField__c, parent.NumberField__c);
    System.assertEquals(null, parent.TextField__c, 'Should not have a value yet since this rollup occurs async');

    Test.startTest();
    // now we force the async part to complete
    Test.stopTest();

    // re-assert on both fields being correct now, just to be sure
    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];
    System.assertEquals(childTwo.NumberField__c, parent.NumberField__c);
    System.assertEquals(childOne.TextField__c, parent.TextField__c);
  }

  @IsTest
  static void shouldRollupTextFromChildToParentOnDelete() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field, MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id, NumberField__c = 1);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id, NumberField__c = 2);
    insert new List<RollupChild__c>{ childOne, childTwo };

    Test.startTest();
    childOne.TextField__c = 'c';
    update childOne;
    delete childTwo; // and for my next trick ...
    Test.stopTest();

    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];

    System.assertEquals(childOne.TextField__c, parent.TextField__c);
    System.assertEquals(childOne.NumberField__c, parent.NumberField__c);
  }

  @IsTest
  static void regressionUpdatingEvalCriteriaShouldNotExcludeItemOnMultipleUpdatePath() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
    // DateField__c rollup relies on NumberField > 0
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', DateField__c = System.today().addDays(3), RollupParent__c = parent.Id, NumberField__c = 0);

    Test.startTest();

    insert childOne;
    childOne.DateField__c = childOne.DateField__c.addDays(-1);
    update childOne;

    // begin recursive update, but with a Child Object Where Clause field change
    childOne.NumberField__c = 1;
    update childOne;

    Test.stopTest();

    parent = [SELECT DateField__c FROM RollupParent__c WHERE Id = :parent.Id];
    System.assertEquals(childOne.DateField__c, parent.DateField__c);
  }

  @IsTest
  static void shouldWorkForParentLevelWhereClausesFromTrigger() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // relies on extra-tests\customMetadata\Rollup.ParentWhereClauseFromTrigger.md-meta.xml
    Rollup.defaultControl = new RollupControl__mdt(
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      IsRollupLoggingEnabled__c = true,
      ReplaceCalcItemsAsyncWhenOverCount__c = 2
    );
    ParentApplication__c parentApp = new ParentApplication__c(Name = 'Parent');
    insert parentApp;

    Test.startTest();
    Application__c app = new Application__c(Picklist__c = 'Standard', ParentApplication__c = parentApp.Id);
    insert app;
    Test.stopTest();

    parentApp = [SELECT Name FROM ParentApplication__c];
    System.assertEquals(app.Picklist__c, parentApp.Name);

    app.Picklist__c = 'Something with and in the name';
    update app;

    System.assert(true, 'Should make it here (validate update works with Trigger.oldMap)');
  }

  @IsTest
  public static void shouldRecalcRollupToGrandparentWhenChildIsReparented() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // relies on extra-tests\customMetadata\Rollup.AmountFromChildrenToGrandparent.md-meta.xml
    RollupGrandparent__c grandparentOne = new RollupGrandparent__c(AmountfromChildren__c = 0);
    RollupGrandparent__c grandparentTwo = new RollupGrandparent__c(AmountfromChildren__c = 0);
    insert new List<RollupGrandparent__c>{ grandparentOne, grandparentTwo };

    RollupParent__c parentOne = new RollupParent__c(RollupGrandparent__c = grandparentOne.Id);
    RollupParent__c parentTwo = new RollupParent__c(RollupGrandparent__c = grandparentTwo.Id);
    insert new List<RollupParent__c>{ parentOne, parentTwo };

    RollupChild__c child = new RollupChild__c(RollupParent__c = parentOne.Id, NumberField__c = 5.00);
    insert child;

    Test.startTest();
    child.RollupParent__c = parentTwo.Id;
    update child;
    Test.stopTest();

    child = [SELECT NumberField__c, RollupParent__r.RollupGrandparent__c FROM RollupChild__c WHERE Id = :child.Id];
    System.assertEquals(grandparentTwo.Id, child.RollupParent__r.RollupGrandparent__c);

    grandparentOne = [SELECT AmountfromChildren__c FROM RollupGrandParent__c WHERE Id = :grandparentOne.Id];
    System.assertEquals(null, grandparentOne.AmountfromChildren__c);

    grandparentTwo = [SELECT AmountfromChildren__c FROM RollupGrandParent__c WHERE Id = :grandparentTwo.Id];
    System.assertEquals(child.NumberField__c, grandparentTwo.AmountfromChildren__c);
  }

  @IsTest
  static void rollupsSucceedDuringFutureMethods() {
    if (RollupTestUtils.IS_NAMESPACED_PACKAGE_ORG) {
      return;
    }
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];

    Test.startTest();
    insertRollupChildrenAsync(parent.Id, 'a', 1);
    Test.stopTest();

    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];
    System.assertEquals('a', parent.TextField__c);
    System.assertEquals(2, parent.NumberField__c);
  }

  @Future
  static void insertRollupChildrenAsync(Id parentId, String firstTextField, Integer firstNumberField) {
    // uses FIRST with TextField__c as the Order By field, MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(
      Name = 'Child one',
      TextField__c = firstTextField,
      RollupParent__c = parentId,
      NumberField__c = firstNumberField
    );
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parentId, NumberField__c = 2);
    insert new List<RollupChild__c>{ childOne, childTwo };
  }
}
