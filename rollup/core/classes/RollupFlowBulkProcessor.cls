global without sharing class RollupFlowBulkProcessor {
  private RollupFlowBulkProcessor() {
    // only used for invocable
  }

  global class FlowInput {
    @InvocableVariable(label='Records to rollup')
    global List<SObject> recordsToRollup;
    @InvocableVariable(label='Prior records to rollup')
    global List<SObject> oldRecordsToRollup = new List<SObject>();
    @InvocableVariable(label='Rollup Context' required=true)
    global String rollupContext;
    // Shared between this and Rollup.FlowInput
    @InvocableVariable(label='Defer processing?')
    global Boolean deferProcessing;
    @InvocableVariable(label='Child Object Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
    // Optional properties that can override the CMDT values
    @InvocableVariable(
      label='Child Object Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;

    @InvocableVariable(
      label='Full Recalculation Default Number Value'
      description='If provided, used in place of the existing value on the rollup field for the parent object for number-based rollups'
    )
    global Decimal fullRecalculationDefaultNumberValue;
    @InvocableVariable(
      label='Full Recalculation Default String Value'
      description='If provided, used in place of the existing value on the rollup field for the parent object for String-based rollups'
    )
    global String fullRecalculationDefaultStringValue;

    @InvocableVariable(label='Grandparent Relationship Field Path' description='Used for grand(or greater)parent rollups')
    global String grandparentRelationshipFieldPath;
    @InvocableVariable(label='One To Many Grandparent Fields (Comma separated list)')
    global String oneToManyGrandparentFields;
    @InvocableVariable(
      label='Is Full Record Set'
      description='If provided, does not try to abort rollup calculation early if no records match, and instead resets the rollup field value'
    )
    global Boolean isFullRecordSet;
    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent;
    @InvocableVariable(label='Order By (First/Last)')
    global String orderByFirstLast;
    @InvocableVariable(label='Limit Amount')
    global Decimal limitAmount;

    @InvocableVariable(
      label='Parent Record Id for Empty Children Collections'
      description='Runs rollup calculations even if no matching children when passed. Must also fill out Child Object Type When Rollup Started From Parent property'
    )
    global Id parentRecordIdForEmptyChildrenCollections;
    @InvocableVariable(
      label='Should rollup to ultimate hierarchy parent'
      description='Used in conjunction with Ultimate Parent Field to drive hierarchical parent rollups'
    )
    global Boolean rollupToUltimateParent;
    @InvocableVariable(label='Sharing Mode' description='Defaults to System, set to User to run with sharing')
    global String sharingMode;
    @InvocableVariable(label='Should run sync?' description='Runs rollup calculations synchronously when set to true')
    global Boolean shouldRunSync;
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;
    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;
  }

  @InvocableMethod(category='Rollups' label='Perform Rollup__mdt-based rollup')
  global static List<Rollup.FlowOutput> addRollup(List<FlowInput> flowInputs) {
    List<Rollup.FlowOutput> outputs = new List<Rollup.FlowOutput>();
    List<Rollup.FlowInput> validInputs = new List<Rollup.FlowInput>();
    for (FlowInput flowInput : flowInputs) {
      Rollup.FlowOutput output = new Rollup.FlowOutput();
      if (flowInput.recordsToRollup?.isEmpty() != false && flowInput.parentRecordIdForEmptyChildrenCollections == null) {
        output.message = 'No records';
        outputs.add(output);
      } else {
        List<Rollup__mdt> rollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
        // for some reason, lists passed from Flow to Apex report their SObjectType as null. womp.
        Schema.SObjectType sObjectType = flowInput.recordsToRollup?.get(0).getSObjectType();
        String childName = sObjectType?.toString();
        for (Rollup__mdt meta : rollupMetadata) {
          if (
            meta.IsRollupStartedFromParent__c ||
            sObjectType != null && String.isNotBlank(meta.GrandparentRelationshipFieldPath__c) && Rollup.getPartOfGrandparentChain(meta, sObjectType) != null
          ) {
            flowInput.calcItemTypeWhenRollupStartedFromParent = flowInput.calcItemTypeWhenRollupStartedFromParent ?? meta.CalcItem__c;
          }
          Boolean isMatchingParentSide = flowInput.calcItemTypeWhenRollupStartedFromParent == meta.CalcItem__c;
          if ((flowInput.recordsToRollup?.isEmpty() != false && isMatchingParentSide) || meta.CalcItem__c == childName || isMatchingParentSide) {
            Rollup.FlowInput input = new Rollup.FlowInput();
            validInputs.add(input);
            // pertinent fields from CMDT (can be overridden by optional flow properties)
            input.calcItemChangedFields = flowInput.calcItemChangedFields ?? meta.ChangedFieldsOnCalcItem__c;
            input.calcItemTypeWhenRollupStartedFromParent = flowInput.calcItemTypeWhenRollupStartedFromParent;
            input.calcItemWhereClause = flowInput.calcItemWhereClause ?? meta.CalcItemWhereClause__c;
            input.concatDelimiter = flowInput.concatDelimiter ?? meta.ConcatDelimiter__c;
            input.fullRecalculationDefaultNumberValue = flowInput.fullRecalculationDefaultNumberValue ?? meta.FullRecalculationDefaultNumberValue__c;
            input.fullRecalculationDefaultStringValue = flowInput.fullRecalculationDefaultStringValue ?? meta.FullRecalculationDefaultStringValue__c;
            input.isFullRecordSet = flowInput.isFullRecordSet ?? meta.IsFullRecordSet__c;
            input.isRollupStartedFromParent = flowInput.isRollupStartedFromParent ?? meta.IsRollupStartedFromParent__c;
            input.grandparentRelationshipFieldPath = flowInput.grandparentRelationshipFieldPath ?? meta.GrandparentRelationshipFieldPath__c;
            input.oneToManyGrandparentFields = flowInput.oneToManyGrandparentFields ?? meta.OneToManyGrandparentFields__c;
            input.rollupToUltimateParent = flowInput.rollupToUltimateParent ?? meta.RollupToUltimateParent__c;
            input.parentRecordIdForEmptyChildrenCollections = flowInput.parentRecordIdForEmptyChildrenCollections;
            input.ultimateParentLookup = flowInput.ultimateParentLookup ?? meta.UltimateParentLookup__c;
            input.limitAmount = flowInput.limitAmount ?? meta.LimitAmount__c;
            input.sharingMode = flowInput.sharingMode ?? meta.SharingMode__c;
            // fixup order by children records
            input.orderByFirstLast = flowInput.orderByFirstLast ?? '';
            if (input.orderByFirstLast == '') {
              input.orderByFirstLast = getConcatenatedOrderBys(new List<RollupOrderBy__mdt>(meta.RollupOrderBys__r));
            }
            // metadata values that don't get overridden
            input.currencyFieldMapping = meta.CurrencyFieldMapping__c;
            input.groupByFields = meta.GroupByFields__c;
            input.groupByRowEndDelimiter = meta.GroupByRowEndDelimiter__c;
            input.groupByRowStartDelimiter = meta.GroupByRowStartDelimiter__c;
            input.isDistinct = meta.IsDistinct__c;
            input.isTableFormatted = meta.IsTableFormatted__c;
            input.lookupFieldOnCalcItem = meta.LookupFieldOnCalcItem__c;
            input.lookupFieldOnOpObject = meta.LookupFieldOnLookupObject__c;
            input.rollupFieldOnCalcItem = meta.RollupFieldOnCalcItem__c;
            input.rollupFieldOnOpObject = meta.RollupFieldOnLookupObject__c;
            input.rollupOperation = meta.RollupOperation__c;
            input.rollupSObjectName = meta.LookupObject__c;
            input.rollupControlId = meta.RollupControl__c;
            input.rollupGrouping = meta.RollupGrouping__r;
            // everything else is supplied from the invocable
            input.deferProcessing = flowInput.deferProcessing ?? true;
            input.oldRecordsToRollup = flowInput.oldRecordsToRollup;
            input.recordsToRollup = flowInput.recordsToRollup;
            input.rollupContext = flowInput.rollupContext;
            input.shouldRunSync = flowInput.shouldRunSync ?? false;
            input.developerName = meta.DeveloperName;
          }
        }
      }
    }

    outputs.addAll(Rollup.performRollup(validInputs));
    while (outputs.size() > flowInputs.size()) {
      outputs.remove(0);
    }
    return outputs;
  }

  private static String getConcatenatedOrderBys(List<RollupOrderBy__mdt> orderBys) {
    orderBys.sort(new RollupRepository.OrderBySorter());
    List<String> joinedOrderBys = new List<String>();
    for (RollupOrderBy__mdt orderBy : orderBys) {
      String soloOrderBy = '';
      soloOrderBy += orderBy.FieldName__c;
      if (orderBy.NullSortOrder__c != null) {
        soloOrderBy += ' ' + orderBy.NullSortOrder__c;
      }
      if (orderBy.SortOrder__c != null) {
        soloOrderBy += ' ' + orderBy.SortOrder__c;
      }
      joinedOrderBys.add(soloOrderBy);
    }
    return String.join(joinedOrderBys, ',');
  }
}
