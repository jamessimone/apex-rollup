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

  /**
   * Serialization proves that we don't get: `System.JSONException: Type unsupported in JSON: common.apex.methods.AccessLevelEnum`
   */
  @future
  private static void serializedRun(String serializedRepo) {
    RollupRepository repo = (RollupRepository) JSON.deserialize(serializedRepo, RollupRepository.class);
    repo.setQuery('SELECT COUNT() FROM Account').getCount();
  }
}
