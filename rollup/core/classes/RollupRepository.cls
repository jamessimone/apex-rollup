public without sharing class RollupRepository implements RollupLogger.ToStringObject {
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  private final Args args = new Args();
  private final RunAsMode localRunAsMode;
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
    List<Rollup__mdt> matchingMetadata = [
      SELECT
        MasterLabel,
        DeveloperName,
        LookupObject__c,
        LookupObjectText__c,
        LookupObject__r.QualifiedApiName,
        CalcItem__c,
        CalcItemText__c,
        CalcItem__r.QualifiedApiName,
        RollupFieldOnCalcItem__c,
        RollupFieldOnCalcItemText__c,
        RollupFieldOnCalcItem__r.QualifiedApiName,
        LookupFieldOnCalcItem__c,
        LookupFieldOnCalcItemText__c,
        LookupFieldOnCalcItem__r.QualifiedApiName,
        LookupFieldOnLookupObject__c,
        LookupFieldOnLookupObjectText__c,
        LookupFieldOnLookupObject__r.QualifiedApiName,
        RollupFieldOnLookupObject__c,
        RollupFieldOnLookupObjectText__c,
        RollupFieldOnLookupObject__r.QualifiedApiName,
        UltimateParentLookup__c,
        UltimateParentLookup__r.QualifiedApiName,
        CalcItemWhereClause__c,
        ChangedFieldsOnCalcItem__c,
        ConcatDelimiter__c,
        CurrencyFieldMapping__c,
        FullRecalculationDefaultNumberValue__c,
        FullRecalculationDefaultStringValue__c,
        GrandparentRelationshipFieldPath__c,
        GroupByFields__c,
        GroupByRowEndDelimiter__c,
        GroupByRowStartDelimiter__c,
        IsDistinct__c,
        IsFullRecordSet__c,
        IsRollupStartedFromParent__c,
        IsTableFormatted__c,
        LimitAmount__c,
        OneToManyGrandparentFields__c,
        OrderByFirstLast__c,
        RollupControl__c,
        RollupOperation__c,
        RollupToUltimateParent__c,
        SharingMode__c,
        ShouldRunWithoutCustomSettingEnabled__c,
        SplitConcatDelimiterOnCalcItem__c,
        (SELECT Id, DeveloperName, FieldName__c, NullSortOrder__c, Ranking__c, SortOrder__c FROM RollupOrderBys__r),
        RollupGrouping__r.Id,
        RollupGrouping__r.RollupOperation__c
      FROM Rollup__mdt
      WHERE RollupControl__r.ShouldAbortRun__c = FALSE
      ORDER BY LookupObject__c
    ];
    // we have to do transforms on the Entity Definition fields because custom objects/custom fields
    // have references that otherwise won't work with the rest of the code
    for (Rollup__mdt meta : matchingMetadata) {
      meta.CalcItem__c = meta.CalcItem__r.QualifiedApiName ?? meta.CalcItemText__c;
      meta.LookupFieldOnCalcItem__c = meta.LookupFieldOnCalcItem__r.QualifiedApiName ?? meta.LookupFieldOnCalcItemText__c;
      meta.LookupFieldOnLookupObject__c = meta.LookupFieldOnLookupObject__r.QualifiedApiName ?? meta.LookupFieldOnLookupObjectText__c;
      meta.RollupFieldOnCalcItem__c = meta.RollupFieldOnCalcItem__r.QualifiedApiName ?? meta.RollupFieldOnCalcItemText__c;
      meta.RollupFieldOnLookupObject__c = meta.RollupFieldOnLookupObject__r.QualifiedApiName ?? meta.RollupFieldOnLookupObjectText__c;
      meta.LookupObject__c = meta.LookupObject__r.QualifiedApiName ?? meta.LookupObjectText__c;

      meta.GroupByRowEndDelimiter__c = meta.GroupByRowEndDelimiter__c?.unescapeJava();
      meta.GroupByRowStartDelimiter__c = meta.GroupByRowStartDelimiter__c?.unescapeJava();
      meta.SharingMode__c = meta.SharingMode__c ?? RollupMetaPicklists.SharingMode.SystemLevel;
      meta.UltimateParentLookup__c = meta.UltimateParentLookup__r.QualifiedApiName;
    }

    return matchingMetadata;
  }

  private void createQueryLog(String message) {
    RollupLogger.Instance.Log(message, this, System.LoggingLevel.DEBUG);
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
