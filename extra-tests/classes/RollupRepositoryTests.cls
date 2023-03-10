@IsTest
private class RollupRepositoryTests {
  @IsTest
  static void transformsCountQueriesProperly() {
    String queryString = 'SELECT Id, AnnualRevenue, Name\nFROM Account';

    Integer accountCount = new RollupRepository(System.AccessLevel.SYSTEM_MODE).getCount(queryString, new Set<String>());

    System.assertEquals(0, accountCount);
  }

  @IsTest
  static void returnsQueryLocator() {
    String queryString = 'SELECT Id FROM Account';

    System.assertNotEquals(null, new RollupRepository(System.AccessLevel.SYSTEM_MODE).getLocator(queryString, new Set<Id>()));
  }
}
