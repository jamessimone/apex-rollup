public without sharing class RollupEvaluators {
  public class SObjectChangedFieldEvaluator implements Rollup.Evaluator {
    private final List<String> changedFieldNames;
    private final Map<Id, SObject> oldRecordsMap;
    public SObjectChangedFieldEvaluator(List<String> changedFieldNames, Map<Id, SObject> oldRecordsMap) {
      this.changedFieldNames = changedFieldNames;
      this.oldRecordsMap = oldRecordsMap;
    }

    public Boolean matches(Object calcItem) {
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
    private final List<String> values;
    private final Set<String> positiveEqualities = new Set<String>{ '=', 'like' };

    public WhereFieldCondition(String fieldName, String criteria, String value, SObjectType sObjectType) {
      this(fieldName, criteria, new List<String>{ value }, sObjectType);
    }
    public WhereFieldCondition(String fieldName, String criteria, List<String> values, SObjectType sObjectType) {
      this.fieldName = fieldName;
      this.criteria = criteria;
      this.values = new List<String>();
      this.sObjectType = sObjectType;

      for(String val : values) {
        this.values.add(val.trim().replace('%', ''));
      }
    }

    public Boolean equals(Object o) {
      Boolean isEqual = o instanceof SObject;
      if (isEqual == false) {
        return isEqual;
      }

      SObject item = (SObject) o;
      String storedValue = this.getFieldValue(item, this.fieldName, this.sObjectType).toString();
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
          for(String val : this.values) {
            containsCriteria = containsCriteria || storedValue.contains(val);
          }
          isEqual = this.criteria == 'like' ? containsCriteria : containsCriteria == false;
        }
      }
      return isEqual;
    }

    private Object getFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      DescribesObjectResult sObjectDescribe = sObjectType.getDescribe();
      Map<String, SObjectField> fieldMap = sObjectDescribe.fields.getMap();
      if (fieldPath.contains('.') && fieldMap.containsKey(fieldPath) == false) {
        List<String> fieldNameParts = fieldPath.split('\\.');
        String relationshipName = fieldNameParts.remove(0);
        String originalName = relationshipName;
        if (relationshipName.contains('__r')) {
          relationshipName = relationshipName.replace('__r', '__c');
        } else {
          relationshipName += 'Id';
        }
        SObjectField fieldToken = fieldMap.get(relationshipName);
        SObjectType parentSObjectType;
        if (fieldToken.getDescribe().isNamePointing()) {
          Id fieldValue = (Id) item.get(relationshipName);
          parentSObjectType = fieldValue.getSobjectType();
        } else {
          parentSObjectType = fieldToken.getDescribe().getReferenceTo()[0];
        }
        SObject parentSObject = item.getSObject(originalName);
        if (fieldNameParts.isEmpty() == false) {
          return this.getFieldValue(parentSObject, String.join(fieldNameParts, '.'), parentSObjectType);
        } else {
          return parentSObject.get(originalName);
        }
      }
      return item == null ? '' : item.get(fieldPath);
    }

    public override String toString() {
      String baseString = this.fieldName + ' ' + this.criteria + ' ';
      baseString += this.values.size() == 1 ? '' : '(';
      for (String val : this.values) {
        String escapedVal = '\'' + val + '\'';
        // TODO: re-add percentage signs for like/!like
        baseString += this.values.indexOf(val) > 0 ? ', ' + escapedVal : escapedVal;
      }
      baseString += this.values.size() == 1 ? '' : ')';
      return baseString;
    }
  }

  public class WhereFieldEvaluator implements Rollup.Evaluator {
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
      List<String> splitWhere = whereClause.split('(and|AND|OR|or)');

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
        System.debug(LoggingLevel.ERROR, ex.getMessage() + '\n' + ex.getStackTraceString());
        throw new IllegalArgumentException('Where clause entered with incorrect number of args: ' + whereClause);
      }
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

    public Boolean matches(Object calcItem) {
      // if there's only one condition, you only need to prove that condition
      // otherwise, if there's more than one condition, you either have to prove them all or
      // have an OR statement be true
      Boolean matches = this.conditions.isEmpty() || this.conditions.size() == 1;
      System.debug(this.whereClause);
      for (WhereFieldCondition condition : this.conditions) {
        // == works here because .equals() is overridden in the WhereFieldCondition class
        Boolean isOrCondition = this.whereClause.containsIgnoreCase('or ' + condition.toString());
        System.debug(condition.toString());
        System.debug(isOrCondition);
        if (isOrCondition) {
          matches = matches || condition == calcItem;
        } else {
          matches = matches && condition == calcItem;
        }
      }
      return matches;
    }
  }
}
