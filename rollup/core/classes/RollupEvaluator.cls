public without sharing abstract class RollupEvaluator implements Rollup.Evaluator {
  private static final String RELATIONSHIP_FIELD_DELIMITER = '\\.';
  private static final String TRUE_VAL = 'true';
  private static final String FALSE_VAL = 'false';
  private static final Set<String> POLYMORPHIC_FIELDS = new Set<String>{ 'Owner', 'Type' };

  // totally not obvious ranking going on here - it's absolutely imperative that
  // the two-word conditions go first; otherwise replacing will fail on the whole string
  // due to casing issues (NOT like, NOT in). I could make those be part of the map, too,
  // but that seems even worse than the pseudo-ranking going on here
  private static final Map<String, String> CONDITION_MAP = new Map<String, String>{
    ' not in ' => ' != ',
    ' NOT IN ' => ' != ',
    ' not like ' => ' !like ',
    ' NOT LIKE ' => ' !like ',
    ' <> ' => ' != ',
    ' in ' => ' = ',
    ' IN ' => ' = ',
    ' LIKE ' => ' like ',
    ' INCLUDES ' => ' includes ',
    ' includes ' => ' includes ',
    ' EXCLUDES ' => ' !includes ',
    ' excludes ' => ' !includes '
  };

  public abstract Boolean matches(Object calcItem);

  public static Rollup.Evaluator getEvaluator(Rollup.Evaluator eval, Rollup__mdt metadata, Map<Id, SObject> oldCalcItems, SObjectType sObjectType) {
    Boolean isChangedFieldEval = String.isNotBlank(metadata.ChangedFieldsOnCalcItem__c);
    Boolean isWhereClauseEval = String.isNotBlank(metadata.CalcItemWhereClause__c);
    RollupEvaluator secondEval;
    if (isChangedFieldEval && isWhereClauseEval) {
      secondEval = new CombinedEvaluator(metadata, oldCalcItems, sObjectType);
    } else if (isChangedFieldEval) {
      secondEval = getChangedFieldEval(metadata, oldCalcItems);
    } else if (isWhereClauseEval) {
      secondEval = new WhereFieldEvaluator(metadata, sObjectType, oldCalcItems);
    }

    if (eval != null && secondEval != null) {
      return new CombinedEvaluator(eval, secondEval);
    } else if (eval == null && secondEval != null) {
      return secondEval;
    }

    return eval;
  }

  private static RollupEvaluator getChangedFieldEval(Rollup__mdt rollupMetadata, Map<Id, SObject> oldCalcItems) {
    List<String> changedFieldNames = rollupMetadata.ChangedFieldsOnCalcItem__c.split(',');
    if (String.isNotBlank(rollupMetadata.LookupFieldOnCalcItem__c) && oldCalcItems.isEmpty() == false) {
      // detect reparenting
      changedFieldNames.add(rollupMetadata.LookupFieldOnCalcItem__c);
    }
    return new SObjectChangedFieldEvaluator(changedFieldNames, oldCalcItems);
  }

  private class CombinedEvaluator extends RollupEvaluator {
    private final Rollup.Evaluator firstEval;
    private final Rollup.Evaluator secondEval;

    public CombinedEvaluator(Rollup__mdt rollupMetadata, Map<Id, SObject> oldCalcItems, SObjectType sObjectType) {
      this.firstEval = getChangedFieldEval(rollupMetadata, oldCalcItems);
      this.secondEval = new WhereFieldEvaluator(rollupMetadata, sObjectType, oldCalcItems);
    }
    public CombinedEvaluator(Rollup.Evaluator firstEval, Rollup.Evaluator secondEval) {
      this.firstEval = firstEval;
      this.secondEval = secondEval;
    }

    public override Boolean matches(Object calcItem) {
      return this.firstEval.matches(calcItem) && this.secondEval.matches(calcItem);
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
      SObject oldRecord = oldRecordsMap.containsKey(calcSObject.Id) ? oldRecordsMap.get(calcSObject.Id) : calcSObject;
      Boolean matches = this.changedFieldNames.isEmpty() && this.oldRecordsMap == null;
      for (String fieldName : this.changedFieldNames) {
        // need to trim because list can be comma-separated with leading/trailing spaces
        if (calcSObject?.get(fieldName.trim()) != oldRecord?.get(fieldName.trim())) {
          matches = true;
          break;
        }
      }
      return matches;
    }
  }

  public class WhereFieldEvaluator extends RollupEvaluator {
    private final String originalWhereClause;
    private final String whereClause;
    private final List<ConditionalGrouping> conditionalGroupings = new List<ConditionalGrouping>();
    private final Set<String> validRelationshipNames;
    private final List<String> splitWheres;
    private final Map<Id, SObject> oldRecords;

    public WhereFieldEvaluator(String whereClause, SObjectType calcItemSObjectType) {
      whereClause = whereClause == null ? '' : whereClause;
      this.originalWhereClause = whereClause;

      for (String conditionKey : CONDITION_MAP.keySet()) {
        whereClause = whereClause.replace(conditionKey, CONDITION_MAP.get(conditionKey));
      }
      this.whereClause = whereClause;
      this.splitWheres = this.createConditions(calcItemSObjectType);
      this.validRelationshipNames = this.getValidRelationshipNames(calcItemSObjectType);
    }

    public WhereFieldEvaluator(Rollup__mdt metadata, SObjectType calcItemSObjectType, Map<Id, SObject> oldRecords) {
      this(metadata.CalcItemWhereClause__c, calcItemSObjectType);
      this.oldRecords = oldRecords;
    }

    public List<String> getWhereClauses() {
      return new List<String>(this.splitWheres);
    }

    public List<String> getQueryFields() {
      Set<String> fieldNames = new Set<String>();
      for (ConditionalGrouping conditionalGrouping : this.conditionalGroupings) {
        for (WhereFieldCondition condition : conditionalGrouping.innerConditions) {
          Boolean hasRelationshipField = condition.fieldName.contains('.');
          if (
            hasRelationshipField &&
            fieldNames.contains(condition.fieldName) == false &&
            condition.fieldName.contains('__c.') == false &&
            this.validRelationshipNames.contains(condition.fieldName.substringBefore('.')) &&
            POLYMORPHIC_FIELDS.contains(condition.fieldName.substringBetween('.')) == false &&
            POLYMORPHIC_FIELDS.contains(condition.fieldName.substringAfter('.')) == false
          ) {
            fieldNames.add(condition.fieldName);
          } else if (hasRelationshipField == false) {
            fieldNames.add(condition.fieldName);
          }
        }
      }
      return new List<String>(fieldNames);
    }

    public override Boolean matches(Object calcItem) {
      Boolean matches = calcItem instanceof SObject;
      if (matches) {
        matches = this.innerMatches(calcItem);

        if (matches) {
          return matches;
        }

        SObject item = (SObject) calcItem;
        // if the where clause would exclude something, but we're in an update
        // and the old value wouldn't have been excluded, pass it on through
        SObject potentialOldItem = this.oldRecords?.isEmpty() == false && this.oldRecords.containsKey(item.Id) ? this.oldRecords.get(item.Id) : item;
        matches = this.innerMatches(potentialOldItem);
      }

      return matches;
    }

    private Boolean innerMatches(Object calcItem) {
      Boolean matches = calcItem instanceof SObject;
      if (matches) {
        for (ConditionalGrouping conditionalGrouping : this.conditionalGroupings) {
          Boolean hasInnerMatch = conditionalGrouping.equals(calcItem);
          if (hasInnerMatch && conditionalGrouping.isOrConditional()) {
            matches = true;
          } else if (conditionalGrouping.isOrConditional() == false) {
            matches = matches && hasInnerMatch;
          }
        }
      }
      return matches;
    }

    private Set<String> getValidRelationshipNames(SObjectType sObjectType) {
      Set<String> localRelationshipNames = new Set<String>();
      List<SObjectField> fields = sObjectType.getDescribe().fields.getMap().values();
      for (SObjectField field : fields) {
        String relationshipName = field.getDescribe().getRelationshipName();
        // filter out polymorphic relationship fields that can't be queried
        if (
          String.isNotBlank(relationshipName) &&
          (relationshipName != 'What' &&
          relationshipName != 'Who' &&
          (field.getDescribe().getReferenceTo().size() < 2 ||
          POLYMORPHIC_FIELDS.contains(relationshipName) == false))
        ) {
          localRelationshipNames.add(relationshipName);
        }
      }
      return localRelationshipNames;
    }

    private List<String> createConditions(SObjectType calcItemSObjectType) {
      List<String> localSplitWheres = this.getSoqlWhereClauses(this.whereClause, calcItemSObjectType);
      try {
        for (String splitWhereClause : localSplitWheres) {
          List<WhereFieldCondition> conditions = this.createConditionsFromString(splitWhereClause, calcItemSObjectType);
          if (this.isOrConditional(this.whereClause, splitWhereClause)) {
            this.conditionalGroupings.add(new OrConditionalGrouping(conditions));
          } else {
            this.conditionalGroupings.add(new AndConditionalGrouping(conditions));
          }
        }
      } catch (Exception ex) {
        this.logError(ex);
        throw new IllegalArgumentException('Where clause entered incorrectly: ' + whereClause);
      }
      return localSplitWheres;
    }

    private List<String> getSoqlWhereClauses(String whereClause, SObjectType calcItemSObjectType) {
      List<String> localSplitWheres = whereClause.split('( and | AND | OR | or )');
      this.reconstructImproperlySplitClauses(localSplitWheres);
      this.recurseForNestedConditionals(localSplitWheres, calcItemSObjectType);

      return localSplitWheres;
    }

    private void reconstructImproperlySplitClauses(List<String> splitWheres) {
      // shocker - strings can have the criteria keywords IN them. reconstitute the strings that have been incorrectly split
      for (Integer index = splitWheres.size() - 1; index >= 0; index--) {
        String splitWhereClause = splitWheres[index];
        // we have to assume that the only place where this could happen is at the back of the string
        if (splitWhereClause.endsWith('\'') && splitWhereClause.indexOf('\'') == splitWhereClause.length() - 1 && index > 0) {
          try {
            String nextString = splitWheres[index - 1];
            String foundCriteria = whereClause.substring(whereClause.indexOf(nextString) + nextString.length(), whereClause.indexOf(splitWhereClause)).trim();
            splitWheres[index - 1] = (nextString + ' ' + foundCriteria + ' ' + splitWhereClause);
            splitWheres.remove(index);
          } catch (Exception ex) {
            this.logError(ex);
          }
        }
      }
    }

    private void recurseForNestedConditionals(List<String> splitWheres, SObjectType calcItemSObjectType) {
      // this time we can't iterate through the list in reverse simply because there are
      // multiple instances where a parathenses is perfectly valid to have at the end of the where clause;
      // any IN-based condition, for example, would end with a paranthetical list of Ids/Strings
      // on the other hand, there's only one way there would be parantheses at the beginning of the statement -
      // if it was a nested conditional
      for (Integer index = 0; index < splitWheres.size(); index++) {
        String potentialNestedConditional = splitWheres[index].trim();
        Integer originalMatchIndex = index;
        Integer openParansRange = potentialNestedConditional.indexOf('(');
        if (openParansRange == 0) {
          // remove the parans now
          potentialNestedConditional = potentialNestedConditional.substring(1, potentialNestedConditional.length() - 1);
          // iterate through the rest of the list, stopping at the end of the parantheses
          for (Integer innerIndex = index + 1; innerIndex < splitWheres.size(); innerIndex++) {
            String innerMatch = splitWheres[innerIndex].trim();
            // remove the blanks afterwards!
            splitWheres[innerIndex] = '';
            if (innerMatch.endsWith(')')) {
              Integer startingPoint = this.whereClause.indexOf(potentialNestedConditional);
              Integer endingPoint = this.whereClause.indexOf(innerMatch) + (innerMatch.length() - 1);
              potentialNestedConditional = this.whereClause.substring(startingPoint, endingPoint);
              break;
            }
          }
          // we'll remove these blanks in a second
          splitWheres[originalMatchIndex] = '';

          List<WhereFieldCondition> conditions = new List<WhereFieldCondition>();
          Boolean isAnInnerOrCondition = false;
          List<String> innerWhereClauses = this.getSoqlWhereClauses(potentialNestedConditional, calcItemSObjectType);
          for (String innerWhere : innerWhereClauses) {
            isAnInnerOrCondition = isAnInnerOrCondition || this.isOrConditional(potentialNestedConditional, innerWhere);
            conditions.addAll(this.createConditionsFromString(innerWhere, calcItemSObjectType));
          }

          if (isAnInnerOrCondition) {
            this.conditionalGroupings.add(new OrConditionalGrouping(conditions));
          } else {
            this.conditionalGroupings.add(new AndConditionalGrouping(conditions));
          }
        }
      }
      for (Integer reverseIndex = splitWheres.size() - 1; reverseIndex >= 0; reverseIndex--) {
        String potentialWhereClause = splitWheres[reverseIndex];
        if (String.isBlank(potentialWhereClause)) {
          splitWheres.remove(reverseIndex);
        }
      }
    }

    private Boolean isOrConditional(String fullString, String conditionalStatement) {
      Boolean isOr = false;
      Boolean isFirstConditional = fullString.indexOf(conditionalStatement) == 0;
      if (isFirstConditional) {
        return isOr;
      }
      Integer whereWeAreInTheFullString = fullString.indexOf(conditionalStatement) + conditionalStatement.length();
      Integer clauseStartingIndex = whereWeAreInTheFullString - (conditionalStatement.length() + 5);
      if (clauseStartingIndex > 0) {
        isOr = fullString.substring(clauseStartingIndex, whereWeAreInTheFullString).containsIgnoreCase('or');
      } else {
        // do nothing, but with PMD happy
        isOr = false;
      }
      return isOr;
    }

    private List<WhereFieldCondition> createConditionsFromString(String whereClause, SObjectType calcItemSObjectType) {
      List<WhereFieldCondition> conditions = new List<WhereFieldCondition>();
      whereClause = whereClause.trim();
      String fieldName = whereClause.substring(0, whereClause.indexOf(' '));
      whereClause = whereClause.replace(fieldName, '').trim();
      String criteria = whereClause.substring(0, whereClause.indexOf(' ')).trim();
      String value = this.getValue(whereClause.substringAfter(criteria));

      if (value.startsWith('(') && value.endsWith(')')) {
        List<String> values = value.substring(1, value.length() - 1).split(',');
        conditions.add(new WhereFieldCondition(fieldName, criteria, values, calcItemSObjectType));
      } else {
        conditions.add(new WhereFieldCondition(fieldName, criteria, value, calcItemSObjectType));
      }
      return conditions;
    }

    private String getValue(String whereClausePiece) {
      if (this.originalWhereClause.contains(whereClausePiece) == false) {
        // whoops - we may have accidentally replaced a conditional keyword in the value
        // let's fix that
        for (String conditionKey : CONDITION_MAP.keySet()) {
          String conditionValue = CONDITION_MAP.get(conditionKey);
          String potentialReplacement = whereClausePiece.replace(conditionKey, conditionValue.trim());
          if (this.originalWhereClause.contains(potentialReplacement)) {
            whereClausePiece = potentialReplacement;
            break;
          } else if (this.originalWhereClause.containsIgnoreCase(whereClausePiece.replace(' = ', ' in '))) {
            whereClausePiece = whereClausePiece.replace(' = ', ' in ');
            break;
          } else if (this.originalWhereClause.containsIgnoreCase(whereClausePiece.replace(' != ', ' not in '))) {
            whereClausePiece = whereClausePiece.replace(' != ', ' not in ');
            break;
          }
        }
      }
      whereClausePiece = whereClausePiece.trim();

      // if it's just a singular value enclosed in quotes or a multi-select picklist, we can just take the inner string
      if (whereClausePiece.startsWith('\'') && whereClausePiece.endsWith('\'')) {
        return whereClausePiece.substring(1, whereClausePiece.length() - 1);
      } else if (whereClausePiece.startsWith('(') && whereClausePiece.endsWith(')') && whereClausePiece.contains(';')) {
        return whereClausePiece.substring(1, whereClausePiece.length() - 1).replaceAll('\'', '').trim();
      }

      // otherwise, clean the string up and replace any inner quotes before returning
      if (whereClausePiece.startsWith('(') && whereClausePiece.endsWith(')') && whereClausePiece.contains(',') == false) {
        whereClausePiece = whereClausePiece.substring(1, whereClausePiece.length() - 1);
      } else if (whereClausePiece.startsWith('(') && whereClausePiece.contains(',') == false) {
        whereClausePiece = whereClausePiece.substring(1, whereClausePiece.length());
      } else if (whereClausePiece.endsWith(')') && whereClausePiece.contains(',') == false) {
        whereClausePiece = whereClausePiece.substring(0, whereClausePiece.length() - 1);
      }
      return whereClausePiece.replaceAll('\'', '').trim();
    }

    private void logError(Exception ex) {
      System.debug(LoggingLevel.ERROR, 'RollupEvaluator: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
    }
  }

  private abstract class ConditionalGrouping {
    protected final List<WhereFieldCondition> innerConditions;
    public ConditionalGrouping(List<WhereFieldCondition> innerConditions) {
      this.innerConditions = innerConditions;
    }

    public Boolean equals(Object calcItem) {
      return this.conditionallyEquals(calcItem);
    }

    public virtual Boolean isOrConditional() {
      return false;
    }

    protected abstract Boolean conditionallyEquals(Object calcItem);
  }

  private class OrConditionalGrouping extends ConditionalGrouping {
    public OrConditionalGrouping(List<WhereFieldCondition> innerConditions) {
      super(innerConditions);
    }

    public override Boolean isOrConditional() {
      return true;
    }

    protected override Boolean conditionallyEquals(Object calcItem) {
      Boolean isEqual = false;
      for (WhereFieldCondition innerCondition : this.innerConditions) {
        isEqual = innerCondition.equals(calcItem);
        if (isEqual) {
          break;
        }
      }
      return isEqual;
    }
  }

  private class AndConditionalGrouping extends ConditionalGrouping {
    public AndConditionalGrouping(List<WhereFieldCondition> innerConditions) {
      super(innerConditions);
    }
    protected override Boolean conditionallyEquals(Object calcItem) {
      Boolean isEqual = true;
      for (WhereFieldCondition condition : this.innerConditions) {
        isEqual = condition.equals(calcItem);
        if (isEqual == false) {
          break;
        }
      }
      return isEqual;
    }
  }

  private class WhereFieldCondition {
    private final SObjectType sObjectType;
    private final String fieldName;
    private final String criteria;
    private final List<String> originalValues;
    private final List<String> values;
    private final Boolean hasValues;

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
        if (String.isNotBlank(val)) {
          if (this.hasValues == null) {
            this.hasValues = true;
          }

          // coerce Boolean values to their standard representation
          if (val.equalsIgnoreCase(TRUE_VAL)) {
            val = TRUE_VAL;
          } else if (val.equalsIgnoreCase(FALSE_VAL)) {
            val = FALSE_VAL;
          }
          this.values.add(val.trim().replace('%', ''));
        }
      }
    }

    public Boolean equals(Object o) {
      SObject item = (SObject) o;
      Boolean isEqual = true;

      String storedValue = String.valueOf(this.getFieldValue(item, this.fieldName, this.sObjectType));
      // special case for currency/multi-decimal situations where zero is being compared to
      // but the comparison value has no decimals
      if (storedValue?.replace('.', '')?.containsOnly('0') == true && this.values.contains('0')) {
        storedValue = '0';
      }
      switch on this.criteria {
        when '=' {
          isEqual = this.values.contains(storedValue) || this.hasValues == null && String.isBlank(storedValue);
        }
        when '!=' {
          isEqual = this.values.contains(storedValue) == false || (String.isBlank(storedValue) && this.hasValues);
        }
        when 'like', '!like' {
          // like/not like have to be handled separately because it's the storedValue
          // that gets tested against, not the other way around
          isEqual = false;
          if (storedValue == null) {
            // do nothing
          } else {
            for (String val : this.values) {
              isEqual = storedValue.contains(val);
              if (isEqual) {
                break;
              }
            }
            isEqual = this.criteria == 'like' ? isEqual : isEqual == false;
          }
        }
        // then there's this whole paradigm; it really shouldn't be possible to have multiple values for either
        // greater than / less than routes, but we test for it first just to be triple-sure
        when '>', '>=' {
          if (this.values.size() != 1) {
            throw new IllegalArgumentException('Comparison not valid with multiple arguments: ' + JSON.serialize(this.values));
          } else if (storedValue == null) {
            isEqual = false;
          } else {
            isEqual = this.criteria.endsWith('=') ? storedValue >= this.values[0] : storedValue > this.values[0];
          }
        }
        when '<', '<=' {
          if (this.values.size() != 1) {
            throw new IllegalArgumentException('Comparison not valid with multiple arguments: ' + JSON.serialize(this.values));
          } else if (storedValue == null) {
            isEqual = false;
          } else {
            isEqual = this.criteria.endsWith('=') ? storedValue <= this.values[0] : storedValue < this.values[0];
          }
        }
        when 'includes', '!includes' {
          isEqual = false;
          for (String value : this.values) {
            List<String> splitValues = value.split(';');
            for (String splitValue : splitValues) {
              isEqual = storedValue.contains(splitValue);
              if (isEqual == false) {
                break;
              }
            }
          }
          isEqual = this.criteria == 'includes' ? isEqual : isEqual == false;
        }
      }
      return isEqual;
    }

    private Object getFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      if (item == null) {
        return '';
      }

      // handle compound fields separately
      Boolean hasField = sObjectType.getDescribe().fields.getMap().containsKey(fieldPath);
      if (fieldPath.contains('.') && hasField == false) {
        return this.getRelationshipFieldValue(item, fieldPath, sObjectType);
      } else if (hasField && item.getPopulatedFieldsAsMap().containsKey(fieldPath) || hasField && item.get(fieldPath) == null) {
        return item.get(fieldPath);
      }
      return '';
    }

    private Object getRelationshipFieldValue(SObject item, String fieldPath, SObjectType sObjectType) {
      List<String> fieldNameParts = fieldPath.split(RELATIONSHIP_FIELD_DELIMITER);
      // here, we pop fields off the front of the list because for tertiary+ object relationships (eg Owner.Profile.Name)
      // we need to recurse till the value itself can be captured
      String relationshipName = fieldNameParts.remove(0).trim();
      String originalName = relationshipName;

      if (relationshipName.contains('__r')) {
        relationshipName = relationshipName.replace('__r', '__c');
      } else {
        relationshipName += 'Id';
      }

      SObjectField fieldToken = sObjectType.getDescribe().fields.getMap().get(relationshipName);
      SObjectType parentSObjectType;
      if (fieldToken.getDescribe().isNamePointing() && item.get(relationshipName) != null) {
        Id fieldValue = (Id) item.get(relationshipName);
        parentSObjectType = fieldValue.getSobjectType();
      } else {
        // there's only ever one item in the list for non-polymorphic fields
        parentSObjectType = fieldToken.getDescribe().getReferenceTo()[0];
      }

      SObject parentSObject = item.getSObject(originalName);
      // the polymorphic "Type" field won't show up in the map of valid fields for an object
      // but if the value's been queried for, it's valid to pass back
      if (fieldNameParts.size() == 1 && fieldNameParts[0] == 'Type' && parentSObject.getPopulatedFieldsAsMap().containsKey('Type')) {
        return parentSObject.get(fieldNameParts[0]);
      } else if (fieldNameParts.isEmpty() == false) {
        return this.getFieldValue(parentSObject, String.join(fieldNameParts, '.'), parentSObjectType);
      } else {
        return parentSObject.get(originalName);
      }
    }
  }
}
