global without sharing class RollupFlowBulkProcessor {
  @testVisible
  private static Rollup__mdt testMetadata;

  global class FlowInput {
    @InvocableVariable(label='Records to rollup' required=true)
    global List<SObject> recordsToRollup;
    @InvocableVariable(label='Rollup Context' required=true)
    global String rollupContext;
  }

  @InvocableMethod(category='Rollups' label='Add flow rollup inputs to later be batched')
  global static List<Rollup.FlowOutput> addRollup(List<FlowInput> flowInputs) {
    List<Rollup.FlowOutput> outputs = new List<Rollup.FlowOutput>();

    for (FlowInput flowInput : flowInputs) {
      Rollup.FlowOutput output = new Rollup.FlowOutput();
      if (flowInput.recordsToRollup == null || flowInput.recordsToRollup.isEmpty()) {
        output.message = 'No records';
      } else {
        List<Rollup__mdt> rollupMetadata = Rollup__mdt.getAll().deepClone().values();
        if (testMetadata != null) {
          rollupMetadata.add(testMetadata);
        }
        // for some reason, lists passed from Flow to Apex report their SObjectType as null. womp.
        String sObjectName = flowInput.recordsToRollup[0].getSObjectType().getDescribe().getName();
        List<Rollup.FlowInput> rollupFlowInputs = new List<Rollup.FlowInput>();
        for (Rollup__mdt meta : rollupMetadata) {
          if (meta.CalcItem__c == sObjectName) {
            Rollup.FlowInput input = new Rollup.FlowInput();
            input.rollupContext = flowInput.rollupContext;
            input.recordsToRollup = flowInput.recordsToRollup;
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
            input.deferProcessing = true;
            rollupFlowInputs.add(input);

            output.message = 'Rollup queued for context: ' + meta.RollupOperation__c + ' with metadata values: ' + JSON.serialize(input);
          }
        }

        Rollup.performRollup(rollupFlowInputs);
      }
      outputs.add(output);
    }

    return outputs;
  }
}
