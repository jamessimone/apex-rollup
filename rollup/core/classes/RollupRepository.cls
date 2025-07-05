public without sharing class RollupRepository implements RollupLogger.ToStringObject {
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  @TestVisible
  private final Args args = new Args();
  private final RunAsMode localRunAsMode;
  private Boolean shouldLog = true;

  private transient System.AccessLevel accessLevel {
    get {
      this.accessLevel = this.accessLevel ?? this.transformPermissionLevel(this.localRunAsMode);
      return this.accessLevel;
    }
    set;
  }

  private class Args {
    public final Map<String, Object> bindVars = new Map<String, Object>();
    public String query;
  }

  /**
   * Essentially a clone of `System.AccessLevel`, but this one:
   *  - can actually be serialized
   *  - doesn't fail an equality check against itself in a Queueable/Batchable (prior comparisons to System.AccessLevel.USER_MODE or System.AccessLevel.SYSTEM_MODE
   *  failed when the property they were referencing was stored as an instance variable post-serialization)
   */
  public enum RunAsMode {
    SYSTEM_LEVEL,
    USER
  }

  public RollupRepository(RunAsMode localRunAsMode) {
    this.localRunAsMode = localRunAsMode;
    this.accessLevel = this.transformPermissionLevel(localRunAsMode);
  }

  public RollupRepository setQuery(String query) {
    this.args.query = query;
    return this;
  }

  public RollupRepository setArg(Object value) {
    return this.setArg(RollupQueryBuilder.BIND_VAR, value);
  }

  public RollupRepository setArg(String key, Object value) {
    this.args.bindVars.put(key, value);
    return this;
  }

  public Database.Cursor getCursor() {
    this.createQueryLog('Getting cursor');
    return Database.getCursorWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
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
    String originalQuery = this.args.query;
    if (this.args.query.contains(RollupQueryBuilder.ALL_ROWS)) {
      this.args.query = this.args.query.replace(RollupQueryBuilder.ALL_ROWS, '');
    }
    this.args.query = this.args.query.replaceFirst('SELECT.+\n', 'SELECT Count()\n');
    this.createQueryLog('Getting count');

    Integer countAmount;
    try {
      countAmount = Database.countQueryWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query', ex, System.LoggingLevel.WARN);
      // not all count queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      countAmount = SENTINEL_COUNT_VALUE;
    }
    this.createQueryLog('Returned amount: ' + countAmount);
    this.args.query = originalQuery;
    return countAmount;
  }

  public override String toString() {
    return this.args.query + '\nBind keys: ' + this.args.bindVars.keySet() + '\nAccess level: ' + this.localRunAsMode;
  }

  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static List<Rollup__mdt> getRollupMetadata() {
    List<Rollup__mdt> matchingMetadata;

    List<String> selectFields = new List<String>{
      '(SELECT Id, DeveloperName, FieldName__c, NullSortOrder__c, Ranking__c, SortOrder__c FROM RollupOrderBys__r)',
      'RollupGrouping__r.Id',
      'RollupGrouping__r.RollupOperation__c',
      Rollup__mdt.CalcItem__c.toString(),
      Rollup__mdt.CalcItemText__c.toString(),
      Rollup__mdt.CalcItemWhereClause__c.toString(),
      Rollup__mdt.ChangedFieldsOnCalcItem__c.toString(),
      Rollup__mdt.ConcatDelimiter__c.toString(),
      Rollup__mdt.CurrencyFieldMapping__c.toString(),
      Rollup__mdt.DeveloperName.toString(),
      Rollup__mdt.FullRecalculationDefaultNumberValue__c.toString(),
      Rollup__mdt.FullRecalculationDefaultStringValue__c.toString(),
      Rollup__mdt.GrandparentRelationshipFieldPath__c.toString(),
      Rollup__mdt.GroupByFields__c.toString(),
      Rollup__mdt.GroupByRowEndDelimiter__c.toString(),
      Rollup__mdt.GroupByRowStartDelimiter__c.toString(),
      Rollup__mdt.IsDisabled__c.toString(),
      Rollup__mdt.IsDistinct__c.toString(),
      Rollup__mdt.IsFullRecordSet__c.toString(),
      Rollup__mdt.IsRollupStartedFromParent__c.toString(),
      Rollup__mdt.IsTableFormatted__c.toString(),
      Rollup__mdt.LimitAmount__c.toString(),
      Rollup__mdt.LookupFieldOnCalcItem__c.toString(),
      Rollup__mdt.LookupFieldOnCalcItemText__c.toString(),
      Rollup__mdt.LookupFieldOnLookupObject__c.toString(),
      Rollup__mdt.LookupFieldOnLookupObjectText__c.toString(),
      Rollup__mdt.LookupObject__c.toString(),
      Rollup__mdt.LookupObjectText__c.toString(),
      Rollup__mdt.MasterLabel.toString(),
      Rollup__mdt.OneToManyGrandparentFields__c.toString(),
      Rollup__mdt.OrderByFirstLast__c.toString(),
      Rollup__mdt.RollupControl__c.toString(),
      Rollup__mdt.RollupFieldOnCalcItem__c.toString(),
      Rollup__mdt.RollupFieldOnCalcItemText__c.toString(),
      Rollup__mdt.RollupFieldOnLookupObject__c.toString(),
      Rollup__mdt.RollupFieldOnLookupObjectText__c.toString(),
      Rollup__mdt.RollupOperation__c.toString(),
      Rollup__mdt.RollupToUltimateParent__c.toString(),
      Rollup__mdt.SharingMode__c.toString(),
      Rollup__mdt.ShouldRunWithoutCustomSettingEnabled__c.toString(),
      Rollup__mdt.SplitConcatDelimiterOnCalcItem__c.toString(),
      Rollup__mdt.UltimateParentLookup__c.toString(),
      Rollup__mdt.UltimateParentLookupText__c.toString()
    };

    if (Rollup.getDefaultControl()?.ShouldOptimizeCMDTQueries__c != true) {
      selectFields.addAll(
        new List<String>{
          'LookupObject__r.QualifiedApiName',
          'CalcItem__r.QualifiedApiName',
          'RollupFieldOnCalcItem__r.QualifiedApiName',
          'LookupFieldOnCalcItem__r.QualifiedApiName',
          'LookupFieldOnLookupObject__r.QualifiedApiName',
          'RollupFieldOnLookupObject__r.QualifiedApiName',
          'UltimateParentLookup__r.QualifiedApiName'
        }
      );
    }

    matchingMetadata = new RollupRepository(RollupRepository.RunAsMode.SYSTEM_LEVEL)
      .setQuery('SELECT ' + String.join(selectFields, ',\n') + '\nFROM Rollup__mdt\nWHERE RollupControl__r.ShouldAbortRun__c = FALSE AND IsDisabled__c = FALSE')
      .setShouldLog(false)
      .get();

    // do the transforms for standard query
    for (Rollup__mdt meta : matchingMetadata) {
      meta.CalcItem__c = meta.CalcItemText__c ?? meta.CalcItem__r.QualifiedApiName;
      meta.LookupObject__c = meta.LookupObjectText__c ?? meta.LookupObject__r.QualifiedApiName;
      meta.LookupFieldOnCalcItem__c = meta.LookupFieldOnCalcItemText__c ?? meta.LookupFieldOnCalcItem__r.QualifiedApiName;
      meta.LookupFieldOnLookupObject__c = meta.LookupFieldOnLookupObjectText__c ?? meta.LookupFieldOnLookupObject__r.QualifiedApiName;
      meta.RollupFieldOnCalcItem__c = meta.RollupFieldOnCalcItemText__c ?? meta.RollupFieldOnCalcItem__r.QualifiedApiName;
      meta.RollupFieldOnLookupObject__c = meta.RollupFieldOnLookupObjectText__c ?? meta.RollupFieldOnLookupObject__r.QualifiedApiName;
      meta.UltimateParentLookup__c = meta.UltimateParentLookupText__c ?? meta.UltimateParentLookup__r.QualifiedApiName;

      meta.GroupByRowEndDelimiter__c = meta.GroupByRowEndDelimiter__c?.unescapeJava();
      meta.GroupByRowStartDelimiter__c = meta.GroupByRowStartDelimiter__c?.unescapeJava();
      meta.SharingMode__c = meta.SharingMode__c ?? RollupMetaPicklists.SharingMode.SystemLevel;
    }

    return matchingMetadata;
  }

  private void createQueryLog(String message) {
    if (this.shouldLog) {
      RollupLogger.Instance.Log(message, this, System.LoggingLevel.DEBUG);
    }
  }

  private RollupRepository setShouldLog(Boolean shouldLog) {
    this.shouldLog = shouldLog;
    return this;
  }

  private System.AccessLevel transformPermissionLevel(RunAsMode currentRunAs) {
    return currentRunAs == RunAsMode.USER ? System.AccessLevel.USER_MODE : System.AccessLevel.SYSTEM_MODE;
  }

  public class OrderBySorter implements System.Comparator<RollupOrderBy__mdt> {
    private final List<Schema.SObjectField> sortFields = new List<Schema.SObjectField>{ RollupOrderBy__mdt.Ranking__c, RollupOrderBy__mdt.DeveloperName };
    public Integer compare(RollupOrderBy__mdt first, RollupOrderBy__mdt second) {
      Integer returnValue = 0;
      List<Schema.SObjectField> localSortFields = new List<Schema.SObjectField>(this.sortFields);
      while (returnValue == 0 && localSortFields.isEmpty() == false) {
        Schema.SObjectField field = localSortFields.remove(0);
        Object firstSortValue = first.get(field);
        Object secondSortValue = second.get(field);

        if (firstSortValue instanceof Decimal) {
          returnValue = this.getDecimalSortedValue((Decimal) firstSortValue, (Decimal) secondSortValue);
        } else if (firstSortValue instanceof String) {
          returnValue = ((String) firstSortValue).compareTo((String) secondSortValue);
        }
      }
      return returnValue;
    }

    private Integer getDecimalSortedValue(Decimal first, Decimal second) {
      Integer returnValue = 0;
      if (first > second) {
        returnValue = 1;
      } else if (first < second) {
        returnValue = -1;
      }
      return returnValue;
    }
  }
}
