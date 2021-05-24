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
    @InvocableVariable(label='Defer processing?')
    global Boolean deferProcessing = true;
    @InvocableVariable(label='Calc Item Type When Rollup Started From Parent')
    global String calcItemTypeWhenRollupStartedFromParent;
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
            // pertinent fields from CMDT
            input.calcItemChangedFields = meta.ChangedFieldsOnCalcItem__c;
            input.calcItemWhereClause = meta.CalcItemWhereClause__c;
            input.fullRecalculationDefaultNumberValue = meta.FullRecalculationDefaultNumberValue__c;
            input.fullRecalculationDefaultStringValue = meta.FullRecalculationDefaultStringValue__c;
            input.isFullRecordSet = meta.IsFullRecordSet__c;
            input.lookupFieldOnCalcItem = meta.LookupFieldOnCalcItem__c;
            input.lookupFieldOnOpObject = meta.LookupFieldOnLookupObject__c;
            input.orderByFirstLast = meta.OrderByFirstLast__c;
            input.rollupFieldOnCalcItem = meta.RollupFieldOnCalcItem__c;
            input.rollupFieldOnOpObject = meta.RollupFieldOnLookupObject__c;
            input.rollupOperation = meta.RollupOperation__c;
            input.rollupSObjectName = meta.LookupObject__c;
            input.isRollupStartedFromParent = meta.IsRollupStartedFromParent__c;
            input.grandparentRelationshipFieldPath = meta.GrandparentRelationshipFieldPath__c;
            input.concatDelimiter = meta.ConcatDelimiter__c;
            input.rollupToUltimateParent = meta.RollupToUltimateParent__c;
            input.ultimateParentLookup = meta.UltimateParentLookup__c;
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
