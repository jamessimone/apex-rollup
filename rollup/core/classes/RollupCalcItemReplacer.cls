/**
 * @return `List<SObject>` - Calc items
 * Depending on the `RollupControl__mdt.ReplaceCalcItemsAsyncWhenOverCount__c` field,
 * re-queries for passed-in calc items when they have either:
 * - a polymorphic child object where clause field
 * - parent-level fields
 */
public without sharing class RollupCalcItemReplacer {
  private final RollupControl__mdt control;
  private final Set<Rollup__mdt> processedMetadata = new Set<Rollup__mdt>();
  private final Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator> metaToEval = new Map<Rollup__mdt, RollupEvaluator.WhereFieldEvaluator>();
  private final Map<String, Set<String>> parentQueryFields = new Map<String, Set<String>>();
  private final Map<String, Set<String>> baseQueryFields = new Map<String, Set<String>>();
  private final Map<String, Set<String>> keyToOptionalWhereClauses = new Map<String, Set<String>>();
  private final Map<SObjectType, Set<String>> typeToAdditionalQueryFields = new Map<SObjectType, Set<String>>();
  private final Set<Integer> calcItemHashCodes = new Set<Integer>();
  private RollupRepository repo;

  private static final String TYPE_FIELD = '.Type';
  private static final String OWNER = 'Owner.';

  public RollupCalcItemReplacer(RollupControl__mdt control) {
    this.control = control;
  }

  public static SObject replaceField(SObject target, Schema.SObjectField fieldToken, Object value) {
    if (fieldToken?.getDescribe().isCalculated() == false && fieldToken?.getDescribe().isUpdateable() == true) {
      target.put(fieldToken, value);
    } else {
      target = serializeReplace(target, fieldToken.toString(), value);
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
    if (this.hasProcessedMetadata(metadata, calcItems)) {
      return calcItems;
    }

    Boolean shouldRunSync = this.control?.ReplaceCalcItemsAsyncWhenOverCount__c >= calcItems?.size();
    Boolean mightNeedReplacement = this.setupRequiresReplacement(calcItems, metadata);
    if (
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
    if (calcItems?.isEmpty() != false || metadata?.isEmpty() != false) {
      return localNeedsReplacement;
    }
    this.repo = this.repo ?? new RollupRepository(RollupMetaPicklists.getAccessLevel(metadata[0]));
    SObjectType calcType = calcItems[0].getSObjectType();
    for (Rollup__mdt meta : metadata) {
      if (meta.CalcItem__c != calcType.toString()) {
        continue;
      }

      RollupEvaluator.WhereFieldEvaluator whereEval = this.metaToEval.get(meta);
      Boolean mightNeedReplacement = String.isNotBlank(meta.CalcItemWhereClause__c) || meta.RollupOrderBys__r.isEmpty() == false;
      if (mightNeedReplacement && whereEval == null) {
        whereEval = RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, calcType);
        this.processWhereClauseForDownstreamEvals(calcType, meta, whereEval);
        for (RollupOrderBy__mdt orderBy : meta.RollupOrderBys__r) {
          this.addQueryableFields(orderBy.FieldName__c.trim(), calcItems[0]);
        }
        for (String queryField : whereEval.getQueryFields()) {
          this.addQueryableFields(queryField, calcItems[0]);
        }

        String sobjectTypeName = '' + calcItems[0].getSObjectType();
        localNeedsReplacement =
          this.parentQueryFields.get(sobjectTypeName)?.isEmpty() == false ||
          this.baseQueryFields.get(sobjectTypeName)?.isEmpty() == false ||
          this.keyToOptionalWhereClauses.get(OWNER + sobjectTypeName)?.isEmpty() == false ||
          this.keyToOptionalWhereClauses.get(TYPE_FIELD + sobjectTypeName)?.isEmpty() == false;
        this.metaToEval.put(meta, localNeedsReplacement ? whereEval : null);
      } else if (whereEval != null) {
        localNeedsReplacement = true;
      }
    }
    return localNeedsReplacement;
  }

  private void addQueryableFields(String fieldName, SObject calcItem) {
    if (fieldName.contains('.')) {
      List<String> relationshipFields = fieldName.split('\\.');
      String actualField = relationshipFields.remove(relationshipFields.size() - 1);
      SObject relativeObject = calcItem;
      while (relationshipFields.isEmpty() == false) {
        try {
          relativeObject = relativeObject.getSObject(relationshipFields.remove(0));
        } catch (Exception ex) {
          this.fillField(this.parentQueryFields, '' + calcItem.getSObjectType(), fieldName);
        }
      }
      try {
        relativeObject.get(actualField);
      } catch (Exception ex) {
        this.fillField(this.parentQueryFields, '' + calcItem.getSObjectType(), fieldName);
      }
    } else {
      if (fieldName.startsWithIgnoreCase('not(')) {
        fieldName = fieldName.substring(4, fieldName.length());
      }
      try {
        // it'd be great to use calcItem.isSet(fieldName) here, but that returns false for null values
        calcItem.get(fieldName);
      } catch (Exception ex) {
        this.fillField(this.baseQueryFields, '' + calcItem.getSObjectType(), fieldName);
      }
    }
  }

  private void fillField(Map<String, Set<String>> keyToFields, String key, String fieldName) {
    Set<String> fieldNames = keyToFields.get(key);
    if (fieldNames == null) {
      fieldNames = new Set<String>();
      keyToFields.put(key, fieldNames);
    }
    fieldNames.add(fieldName);
  }

  private List<SObject> potentiallyReplaceMissingBaseFields(List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return calcItems;
    }
    Map<Id, SObject> idToCalcItem = RollupFieldInitializer.Current.createSafeMap(calcItems);
    Set<String> baseFields = this.baseQueryFields.get('' + calcItems[0].getSObjectType());
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
    if (calcItems.isEmpty() == false) {
      Map<String, Schema.SObjectField> fieldMap = calcItems[0].getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
      for (Rollup__mdt meta : this.metaToEval.keySet()) {
        calcItems = this.replaceCalcItemsWithPolymorphicWhereClauses(calcItems, meta, fieldMap);
        if (calcItems.isEmpty()) {
          break;
        }
      }
    }
    return calcItems;
  }

  private List<SObject> replaceCalcItemsWithPolymorphicWhereClauses(List<SObject> calcItems, Rollup__mdt metadata, Map<String, Schema.SObjectField> fieldMap) {
    // first we check to see if there is a child object where clause, and that it contains any of the common polymorphic fields
    SObject firstItem = calcItems[0];
    SObjectType sObjectType = firstItem.getSObjectType();
    Set<String> optionalWhereClauses = this.keyToOptionalWhereClauses.get(OWNER + sObjectType) ?? new Set<String>();
    Boolean hasOwnerClause = optionalWhereClauses.isEmpty() == false;
    Boolean hasTypeClause = this.keyToOptionalWhereClauses.containsKey(TYPE_FIELD + sObjectType);
    if (hasTypeClause) {
      optionalWhereClauses.addAll(this.keyToOptionalWhereClauses.get(TYPE_FIELD + sObjectType));
    }
    Boolean hasPolymorphicFields = hasOwnerClause || hasTypeClause || fieldMap.get(metadata.LookupFieldOnCalcItem__c)?.getDescribe().isNamePointing() == true;

    if (hasPolymorphicFields == false) {
      return calcItems;
    }
    if (hasTypeClause == false && hasOwnerClause == false) {
      return calcItems;
    }

    // the child object where clause contains at least one polymorphic field, but before re-querying we validate whether or not the fields are already provided
    Map<String, Object> populatedFields = firstItem.getPopulatedFieldsAsMap();
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
    } else if (hasTypeClause && hasTypePrepopulated == false && hasOwnerClause == false) {
      Boolean hasAllSoughtFields = true;
      for (String whereClause : optionalWhereClauses) {
        hasAllSoughtFields = hasAllSoughtFields && this.hasSoughtField(TYPE_FIELD, whereClause, firstItem);
        if (hasAllSoughtFields == false) {
          break;
        }
      }
      if (hasAllSoughtFields) {
        return calcItems;
      }
    }

    Set<String> additionalQueryFields = this.typeToAdditionalQueryFields.get(sObjectType);
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
      String.join(optionalWhereClauses, ' OR ')
    );

    calcItems = this.repo.setQuery(queryString).setArg(calcItems).get();
    return calcItems;
  }

  private void processWhereClauseForDownstreamEvals(Schema.SObjectType sObjectType, Rollup__mdt metadata, RollupEvaluator.WhereFieldEvaluator whereEval) {
    for (String whereClause : whereEval.getWhereClauses()) {
      Boolean hasTypeField = whereClause.split(TYPE_FIELD + '(?!__r)').size() > 1;
      Boolean hasOwnerField = whereClause.contains(OWNER);
      if (hasTypeField == false && hasOwnerField == false) {
        continue;
      }
      // "consume" the metadata where clause for downstream evaluators
      List<String> splitWheres = whereClause.split(' ');
      if (splitWheres.size() > 0) {
        Set<String> additionalQueryFields = this.typeToAdditionalQueryFields.get(sObjectType);
        if (additionalQueryFields == null) {
          additionalQueryFields = new Set<String>();
          this.typeToAdditionalQueryFields.put(sObjectType, additionalQueryFields);
        }
        additionalQueryFields.add(splitWheres[0]);
      }
      metadata.CalcItemWhereClause__c = metadata.CalcItemWhereClause__c.replace(whereClause, '');
      if (hasTypeField) {
        String key = TYPE_FIELD + sObjectType;
        this.fillField(this.keyToOptionalWhereClauses, key, whereClause);
      }
      if (hasOwnerField) {
        String key = OWNER + sObjectType;
        this.fillField(this.keyToOptionalWhereClauses, key, whereClause);
      }
    }
  }

  private void replaceCalcItemsWithParentWhereClauses(List<SObject> calcItems) {
    if (calcItems.isEmpty()) {
      return;
    }
    Set<String> parentQueryFields = this.parentQueryFields.get('' + calcItems[0].getSObjectType());
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
      SObject calcItemWithUpdatedParentField = idToCalcItemsWithParentFields.get(calcItem.Id);
      Map<String, Object> updatedParentFields = calcItemWithUpdatedParentField?.getPopulatedFieldsAsMap() ?? new Map<String, Object>();
      for (String fieldName : updatedParentFields.keySet()) {
        Schema.DescribeFieldResult fieldToken = fieldNameToFieldToken.get(fieldName)?.getDescribe();
        Boolean isSkippableField = fieldToken?.getReferenceTo().isEmpty() != false || fieldToken?.getName() == 'Id';
        if (isSkippableField) {
          continue;
        }

        if (fieldToken.isNamePointing() == false) {
          try {
            SObject parent = calcItem.getSObject(fieldToken.getRelationshipName());
            if (parent == null) {
              calcItem.putSObject(fieldToken.getRelationshipName(), calcItemWithUpdatedParentField.getSObject(fieldToken.getRelationshipName()));
            } else {
              parent.put(fieldName, updatedParentFields.get(fieldName));
            }
          } catch (SObjectException ex) {
            // avoids "System.SObjectException: Relationship { relationship name } is not editable"
            if (updatedParentFields.containsKey(fieldToken.getRelationshipName())) {
              String relationshipName = fieldToken.getRelationshipName();
              calcItems.set(index, serializeReplace(calcItem, relationshipName, calcItemWithUpdatedParentField.getSObject(relationshipName)));
            }
          }
        } else {
          // polymorphic parent fields that are returned from SOQL can get retrieved via .getSObject,
          // but can't be appended via .putSObject without reinitializing the parent object to its actual type
          // this is because they are returned with type "Name", and avoids the dreaded:
          // "System.SObjectException: Illegal assignment from Name to { the calcItem type }"
          SObject parentFieldObject = calcItemWithUpdatedParentField.getSObject(fieldToken.getRelationshipName());
          SObject replacementObject = parentFieldObject.Id.getSObjectType().newSObject();
          for (String populatedFieldName : parentFieldObject.getPopulatedFieldsAsMap().keySet()) {
            replacementObject.put(populatedFieldName, parentFieldObject.get(populatedFieldName));
          }
          calcItem.putSObject(fieldToken.getRelationshipName(), replacementObject);
        }
      }
    }
  }

  @SuppressWarnings('PMD.EmptyCatchBlock')
  private Boolean hasSoughtField(String fieldName, String whereClause, SObject item) {
    if (whereClause.containsIgnoreCase(fieldName)) {
      try {
        String possibleSoughtField = whereClause.substringBefore(fieldName);
        return item.getPopulatedFieldsAsMap().get(possibleSoughtField) != null;
      } catch (Exception ex) {
        // the field isn't populated, so we SHOULD re-query it
      }
    }
    return false;
  }

  private static SObject serializeReplace(SObject calcItem, String fieldName, Object value) {
    Map<String, Object> deserialized = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(calcItem));
    deserialized.put(fieldName, value);
    return (SObject) JSON.deserialize(JSON.serialize(deserialized), SObject.class);
  }
}
