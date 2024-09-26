@IsTest
private class RollupRepositoryTests {
  @IsTest
  static void transformsCountQueriesProperly() {
    String queryString = 'SELECT Id, AnnualRevenue, Name\nFROM Account';

    Integer accountCount = new RollupRepository(RollupRepository.RunAsMode.SYSTEM_LEVEL).setQuery(queryString).getCount();

    Assert.areEqual(0, accountCount);
  }

  @IsTest
  static void serializesPermissionLevelProperly() {
    Exception ex;
    try {
      Test.startTest();
      serializedRun(JSON.serialize(new RollupRepository(RollupRepository.RunAsMode.USER)));
      Test.stopTest();
    } catch (Exception e) {
      ex = e;
    }

    Assert.isNull(ex);
  }

  @IsTest
  static void orderBysEndUpCorrectlySorter() {
    List<RollupOrderBy__mdt> orderBys = new List<RollupOrderBy__mdt>{
      new RollupOrderBy__mdt(Ranking__c = 3, DeveloperName = 'd'),
      new RollupOrderBy__mdt(Ranking__c = 0, DeveloperName = 'a'),
      new RollupOrderBy__mdt(Ranking__c = 1, DeveloperName = 'b'),
      new RollupOrderBy__mdt(Ranking__c = 2, DeveloperName = 'c')
    };

    orderBys.sort(new RollupRepository.OrderBySorter());

    Assert.areEqual(0, orderBys.get(0).Ranking__c);
    Assert.areEqual(1, orderBys.get(1).Ranking__c);
    Assert.areEqual(2, orderBys.get(2).Ranking__c);
    Assert.areEqual(3, orderBys.get(3).Ranking__c);
  }

  @IsTest
  static void orderBysUseDeveloperNameForTieBreaker() {
    List<RollupOrderBy__mdt> orderBys = new List<RollupOrderBy__mdt>{
      new RollupOrderBy__mdt(Ranking__c = 0, DeveloperName = 'd'),
      new RollupOrderBy__mdt(Ranking__c = 0, DeveloperName = 'a'),
      new RollupOrderBy__mdt(Ranking__c = 0, DeveloperName = 'b'),
      new RollupOrderBy__mdt(Ranking__c = 0, DeveloperName = 'c')
    };

    orderBys.sort(new RollupRepository.OrderBySorter());

    Assert.areEqual('a', orderBys.get(0).DeveloperName);
    Assert.areEqual('b', orderBys.get(1).DeveloperName);
    Assert.areEqual('c', orderBys.get(2).DeveloperName);
    Assert.areEqual('d', orderBys.get(3).DeveloperName);
  }

  /**
   * Serialization proves that we don't get: `System.JSONException: Type unsupported in JSON: common.apex.methods.AccessLevelEnum`
   */
  @future
  private static void serializedRun(String serializedRepo) {
    RollupRepository repo = (RollupRepository) JSON.deserialize(serializedRepo, RollupRepository.class);
    repo.setQuery('SELECT COUNT() FROM Account').getCount();
  }
}
