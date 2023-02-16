public without sharing class RollupRepository {
  private abstract class QueryRunner {
    public List<SObject> get(String queryString, Map<String, Object> queryBinds) {
      return Database.queryWithBinds(queryString, queryBinds, System.AccessLevel.SYSTEM_MODE);
    }
  }
}
