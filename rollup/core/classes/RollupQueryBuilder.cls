public without sharing class RollupQueryBuilder {
  public static final RollupQueryBuilder Current = new RollupQueryBuilder();
  public static final Integer SENTINEL_COUNT_VALUE = -1;
  public static final String ALL_ROWS = 'ALL ROWS';

  private RollupQueryBuilder() {
  }

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
    }

    this.addCurrencyIsoCodeForMultiCurrencyOrgs(uniqueQueryFieldNames, lowerCaseFieldNames);

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

      if (optionalWhereClause.containsIgnoreCase(' or ') && optionalWhereClause.containsIgnoreCase(' and ') == false) {
        optionalWhereClause = '(' + optionalWhereClause + ')';
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

  public String getQuery(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String lookupFieldOnLookupObject, String equality) {
    return this.getQuery(sObjectType, uniqueQueryFieldNames, lookupFieldOnLookupObject, equality, null);
  }

  public String getAllRowSafeQuery(Schema.SObjectType sObjectType, String query) {
    Boolean mightNeedReplacement = sObjectType == Task.SObjectType || sObjectType == Event.SObjectType;
    if (mightNeedReplacement && query.endsWith(ALL_ROWS) == false) {
      query = query.replace(ALL_ROWS, '') + (' ' + ALL_ROWS);
    }
    return query;
  }

  private String adjustWhereClauseForPolymorphicFields(SObjectType sObjectType, List<String> uniqueQueryFieldNames, String optionalWhereClause) {
    // you can't filter on *.Owner for polymorphic fields - or even select them, for that matter. Instead we have to massage the query to use
    // TYPEOF instead
    Map<String, SObjectField> fieldNameToField = sObjectType.getDescribe().fields.getMap();
    if (this.hasPolymorphicOwnerClause(optionalWhereClause, fieldNameToField) == false || uniqueQueryFieldNames.contains('Count()')) {
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

        uniqueQueryFieldNames.add('TYPEOF ' + whoOrWhat + ' WHEN ' + relationshipName + ' THEN ' + typeOfField + ' END');

        optionalWhereClause = optionalWhereClause.replace(indexer + relationshipName + '\'', '')
          .replace(whereClause, '')
          .replace('()', '')
          .replace('( OR )', '')
          .replace('( AND )', '')
          .trim();
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

  private void addCurrencyIsoCodeForMultiCurrencyOrgs(List<String> fieldNames, Set<String> uniqueLowercaseFields) {
    if (RollupCurrencyInfo.isMultiCurrency() && uniqueLowercaseFields.contains(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME.toLowerCase()) == false) {
      Boolean hasAggregateFunction = false;
      for (String uniqueQueryFieldName : fieldNames) {
        // This is definitely not the most intuitive way to do this, but need to determine if the query
        // will be a regular query vs an aggregated query - all aggregate functions use '()', so checking
        // for '(' is a quick & lazy way to check without making larger changes to how RollupQueryBuilder works
        // (but it's very goofy & could definitely be improved)
        if (uniqueQueryFieldName?.contains('(')) {
          hasAggregateFunction = true;
          break;
        }
      }
      if (hasAggregateFunction == false) {
        fieldNames.add(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME);
      }
    }
  }
}
