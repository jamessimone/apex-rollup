public without sharing class RollupQueryBuilder {
  public static final RollupQueryBuilder Current = new RollupQueryBuilder();
  public static final String ALL_ROWS = 'ALL ROWS';
  public static final String BIND_VAR = 'objIds';

  private static final Pattern AGGREGATE_QUERY_REGEX = Pattern.compile('(count(_distinct|)|avg|sum|max|min)\\(');
  private static final Map<String, String> OG_WHERE_CLAUSE_TO_SANITIZED_VERSION = new Map<String, String>();

  private RollupQueryBuilder() {
  }

  /**
   * @return String `queryString` - returns a query string with "objIds" expected as a bind variable
   */
  public String getQuery(SObjectType sObjectType, List<String> fieldNames, String lookupFieldOnLookupObject, String equality, String optionalWhereClause) {
    Set<String> lowerCaseFieldNames = new Set<String>();
    for (String fieldName : fieldNames) {
      if (String.isNotBlank(fieldName)) {
        lowerCaseFieldNames.add(fieldName.toLowerCase());
      }
    }
    fieldNames.clear();
    fieldNames.addAll(lowerCaseFieldNames);

    this.addCurrencyIsoCodeForMultiCurrencyOrgs(fieldNames, lowerCaseFieldNames, sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED));

    String originalWhereClause = optionalWhereClause;
    Boolean isBlank = String.isBlank(originalWhereClause);
    Boolean hasBeenSanitized = isBlank || OG_WHERE_CLAUSE_TO_SANITIZED_VERSION.containsKey(originalWhereClause);
    optionalWhereClause = hasBeenSanitized
      ? OG_WHERE_CLAUSE_TO_SANITIZED_VERSION.get(originalWhereClause)
      : this.adjustWhereClauseForPolymorphicFields(sObjectType, fieldNames, optionalWhereClause);

    String baseQuery =
      'SELECT ' +
      String.join(fieldNames, ',') +
      '\nFROM ' +
      sObjectType +
      '\nWHERE ' +
      lookupFieldOnLookupObject +
      ' ' +
      equality +
      ' :' +
      BIND_VAR;
    if (String.isNotBlank(optionalWhereClause)) {
      if (hasBeenSanitized == false) {
        optionalWhereClause = this.getSanitizedWhereClause(originalWhereClause, optionalWhereClause, sObjectType);
      }
      if (optionalWhereClause.length() > 0 && (optionalWhereClause.startsWith('\nAND') || optionalWhereClause.startsWith('\nOR'))) {
        baseQuery += optionalWhereClause;
      } else if (optionalWhereClause.length() > 0) {
        baseQuery += '\nAND ' + optionalWhereClause;
      }
    }
    if (sObjectType == Task.SObjectType || sObjectType == Event.SObjectType) {
      // handle archived rows
      baseQuery += '\nAND IsDeleted = false ' + ALL_ROWS;
    }
    return baseQuery;
  }

  public String getQuery(SObjectType sObjectType, List<String> fieldNames, String lookupFieldOnLookupObject, String equality) {
    return this.getQuery(sObjectType, fieldNames, lookupFieldOnLookupObject, equality, null);
  }

  public String getAllRowSafeQuery(Schema.SObjectType sObjectType, String query) {
    Boolean mightNeedReplacement = sObjectType == Task.SObjectType || sObjectType == Event.SObjectType;
    if (mightNeedReplacement && query.endsWith(ALL_ROWS) == false) {
      query = query.replace(ALL_ROWS, '') + (' ' + ALL_ROWS);
    }
    return query;
  }

  private String adjustWhereClauseForPolymorphicFields(SObjectType sObjectType, List<String> fieldNames, String optionalWhereClause) {
    // you can't filter on *.Owner for polymorphic fields - or even select them, for that matter. Instead we have to massage the query to use
    // TYPEOF instead
    Map<String, SObjectField> fieldNameToField = sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    if (this.hasPolymorphicOwnerClause(optionalWhereClause, fieldNameToField) == false || fieldNames.contains('Count()')) {
      return optionalWhereClause;
    }
    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(optionalWhereClause, sObjectType);
    try {
      for (String whereClause : whereEval.getWhereClauses()) {
        if (this.hasPolymorphicOwnerClause(whereClause, fieldNameToField) == false) {
          continue;
        }
        String fieldName = whereClause.split(' ')[0];
        List<String> fieldParts = fieldName.split('\\.');
        String whoOrWhat = fieldParts.remove(0);
        String indexer = whoOrWhat + '.Type = \'';
        String relationshipName = optionalWhereClause.substring(optionalWhereClause.indexOf(indexer) + indexer.length()).substringBefore('\'');
        String typeOfField = String.join(fieldParts, '.');

        fieldNames.add('TYPEOF ' + whoOrWhat + ' WHEN ' + relationshipName + ' THEN ' + typeOfField + ' END');

        optionalWhereClause = optionalWhereClause.replace(indexer + relationshipName + '\'', '').replace(whereClause, '');
      }
    } catch (Exception ex) {
      RollupLogger.Instance.log('exception occurred while converting polymorphic where clause:', ex, LoggingLevel.WARN);
    }
    return optionalWhereClause;
  }

  private Boolean hasPolymorphicOwnerClause(String whereClause, Map<String, SObjectField> fieldNameToField) {
    Boolean hasPolymorphicField = false;
    if (whereClause?.contains('.Owner') == true) {
      List<String> fields = whereClause.split('\\.');
      for (String fieldPart : fields) {
        String fieldName = fieldPart.endsWith('__r') ? fieldPart.substringBeforeLast('__r') + '__c' : fieldPart + 'Id';
        SObjectField fieldToken = fieldNameToField.get(fieldName);
        hasPolymorphicField = fieldToken?.getDescribe().isNamePointing() == true;
        if (hasPolymorphicField) {
          break;
        }
      }
    }
    return hasPolymorphicField;
  }

  private void addCurrencyIsoCodeForMultiCurrencyOrgs(List<String> fieldNames, Set<String> uniqueLowercaseFields, Schema.DescribeSObjectResult objectToken) {
    if (
      RollupCurrencyInfo.isMultiCurrency() &&
      uniqueLowercaseFields.contains(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME.toLowerCase()) == false &&
      objectToken.fields.getMap().containsKey(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME)
    ) {
      Boolean hasAggregateFunction = AGGREGATE_QUERY_REGEX.matcher(String.join(fieldNames, ',')).find();
      if (hasAggregateFunction == false) {
        fieldNames.add(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME);
      }
    }
  }

  private String getSanitizedWhereClause(String key, String whereClause, Schema.SObjectType sObjectType) {
    // sanitize what's left of the where clause
    if (whereClause.containsOnly('() AND OR')) {
      whereClause = '';
    } else {
      while (whereClause.trim().endsWith('AND') || whereClause.trim().endsWith('OR')) {
        whereClause = whereClause.substringBeforeLast('AND').trim();
        whereClause = whereClause.substringBeforeLast('OR').trim();
      }
      while (whereClause?.startsWith('(') == true && whereClause?.countMatches('(') > whereClause?.countMatches(')')) {
        whereClause = whereClause.removeStart('(');
      }
      while (whereClause?.endsWith(')') == true && whereClause?.countMatches(')') > whereClause?.countMatches('(')) {
        whereClause = whereClause.removeEnd(')');
      }
      whereClause = whereClause.replace('()', '');
      whereClause = RollupEvaluator.getWhereEval(whereClause, sObjectType).getSafeQuery();

      if (whereClause.containsIgnoreCase(' or ') && whereClause.containsIgnoreCase(' and ') == false) {
        whereClause = '(' + whereClause + ')';
      }
    }
    OG_WHERE_CLAUSE_TO_SANITIZED_VERSION.put(key, whereClause);
    return whereClause;
  }
}
