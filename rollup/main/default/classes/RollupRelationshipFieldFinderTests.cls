@isTest
private class RollupRelationshipFieldFinderTests {
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

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder('Application__r.ParentApplication__r.Account__r.Name', 'Account');

    RollupRelationshipFieldFinder.TraversalObject traversal = finder.getParents(appLogs);
    System.assertEquals(true, traversal.isFinished, 'Traversal should not have aborted early');
    System.assertEquals(greatGrandparent, traversal.retrieveParents(child.Id)[0], 'Account should match!');

    System.assertEquals(
      true,
      traversal.retrieveParents(nonMatchingChild.Id).isEmpty(),
      'No matching records should be returned for relationship that does not go fully up the chain'
    );
  }

  // @isTest
  // static void shouldFindParentRelationshipBetweenStandardObjects() {
  //   Id accountId = '0016g00000TvyKnAAJ';
  //   Opportunity opp = new Opportunity(AccountId = accountId);

  //   RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder('Account');

  //   System.assertEquals(
  //     new List<SObjectType>{ Opportunity.SObjectType, Account.SObjectType },
  //     finder.getParentTypes(opp.getSObjectType(), 'AccountId', opp.AccountId)
  //   );
  // }

  // @isTest
  // static void shouldFindGrandParentRelationshipBetweenStandardObjects() {
  //   Id oppId = Id.valueOf('0066g00000TvyKnAAJ');
  //   OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = oppId);

  //   RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder('Account');

  //   System.assertEquals(
  //     new List<SObjectType>{ OpportunityLineItem.SObjectType, Opportunity.SObjectType, Account.SObjectType },
  //     finder.getParentTypes(oli.getSObjectType(), 'OpportunityId', oli.OpportunityId)
  //   );
  // }
}
