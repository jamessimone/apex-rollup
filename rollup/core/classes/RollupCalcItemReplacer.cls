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
  private final Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator> metaToEval;
  private final Set<String> queryFields;
  private final Set<Integer> calcItemHashCodes = new Set<Integer>();
  public RollupCalcItemReplacer(RollupControl__mdt control) {
    this.control = control;
    this.processedMetadata = new Set<Rollup__mdt>();
    this.metaToEval = new Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator>();
    this.queryFields = new Set<String>();
  }

  public Boolean hasProcessedMetadata(List<Rollup__mdt> metas, List<SObject> calcItems) {
    return this.processedMetadata.containsAll(metas) && this.calcItemHashCodes.contains(calcItems?.hashCode());
  }

  public void resetShouldRunAs(String shouldRunAsValue) {
    this.control.ShouldRunAs__c = shouldRunAsValue;
  }

  public List<SObject> replace(List<SObject> calcItems, List<Rollup__mdt> metadata) {
    Boolean shouldRunSync = this.control?.ReplaceCalcItemsAsyncWhenOverCount__c >= calcItems?.size();
    Boolean mightNeedReplacement = this.setupRequiresReplacement(calcItems, metadata);

    if (this.hasProcessedMetadata(metadata, calcItems)) {
      return calcItems;
    } else if (
      mightNeedReplacement &&
      shouldRunSync == false &&
      this.control.ShouldRunAs__c != RollupMetaPicklists.ShouldRunAs.Synchronous &&
      System.isBatch() == false &&
      System.isQueueable() == false
    ) {
      return calcItems;
    } else if (mightNeedReplacement && calcItems?.isEmpty() == false) {
      this.calcItemHashCodes.add(calcItems.hashCode());
      this.processedMetadata.addAll(metadata);
      calcItems = this.potentiallyReplacePolymorphicWhereClauses(calcItems);
      this.replaceCalcItemsWithParentWhereClauses(calcItems);
    } else if (mightNeedReplacement == false) {
      this.processedMetadata.addAll(metadata);
    }
    return calcItems;
  }

  private Boolean setupRequiresReplacement(List<SObject> calcItems, List<Rollup__mdt> metadata) {
    Boolean localNeedsReplacement = false;
    for (Rollup__mdt meta : metadata) {
      Boolean isPresentInMapAlready = this.metaToEval.containsKey(meta);
      Boolean mightNeedReplacement = String.isNotBlank(meta.CalcItemWhereClause__c);
      if (mightNeedReplacement && calcItems?.isEmpty() == false && isPresentInMapAlready == false) {
        localNeedsReplacement = true;
        RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, calcItems[0].getSObjectType());
        this.metaToEval.put(meta, whereEval);
        for (String queryField : whereEval.getQueryFields()) {
          if (queryField.contains('.')) {
            this.queryFields.add(queryField);
          }
        }
      } else if (isPresentInMapAlready) {
        localNeedsReplacement = true;
      }
    }
    return localNeedsReplacement;
  }

  private List<SObject> potentiallyReplacePolymorphicWhereClauses(List<SObject> calcItems) {
    for (Rollup__mdt meta : this.metaToEval.keySet()) {
      calcItems = this.replaceCalcItemsWithPolymorphicWhereClauses(calcItems, meta);
    }
    return calcItems;
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
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
    List<String> optionalWhereClauses = new List<String>();
    Set<String> additionalQueryFields = new Set<String>();
    RollupEvaluator.WhereFieldEvaluator eval = this.metaToEval.get(metadata);
    this.processWhereClauseForDownstreamEvals(optionalWhereClauses, additionalQueryFields, sObjectType, typeField, owner, metadata, eval);

    Boolean hasOwnerPrepolulated = populatedFields.containsKey('Owner');
    Boolean hasTypePrepopulated = populatedFields.containsKey('Type');

    if (optionalWhereClauses.isEmpty()) {
      return calcItems;
    } else if (hasOwnerClause && hasOwnerPrepolulated && hasTypeClause == false) {
      return calcItems;
    } else if (hasTypeClause && hasTypePrepopulated && hasOwnerClause == false) {
      return calcItems;
    } else if (hasTypeClause && hasTypePrepopulated && hasOwnerClause && hasOwnerPrepolulated) {
      return calcItems;
    }

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
    List<SObject> objIds = calcItems; // for bind variable

    RollupLogger.Instance.log('replacing calc items with polymorphic where clause using query string:', queryString, LoggingLevel.FINE);
    calcItems = Database.query(queryString);
    return calcItems;
  }

  private void processWhereClauseForDownstreamEvals(
    List<String> optionalWhereClauses,
    Set<String> additionalQueryFields,
    SObjectType sObjectType,
    String typeField,
    String owner,
    Rollup__mdt metadata,
    RollupEvaluator.WhereFieldEvaluator whereEval
  ) {
    for (String whereClause : whereEval.getWhereClauses()) {
      if (whereClause.contains(typeField) || whereClause.contains(owner)) {
        // "consume" the metadata where clause for downstream evaluators
        List<String> splitWheres = whereClause.split(' ');
        if (splitWheres.size() > 0) {
          additionalQueryFields.add(splitWheres[0]);
        }
        metadata.CalcItemWhereClause__c = metadata.CalcItemWhereClause__c.replace(whereClause, '');
        optionalWhereClauses.add(whereClause);
      }
    }
  }

  @SuppressWarnings('PMD.UnusedLocalVariable')
  private void replaceCalcItemsWithParentWhereClauses(List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return;
    }
    SObjectType calcItemType = calcItems[0].getSObjectType();
    Map<String, SObjectField> fieldNameToToken = calcItemType.getDescribe().fields.getMap();
    Boolean hasUnqueriedParentFields = false;
    for (String queryField : this.queryFields) {
      String fieldPart = queryField.substringBefore('.');
      String fieldName = this.getFullyQualifiedFieldName(fieldPart);
      if (this.isParentFieldAlreadyPopulated(fieldNameToToken, fieldName, queryField, calcItems[0]) == false) {
        hasUnqueriedParentFields = true;
        break;
      }
    }

    if (hasUnqueriedParentFields) {
      List<SObject> objIds = calcItems; // for bind variable
      String queryString = RollupQueryBuilder.Current.getQuery(calcItemType, new List<String>(this.queryFields), 'Id', '=');
      RollupLogger.Instance.log('replacing calc items with parent-level where clause using query string:', queryString, LoggingLevel.FINE);
      Map<Id, SObject> idToCalcItemsWithParentFields = new Map<Id, SObject>(Database.query(queryString));
      this.appendUpdatedParentFields(calcItems, idToCalcItemsWithParentFields);
    }
  }

  private String getFullyQualifiedFieldName(String fieldPart) {
    return fieldPart.endsWith('__r') ? fieldPart.removeEnd('__r') + '__c' : fieldPart + 'Id';
  }

  private Boolean isParentFieldAlreadyPopulated(Map<String, SObjectField> fieldNameToToken, String fieldName, String fieldPath, SObject firstRecord) {
    return fieldNameToToken.containsKey(fieldName) &&
      fieldNameToToken.get(fieldName).getDescribe().isNamePointing() == false &&
      this.hasParentField(firstRecord, fieldNameToToken, fieldPath);
  }

  private Boolean hasParentField(SObject record, Map<String, Schema.SObjectField> fieldNameToToken, String fieldPath) {
    List<String> splitParts = fieldPath.split('\\.');
    try {
      while (splitParts.size() > 1) {
        String fieldPart = splitParts.remove(0);
        String field = this.getFullyQualifiedFieldName(fieldPart);
        Schema.SObjectField fieldToken = fieldNameToToken.get(field);
        if (fieldToken.getDescribe().getReferenceTo()?.isEmpty() == false) {
          SObject parentRecord = record.getSObject(fieldPart);
          if (parentRecord == null) {
            return false;
          } else {
            return this.hasParentField(parentRecord, parentRecord.getSObjectType().getDescribe().fields.getMap(), String.join(splitParts, '.'));
          }
        }
      }
      return record.get(splitParts.remove(0)) != null;
    } catch (SObjectException ex) {
      // for records passed in from non Trigger / RT flows, this handles the
      // System.SObjectException: SObject row was retrieved via SOQL without querying the requested field ... exception
      return false;
    }
  }

  private void appendUpdatedParentFields(List<SObject> calcItems, Map<Id, SObject> idToCalcItemsWithParentFields) {
    Map<String, SObjectField> fieldNameToFieldToken = calcItems[0].getSObjectType().getDescribe().fields.getMap();
    for (SObject calcItem : calcItems) {
      SObject calcItemWIthUpdatedParentField = idToCalcItemsWithParentFields.get(calcItem.Id);
      for (String fieldName : calcItemWIthUpdatedParentField.getPopulatedFieldsAsMap().keySet()) {
        if (fieldNameToFieldToken.containsKey(fieldName)) {
          DescribeFieldResult fieldToken = fieldNameToFieldToken.get(fieldName).getDescribe();
          if (fieldToken.getReferenceTo().isEmpty() == false && fieldToken.isNamePointing() == false && fieldToken.getName() != 'Id') {
            calcItem.putSObject(fieldToken.getRelationshipName(), calcItemWIthUpdatedParentField.getSObject(fieldToken.getRelationshipName()));
          }
        }
      }
    }
  }
}
