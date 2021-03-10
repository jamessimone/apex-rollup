@isTest
private class RollupRelationshipFieldFinderTests {
  static RollupControl__mdt control = new RollupControl__mdt(MaxQueryRows__c = 10000);

  // TODO move this to integration tests
  @isTest
  static void shouldFindGreatGrandParentRelationshipBetweenCustomObjects() {
    Account greatGrandparent = new Account(Name = 'Great-grandparent');
    insert greatGrandparent;

    ParentApplication__c grandParent = new ParentApplication__c(Name = 'Grandparent', Account__c = greatGrandparent.Id);
    ParentApplication__c nonMatchingGrandParent = new ParentApplication__c(Name = 'Non-matching grandparent');
    insert new List<ParentApplication__c>{ grandParent, nonMatchingGrandParent };

    Application__c parent = new Application__c(Name = 'Parent', ParentApplication__c = grandParent.Id);
    Application__c nonMatchingParent = new Application__c(Name = 'Non matching parent', ParentApplication__c = nonMatchingGrandParent.Id);
    insert new List<Application__c>{ parent, nonMatchingParent };

    ApplicationLog__c child = new ApplicationLog__c(Application__c = parent.Id, Name = 'Test Rollup Grandchildren');
    ApplicationLog__c nonMatchingChild = new ApplicationLog__c(Name = 'Non matching child', Application__c = nonMatchingParent.Id);
    List<ApplicationLog__c> appLogs = new List<ApplicationLog__c>{ child, nonMatchingChild };
    insert appLogs;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      'Application__r.ParentApplication__r.Account__r.Name',
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(appLogs);
    System.assertEquals(true, traversal.isFinished, 'Traversal should not have aborted early');
    System.assertEquals(greatGrandparent, traversal.retrieveParent(child.Id), 'Account should match!');

    System.assertEquals(
      null,
      traversal.retrieveParent(nonMatchingChild.Id),
      'No matching records should be returned for relationship that does not go fully up the chain'
    );
  }

  @isTest
  static void shouldFindParentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent relationship between standard objects');
    insert parent;

    Opportunity opp = new Opportunity(AccountId = parent.Id, Name = 'Child opp', StageName = 'Prospecting', CloseDate = System.today());
    insert opp;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Name', Account.SObjectType, new Map<Id, SObject>());

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    System.assertEquals(parent, traversal.retrieveParent(opp.Id));
  }

  @isTest
  static void shouldFindGrandparentRelationshipBetweenStandardObjects() {
    Account parent = new Account(Name = 'Parent account looking up to User');
    insert parent;

    Opportunity opp = new Opportunity(AccountId = parent.Id, Name = 'Child opp looking up to account', StageName = 'Prospecting', CloseDate = System.today());
    insert opp;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', User.SObjectType, new Map<Id, SObject>());
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    parent = [SELECT OwnerId FROM Account WHERE Id = :parent.Id];
    System.assertEquals([SELECT Id, Name FROM User WHERE Id = :parent.OwnerId][0], traversal.retrieveParent(opp.Id), 'User should have been retrieved correctly!');
  }

  @isTest
  static void shouldBailEarlyIfQueryCountExceedsControlCount() {
    Account acc = new Account(Name = 'Parent to opp');
    insert acc;

    Opportunity opp = new Opportunity(AccountId = acc.Id, Name = 'Child opp');
    control.MaxQueryRows__c = 1;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', User.SObjectType, new Map<Id, SObject>());
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });

    System.assertEquals(false, traversal.isFinished, 'Should have bailed early!');
  }

  @isTest
  static void shouldNotReportFalsePositiveIfUltimateParentStaysTheSame() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    Account intermediateTwo = new Account(Name = 'Intermediate 2');
    insert new List<Account>{ intermediateOne, intermediateTwo };

    Opportunity opp = new Opportunity(AccountId = intermediateTwo.Id, Name = 'Child reparented', StageName = 'Prospecting', CloseDate = System.today());
    List<Opportunity> opps = new List<Opportunity>{ opp };
    insert opps;

    Map<Id, SObject> oldOpps = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Id = opp.Id, AccountId = intermediateOne.Id) };

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', User.SObjectType, oldOpps);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(false, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should not report false positive!');

    finder = new RollupRelationshipFieldFinder(control, 'Account.Name', Account.SObjectType, oldOpps);
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

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', User.SObjectType, oldOpps);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(opps);

    System.assertEquals(true, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should correctly report reparenting if old lookup null');

    oldOpps.put(opp.Id, new Opportunity(Id = opp.Id, AccountId = intermediateOne.Id));
    opp.AccountId = null;
    update opp;

    finder = new RollupRelationshipFieldFinder(control, 'Account.Owner.Name', User.SObjectType, oldOpps);
    System.assertEquals(true, traversal.isUltimatelyReparented(opp, 'AccountId'), 'Should correctly report reparenting if new lookup is null');
  }
}
