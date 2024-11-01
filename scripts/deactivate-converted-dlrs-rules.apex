// This script deactivates all DLRS rules (stored in dlrs__LookupRollupSummary2__mdt) that have been converted to Rollup__mdt records
// This assumes that the records in dlrs__LookupRollupSummary2__mdt and Rollup__mdt have the same DeveloperName

Set<String> rollupRecordDeveloperNames = Rollup__mdt.getAll().keySet();
String dlrsCustomMetadataTypePrefix = Schema.dlrs__LookupRollupSummary2__mdt.SObjectType.toString().replace('__mdt', '');
Metadata.DeployContainer deployment = new Metadata.DeployContainer();

for (dlrs__LookupRollupSummary2__mdt dlrsRule : dlrs__LookupRollupSummary2__mdt.getAll().values()) {
  // Skip any DLRS rules that are already inactive, or that have not been migrated to Rollup__mdt
  if (dlrsRule.dlrs__Active__c == false || rollupRecordDeveloperNames.contains(dlrsRule.DeveloperName) == false) {
    continue;
  }

  Metadata.CustomMetadataValue dlrsIsActiveField = new Metadata.CustomMetadataValue();
  dlrsIsActiveField.field = Schema.dlrs__LookupRollupSummary2__mdt.dlrs__Active__c.toString();
  dlrsIsActiveField.value = false;

  Metadata.CustomMetadata dlrsCustomMetadataRecord = new Metadata.CustomMetadata();
  dlrsCustomMetadataRecord.fullName = dlrsCustomMetadataTypePrefix + '.' + dlrsRule.DeveloperName;
  dlrsCustomMetadataRecord.label = dlrsRule.MasterLabel;
  dlrsCustomMetadataRecord.values.add(dlrsIsActiveField);

  deployment.addMetadata(dlrsCustomMetadataRecord);
}

if (deployment.getMetadata().isEmpty() == false) {
  // Deploy the dlrs__LookupRollupSummary2__mdt CMDT records to deactivate them - these will be treated like an upsert based on DeveloperName
  System.debug(LoggingLevel.INFO, 'Deployment metadata==' + JSON.serialize(deployment));
  Id jobId = Metadata.Operations.enqueueDeployment(deployment, null);
  System.debug(LoggingLevel.INFO, 'Deployment Job ID: ' + jobId);
}
