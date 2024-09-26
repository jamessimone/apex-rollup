@SuppressWarnings('PMD.NcssTypeCount')
public without sharing abstract class RollupEvaluator implements Rollup.Evaluator, RollupLogger.ToStringObject {
  private static final String RELATIONSHIP_FIELD_DELIMITER = '\\.';
  private static final String TRUE_VAL = 'true';
  private static final String FALSE_VAL = 'false';
  private static final Set<String> POLYMORPHIC_FIELDS = new Set<String>{ 'Owner', 'Type' };
  private static final AlwaysTrueEvaluator ALWAYS_TRUE_SINGLETON = new AlwaysTrueEvaluator();
  @TestVisible
  private static String stubRequestId;

  private static final Map<String, WhereFieldEvaluator> CACHED_WHERE_EVALS = new Map<String, WhereFieldEvaluator>();
  private static Map<String, Boolean> CACHED_WHERE_DECISIONS = new Map<String, Boolean>();

  private static Map<String, RecursiveTracker> OPERATION_TO_RECURSION_TRACKER {
    get {
      OPERATION_TO_RECURSION_TRACKER = OPERATION_TO_RECURSION_TRACKER ?? new Map<String, RecursiveTracker>();
      return OPERATION_TO_RECURSION_TRACKER;
    }
    private set;
  }

  public abstract Boolean matches(Object calcItem);

  public abstract override String toString();

  public static WhereFieldEvaluator getWhereEval(String calcItemWhereClause, SObjectType calcItemType) {
    String key = calcItemWhereClause + calcItemType;
    WhereFieldEvaluator eval = CACHED_WHERE_EVALS.get(key);
    if (eval == null) {
      eval = new WhereFieldEvaluator(calcItemWhereClause, calcItemType);
      CACHED_WHERE_EVALS.put(key, eval);
    }
    return eval;
  }

  public static Rollup.Evaluator getEvaluator(Rollup.Evaluator eval, Rollup__mdt metadata, Map<Id, SObject> oldCalcItems, SObjectType sObjectType) {
    List<Rollup.Evaluator> evals = eval == null ? new List<Rollup.Evaluator>() : new List<Rollup.Evaluator>{ eval };

    if (String.isNotBlank(metadata.CalcItemWhereClause__c)) {
      evals.add(getWhereEval(metadata.CalcItemWhereClause__c, sObjectType));
    }
    if (String.isNotBlank(metadata.ChangedFieldsOnCalcItem__c)) {
      evals.add(getChangedFieldEval(metadata, oldCalcItems));
    }
    if (metadata.RollupOperation__c?.contains('UPDATE') == true) {
      evals.add(new RecursiveUpdateEvaluator(metadata));
    }
    if (evals.isEmpty()) {
      evals.add(ALWAYS_TRUE_SINGLETON);
    }

    return getCombinedEvals(evals);
  }

  public static void clearCache() {
    CACHED_WHERE_DECISIONS = new Map<String, Boolean>();
    OPERATION_TO_RECURSION_TRACKER = null;
  }

  private static Rollup.Evaluator getCombinedEvals(List<Rollup.Evaluator> evals) {
    Rollup.Evaluator eval = evals.remove(0);
    if (evals.isEmpty()) {
      return eval;
    } else {
      return new CombinedEvaluator(eval, getCombinedEvals(evals));
    }
  }

  private static RollupEvaluator getChangedFieldEval(Rollup__mdt rollupMetadata, Map<Id, SObject> oldCalcItems) {
    List<String> changedFieldNames = rollupMetadata.ChangedFieldsOnCalcItem__c.split(',');
    if (String.isNotBlank(rollupMetadata.LookupFieldOnCalcItem__c) && oldCalcItems.isEmpty() == false) {
      // detect reparenting
      changedFieldNames.add(rollupMetadata.LookupFieldOnCalcItem__c);
    }
    return new SObjectChangedFieldEvaluator(changedFieldNames, oldCalcItems);
  }

  @TestVisible
  private class AlwaysTrueEvaluator extends RollupEvaluator {
    public override Boolean matches(Object calcItem) {
      return true;
    }

    public override String toString() {
      return AlwaysTrueEvaluator.class.getName();
    }
  }

  private class CombinedEvaluator extends RollupEvaluator {
    private final Rollup.Evaluator firstEval;
    private final Rollup.Evaluator secondEval;

    public CombinedEvaluator(Rollup.Evaluator firstEval, Rollup.Evaluator secondEval) {
      this.firstEval = firstEval;
      this.secondEval = secondEval;
    }

    public override Boolean matches(Object calcItem) {
      return this.firstEval.matches(calcItem) && this.secondEval.matches(calcItem);
    }

    public override String toString() {
      return CombinedEvaluator.class.getName() + '\nFirst eval: ' + this.firstEval.toString() + '\nSecond eval: ' + this.secondEval.toString();
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
        if (calcSObject.getPopulatedFieldsAsMap().containsKey(fieldName)) {
          if (calcSObject == oldRecord || calcSObject?.get(fieldName.trim()) != oldRecord?.get(fieldName.trim())) {
            matches = true;
            break;
          }
        }
      }
      addLog(this, matches, calcItem, System.LoggingLevel.FINEST);
      return matches;
    }

    public override String toString() {
      return SObjectChangedFieldEvaluator.class.getName() + '\nChanged fields: ' + changedFieldNames;
    }
  }

  private abstract class WhereCondition implements RollupLogger.ToStringObject {
    public virtual Boolean isOrConditional() {
      return false;
    }
    public abstract Boolean matches(Object calcItem);
    public abstract override String toString();
  }

  private class NegatedCondition extends WhereCondition {
    private final WhereCondition innerCondition;

    public NegatedCondition(WhereCondition innerCondition) {
      this.innerCondition = innerCondition;
    }

    public override Boolean matches(Object item) {
      return !this.innerCondition.matches(item);
    }

    public override String toString() {
      return NegatedCondition.class.getName() + '\nNegated condition: ' + this.innerCondition;
    }
  }

  private virtual class ConditionalGrouping extends WhereCondition {
    protected final List<WhereCondition> innerConditions;
    public ConditionalGrouping(List<WhereCondition> innerConditions) {
      this.innerConditions = new List<WhereCondition>(innerConditions);
    }

    public virtual override Boolean matches(Object calcItem) {
      Boolean isEqual = true;
      for (WhereCondition innerCondition : this.innerConditions) {
        Boolean innerEquals = innerCondition.matches(calcItem);
        isEqual = isEqual && innerEquals;
        if (innerCondition.isOrConditional()) {
          isEqual = isEqual || innerEquals;
          if (isEqual) {
            break;
          }
        } else if (isEqual == false) {
          break;
        }
      }
      return isEqual;
    }

    public override String toString() {
      return ConditionalGrouping.class.getName() + '\nIs Or Conditional: ' + this.isOrConditional() + '\nInner conditions: ' + this.innerConditions;
    }
  }

  private class OrConditionalGrouping extends ConditionalGrouping {
    public OrConditionalGrouping(List<WhereCondition> innerConditions) {
      super(innerConditions);
    }

    public override Boolean isOrConditional() {
      return true;
    }

    public override Boolean matches(Object calcItem) {
      Boolean isEqual = this.innerConditions.isEmpty();
      for (Integer index = 0; index < this.innerConditions.size(); index++) {
        if (index == 0) {
          isEqual = true;
        }
        WhereCondition innerCondition = this.innerConditions[index];
        if (innerCondition.isOrConditional() == false) {
          isEqual = isEqual && innerCondition.matches(calcItem);
        } else {
          isEqual = innerCondition.matches(calcItem);
          if (isEqual) {
            break;
          }
        }
      }
      return isEqual;
    }
  }

  public class WhereFieldEvaluator extends RollupEvaluator {
    private final SObjectType calcItemType;
    private final String whereClause;
    private final List<WhereCondition> whereConditions = new List<WhereCondition>();
    private final Set<String> validRelationshipNames;
    private final Set<String> splitWheres = new Set<String>();
    private final Set<String> queryFields = new Set<String>();

    private final Map<String, Schema.SObjectField> fieldNameToField {
      get {
        this.fieldNameToField = this.fieldNameToField ?? this.calcItemType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).fields.getMap();
        return this.fieldNameToField;
      }
      set;
    }

    public WhereFieldEvaluator(String whereClause, SObjectType calcItemSObjectType) {
      whereClause = whereClause?.replaceAll('(\n|\r|\t)', ' ') ?? '';
      this.whereClause = whereClause;
      this.calcItemType = calcItemSObjectType;
      this.validRelationshipNames = this.getValidRelationshipNames(calcItemSObjectType);
      this.createConditions(calcItemSObjectType, whereClause);
      RollupLogger.Instance.log('where clause for eval: ' + this.whereClause, System.LoggingLevel.FINER);
      RollupLogger.Instance.log('conditionals', this.whereConditions, System.LoggingLevel.FINER);
    }

    public override String toString() {
      return WhereFieldEvaluator.class.getName() + '\nWhere clause: ' + this.whereClause;
    }

    public List<String> getWhereClauses() {
      return new List<String>(this.splitWheres);
    }

    public List<String> getQueryFields() {
      return new List<String>(this.queryFields);
    }

    public override Boolean matches(Object calcItem) {
      Boolean matches = calcItem instanceof SObject;
      if (matches) {
        for (Integer index = 0; index < this.whereConditions.size(); index++) {
          WhereCondition condition = this.whereConditions[index];
          Boolean hasInnerMatch = condition.matches(calcItem);
          if (condition.isOrConditional()) {
            matches = index == 0 ? hasInnerMatch : hasInnerMatch || matches;
          } else {
            matches = matches && hasInnerMatch;
          }
        }
      }
      return matches;
    }

    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    private Set<String> getValidRelationshipNames(SObjectType sObjectType) {
      Set<String> localRelationshipNames = new Set<String>();
      List<SObjectField> fields = sObjectType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).fields.getMap().values();
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
          localRelationshipNames.add(relationshipName.toLowerCase());
        }
      }
      return localRelationshipNames;
    }

    private void createConditions(Schema.SObjectType calcItemSObjectType, String localWhereClause) {
      try {
        this.whereConditions.addAll(this.recursivelyCreateConditions(localWhereClause));
      } catch (Exception ex) {
        RollupLogger.Instance.log('an error occurred in RollupEvaluator:', ex, System.LoggingLevel.ERROR);
        RollupLogger.Instance.save();
        throw new IllegalArgumentException(
          'Where clause entered incorrectly: ' + whereClause + '\nException: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
        );
      }
    }

    @SuppressWarnings('PMD.AvoidDeeplyNestedIfStmts')
    private List<WhereCondition> recursivelyCreateConditions(String localWhereClause) {
      if (localWhereClause.startsWith('(') && localWhereClause.endsWith(')')) {
        localWhereClause = localWhereClause.substring(1, localWhereClause.length() - 1);
      }
      List<WhereCondition> conditionals = new List<WhereCondition>();
      // double pass through: once to remove blanks and any trailing conditionals
      // then once straight through, stopping only at inner conditionals
      List<String> words = localWhereClause.split(' ');
      for (Integer reverseIndex = words.size() - 1; reverseIndex >= 0; reverseIndex--) {
        String word = words[reverseIndex].deleteWhitespace().toLowerCase();
        if (word == '') {
          words.remove(reverseIndex);
        } else if (reverseIndex == words.size() - 1 && (word == 'or' || word == 'and')) {
          words.remove(reverseIndex);
        }
      }
      for (Integer index = 0; index < words.size(); index++) {
        Boolean isOrConditional = index == 0;
        String word = words[index].trim();
        if (word == ')') {
          word = words[++index];
        }
        if (word.equalsIgnoreCase('or')) {
          isOrConditional = true;
          word = words[++index];
        } else if (word.equalsIgnoreCase('and')) {
          isOrConditional = false;
          word = words[++index];
        }

        Boolean isNegated = false;
        if (word.startsWithIgnoreCase('(not(')) {
          word = word.removeStartIgnoreCase('(not');
          isNegated = true;
        } else if (word.equalsIgnoreCase('not')) {
          // check for presence of nested conditional, otherwise let fall through to next NOT check
          word = words[++index];
          isNegated = true;
        }

        if (word.startsWith('(')) {
          Integer openParansCounter = 1;
          while (openParansCounter > 0) {
            String nextToken = words[++index];
            if (nextToken.contains('(')) {
              openParansCounter++;
            }
            if (nextToken.contains(')')) {
              openParansCounter--;
              if (openParansCounter == 0) {
                nextToken = nextToken.removeEnd(')');
              }
            }
            word += ' ' + nextToken;
            if (index == words.size() - 1) {
              word = word.removeStart('(');
              break;
            }
          }
          List<WhereCondition> innerConditions = this.recursivelyCreateConditions(word);
          WhereCondition condition = isOrConditional ? new OrConditionalGrouping(innerConditions) : new ConditionalGrouping(innerConditions);
          if (isNegated) {
            condition = new NegatedCondition(condition);
          }
          conditionals.add(condition);
          continue;
        }

        if (word.equalsIgnoreCase('not')) {
          isNegated = true;
          word = words[++index];
        } else if (word.equalsIgnoreCase('or')) {
          isOrConditional = true;
          word = words[++index];
        } else if (word.equalsIgnoreCase('and')) {
          isOrConditional = false;
          word = words[++index];
        }

        String fieldName = word;
        String criteria = words[++index];
        if (criteria.equalsIgnoreCase('not') && words.size() - 1 > index) {
          String potentialNextToken = words[index + 1];
          if (potentialNextToken.equalsIgnoreCase('in')) {
            criteria += ' ' + potentialNextToken;
            index++;
          }
        }
        String value = words[++index];
        if (criteria.endsWithIgnoreCase('in')) {
          while (value.endsWith(')') == false) {
            String nextWord = words[++index];
            value += ' ' + nextWord;
            if (index + 1 == words.size()) {
              break;
            }
          }
          if (value.startsWith('(') && value.endsWith(')') == false) {
            value += ')';
          }
        } else if (value.startsWith('\'') && value.endsWith('\'') == false) {
          String tempVal = value;
          while (tempVal.endsWith(')')) {
            tempVal = tempVal.removeEnd(')');
          }
          while (tempVal.endsWith('\'') == false) {
            tempVal += ' ' + words[++index];
          }
          value = tempVal;
        } else {
          value = value.removeEnd(')');
        }

        WhereFieldCondition simpleCondition = this.createConditionsFromString(fieldName, criteria, value);
        this.splitWheres.add(fieldName + ' ' + criteria + ' ' + value);
        if (index < words.size() - 1) {
          Integer forwardCounter = index;
          String nextToken = words[++forwardCounter];
          isOrConditional = nextToken.equalsIgnoreCase('or');
        }
        simpleCondition.isOrConditional = isOrConditional;
        conditionals.add(isNegated ? new NegatedCondition(simpleCondition) : (WhereCondition) simpleCondition);
      }

      return conditionals;
    }

    private WhereFieldCondition createConditionsFromString(String fieldName, String criteria, String value) {
      WhereFieldCondition condition;
      value = this.getValue(value);
      if (value.startsWith('(') && value.endsWith(')')) {
        List<String> values = value.substring(1, value.length() - 1).split(',');
        condition = new WhereFieldCondition(fieldName, criteria, values, this.calcItemType);
      } else {
        condition = new WhereFieldCondition(fieldName, criteria, value, this.calcItemType);
      }

      Boolean hasRelationshipField = condition.fieldName.contains('.');
      if (
        hasRelationshipField &&
        condition.fieldName.contains('__c.') == false &&
        this.validRelationshipNames.contains(condition.fieldName.substringBefore('.').toLowerCase()) &&
        this.isValidRelationshipField(condition.fieldName)
      ) {
        this.queryFields.add(condition.fieldName);
      } else if (RollupDateLiteral.isSoqlDateFunction(condition.fieldName)) {
        this.queryFields.add(getDateFunctionField(condition.fieldName));
      } else if (hasRelationshipField == false) {
        this.queryFields.add(condition.fieldName);
      }
      return condition;
    }

    private String getValue(String whereClausePiece) {
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

    private Boolean isValidRelationshipField(String fieldName) {
      if (fieldName.contains('.') == false) {
        return false;
      }
      List<String> fieldParts = fieldName.split(RELATIONSHIP_FIELD_DELIMITER);
      if (fieldName.contains('Owner.') == false) {
        Map<String, Schema.SObjectField> localFieldNameToField = this.fieldNameToField;
        while (fieldParts.size() > 1) {
          String relationshipPart = fieldParts.remove(0);
          relationshipPart = relationshipPart.endsWith('__r') ? relationshipPart.replace('__r', '__c') : relationshipPart + 'Id';
          Schema.SObjectField relationField = localFieldNameToField.get(relationshipPart);
          Schema.DescribeFieldResult fieldDescribe = relationField.getDescribe();
          if (fieldDescribe.isFilterable() == false) {
            return false;
          } else {
            localFieldNameToField = fieldDescribe.getReferenceTo()[0].getDescribe(Schema.SObjectDescribeOptions.DEFERRED).fields.getMap();
          }
        }
        String endPart = fieldParts[0];
        return localFieldNameToField.containsKey(endPart);
      }
      Schema.SObjectType ownerType = this.calcItemType;
      Integer ownerIndex = fieldParts.indexOf('Owner');
      if (ownerIndex > 0) {
        Integer index = 0;
        while (index < ownerIndex) {
          String relationshipName = fieldParts[index];
          String fieldRef = getRelationshipNameFromField(relationshipName);
          SObjectField fieldToken = this.fieldNameToField.get(fieldRef);
          if (fieldToken.getDescribe().isNamePointing()) {
            return false;
          }
          ownerType = fieldToken.getDescribe().getReferenceTo()[0];
          index++;
        }
      }
      return (ownerType == this.calcItemType ? this.fieldNameToField : ownerType.getDescribe().fields.getMap()).get('OwnerId').getDescribe().isNamePointing() ==
        false;
    }
  }

  private class WhereFieldCondition extends WhereCondition implements RollupLogger.ToStringObject {
    private final SObjectType sObjectType;
    private final String fieldName;
    private final Map<String, Schema.SObjectField> fieldNameToTokens;
    private final String criteria;
    private final List<String> originalValues;
    private final List<String> values;
    private final Boolean hasValues;

    private Boolean isOrConditional = false;

    public WhereFieldCondition(String fieldName, String criteria, String value, SObjectType sObjectType) {
      this(fieldName, criteria, new List<String>{ value }, sObjectType);
    }
    public WhereFieldCondition(String fieldName, String criteria, List<String> values, SObjectType sObjectType) {
      this.fieldName = fieldName;
      this.criteria = criteria;
      this.originalValues = values;
      this.sObjectType = sObjectType;
      this.fieldNameToTokens = this.sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
      this.values = new List<String>();

      for (String val : values) {
        if (String.isNotBlank(val)) {
          if (this.hasValues == null) {
            this.hasValues = true;
          }
          val = val.trim();
          // coerce Boolean values to their standard representation
          if (val.equalsIgnoreCase(TRUE_VAL)) {
            val = TRUE_VAL;
          } else if (val.equalsIgnoreCase(FALSE_VAL)) {
            val = FALSE_VAL;
          } else if (val.equalsIgnoreCase('null')) {
            val = null;
          }
          this.values.add(val);
        }
      }
      if (this.hasValues == null) {
        this.hasValues = false;
      }
    }

    public override String toString() {
      return WhereFieldCondition.class.getName() +
        ':{Field: ' +
        this.fieldName +
        ', Criteria: ' +
        this.criteria +
        ', Values: ' +
        this.originalValues +
        ', Is Or Conditional: ' +
        this.isOrConditional +
        '}';
    }

    public override Boolean isOrConditional() {
      return this.isOrConditional;
    }

    @SuppressWarnings('PMD.EmptyCatchBlock')
    public override Boolean matches(Object o) {
      String decisionKey = this.fieldName + this.criteria + this.originalValues + o.hashCode();
      Boolean possiblePriorMatchOutcome = CACHED_WHERE_DECISIONS.get(decisionKey);
      if (possiblePriorMatchOutcome != null) {
        return possiblePriorMatchOutcome;
      }

      SObject item = (SObject) o;
      Boolean isEqual = true;
      Boolean hasOnlyOneValue = this.originalValues.size() == 1;
      Boolean isDateFunction = RollupDateLiteral.isSoqlDateFunction(this.fieldName);

      String fieldNameToUse = isDateFunction ? getDateFunctionField(this.fieldName) : this.fieldName;
      Object originalValue = this.getFieldValue(item, fieldNameToUse, this.fieldNameToTokens);
      String storedValue = originalValue == null ? (String) originalValue : String.valueOf(originalValue);

      if (hasOnlyOneValue && isDateFunction) {
        isEqual = RollupDateLiteral.getFunction(this.fieldName, this.originalValues[0]).matches(originalValue, this.criteria);
      } else if (hasOnlyOneValue && RollupDateLiteral.isDateLiteral(this.originalValues[0])) {
        isEqual = RollupDateLiteral.get(this.originalValues[0]).matches(originalValue, this.criteria);
      } else {
        if (originalValue instanceof Decimal) {
          for (Integer index = 0; index < this.values.size(); index++) {
            Object val = this.values[index];
            try {
              String stringVal = String.valueOf(val);
              Decimal decimalVal = Decimal.valueOf(stringVal);
              if (decimalVal == originalValue) {
                originalValue = decimalVal;
                storedValue = stringVal;
                break;
              }
            } catch (Exception ex) {
              // do nothing
            }
          }
        }

        switch on this.criteria.toLowerCase() {
          when '=', '!=', '<>', 'in', 'not in' {
            String criteria = this.criteria;
            if (criteria == 'in') {
              criteria = '=';
            } else if (criteria == 'not in') {
              criteria = '!=';
            }
            if (this.hasValues == false) {
              isEqual = String.isBlank(storedValue);
            } else {
              for (String value : this.values) {
                isEqual = value?.equalsIgnoreCase(storedValue) == true || value == null && storedValue == null;
                if (isEqual) {
                  break;
                }
              }
            }
            isEqual = criteria == '=' ? isEqual : !isEqual;
          }
          when 'like', 'not like' {
            isEqual = false;
            if (storedValue == null) {
              return false;
            }
            storedValue = storedValue.toLowerCase();
            String val = this.values[0].toLowerCase();

            if (val.contains('%')) {
              // % as a wildcard can be read as either:
              // "any character till the next match sequence, or no character till the next match"
              isEqual = storedValue.replaceAll(val.replace('%', '(.+|)'), '') == '';
            } else {
              isEqual = storedValue.equals(val);
            }

            isEqual = criteria == 'like' ? isEqual : isEqual == false;
          }
          when '>', '>=', '<', '<=' {
            if (storedValue == null) {
              isEqual = false;
            } else {
              isEqual = this.getGreaterOrLessThan(this.values[0], originalValue);
            }
          }
          when 'includes', '!includes' {
            isEqual = false;
            for (String value : this.values) {
              List<String> splitValues = value.split(';');
              for (String splitValue : splitValues) {
                isEqual = storedValue.containsIgnoreCase(splitValue);
                if (isEqual == false) {
                  break;
                }
              }
            }
            isEqual = criteria == 'includes' ? isEqual : isEqual == false;
          }
        }
      }
      CACHED_WHERE_DECISIONS.put(decisionKey, isEqual);
      return isEqual;
    }

    private Object getFieldValue(SObject item, String fieldPath, Map<String, Schema.SObjectField> localFieldNameToTokens) {
      if (item == null) {
        return null;
      }

      Boolean hasField = localFieldNameToTokens.containsKey(fieldPath);
      // handle compound fields separately
      if (fieldPath.contains('.') && hasField == false) {
        return this.getRelationshipFieldValue(item, fieldPath, localFieldNameToTokens);
      } else if (hasField) {
        return item.get(fieldPath);
      }
      return null;
    }

    private Object getRelationshipFieldValue(SObject item, String fieldPath, Map<String, Schema.SObjectField> localFieldNameToTokens) {
      List<String> fieldNameParts = fieldPath.split(RELATIONSHIP_FIELD_DELIMITER);
      // here, we pop fields off the front of the list because for tertiary+ object relationships (eg Owner.Profile.Name)
      // we need to recurse till the value itself can be captured
      String relationshipName = fieldNameParts.remove(0).trim();
      String originalName = relationshipName;
      relationshipName = getRelationshipNameFromField(relationshipName);

      SObjectField fieldToken = localFieldNameToTokens.get(relationshipName);
      if (fieldToken == null) {
        // it could be a rollup started from the parent using a parent-level where clause
        try {
          return item.get(fieldPath.substringAfter('.'));
        } catch (System.SObjectException ex) {
          // if the field value is invalid, it's almost certainly a parent-level where clause targeting
          // a different parent - pass the records through for now
          return this.getValueOrDefault();
        }
      }
      SObjectType parentSObjectType;
      if (fieldToken.getDescribe().isNamePointing() && item.get(relationshipName) != null) {
        Id fieldValue = (Id) item.get(relationshipName);
        parentSObjectType = fieldValue.getSObjectType();
      } else {
        // there's only ever one item in the list for non-polymorphic fields
        parentSObjectType = fieldToken.getDescribe().getReferenceTo()[0];
      }

      SObject parentSObject = item.getSObject(originalName);
      // the polymorphic "Type" field won't show up in the map of valid fields for an object
      // but if the value's been queried for, it's valid to pass back
      if (fieldNameParts.size() == 1 && fieldNameParts[0] == 'Type') {
        return parentSObject?.getPopulatedFieldsAsMap().containsKey('Type') == true ? parentSObject.get(fieldNameParts[0]) : this.getValueOrDefault();
      } else if (fieldNameParts.isEmpty() == false) {
        return this.getFieldValue(
          parentSObject,
          String.join(fieldNameParts, '.'),
          parentSObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap()
        );
      } else {
        return parentSObject?.get(originalName);
      }
    }

    private Object getValueOrDefault() {
      return this.originalValues.isEmpty() == false ? this.originalValues[0] : null;
    }

    private Boolean getGreaterOrLessThan(Object comparisonValue, Object storedValue) {
      // storedValue is still strongly typed, so it just needs to be cast to the appropriate type
      Boolean isLessThan = this.criteria.startsWith('<');
      Boolean isEqualTo = this.criteria.endsWith('=');
      String comparisonText = String.valueOf(comparisonValue);

      // the order of the instanceof checks matters here; both Date and Time classes are subclasses of Datetime
      // and thus have to be checked first
      if (storedValue instanceof Date) {
        Date comparisonDate = Date.valueOf(comparisonText);
        Date storedDate = (Date) storedValue;

        if (isLessThan) {
          return isEqualTo ? storedDate <= comparisonDate : storedDate < comparisonDate;
        } else {
          return isEqualTo ? storedDate >= comparisonDate : storedDate > comparisonDate;
        }
      } else if (storedValue instanceof Time) {
        List<String> timeDigits = comparisonText.substringBefore('Z').split(':');
        List<String> secondDigits = timeDigits[2].split(RELATIONSHIP_FIELD_DELIMITER);
        Time comparisonTime = Time.newInstance(
          Integer.valueOf(timeDigits[0]),
          Integer.valueOf(timeDigits[1]),
          Integer.valueOf(secondDigits[0]),
          Integer.valueOf(secondDigits[1])
        );
        Time storedTime = (Time) storedValue;

        if (isLessThan) {
          return isEqualTo ? storedTime <= comparisonTime : storedTime < comparisonTime;
        } else {
          return isEqualTo ? storedTime >= comparisonTime : storedTime > comparisonTime;
        }
      } else if (storedValue instanceof Datetime) {
        if (comparisonText.contains('T')) {
          comparisonText = comparisonText.replace('T', ' ');
        }
        Datetime comparisonDatetime = Datetime.valueOf(comparisonText);
        Datetime storedDatetime = RollupFieldInitializer.Current.getApexCompliantDatetime((Datetime) storedValue);

        if (isLessThan) {
          return isEqualTo ? storedDatetime <= comparisonDatetime : storedDatetime < comparisonDatetime;
        } else {
          return isEqualTo ? storedDatetime >= comparisonDatetime : storedDatetime > comparisonDatetime;
        }
      } else if (storedValue instanceof Decimal) {
        // covers Double / Integer / Decimal / Long
        Decimal comparisonDecimal = Decimal.valueOf(comparisonText);
        Decimal storedDecimal = (Decimal) storedValue;

        if (isLessThan) {
          return isEqualTo ? storedDecimal <= comparisonDecimal : storedDecimal < comparisonDecimal;
        } else {
          return isEqualTo ? storedDecimal >= comparisonDecimal : storedDecimal > comparisonDecimal;
        }
      } else {
        // covers pretty much anything else
        String storedText = String.valueOf(storedValue);
        if (isLessThan) {
          return isEqualTo ? storedText <= comparisonText : storedText < comparisonText;
        } else {
          return isEqualTo ? storedText >= comparisonText : storedText > comparisonText;
        }
      }
    }
  }

  private class RecursiveTracker {
    public String requestId = getCurrentTransactionId();
    public Integer stackCount = 0;
    public Set<RollupRecursionItem> recursionItems = new Set<RollupRecursionItem>();
  }

  private class RecursiveUpdateEvaluator extends RollupEvaluator {
    private final Rollup__mdt metadata;
    private final String metadataKey;

    public RecursiveUpdateEvaluator(Rollup__mdt metadata) {
      this.metadata = metadata;
      this.metadataKey = String.valueOf(metadata);

      RecursiveTracker tracker = OPERATION_TO_RECURSION_TRACKER.get(this.metadataKey);
      if (tracker == null) {
        tracker = new RecursiveTracker();
        OPERATION_TO_RECURSION_TRACKER.put(this.metadataKey, new RecursiveTracker());
      }
      String currentRequestId = getCurrentTransactionId();
      if (tracker.requestId != currentRequestId) {
        tracker.requestId = currentRequestId;
        tracker.stackCount++;
      }
    }

    public override String toString() {
      return RecursiveUpdateEvaluator.class.getName() + ' tracking ' + OPERATION_TO_RECURSION_TRACKER.size() + ' potentially recursive operations';
    }

    // at some point, it's possible that this will be revisited, but for now recursion detection
    // for grandparent / ultimate parent rollups is not supported
    public override Boolean matches(Object item) {
      Boolean matches = true;
      if (
        item instanceof SObject &&
        String.isBlank(this.metadata.GrandparentRelationshipFieldPath__c) &&
        this.metadata.RollupToUltimateParent__c == false &&
        OPERATION_TO_RECURSION_TRACKER.containsKey(this.metadataKey)
      ) {
        SObject calcItem = (SObject) item;
        RecursiveTracker recursionTracker = OPERATION_TO_RECURSION_TRACKER.get(this.metadataKey);
        RollupRecursionItem rollupItem = new RollupRecursionItem(calcItem, this.metadata, recursionTracker.stackCount);
        Boolean hasSeenItemPreviously = recursionTracker?.recursionItems.contains(rollupItem) == true;

        if (hasSeenItemPreviously == false) {
          recursionTracker.recursionItems.add(rollupItem);
        } else if (recursionTracker != null && recursionTracker.stackCount > 0 && hasSeenItemPreviously) {
          matches = false;
        }
      }

      return matches;
    }
  }

  private static String getRelationshipNameFromField(String relationshipField) {
    return relationshipField.endsWith('__r') ? relationshipField.substringBeforeLast('__r') + '__c' : relationshipField + 'Id';
  }

  private static void addLog(RollupLogger.ToStringObject clazz, Boolean matches, Object item, System.LoggingLevel logLevel) {
    if (matches == false) {
      RollupLogger.Instance.log('Removing non-match for: ' + item, clazz, logLevel);
    }
  }

  private static String getCurrentTransactionId() {
    return stubRequestId ?? Request.getCurrent().getRequestId();
  }

  private static String getDateFunctionField(String field) {
    return field.substringBetween('(', ')');
  }
}
