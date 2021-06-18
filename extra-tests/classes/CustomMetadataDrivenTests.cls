@isTest
private class CustomMetadataDrivenTests {

  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new RollupParent__c(Name = 'CustomMetadataDrivenTests');
  }

  @isTest
  static void shouldRollupFromChildToParentOnInsert() {
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field, MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id, NumberField__c = 3);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id, NumberField__c = 2);

    Test.startTest();
    insert new List<RollupChild__c>{ childOne, childTwo };
    Test.stopTest();

    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];

    System.assertEquals(childOne.TextField__c, parent.TextField__c);
    System.assertEquals(childOne.NumberField__c, parent.NumberField__c);
  }

  @isTest
  static void shouldRollupFromChildToParentOnUpdate() {
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field, MAX for the NumberField__c
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id, NumberField__c = 3);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id, NumberField__c = 2);
    insert new List<RollupChild__c>{ childOne, childTwo };

    Test.startTest();
    childOne.TextField__c = 'c';
    childOne.NumberField__c = 0;
    update childOne;
    Test.stopTest();

    parent = [SELECT Id, TextField__c, NumberField__c FROM RollupParent__c];

    System.assertEquals(childTwo.TextField__c, parent.TextField__c);
    System.assertEquals(childTwo.NumberField__c, parent.NumberField__c);
  }

  @isTest
  static void shouldRollupTextFromChildToParentOnDelete() {
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

  @isTest
  static void regressionUpdatingEvalCriteriaShouldNotExcludeItemOnMultipleUpdatePath() {
    // DateField__c rollup relies on NumberField > 0
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', DateField__c = System.today().addDays(3), RollupParent__c = parent.Id, NumberField__c = 0);

    Test.startTest();

    insert childOne;
    childOne.DateField__c = childOne.DateField__c.addDays(-1);
    update childOne;

    // begin recursive update, but with a Calc Item Where Clause field change
    childOne.NumberField__c = 1;
    update childOne;

    Test.stopTest();

    parent = [SELECT DateField__c FROM RollupParent__c WHERE Id = :parent.Id];
    System.assertEquals(childOne.DateField__c, parent.DateField__c);
  }
}