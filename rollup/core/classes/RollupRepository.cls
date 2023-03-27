public without sharing class RollupRepository implements RollupLogger.ToStringObject {
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  private final Args args = new Args();
  private final System.AccessLevel accessLevel;
  private final String accessLevelName;

  private class Args {
    public final Map<String, Object> bindVars = new Map<String, Object>();
    public String query;
  }

  public RollupRepository(System.AccessLevel accessLevel) {
    this.accessLevel = accessLevel;
    this.accessLevelName = this.accessLevel == System.AccessLevel.SYSTEM_MODE ? 'System' : 'User';
  }

  public RollupRepository setQuery(String query) {
    this.args.query = query;
    return this;
  }

  public RollupRepository setArg(Object value) {
    this.args.bindVars.put(RollupQueryBuilder.BIND_VAR, value);
    return this;
  }

  public RollupRepository setArg(String key, Object value) {
    this.args.bindVars.put(key, value);
    return this;
  }

  public Database.QueryLocator getLocator() {
    this.createQueryLog('Getting query locator');
    return Database.getQueryLocatorWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
  }

  public List<SObject> get() {
    this.createQueryLog('Querying...');
    return Database.queryWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
  }

  public Integer getCount() {
    if (this.args.query.contains(RollupQueryBuilder.ALL_ROWS)) {
      this.args.query = this.args.query.replace(RollupQueryBuilder.ALL_ROWS, '');
    }
    this.args.query = this.args.query.replaceFirst('SELECT.+\n', 'SELECT Count()\n');

    Integer countAmount;
    try {
      countAmount = Database.countQueryWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query', ex, LoggingLevel.WARN);
      // not all count queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      countAmount = SENTINEL_COUNT_VALUE;
    }
    this.createQueryLog('Returned amount: ' + countAmount);
    return countAmount;
  }

  public override String toString() {
    return this.args.query + '\n' + 'with bind var keys: ' + this.args.bindVars.keySet();
  }

  private void createQueryLog(String message) {
    RollupLogger.Instance.Log(message, 'Query: ' + this.args.query + '\nAccess level: ' + this.accessLevelName, LoggingLevel.DEBUG);
  }
}
