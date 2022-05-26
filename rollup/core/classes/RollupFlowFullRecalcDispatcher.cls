global without sharing class RollupFlowFullRecalcDispatcher {
  private RollupFlowFullRecalcDispatcher() {
    // Only used for invocable
  }

  global class FlowInput {
    @InvocableVariable(label='Comma-separated list of API Names of the Rollup__mdt Records you want to run' required=true)
    global String rollupDeveloperNames;
    @InvocableVariable(label='Optional list of rollup records to constrain operation to')
    global List<SObject> rollupRecords;
  }

  @InvocableMethod(category='Rollups' label='Full Recalc CMDT-driven Invocable')
  public static void performFullRecalcRollups(List<FlowInput> inputs) {
    List<Rollup__mdt> localRollupMetadata = Rollup.getMetadataFromCache(Rollup__mdt.SObjectType);
    Set<String> rollupDeveloperNames = new Set<String>();
    Map<String, Set<String>> devNameToRollupRecords = new Map<String, Set<String>>();
    for (FlowInput input : inputs) {
      if (String.isBlank(input.rollupDeveloperNames)) {
        throw new IllegalArgumentException('Comma-separated list of Rollup__mdt DeveloperName(s) was not provided');
      }
      List<String> splitListOfApiNames = input.rollupDeveloperNames.split(',');
      Set<String> recordIds = new Set<String>();
      if (input.rollupRecords != null) {
        for (SObject record : input.rollupRecords) {
          recordIds.add('\'' + record.Id + '\'');
        }
      }
      for (String apiName : splitListOfApiNames) {
        String trimmedDevName = apiName.trim();
        rollupDeveloperNames.add(trimmedDevName);
        if (recordIds.isEmpty() == false) {
          devNameToRollupRecords.put(trimmedDevName, recordIds);
        }
      }
    }
    List<Rollup__mdt> selectedRollupMetadata = new List<Rollup__mdt>();
    for (Rollup__mdt rollupMeta : localRollupMetadata) {
      if (rollupDeveloperNames.contains(rollupMeta.DeveloperName)) {
        selectedRollupMetadata.add(rollupMeta);
      }
      if (devNameToRollupRecords.containsKey(rollupMeta.DeveloperName)) {
        List<String> uniqueRecordIds = new List<String>(devNameToRollupRecords.get(rollupMeta.DeveloperName));
        String additionalWhereClause = 'Id IN (' + String.join(uniqueRecordIds, ',') + ')';
        rollupMeta.CalcItemWhereClause__c = String.isNotBlank(rollupMeta.CalcItemWhereClause__c)
          ? rollupMeta.CalcItemWhereClause__c + (' AND ' + additionalWhereClause)
          : additionalWhereClause;
      }
    }
    if (selectedRollupMetadata.isEmpty() == false) {
      Rollup.performBulkFullRecalc(selectedRollupMetadata, Rollup.InvocationPoint.FROM_FULL_RECALC_FLOW.name());
    }
  }
}
