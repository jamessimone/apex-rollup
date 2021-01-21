public without sharing abstract class RollupEvaluator implements Rollup.Evaluator {
  public abstract Boolean matches(Object calcItem);

  public static RollupEvaluator getEvaluator(Rollup__mdt rollupMetadata, Map<Id, SObject> oldCalcItems, SObjectType sObjectType) {
    Boolean isChangedFieldEval = String.isNotBlank(rollupMetadata.ChangedFieldsOnCalcItem__c);
    Boolean isWhereClauseEval = String.isNotBlank(rollupMetadata.CalcItemWhereClause__c);
    if (isChangedFieldEval && isWhereClauseEval) {
      return new CombinedEvaluator(rollupMetadata, oldCalcItems, sObjectType);
    } else if (isChangedFieldEval) {
      return new SObjectChangedFieldEvaluator(rollupMetadata.ChangedFieldsOnCalcItem__c.split(','), oldCalcItems);
    } else if (isWhereClauseEval) {
      return new WhereFieldEvaluator(rollupMetadata.CalcItemWhereClause__c, sObjectType);
    }
    return null;
  }

  private class CombinedEvaluator extends RollupEvaluator {
    private final RollupEvaluator changedFiedEval;
    private final RollupEvaluator whereClauseEval;
    public CombinedEvaluator(Rollup__mdt rollupMetadata, Map<Id, SObject> oldCalcItems, SObjectType sObjectType) {
      this.changedFiedEval = new SObjectChangedFieldEvaluator(rollupMetadata.ChangedFieldsOnCalcItem__c.split(','), oldCalcItems);
      this.whereClauseEval = new WhereFieldEvaluator(rollupMetadata.CalcItemWhereClause__c, sObjectType);
    }

    public override Boolean matches(Object calcItem) {
      return this.changedFiedEval.matches(calcItem) && this.whereClauseEval.matches(calcItem);
    }
  }

  public class SObjectChangedFieldEvaluator extends RollupEvaluator {
    private final List<String> changedFieldNames;
    private final Map<Id, SObject> oldRecordsMap;
    public SObjectChangedFieldEvaluator(List<String> changedFieldNames, Map<Id, SObject> oldRecordsMap) {
      this.changedFieldNames = changedFieldNames;
      this.oldRecordsMap = oldRecordsMap;
    }

    public override Boolean matches(Object calcItem) {
      SObject calcSObject = (SObject) calcItem;
      SObject oldRecord = oldRecordsMap.get(calcSObject.Id);
      Boolean matches = this.changedFieldNames.isEmpty() || this.oldRecordsMap == null;
      for (String fieldName : this.changedFieldNames) {
        // need to trim because list can be comma-separated with leading/trailing spaces
        if (calcSObject.get(fieldName.trim()) != oldRecord.get(fieldName.trim())) {
          matches = true;
          break;
        }
      }
      return matches;
    }
  }

  private class WhereFieldCondition {
    private final SObjectType sObjectType;
    private final String fieldName;
    private final String criteria;
    private final String value;
    private final List<String> originalValues;
    private final List<String> values;
    private final Set<String> positiveEqualities = new Set<String>{ '=', 'like' };

    public WhereFieldCondition(String fieldName, String criteria, String value, SObjectType sObjectType) {
      this(fieldName, criteria, new List<String>{ value }, sObjectType);
    }
    public WhereFieldCondition(String fieldName, String criteria, List<String> values, SObjectType sObjectType) {
      this.fieldName = fieldName;
      this.criteria = criteria;
      this.originalValues = values;
      this.sObjectType = sObjectType;
      this.values = new List<String>();

      for (String val : values) {
        this.values.add(val?.trim()?.replace('%', ''));
      }
    }

    public Boolean equals(Object o) {
      Boolean isEqual = o instanceof SObject;
      if (isEqual == false) {
        return isEqual;
      }

      SObject item = (SObject) o;
      String storedValue = String.valueOf(this.getFieldValue(item, this.fieldName, this.sObjectType));
      switch on this.criteria {
        when '=' {
          isEqual = this.values.contains(storedValue);
        }
        when '!=' {
          isEqual = this.values.contains(storedValue) == false;
        }
        when 'like', '!like' {
          // like/not like have to be handled separately because it's the storedValue
          // that gets tested against, not the other way around
          Boolean containsCriteria = false;
          for (String val : this.values) {
            containsCriteria = containsCriteria || storedValue.contains(val);
          }
          isEqual = this.criteria == 'like' ? containsCriteria : containsCriteria == false;
        }
        when '>', '>=' {
          if (this.values.size() != 1) {
            throw new IllegalArgumentException('Comparison not valid with multiple arguments: ' + JSON.serialize(this.values));
          }

          return this.criteria.endsWith('=') ? storedValue >= this.values[0] : storedValue > this.values[0];
        }
        when '<', '<=' {
          if (this.values.size() != 1) {
            throw new IllegalArgumentException('Comparison not valid with multiple arguments: ' + JSON.serialize(this.values));
          }

          return this.criteria.endsWith('=') ? storedValue <= this.values[0] : storedValue < this.values[0];
        }
      }
      return isEqual;
    }

    public override String toString() {
      String baseString = this.fieldName + ' ' + this.criteria + ' ';
      baseString += this.originalValues.size() == 1 ? '' : '(';
      for (String val : this.originalValues) {
        String escapedVal = '\'' + val + '\'';
        baseString += this.originalValues.indexOf(val) > 0 ? ', ' + escapedVal : escapedVal;
      }
      baseString += this.originalValues.size() == 1 ? '' : ')';
      return baseString;
    }

    private Object getFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      // handle compound fields separately
      if (fieldPath.contains('.') && sObjectType.getDescribe().fields.getMap().containsKey(fieldPath) == false) {
        return this.getRelationshipFieldValue(item, fieldPath, sObjectType);
      }
      return item == null ? '' : item.get(fieldPath);
    }

    private Object getRelationshipFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      List<String> fieldNameParts = fieldPath.split('\\.');
      // here, we pop fields off the front of the list because for tertiary+ object relationships (eg Owner.Profile.Name)
      // we need to recurse till the value itself can be captured
      String relationshipName = fieldNameParts.remove(0);
      String originalName = relationshipName;
      if (relationshipName.contains('__r')) {
        relationshipName = relationshipName.replace('__r', '__c');
      } else {
        relationshipName += 'Id';
      }
      SObjectField fieldToken = sObjectType.getDescribe().fields.getMap().get(relationshipName);
      SObjectType parentSObjectType;
      if (fieldToken.getDescribe().isNamePointing()) {
        Id fieldValue = (Id) item.get(relationshipName);
        parentSObjectType = fieldValue.getSobjectType();
      } else {
        // there's only ever one item in the list for non-polymorphic fields
        parentSObjectType = fieldToken.getDescribe().getReferenceTo()[0];
      }
      SObject parentSObject = item.getSObject(originalName);
      if (fieldNameParts.isEmpty() == false) {
        return this.getFieldValue(parentSObject, String.join(fieldNameParts, '.'), parentSObjectType);
      } else {
        return parentSObject.get(originalName);
      }
    }
  }

  public class WhereFieldEvaluator extends RollupEvaluator {
    private final String whereClause;
    // totally not obvious ranking going on here - it's absolutely imperative that
    // the two-word conditions go first; otherwise replacing will fail on the whole string
    // due to casing issues (NOT like, NOT in). I could make those be part of the map, too,
    // but that seems even worse than the pseudo-ranking going on here
    private final Map<String, String> conditionMapping = new Map<String, String>{
      'not in' => '!=',
      'NOT IN' => '!=',
      'not like' => '!like',
      'NOT LIKE' => '!like',
      '<>' => '!=',
      'in' => '=',
      'IN' => '=',
      'LIKE' => 'like'
    };
    private final List<WhereFieldCondition> conditions = new List<WhereFieldCondition>();

    public WhereFieldEvaluator(String whereClause, SObjectType calcItemSObjectType) {
      if (whereClause == null) {
        whereClause = '';
      }
      for (String conditionKey : this.conditionMapping.keySet()) {
        whereClause = whereClause.replace(conditionKey, conditionMapping.get(conditionKey));
      }
      this.whereClause = whereClause;
      List<String> splitWhere = this.getSplitWhereClause();
      this.createConditions(splitWhere, calcItemSObjectType);
    }

    public List<String> getRelationshipFieldNames() {
      List<String> fieldNames = new List<String>();
      for (WhereFieldCondition condition : this.conditions) {
        if (fieldNames.contains(condition.fieldName) == false) {
          fieldNames.add(condition.fieldName);
          if (condition.fieldName.contains('.')) {
            List<String> relationshipNames = condition.fieldName.split('\\.');
            String priorVal = '';
            for (String relationshipName : relationshipNames) {
              if (String.isNotBlank(priorVal)) {
                priorVal += '.';
              }
              priorVal += relationshipName.trim();
            }
            if (fieldNames.contains(priorVal) == false) {
              fieldNames.add(priorVal);
            }
          }
        }
      }
      return fieldNames;
    }

    public override Boolean matches(Object calcItem) {
      // if there's only one condition, you only need to prove that condition
      // otherwise, if there's more than one condition, you either have to prove them all or
      // have an OR statement be true
      Boolean matches = this.conditions.isEmpty() || this.conditions.size() == 1;
      for (WhereFieldCondition condition : this.conditions) {
        // == works here because .equals() is overridden in the WhereFieldCondition class
        Boolean innerMatch = condition == calcItem;
        Boolean isOrCondition = this.whereClause.containsIgnoreCase('or ' + condition.toString());
        if (isOrCondition) {
          matches = innerMatch || matches;
        } else {
          matches = innerMatch && matches;
        }
      }
      return matches;
    }

    private List<String> getSplitWhereClause() {
      List<String> splitWhere = this.whereClause.split('( and | AND | OR | or )');
      // shocker - strings can have the criteria keywords IN them. reconstitute the strings that have been incorrectly split
      for (Integer index = splitWhere.size() - 1; index >= 0; index--) {
        String splitWhereClause = splitWhere[index];
        // we have to assume that the only place where this could happen is at the back of the string
        if (splitWhereClause.endsWith('\'') && splitWhereClause.indexOf('\'') == splitWhereClause.length() - 1 && index > 0) {
          try {
            String nextString = splitWhere[index - 1];
            String foundCriteria = this.whereClause.substring(
                this.whereClause.indexOf(nextString) + nextString.length(),
                this.whereClause.indexOf(splitWhereClause)
              )
              .trim();
            splitWhere[index - 1] = (nextString + ' ' + foundCriteria + ' ' + splitWhereClause);
            splitWhere[index] = '';
          } catch (Exception ex) {
            this.logError(ex);
          }
        }
      }
      return splitWhere;
    }

    private void createConditions(List<String> splitWhere, SObjectType calcItemSObjectType) {
      try {
        for (String splitWhereClause : splitWhere) {
          if (String.isBlank(splitWhereClause)) {
            continue;
          }
          splitWhereClause = splitWhereClause.trim();
          String fieldName = splitWhereClause.substring(0, splitWhereClause.indexOf(' '));
          splitWhereClause = splitWhereClause.replace(fieldName, '').trim();
          String criteria = splitWhereClause.substring(0, splitWhereClause.indexOf(' ')).trim();
          String value = splitWhereClause.replace(criteria, '').trim().replaceAll('\'', '').trim();
          if (value.startsWith('(') && value.endsWith(')')) {
            List<String> values = value.substring(1, value.length() - 1).split(',');
            this.conditions.add(new WhereFieldCondition(fieldName, criteria, values, calcItemSObjectType));
          } else {
            this.conditions.add(new WhereFieldCondition(fieldName, criteria, value, calcItemSObjectType));
          }
        }
      } catch (Exception ex) {
        this.logError(ex);
        throw new IllegalArgumentException('Where clause entered with incorrect number of args: ' + whereClause);
      }
    }

    private void logError(Exception ex) {
      System.debug(LoggingLevel.ERROR, 'RollupEvaluator: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
    }
  }
}
