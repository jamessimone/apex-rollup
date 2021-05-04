@isTest
private class RollupRelationshipFieldFinderTests {
  static RollupControl__mdt control = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 10000);

  @isTest
  static void shouldFindParentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent relationship between standard objects');
    insert parent;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = parent.Id, Name = 'Child cpa');
    insert cpa;

    Set<String> uniqueFieldNames = new Set<String>{ 'Name', 'Id' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Name'),
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    System.assertEquals(parent, traversal.retrieveParent(cpa.Id));

    // validates that the relationship field finder works even if a fully qualified path isn't provided if the parent
    // is "just" the next level up
    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    System.assertEquals(parent, traversal.retrieveParent(cpa.Id));
  }

  @isTest
  static void shouldFindGrandparentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent account looking up to User');
    insert parent;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = parent.Id, Name = 'Child looking up to account');
    insert cpa;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      new Set<String>{ 'Name', 'Id' },
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    parent = [SELECT OwnerId FROM Account WHERE Id = :parent.Id];
    System.assertEquals(
      [SELECT Id, Name FROM User WHERE Id = :parent.OwnerId][0],
      traversal.retrieveParent(cpa.Id),
      'User should have been retrieved correctly!'
    );
  }

  @isTest
  static void shouldBailEarlyIfQueryCountExceedsControlCount() {
    Account acc = new Account(Name = 'Parent to cpa');
    insert acc;

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Child cpa');
    control.MaxNumberOfQueries__c = 1;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      new Set<String>{ 'Name', 'Id' },
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    System.assertEquals(false, traversal.getIsFinished(), 'Should have bailed early!');
  }

  @isTest
  static void shouldNotReportFalsePositiveIfUltimateParentStaysTheSame() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    Account intermediateTwo = new Account(Name = 'Intermediate 2');
    insert new List<Account>{ intermediateOne, intermediateTwo };

    List<Account> updatedAccounts = [SELECT Id, OwnerId, Name FROM Account];
    if (updatedAccounts.size() == 2) {
      // don't run the rest of the test if the org has some kind of ownership assignment going on that would invalidate
      // the results
      Account one = updatedAccounts[0];
      Account two = updatedAccounts[1];
      if (one.OwnerId != two.OwnerId) {
        return;
      } else {
        intermediateOne = one.Id == intermediateOne.Id ? one : two;
        intermediateTwo = two.Id == intermediateTwo.Id ? two : one;
      }
    }

    ContactPointAddress cpa = new ContactPointAddress(ParentId = intermediateTwo.Id, Name = 'Child reparented');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    insert cpas;

    Map<Id, SObject> oldCpas = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, ParentId = intermediateOne.Id) };

    Set<String> uniqueFieldNames = new Set<String>{ 'Name', 'Id' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Owner.Name'),
      uniqueFieldNames,
      User.SObjectType,
      oldCpas
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(false, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should not report false positive!');
    System.assertEquals(intermediateTwo.Id, traversal.getOldLookupId(cpa, 'ParentId'));

    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Name'),
      uniqueFieldNames,
      Account.SObjectType,
      oldCpas
    );
    traversal = finder.getParents(cpas);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if ultimate lookup is different');
  }

  @isTest
  static void shouldReportReparentingCorrectlyForNulls() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    insert new List<Account>{ intermediateOne };

    ContactPointAddress cpa = new ContactPointAddress(ParentId = intermediateOne.Id, Name = 'Child reparented');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    insert cpas;

    Map<Id, SObject> oldOpps = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, ParentId = null) };

    Set<String> uniqueFieldNames = new Set<String>{ 'Id', 'Name' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      User.SObjectType,
      oldOpps
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if old lookup null');

    oldOpps.put(cpa.Id, new ContactPointAddress(Id = cpa.Id, ParentId = intermediateOne.Id));
    cpa.ParentId = null;
    update cpa;

    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      User.SObjectType,
      oldOpps
    );
    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if new lookup is null');
  }

  @isTest
  static void shouldReportReparentingCorrectlyForImmediateParent() {
    Account parentOne = new Account(Name = 'Parent1');
    Account parentTwo = new Account(Name = 'Parent2');
    insert new List<Account>{ parentOne, parentTwo };

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'Child1');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentOne.Id, Name = 'Child2');
    List<ContactPointAddress> opps = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert opps;

    Map<Id, SObject> oldOpps = new Map<Id, SObject>{ cpaOne.Id => cpaOne, cpaTwo.Id => new ContactPointAddress(ParentId = parentTwo.Id) };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      new Set<String>{ 'Name', 'Id' },
      Account.SObjectType,
      oldOpps
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpaTwo, 'ParentId'));
    System.assertEquals(false, traversal.isUltimatelyReparented(cpaOne, 'ParentId'));
  }

  @isTest
  static void shouldTrackMultipleParents() {
    Account parentOne = new Account(Name = 'SoloParent');
    insert parentOne;

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentOne.Id, Name = 'SecondParentedChild');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      new Set<String>{ 'Name', 'Id' },
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(parentOne, traversal.retrieveParent(cpaOne.Id), 'First opp parent should not be exluded!');
    System.assertEquals(parentOne, traversal.retrieveParent(cpaTwo.Id), 'Second opp should not have been excluded!');
  }

  @isTest
  static void shouldProperlyReturnParentRecordsWithNestedConditionals() {
    Account parentOne = new Account(Name = 'match', AccountNumber = '1');
    Account parentTwo = new Account(Name = 'non-match');
    insert new List<Account>{ parentOne, parentTwo };

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentTwo.Id, Name = 'SecondParentedChild');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        GrandparentRelationshipFieldPath__c = 'Parent.Name',
        CalcItemWhereClause__c = 'Parent.Name != \'\' AND (Parent.Name != \'' +
          parentOne.Name +
          '\' OR Parent.AccountNumber = \'' +
          parentOne.AccountNumber +
          '\') AND Parent.Name != \'' +
          parentTwo.Name +
          '\''
      ),
      new Set<String>{ 'Name', 'Id' },
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    // we don't anticipate it being necessary to return fields used in the where clause; just that records are filtered correctly
    Account expectedAcc = new Account(Id = parentOne.Id, Name = parentOne.Name);
    System.assertEquals(expectedAcc, traversal.retrieveParent(cpaOne.Id), 'First opp parent should not be exluded with nested conditional!');
    System.assertEquals(null, traversal.retrieveParent(cpaTwo.Id), 'Second opp should have been excluded with clause after nested conditional!');
  }

  @isTest
  static void shouldTraverseAllTheWayUpWhenMetadataFlagIsEnabled() {
    Account parentOne = new Account(Name = 'ultimate parent');
    insert parentOne;
    Account parentTwo = new Account(Name = 'child parent', ParentId = parentOne.Id);
    // also start another chain of relationships
    Account secondParent = new Account(Name = 'second child parent', ParentId = parentOne.Id);
    insert new List<Account>{ parentTwo, secondParent };

    Account grandChild = new Account(Name = 'grandchild', ParentId = secondParent.Id);
    insert grandChild;

    Account greatGrandchild = new Account(Name = 'great-grandchild', ParentId = grandChild.Id);
    insert greatGrandchild;

    Account greatGreatGrandchild = new Account(Name = 'great great grandchild', ParentId = greatGrandchild.Id);
    insert greatGreatGrandchild;

    Account greatGreatGreatGrandchild = new Account(Name = 'great great great!', ParentId = greatGreatGrandchild.Id);
    insert greatGreatGreatGrandchild;

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentTwo.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = greatGreatGreatGrandchild.Id, Name = 'Second parented child');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        RollupToUltimateParent__c = true,
        UltimateParentLookup__c = 'ParentId',
        GrandparentRelationshipFieldPath__c = 'Parent.Name'
      ),
      new Set<String>{ 'Name', 'Id' },
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    Account expectedAcc = new Account(Id = parentOne.Id, Name = parentOne.Name);
    System.assertEquals(expectedAcc, traversal.retrieveParent(cpaOne.Id), 'Ultimate parent should have been used!');
    System.assertEquals(expectedAcc, traversal.retrieveParent(cpaTwo.Id), 'Ultimate parent should be found even if 5+ levels deep in hierarchy');
  }
}
