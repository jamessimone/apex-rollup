@isTest
private class RollupRelationshipFieldFinderTests {
  static RollupControl__mdt control = new RollupControl__mdt(MaxQueryRows__c = 10000);

  @isTest
  static void shouldFindParentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent relationship between standard objects');
    insert parent;

    Opportunity opp = new Opportunity(AccountId = parent.Id, Name = 'Child opp', StageName = 'Prospecting', CloseDate = System.today());
    insert opp;

    Set<String> uniqueFieldNames = new Set<String>{ 'Name', 'Id' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      'Account.Name',
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    System.assertEquals(parent, traversal.retrieveParent(opp.Id));

    finder = new RollupRelationshipFieldFinder(control, 'Name', uniqueFieldNames, Account.SObjectType, new Map<Id, SObject>());
    traversal = finder.getParents(new List<Opportunity>{ opp });

    System.assertEquals(parent, traversal.retrieveParent(opp.Id));
  }

  @isTest
  static void shouldFindGrandparentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent account looking up to User');
    insert parent;

    Opportunity opp = new Opportunity(AccountId = parent.Id, Name = 'Child opp looking up to account', StageName = 'Prospecting', CloseDate = System.today());
    insert opp;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      'Account.Owner.Name',
      new Set<String>{ 'Name', 'Id' },
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    parent = [SELECT OwnerId FROM Account WHERE Id = :parent.Id];
    System.assertEquals(
      [SELECT Id, Name FROM User WHERE Id = :parent.OwnerId][0],
      traversal.retrieveParent(opp.Id),
      'User should have been retrieved correctly!'
    );
  }

  @isTest
  static void shouldBailEarlyIfQueryCountExceedsControlCount() {
    Account acc = new Account(Name = 'Parent to opp');
    insert acc;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'Child opp');
    control.MaxQueryRows__c = 1;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      'Account.Owner.Name',
      new Set<String>{ 'Name', 'Id' },
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    System.assertEquals(false, traversal.getIsFinished(), 'Should have bailed early!');
  }

  @isTest
  static void shouldNotReportFalsePositiveIfUltimateParentStaysTheSame() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    Account intermediateTwo = new Account(Name = 'Intermediate 2');
    insert new List<Account>{ intermediateOne, intermediateTwo };

    List<Account> updatedAccounts = [SELECT Id, OwnerId FROM Account];
    if (updatedAccounts.size() == 2) {
      // don't run the rest of the test if the org has some kind of ownership assignment going on that would invalidate
      // the results
      Account one = updatedAccounts[0];
      Account two = updatedAccounts[1];
      if (one.OwnerId != two.OwnerId) {
        return;
      }
    }

    Opportunity opp = new Opportunity(AccountId = intermediateTwo.Id, Name = 'Child reparented', StageName = 'Prospecting', CloseDate = System.today());
    List<Opportunity> opps = new List<Opportunity>{ opp };
    insert opps;

    Map<Id, SObject> oldOpps = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, AccountId = intermediateOne.Id) };

    Set<String> uniqueFieldNames = new Set<String>{ 'Name', 'Id' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', uniqueFieldNames, User.SObjectType, oldOpps);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(false, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should not report false positive!');

    finder = new RollupRelationshipFieldFinder(control, 'Account.Name', uniqueFieldNames, Account.SObjectType, oldOpps);
    traversal = finder.getParents(opps);

    System.assertEquals(true, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should correctly report reparenting if ultimate lookup is different');
  }

  @isTest
  static void shouldReportReparentingCorrectlyForNulls() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    insert new List<Account>{ intermediateOne };

    Opportunity opp = new Opportunity(AccountId = intermediateOne.Id, Name = 'Child reparented', StageName = 'Prospecting', CloseDate = System.today());
    List<Opportunity> opps = new List<Opportunity>{ opp };
    insert opps;

    Map<Id, SObject> oldOpps = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, AccountId = null) };

    Set<String> uniqueFieldNames = new Set<String>{ 'Id', 'Name' };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', uniqueFieldNames, User.SObjectType, oldOpps);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(true, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should correctly report reparenting if old lookup null');

    oldOpps.put(opp.Id, new Opportunity(Id = opp.Id, AccountId = intermediateOne.Id));
    opp.AccountId = null;
    update opp;

    finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', uniqueFieldNames, User.SObjectType, oldOpps);
    System.assertEquals(true, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should correctly report reparenting if new lookup is null');
  }

  @isTest
  static void shouldReportReparentingCorrectlyForImmediateParent() {
    Account parentOne = new Account(Name = 'Parent1');
    Account parentTwo = new Account(Name = 'Parent2');
    insert new List<Account>{ parentOne, parentTwo };

    Opportunity oppOne = new Opportunity(AccountId = parentOne.Id, Name = 'Child1', StageName = 'Prospecting', CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(AccountId = parentOne.Id, Name = 'Child1', StageName = 'Prospecting', CloseDate = System.today());
    List<Opportunity> opps = new List<Opportunity>{ oppOne, oppTwo };
    insert opps;

    Map<Id, SObject> oldOpps = new Map<Id, SObject>{ oppOne.Id => oppOne, oppTwo.Id => new Opportunity(AccountId = parentTwo.Id) };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Name', new Set<String>{ 'Name', 'Id' }, Account.SObjectType, oldOpps);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(true, traversal.isUltimatelyReparented(oppTwo, 'AccountId'));
    System.assertEquals(false, traversal.isUltimatelyReparented(oppOne, 'AccountId'));
  }

  @isTest
  static void shouldTrackMultipleParents() {
    Account parentOne = new Account(Name = 'SoloParent');
    insert parentOne;

    Opportunity oppOne = new Opportunity(AccountId = parentOne.Id, Name = 'FirstParentedChild', StageName = 'Prospecting', CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(AccountId = parentOne.Id, Name = 'SecondParentedChild', StageName = 'Prospecting', CloseDate = System.today());
    List<Opportunity> opps = new List<Opportunity>{ oppOne, oppTwo };
    insert opps;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      'Name',
      new Set<String>{ 'Name', 'Id' },
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(parentOne, traversal.retrieveParent(oppOne.Id), 'First opp parent should not be exluded!');
    System.assertEquals(parentOne, traversal.retrieveParent(oppTwo.Id), 'Second opp should not have been excluded!');
  }
}
