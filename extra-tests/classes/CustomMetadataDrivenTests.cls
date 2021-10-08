@IsTest
private class CustomMetadataDrivenTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    insert new RollupParent__c(Name = CustomMetadataDrivenTests.class.getName());
  }

  @IsTest
  static void shouldRollupFromChildToParentOnInsert() {
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
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

  @IsTest
  static void shouldRollupFromChildToParentOnUpdate() {
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
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

  @IsTest
  static void shouldRollupTextFromChildToParentOnDelete() {
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
    // uses a combination of Rollup__mdt found in extra-tests/customMetadata AND extra-tests/triggers/RollupChildTrigger.trigger
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

  @IsTest
  static void shouldRunCorrectlyForGrandparentReparenting() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    Account secondGreatGrandparent = new Account(Name = 'Second great-grandparent');
    insert new List<Account>{ greatGrandparent, secondGreatGrandparent };

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = greatGrandparent.Id);
    ParentApplication__c secondGrandparent = new ParentApplication__c(Name = 'Second grandparent', Account__c = secondGreatGrandparent.Id);
    insert new List<ParentApplication__c>{ grandParent, secondGrandparent };

    Application__c parent = new Application__c(Name = 'Parent-level', ParentApplication__c = grandParent.Id);
    Application__c secondParent = new Application__c(Name = 'Second parent-level', ParentApplication__c = secondGrandparent.Id);
    insert new List<Application__c>{ parent, secondParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = parent.Id, Name = greatGrandparent.Name);
    ApplicationLog__c secondChild = new ApplicationLog__c(Application__c = secondParent.Id, Name = secondGreatGrandparent.Name);
    insert new List<ApplicationLog__c>{ child, secondChild };

    child = new ApplicationLog__c(Id = child.Id, Application__c = secondParent.Id, Name = 'Test Rollup Grandchildren Reparenting');
    secondChild = new ApplicationLog__c(Id = secondChild.Id, Name = 'Reparenting deux', Application__c = parent.Id);

    Test.startTest();
    update new List<ApplicationLog__c>{ child, secondChild };
    Test.stopTest();

    Account updatedGreatGrandparent = [SELECT Name FROM Account WHERE Id = :greatGrandparent.Id];
    Account updatedGreatGrandparentTwo = [SELECT Name FROM Account WHERE Id = :secondGreatGrandparent.Id];

    System.assertEquals(secondChild.Name, updatedGreatGrandparent.Name, 'CONCAT_DISTINCT and reparenting should have worked');
    System.assertEquals(child.Name, updatedGreatGrandparentTwo.Name, 'CONCAT_DISTINCT and reparenting should have worked again');
  }
}
