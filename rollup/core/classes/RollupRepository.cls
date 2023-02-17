public without sharing class RollupRepository {
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  private final System.AccessLevel accessLevel;

  public RollupRepository(System.AccessLevel accessLevel) {
    this.accessLevel = accessLevel;
  }

  public List<SObject> get(String queryString, Map<String, Object> queryBinds) {
    return this.query(queryString, queryBinds);
  }

  public Integer getCount(String queryString, Set<String> objIds) {
    return this.getCount(queryString, new Map<String, Object>{ 'objIds' => objIds });
  }

  public Integer getCount(String queryString, Map<String, Object> queryBinds) {
    if (queryString.contains(RollupQueryBuilder.ALL_ROWS)) {
      queryString = queryString.replace(RollupQueryBuilder.ALL_ROWS, '');
    }
    queryString = queryString.replaceFirst('SELECT.+\n', 'SELECT Count()\n');

    Integer countAmount;
    try {
      countAmount = Database.countQueryWithBinds(queryString, queryBinds, this.accessLevel);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query:\n' + queryString, ex, LoggingLevel.WARN);
      // not all count queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      countAmount = SENTINEL_COUNT_VALUE;
    }
    return countAmount;
  }

  private List<SObject> query(String queryString, Map<String, Object> queryBinds) {
    return Database.queryWithBinds(queryString, queryBinds, this.accessLevel);
  }
}
