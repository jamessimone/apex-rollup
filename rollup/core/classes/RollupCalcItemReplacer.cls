/**
 * @return `List<SObject>` - Calc items
 * Depending on the `RollupControl__mdt.ReplaceCalcItemsAsyncWhenOverCount__c` field,
 * re-queries for passed-in calc items when they have either:
 * - a polymorphic child object where clause field
 * - parent-level fields
 */
public without sharing class RollupCalcItemReplacer {
  private final RollupControl__mdt control;
  private final Set<Rollup__mdt> processedMetadata;
  private final Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator> metaToEval;
  private final Map<SObjectType, Set<String>> parentQueryFields;
  private final Map<SObjectType, Set<String>> baseQueryFields;
  private final Set<Integer> calcItemHashCodes = new Set<Integer>();
  private RollupRepository repo;

  public RollupCalcItemReplacer(RollupControl__mdt control) {
    this.control = control;
    this.processedMetadata = new Set<Rollup__mdt>();
    this.metaToEval = new Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator>();
    this.parentQueryFields = new Map<SObjectType, Set<String>>();
    this.baseQueryFields = new Map<SObjectType, Set<String>>();
  }

  public static SObject replaceField(SObject target, Schema.SObjectField fieldToken, Object value) {
    if (fieldToken?.getDescribe().isCalculated() == false && fieldToken?.getDescribe().isUpdateable() == true) {
      target.put(fieldToken, value);
    } else {
      target = serializeReplace(target, fieldToken.getDescribe().getName(), value);
    }
    return target;
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
      calcItems = this.potentiallyReplaceMissingBaseFields(calcItems);
      calcItems = this.potentiallyReplacePolymorphicWhereClauses(calcItems);
      this.replaceCalcItemsWithParentWhereClauses(calcItems);
    } else if (mightNeedReplacement == false) {
      this.calcItemHashCodes.add(calcItems.hashCode());
      this.processedMetadata.addAll(metadata);
    }
    return calcItems;
  }

  private Boolean setupRequiresReplacement(List<SObject> calcItems, List<Rollup__mdt> metadata) {
    Boolean localNeedsReplacement = false;
    if (calcItems?.isEmpty() != false) {
      return localNeedsReplacement;
    }
    SObjectType calcType = calcItems[0].getSObjectType();
    for (Rollup__mdt meta : metadata) {
      if (meta.IsRollupStartedFromParent__c && meta.LookupObject__c == calcType.getDescribe().getName()) {
        return localNeedsReplacement;
      } else if (meta.CalcItem__c != calcType.getDescribe().getName()) {
        return localNeedsReplacement;
      }
      if (this.repo == null) {
        this.repo = new RollupRepository(RollupMetaPicklists.getAccessLevel(meta));
      }

      Boolean isPresentInMapAlready = this.metaToEval.containsKey(meta);
      Boolean mightNeedReplacement = String.isNotBlank(meta.CalcItemWhereClause__c) || meta.RollupOrderBys__r.isEmpty() == false;
      if (mightNeedReplacement && isPresentInMapAlready == false) {
        localNeedsReplacement = true;
        RollupEvaluator.WhereFieldEvaluator whereEval = RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, calcType);
        this.metaToEval.put(meta, whereEval);
        Set<String> parentQueryFieldSet = this.parentQueryFields.containsKey(calcType) ? this.parentQueryFields.get(calcType) : new Set<String>();
        Set<String> baseQueryFieldSet = this.baseQueryFields.containsKey(calcType) ? this.baseQueryFields.get(calcType) : new Set<String>();
        for (RollupOrderBy__mdt orderBy : meta.RollupOrderBys__r) {
          this.addQueryableFields(orderBy.FieldName__c, parentQueryFieldSet, baseQueryFieldSet, calcItems[0]);
        }
        for (String queryField : whereEval.getQueryFields()) {
          this.addQueryableFields(queryField, parentQueryFieldSet, baseQueryFieldSet, calcItems[0]);
        }
        this.parentQueryFields.put(calcType, parentQueryFieldSet);
        this.baseQueryFields.put(calcType, baseQueryFieldSet);
      } else if (isPresentInMapAlready) {
        localNeedsReplacement = true;
      }
    }
    return localNeedsReplacement;
  }

  private void addQueryableFields(String fieldName, Set<String> parentQueryFieldSet, Set<String> baseQueryFieldSet, SObject calcItem) {
    if (fieldName.contains('.')) {
      parentQueryFieldSet.add(fieldName);
    } else if (calcItem.isSet(fieldName) == false) {
      baseQueryFieldSet.add(fieldName);
    }
  }

  private List<SObject> potentiallyReplaceMissingBaseFields(List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return calcItems;
    }
    Map<Id, SObject> idToCalcItem = new Map<Id, SObject>(calcItems);
    Set<String> baseFields = this.baseQueryFields.get(calcItems[0].getSObjectType());
    if (baseFields?.isEmpty() == false) {
      SObject firstItem = calcItems[0];
      String queryString = RollupQueryBuilder.Current.getQuery(firstItem.getSObjectType(), new List<String>(baseFields), 'Id', '=');
      List<SObject> calcItemsWithReplacement = this.repo.setQuery(queryString).setArg(calcItems).get();
      Map<String, Schema.SObjectField> fieldNameToDescribe = firstItem.getSObjectType().getDescribe().fields.getMap();
      for (SObject calcItemWithReplacement : calcItemsWithReplacement) {
        if (idToCalcItem.containsKey(calcItemWithReplacement.Id)) {
          SObject calcItem = idToCalcItem.get(calcItemWithReplacement.Id);
          for (String baseField : baseFields) {
            Schema.SObjectfield baseFieldToken = fieldNameToDescribe.get(baseField);
            idToCalcItem.put(calcItem.Id, replaceField(calcItem, baseFieldToken, calcItemWithReplacement.get(baseField)));
          }
        }
      }
    }
    return idToCalcItem.values();
  }

  private List<SObject> potentiallyReplacePolymorphicWhereClauses(List<SObject> calcItems) {
    for (Rollup__mdt meta : this.metaToEval.keySet()) {
      calcItems = this.replaceCalcItemsWithPolymorphicWhereClauses(calcItems, meta);
    }
    return calcItems;
  }

  private List<SObject> replaceCalcItemsWithPolymorphicWhereClauses(List<SObject> calcItems, Rollup__mdt metadata) {
    final String typeField = '.Type';
    final String owner = 'Owner.';
    // first we check to see if there is a child object where clause, and that it contains any of the common polymorphic fields
    SObject firstItem = calcItems[0];
    Boolean hasOwnerClause = metadata.CalcItemWhereClause__c?.contains(owner) == true;
    Boolean hasTypeClause = metadata.CalcItemWhereClause__c?.contains(typeField) == true;
    SObjectType sObjectType = firstItem.getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    Boolean hasPolyMorphicFields = hasOwnerClause || hasTypeClause || fieldMap.get(metadata.LookupFieldOnCalcItem__c)?.getDescribe().isNamePointing() == true;

    if (hasPolyMorphicFields == false) {
      return calcItems;
    }
    if (hasTypeClause == false && hasOwnerClause == false) {
      return calcItems;
    }

    // the child object where clause contains at least one polymorphic field, but before re-querying we validate whether or not the fields are already provided
    Map<String, Object> populatedFields = firstItem.getPopulatedFieldsAsMap();
    List<String> optionalWhereClauses = new List<String>();
    Set<String> additionalQueryFields = new Set<String>();
    if (this.metaToEval.containsKey(metadata)) {
      RollupEvaluator.WhereFieldEvaluator eval = this.metaToEval.get(metadata);
      this.processWhereClauseForDownstreamEvals(optionalWhereClauses, additionalQueryFields, sObjectType, typeField, owner, metadata, eval);
    }

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

    calcItems = this.repo.setQuery(queryString).setArg(calcItems).get();
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

  private void replaceCalcItemsWithParentWhereClauses(List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return;
    }
    Set<String> parentQueryFields = this.parentQueryFields.get(calcItems[0].getSObjectType());
    if (parentQueryFields?.isEmpty() != false) {
      return;
    }
    SObjectType calcItemType = calcItems[0].getSObjectType();
    Map<String, SObjectField> fieldNameToToken = calcItemType.getDescribe().fields.getMap();
    Boolean hasUnqueriedParentFields = false;
    for (String queryField : parentQueryFields) {
      String fieldPart = queryField.substringBefore('.');
      String fieldName = this.getFullyQualifiedFieldName(fieldPart);
      if (this.isParentFieldAlreadyPopulated(fieldNameToToken, fieldName, queryField, calcItems[0]) == false) {
        hasUnqueriedParentFields = true;
        break;
      }
    }

    if (hasUnqueriedParentFields) {
      String queryString = RollupQueryBuilder.Current.getQuery(calcItemType, new List<String>(parentQueryFields), 'Id', '=');
      Map<Id, SObject> idToCalcItemsWithParentFields = new Map<Id, SObject>(this.repo.setQuery(queryString).setArg(calcItems).get());
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
    for (Integer index = 0; index < calcItems.size(); index++) {
      SObject calcItem = calcItems[index];
      SObject calcItemWIthUpdatedParentField = idToCalcItemsWithParentFields.get(calcItem.Id);
      if (calcItemWIthUpdatedParentField == null) {
        continue;
      }
      for (String fieldName : calcItemWIthUpdatedParentField.getPopulatedFieldsAsMap().keySet()) {
        if (fieldNameToFieldToken.containsKey(fieldName)) {
          DescribeFieldResult fieldToken = fieldNameToFieldToken.get(fieldName).getDescribe();
          Boolean isAcceptableField = fieldToken.getReferenceTo().isEmpty() == false && fieldToken.getName() != 'Id';
          if (isAcceptableField && fieldToken.isNamePointing() == false) {
            try {
              calcItem.putSObject(fieldToken.getRelationshipName(), calcItemWIthUpdatedParentField.getSObject(fieldToken.getRelationshipName()));
            } catch (SObjectException ex) {
              // avoids "System.SObjectException: Relationship { relationship name } is not editable"
              if (calcItemWIthUpdatedParentField.getPopulatedFieldsAsMap().containsKey(fieldToken.getRelationshipName())) {
                String relationshipName = fieldToken.getRelationshipName();
                calcItems.set(index, serializeReplace(calcItem, relationshipName, calcItemWIthUpdatedParentField.getSObject(relationshipName)));
              }
            }
          } else if (isAcceptableField) {
            // polymorphic parent fields that are returned from SOQL can get retrieved via .getSObject,
            // but can't be appended via .putSObject without reinitializing the parent object to its actual type
            // this is because they are returned with type "Name", and avoids the dreaded:
            // "System.SObjectException: Illegal assignment from Name to { the calcItem type }"
            SObject parentFieldObject = calcItemWIthUpdatedParentField.getSObject(fieldToken.getRelationshipName());
            SObject replacementObject = parentFieldObject.Id.getSObjectType().newSObject();
            for (String populatedFieldName : parentFieldObject.getPopulatedFieldsAsMap().keySet()) {
              replacementObject.put(populatedFieldName, parentFieldObject.get(populatedFieldName));
            }
            calcItem.putSObject(fieldToken.getRelationshipName(), replacementObject);
          }
        }
      }
    }
  }

  private static SObject serializeReplace(SObject calcItem, String fieldName, Object value) {
    Map<String, Object> deserialized = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(calcItem));
    deserialized.put(fieldName, value);
    return (SObject) JSON.deserialize(JSON.serialize(deserialized), SObject.class);
  }
}
