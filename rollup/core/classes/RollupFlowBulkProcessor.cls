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
    global Boolean deferProcessing = true;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
    // Optional properties that can override the CMDT values
    @InvocableVariable(
      label='Calc Item Changed Fields'
      description='Provide a comma-separated list of field API Names to consider prior to using records in the rollup'
    )
    global String calcItemChangedFields;
    @InvocableVariable(label='Concat Delimiter' description='Defaults to comma')
    global String concatDelimiter;

    @InvocableVariable(
      label='Full Recalculation Default Number Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for number-based rollups'
    )
    global Decimal fullRecalculationDefaultNumberValue;
    @InvocableVariable(
      label='Full Recalculation Default String Value'
      description='If provided, used in place of the existing value on the rollup field for the lookup object for String-based rollups'
    )
    global String fullRecalculationDefaultStringValue;

    @InvocableVariable(label='Grandparent Relationship Field Path' description='Used for grand(or greater)parent rollups')
    global String grandparentRelationshipFieldPath;
    @InvocableVariable(
      label='Is Full Record Set'
      description='If provided, does not try to abort rollup calculation early if no records match, and instead resets the rollup field value'
    )
    global Boolean isFullRecordSet;
    @InvocableVariable(label='Is Rollup Started From Parent' description='If the calc records are the parent records, set this to true')
    global Boolean isRollupStartedFromParent = false;
    @InvocableVariable(label='Order By (First/Last)' description='First/Last order by field')
    global String orderByFirstLast;

    @InvocableVariable(
      label='Should rollup to ultimate hierarchy parent'
      description='Used in conjunction with Ultimate Parent Field to drive hierarchical parent rollups'
    )
    global Boolean rollupToUltimateParent = false;
    @InvocableVariable(label='SOQL Where Clause To Exclude Calc Items' description='If provided, excludes records based on a valid SOQL where clause')
    global String calcItemWhereClause;
    @InvocableVariable(label='Ultimate Parent Field' description='The lookup field in hierarchy rollups')
    global String ultimateParentLookup;
  }

  @InvocableMethod(category='Rollups' label='Perform Rollup__mdt-based rollup')
  global static List<Rollup.FlowOutput> addRollup(List<FlowInput> flowInputs) {
    List<Rollup.FlowOutput> outputs = new List<Rollup.FlowOutput>();

    for (FlowInput flowInput : flowInputs) {
      Rollup.FlowOutput output = new Rollup.FlowOutput();
      if (flowInput.recordsToRollup?.isEmpty() != false) {
        output.message = 'No records';
      } else {
        List<Rollup__mdt> rollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);

        // for some reason, lists passed from Flow to Apex report their SObjectType as null. womp.
        String sObjectName = flowInput.recordsToRollup == null ? '' : flowInput.recordsToRollup[0].getSObjectType().getDescribe().getName();
        List<Rollup.FlowInput> rollupFlowInputs = new List<Rollup.FlowInput>();
        for (Rollup__mdt meta : rollupMetadata) {
          if (
            flowInput.recordsToRollup == null ||
            meta.CalcItem__c == sObjectName ||
            String.isNotBlank(flowInput.calcItemTypeWhenRollupStartedFromParent) && flowInput.calcItemTypeWhenRollupStartedFromParent == meta.CalcItem__c
          ) {
            Rollup.FlowInput input = new Rollup.FlowInput();
            // pertinent fields from CMDT (can be overridden by optional flow properties)
            input.calcItemChangedFields = flowInput.calcItemChangedFields != null ? flowInput.calcItemChangedFields : meta.ChangedFieldsOnCalcItem__c;
            input.calcItemWhereClause = flowInput.calcItemWhereClause != null ? flowInput.calcItemWhereClause : meta.CalcItemWhereClause__c;
            input.concatDelimiter = flowInput.concatDelimiter != null ? flowInput.concatDelimiter : meta.ConcatDelimiter__c;
            input.fullRecalculationDefaultNumberValue = flowInput.fullRecalculationDefaultNumberValue != null
              ? flowInput.fullRecalculationDefaultNumberValue
              : meta.FullRecalculationDefaultNumberValue__c;
            input.fullRecalculationDefaultStringValue = flowInput.fullRecalculationDefaultStringValue != null
              ? flowInput.fullRecalculationDefaultStringValue
              : meta.FullRecalculationDefaultStringValue__c;
            input.isFullRecordSet = flowInput.isFullRecordSet != null ? flowInput.isFullRecordSet : meta.IsFullRecordSet__c;
            input.orderByFirstLast = flowInput.orderByFirstLast != null ? flowInput.orderByFirstLast : meta.OrderByFirstLast__c;
            input.isRollupStartedFromParent = flowInput.isRollupStartedFromParent != null
              ? flowInput.isRollupStartedFromParent
              : meta.IsRollupStartedFromParent__c;
            input.grandparentRelationshipFieldPath = flowInput.grandparentRelationshipFieldPath != null
              ? flowInput.grandparentRelationshipFieldPath
              : meta.GrandparentRelationshipFieldPath__c;
            input.rollupToUltimateParent = flowInput.rollupToUltimateParent != null ? flowInput.rollupToUltimateParent : meta.RollupToUltimateParent__c;
            input.ultimateParentLookup = flowInput.ultimateParentLookup != null ? flowInput.ultimateParentLookup : meta.UltimateParentLookup__c;
            // metadata values that don't get overridden
            input.lookupFieldOnCalcItem = meta.LookupFieldOnCalcItem__c;
            input.lookupFieldOnOpObject = meta.LookupFieldOnLookupObject__c;
            input.rollupFieldOnCalcItem = meta.RollupFieldOnCalcItem__c;
            input.rollupFieldOnOpObject = meta.RollupFieldOnLookupObject__c;
            input.rollupOperation = meta.RollupOperation__c;
            input.rollupSObjectName = meta.LookupObject__c;
            // everything else is supplied from the invocable
            input.rollupContext = flowInput.rollupContext;
            input.recordsToRollup = flowInput.recordsToRollup;
            input.oldRecordsToRollup = flowInput.oldRecordsToRollup;
            input.deferProcessing = flowInput.deferProcessing;
            input.calcItemTypeWhenRollupStartedFromParent = flowInput.calcItemTypeWhenRollupStartedFromParent;
            rollupFlowInputs.add(input);

            output.message = 'Rollup queued for context: ' + meta.RollupOperation__c + ' with metadata values: ' + JSON.serialize(input);
          }
        }

        List<Rollup.FlowOutput> innerOutputs = Rollup.performRollup(rollupFlowInputs);
        for (Rollup.FlowOutput innerOutput : innerOutputs) {
          if (innerOutput.isSuccess == false) {
            output.isSuccess = false;
            output.message = innerOutput.message;
          }
        }
      }
      outputs.add(output);
    }

    return outputs;
  }
}
