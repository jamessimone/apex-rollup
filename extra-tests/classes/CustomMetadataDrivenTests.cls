@isTest
private class CustomMetadataDrivenTests {

  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new RollupParent__c(Name = 'CustomMetadataDrivenTests');
  }

  @isTest
  static void shouldRollupTextFromChildToParentOnInsert() {
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id);

    Test.startTest();
    insert new List<RollupChild__c>{ childOne, childTwo };
    Test.stopTest();

    parent = [SELECT Id, TextField__c FROM RollupParent__c];

    System.assertEquals(childOne.TextField__c, parent.TextField__c);
  }

  @isTest
  static void shouldRollupTextFromChildToParentOnUpdate() {
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id);
    insert new List<RollupChild__c>{ childOne, childTwo };

    Test.startTest();
    childOne.TextField__c = 'c';
    update childOne;
    Test.stopTest();

    parent = [SELECT Id, TextField__c FROM RollupParent__c];

    System.assertEquals(childTwo.TextField__c, parent.TextField__c);
  }

  @isTest
  static void shouldRollupTextFromChildToParentOnDelete() {
    RollupParent__c parent = [SELECT Id FROM RollupParent__c];
    // uses FIRST with TextField__c as the Order By field
    RollupChild__c childOne = new RollupChild__c(Name = 'Child one', TextField__c = 'a', RollupParent__c = parent.Id);
    RollupChild__c childTwo = new RollupChild__c(Name = 'Child two', TextField__c = 'b', RollupParent__c = parent.Id);
    insert new List<RollupChild__c>{ childOne, childTwo };

    Test.startTest();
    childOne.TextField__c = 'c';
    update childOne;
    delete childTwo; // and for my next trick ...
    Test.stopTest();

    parent = [SELECT Id, TextField__c FROM RollupParent__c];

    System.assertEquals(childOne.TextField__c, parent.TextField__c);
  }
}