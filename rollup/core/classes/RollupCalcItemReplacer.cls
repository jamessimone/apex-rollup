/**
 * @return `List<SObject>` - Calc items
 * Depending on the `RollupControl__mdt.ReplaceCalcItemsAsyncWhenOverCount__c` field,
 * re-queries for passed-in calc items when they have either:
 * - a polymorphic calc item where clause field
 * - parent-level fields
 */
public without sharing class RollupCalcItemReplacer {
  private final RollupControl__mdt control;
  private final Set<Rollup__mdt> processedMetadata;
  public RollupCalcItemReplacer(RollupControl__mdt control) {
    this.control = control;
    this.processedMetadata = new Set<Rollup__mdt>();
  }

  public Boolean hasProcessedMetadata(Rollup__mdt meta) {
    return this.processedMetadata.contains(meta);
  }

  public List<SObject> replace(List<SObject> calcItems, Rollup__mdt metadata) {
    Boolean shouldRunSync = this.control.ReplaceCalcItemsAsyncWhenOverCount__c >= calcItems.size();
    if (this.hasProcessedMetadata(metadata)) {
      return calcItems;
    } else if (
      shouldRunSync == false &&
      this.control.ShouldRunAs__c != RollupMetaPicklists.ShouldRunAs.Synchronous &&
      System.isBatch() == false &&
      System.isQueueable() == false
    ) {
      return calcItems;
    } else if (String.isNotBlank(metadata.CalcItemWhereClause__c) && calcItems.isEmpty() == false) {
      this.processedMetadata.add(metadata);
      calcItems = this.replaceCalcItemsWithPolymorphicWhereClauses(calcItems, metadata);
      return this.replaceCalcItemsWithParentWhereClauses(calcItems, metadata);
    } else {
      return calcItems;
    }
  }

  private List<SObject> replaceCalcItemsWithPolymorphicWhereClauses(List<SObject> calcItems, Rollup__mdt metadata) {
    final String typeField = '.Type';
    final String owner = 'Owner.';
    // first we check to see if there is a calc item where clause, and that it contains any of the common polymorphic fields
    SObject firstItem = calcItems[0];
    Boolean hasOwnerClause = metadata.CalcItemWhereClause__c.contains(owner);
    Boolean hasTypeClause = metadata.CalcItemWhereClause__c.contains(typeField);
    SObjectType sObjectType = firstItem.getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
    Boolean hasPolyMorphicFields = hasOwnerClause || hasTypeClause || fieldMap.get(metadata.LookupFieldOnCalcItem__c)?.getDescribe().isNamePointing() == true;

    if (hasPolyMorphicFields == false) {
      return calcItems;
    }
    if (hasTypeClause == false && hasOwnerClause == false) {
      return calcItems;
    }

    // the calc item where clause contains at least one polymorphic field, but before re-querying we validate whether or not the fields are already provided
    Map<String, Object> populatedFields = firstItem.getPopulatedFieldsAsMap();
    Set<String> additionalQueryFields = new Set<String>();
    List<String> optionalWhereClauses = new List<String>();

    this.processWhereClauseForDownstreamEvals(optionalWhereClauses, additionalQueryFields, sObjectType, typeField, owner, metadata);

    if (optionalWhereClauses.isEmpty()) {
      return calcItems;
    }

    // we have to manually iterate through these fields because the "fieldMap" keySet is all in lowercase because it's ... special
    // and only responds properly to proper-cased fields when you call the map "containsKey" method - if the field names in the keySet were
    // proper-cased, we could just call additionalQueryFields.addAll(populatedFields.keySet().removeAll(fieldMap.keySet())) - alas
    // this awesome one-liner doesn't work for us
    for (String fieldName : populatedFields.keySet()) {
      if (fieldMap.containsKey(fieldName)) {
        additionalQueryFields.add(fieldName);
      }
    }

    String queryString = RollupQueryBuilder.Current.getQuery(
      sObjectType,
      new List<String>(additionalQueryFields),
      'Id',
      '=',
      String.join(optionalWhereClauses, ' AND ')
    );
    List<String> objIds = new List<String>();
    for (SObject record : calcItems) {
      if (String.isNotBlank(record.Id)) {
        objIds.add(record.Id);
      }
    }
    RollupLogger.Instance.log('replacing calc items with polymorphic where clause using query string:', queryString, LoggingLevel.FINE);
    return Database.query(queryString);
  }

  private void processWhereClauseForDownstreamEvals(
    List<String> optionalWhereClauses,
    Set<String> additionalQueryFields,
    SObjectType sObjectType,
    String typeField,
    String owner,
    Rollup__mdt metadata
  ) {
    if (String.isBlank(metadata.CalcItemWhereClause__c)) {
      return;
    }
    RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(metadata.CalcItemWhereClause__c, sObjectType);
    for (String whereClause : whereEval.getWhereClauses()) {
      if (whereClause.contains(typeField) || whereClause.contains(owner)) {
        List<String> splitWheres = whereClause.split(' ');
        if (splitWheres.size() > 0) {
          additionalQueryFields.add(splitWheres[0]);
        }
        // "consume" the metadata where clause for downstream evaluators
        metadata.CalcItemWhereClause__c = metadata.CalcItemWhereClause__c.replace(whereClause, '');
        optionalWhereClauses.add(whereClause);
      }
    }
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  private List<SObject> replaceCalcItemsWithParentWhereClauses(List<SObject> calcItems, Rollup__mdt metadata) {
    if (calcItems.isEmpty()) {
      return calcItems;
    }
    SObjectType calcItemType = calcItems[0].getSObjectType();
    List<String> queryFields = RollupEvaluator.getWhereEval(metadata.CalcItemWhereClause__c, calcItemType).getQueryFields();
    Map<String, SObjectField> fieldNameToToken = calcItemType.getDescribe().fields.getMap();
    List<String> validQueryFields = new List<String>();
    for (String queryField : queryFields) {
      String fieldPart = queryField.substringBefore('.');
      String fieldName = fieldPart.endsWith('__r') ? fieldPart.removeEnd('__r') + '__c' : fieldPart + 'Id';
      if (queryField.contains('.') && fieldNameToToken.containsKey(fieldName) && fieldNameToToken.get(fieldName).getDescribe().isNamePointing() == false) {
        validQueryFields.add(queryField);
        validQueryFields.add(fieldName);
      }
    }

    if (validQueryFields.isEmpty() == false) {
      // re-initialize the Set to avoid: System.FinalException: Collection is read-only
      Set<String> includedFields = new Set<String>(calcItems[0].getPopulatedFieldsAsMap().keySet());
      includedFields.addAll(queryFields);
      List<SObject> objIds = calcItems; // for bind variable
      String queryString = RollupQueryBuilder.Current.getQuery(calcItemType, new List<String>(includedFields), 'Id', '=');
      RollupLogger.Instance.log('replacing calc items with parent-level where clause using query string:', queryString, LoggingLevel.FINE);
      calcItems = Database.query(queryString);
    }
    return calcItems;
  }
}
