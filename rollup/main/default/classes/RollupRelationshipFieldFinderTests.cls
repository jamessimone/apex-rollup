@isTest
private class RollupRelationshipFieldFinderTests {
  @isTest
  static void shouldFindRelationshipBetweenCustomObjects() {
    Id appId = Id.valueOf('a036g00000TvyKnAAJ');
    ApplicationLog__c log = new ApplicationLog__c(Application__c = appId, Name = 'Test Rollup Grandchildren');

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder('Account');

    System.assertEquals(
      new List<SObjectType>{ ApplicationLog__c.SObjectType, Application__c.SObjectType, ParentApplication__c.SObjectType, Account.SObjectType },
      finder.getParentTypes(log.getSObjectType(), 'Application__c', log.Application__c)
    );
  }

  @isTest
  static void shouldFindRelationshipBetweenStandardObjects() {
    Id oppId = Id.valueOf('0066g00000TvyKnAAJ');
    OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = oppId);

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder('Account');

    System.assertEquals(
      new List<SObjectType>{ OpportunityLineItem.SObjectType, Opportunity.SObjectType, Account.SObjectType },
      finder.getParentTypes(oli.getSObjectType(), 'OpportunityId', oli.OpportunityId)
    );
  }
}
