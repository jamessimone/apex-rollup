public without sharing class RollupQueryBuilder {
  private RollupQueryBuilder() {
  }

  public static final RollupQueryBuilder Current = new RollupQueryBuilder();
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  private static final String CURRENCY_ISO_CODE_FIELD_NAME = 'CurrencyIsoCode';

  /**
   * @return String `queryString` - returns a query string with "objIds" expected as a bind variable
   */
  public String getQuery(
    SObjectType sObjectType,
    List<String> uniqueQueryFieldNames,
    String lookupFieldOnLookupObject,
    String equality,
    String optionalWhereClause
  ) {
    DescribeSObjectResult sObjectToken = sObjectType.getDescribe();
    Map<String, SObjectField> baseFields = sObjectToken.fields.getMap();
    Set<String> lowerCaseFieldNames = new Set<String>();

    for (Integer index = uniqueQueryFieldNames.size() - 1; index >= 0; index--) {
      String uniqueFieldName = uniqueQueryFieldNames[index];
      if (String.isBlank(uniqueFieldName)) {
        uniqueQueryFieldNames.remove(index);
        continue;
      }

      String lowerCaseField = uniqueFieldName.toLowerCase();
      // it's possible for fields that differ only in casing to be passed in -
      // but that throws an exception when passed to SOQL. Let's avoid that!
      if (lowerCaseFieldNames.contains(lowerCaseField)) {
        uniqueQueryFieldNames.remove(index);
      } else {
        lowerCaseFieldNames.add(lowerCaseField);
      }
      // ensure that the base relationship name field is transformed appropriately
      if (baseFields.containsKey(uniqueFieldName + 'Id') || baseFields.containsKey(uniqueFieldName + '__c')) {
        SObjectField baseField = baseFields.get(uniqueFieldName + 'Id') == null
          ? baseFields.get(uniqueFieldName + '__c')
          : baseFields.get(uniqueFieldName + 'Id');
        DescribeFieldResult fieldToken = baseField.getDescribe();
        if (fieldToken.getType() == DisplayType.REFERENCE && uniqueQueryFieldNames.contains(fieldToken.getName()) == false) {
          uniqueQueryFieldNames[index] = fieldToken.getName();
        }
      } else if (
        baseFields.containsKey(uniqueFieldName) &&
        sObjectToken.getName() == uniqueFieldName.substringBefore('.') &&
        uniqueQueryFieldNames.contains(uniqueFieldName) == false
      ) {
        uniqueQueryFieldNames[index] = uniqueFieldName;
      }
    }

    Boolean hasAggregateFunction = false;
    for (String uniqueQueryFieldName : uniqueQueryFieldNames) {
      // This is definitely not the most intuitive way to do this, but need to determine if the query
      // will be a regular query vs an aggregated query - all aggregate functions use '()', so checking
      // for '(' is a quick & lazy way to check without making larger changes to how RollupQueryBuilder works
      // (but it's very goofy & could definitely be improved)
      if (uniqueQueryFieldName?.contains('(')) {
        hasAggregateFunction = true;
        break;
      }
    }
    if (
      hasAggregateFunction == false &&
      uniqueQueryFieldNames.contains(CURRENCY_ISO_CODE_FIELD_NAME) == false &&
      UserInfo.isMultiCurrencyOrganization() &&
      sObjectToken.fields.getMap().containsKey(CURRENCY_ISO_CODE_FIELD_NAME)
    ) {
      uniqueQueryFieldNames.add(CURRENCY_ISO_CODE_FIELD_NAME);
    }

    optionalWhereClause = this.adjustWhereClauseForPolymorphicFields(sObjectType, uniqueQueryFieldNames, optionalWhereClause);

    // again noting the coupling for consumers of this method
    // "objIds" is required to be present in the scope where the query is run
    String baseQuery =
      'SELECT ' +
      String.join(uniqueQueryFieldNames, ',') +
      '\nFROM ' +
      sObjectType +
      '\nWHERE ' +
      lookupFieldOnLookupObject +
      ' ' +
      equality +
      ' :objIds';
    if (String.isNotBlank(optionalWhereClause)) {
      // sanitize what's left of the where clause
      while (optionalWhereClause.trim().endsWith('AND') || optionalWhereClause.trim().endsWith('OR')) {
        optionalWhereClause = optionalWhereClause.substringBeforeLast('AND').trim();
        optionalWhereClause = optionalWhereClause.substringBeforeLast('OR').trim();
      }
      while (optionalWhereClause?.startsWith('(') == true && optionalWhereClause?.countMatches('(') > optionalWhereClause?.countMatches(')')) {
        optionalWhereClause = optionalWhereClause.removeStart('(');
      }
      while (optionalWhereClause?.endsWith(')') == true && optionalWhereClause?.countMatches(')') > optionalWhereClause?.countMatches('(')) {
        optionalWhereClause = optionalWhereClause.removeEnd(')');
      }
      optionalWhereClause = RollupEvaluator.getWhereEval(optionalWhereClause, sObjectType).getSafeQuery();

      if (optionalWhereClause.length() > 0 && (optionalWhereClause.startsWith('\nAND') || optionalWhereClause.startsWith('\nOR'))) {
        baseQuery += optionalWhereClause;
      } else if (optionalWhereClause.length() > 0) {
        baseQuery += '\nAND ' + optionalWhereClause;
      }
    }
    if (sObjectType == Task.SObjectType || sObjectType == Event.SObjectType) {
      // handle archived rows
      baseQuery += '\nAND IsDeleted = false ALL ROWS';
    }
    return baseQuery;
  }

  public String getQuery(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String lookupFieldOnLookupObject, String equality) {
    return this.getQuery(sObjectType, uniqueQueryFieldNames, lookupFieldOnLookupObject, equality, null);
  }

  private String adjustWhereClauseForPolymorphicFields(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String optionalWhereClause) {
    // you can't filter on *.Owner for polymorphic fields - or even select them, for that matter. Instead we have to massage the query to use
    // TYPEOF instead
    if (this.hasPolymorphicOwnerClause(optionalWhereClause) == false || uniqueQueryFieldNames.contains('Count()')) {
      return optionalWhereClause;
    }
    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(optionalWhereClause, sObjectType);
    try {
      for (String whereClause : whereEval.getWhereClauses()) {
        if (this.hasPolymorphicOwnerClause(whereClause) == false) {
          continue;
        }
        String fieldName = whereClause.split(' ')[0];
        List<String> fieldParts = fieldName.split('\\.');
        String whoOrWhat = fieldParts.remove(0);
        String indexer = whoOrWhat + '.Type = \'';
        String relationshipName = optionalWhereClause.substring(optionalWhereClause.indexOf(indexer) + indexer.length()).substringBeforeLast('\'');
        String typeOfField = String.join(fieldParts, '.');

        uniqueQueryFieldNames.add('TYPEOF ' + whoOrWhat + ' WHEN ' + relationshipName + ' THEN ' + typeOfField + ' END');

        optionalWhereClause = optionalWhereClause.replace(indexer + relationshipName + '\'', '')
          .replace(whereClause, '')
          .replace('()', '')
          .replace('( OR )', '')
          .replace('( AND )', '')
          .trim();
      }
    } catch (Exception ex) {
      RollupLogger.Instance.log('exception occurred while converting polymorphic where clause: ', ex, LoggingLevel.WARN);
    }
    return optionalWhereClause;
  }

  private Boolean hasPolymorphicOwnerClause(String whereClause) {
    return whereClause?.contains('.Owner') == true;
  }
}
