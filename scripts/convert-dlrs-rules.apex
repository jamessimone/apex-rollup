// This script converts all DLRS rules (stored in dlrs__LookupRollupSummary2__mdt) to Rollup__mdt records and deploys them to the current org

// Use the org defaults for all converted rules
static final RollupControl__mdt ROLLUP_CONTROL = [SELECT Id, DeveloperName FROM RollupControl__mdt WHERE DeveloperName = 'Org_Defaults'];

// Prepare the converted Rollup__mdt CMDT records for deployment
String customMetadataTypePrefix = Schema.Rollup__mdt.SObjectType.getDescribe().getName().replace('__mdt', '');
Metadata.DeployContainer deployment = new Metadata.DeployContainer();
for (dlrs__LookupRollupSummary2__mdt dlrsRule : dlrs__LookupRollupSummary2__mdt.getAll().values()) {
    if(!dlrsRule.dlrs__Active__c){
      continue;
      }
    List<String> invalidChildren = new List<String>{'Event','Task','User'};
    if(invalidchildren.contains(dlrsRule.dlrs__ChildObject__c)){
        continue;
    }
  Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
  customMetadata.fullName = customMetadataTypePrefix + '.' + dlrsRule.get('DeveloperName');
  customMetadata.label = (String) dlrsRule.get('MasterLabel');

  String operation;
  switch on dlrsRule.dlrs__AggregateOperation__c {
    when 'Concatenate' {
      operation = 'CONCAT';
    }
    when 'Concatenate Distinct' {
      operation = 'CONCAT_DISTINCT';
    }
    when 'Count Distinct' {
      operation = 'COUNT_DISTINCT';
    }
    when else {
      operation = dlrsRule.dlrs__AggregateOperation__c;
    }
  }

  // This code uses instances of Metadata.CustomMetadataValue for the deployment - not instances of Rollup__mdt
  // So, use a map & field tokens to store the expected values - Salesforce will store the data as Rollup__mdt records when deployed
  Map<String, Object> fieldValuesToCopy = new Map<String, Object>{
    Schema.Rollup__mdt.CalcItem__c.getDescribe().getName() => dlrsRule.dlrs__ChildObject__c,
    Schema.Rollup__mdt.CalcItemWhereClause__c.getDescribe().getName() => dlrsRule.dlrs__RelationshipCriteria__c,
    Schema.Rollup__mdt.ConcatDelimiter__c.getDescribe().getName() => operation.startsWith('CONCAT') ? dlrsRule.dlrs__ConcatenateDelimiter__c : null,
    Schema.Rollup__mdt.LookupFieldOnCalcItem__c.getDescribe().getName() => dlrsRule.dlrs__RelationshipField__c,
    Schema.Rollup__mdt.LookupFieldOnLookupObject__c.getDescribe().getName() => 'Id',
    Schema.Rollup__mdt.LookupObject__c.getDescribe().getName() => dlrsRule.dlrs__ParentObject__c,
    Schema.Rollup__mdt.OrderByFirstLast__c.getDescribe().getName() => dlrsRule.dlrs__FieldToOrderBy__c,
    Schema.Rollup__mdt.RollupControl__c.getDescribe().getName() => ROLLUP_CONTROL.DeveloperName,
    Schema.Rollup__mdt.RollupFieldOnCalcItem__c.getDescribe().getName() => dlrsRule.dlrs__FieldToAggregate__c,
    Schema.Rollup__mdt.RollupFieldOnLookupObject__c.getDescribe().getName() => dlrsRule.dlrs__AggregateResultField__c,
    Schema.Rollup__mdt.RollupOperation__c.getDescribe().getName() => operation.toUpperCase()

    // Additional DLRS fields that are not supported/used by Rollup
    // dlrs__Active__c
    // dlrs__AggregateAllRows__c
    // dlrs__CalculationMode__c
    // dlrs__CalculationSharingMode__c
    // dlrs__Description__c
    // dlrs__RelationshipCriteriaFields__c
    // dlrs__RowLimit__c
    // dlrs__TestCode__c
    // dlrs__TestCode2__c
    // dlrs__TestCodeParent__c
    // dlrs__TestCodeSeeAllData__c
  };

  // Create the instance of Metadata.CustomMetadataValue for the current DLRS rule
  for (String fieldName : fieldValuesToCopy.keySet()) {
    Metadata.CustomMetadataValue customField = new Metadata.CustomMetadataValue();
    customField.field = fieldName;
    customField.value = fieldValuesToCopy.get(fieldName);

    customMetadata.values.add(customField);
  }

  deployment.addMetadata(customMetadata);
}

// Deploy the converted Rollup__mdt CMDT records - these will be treated like an upsert based on DeveloperName
System.debug(LoggingLevel.INFO, 'Deployment metadata==' + JSON.serialize(deployment));
Id jobId = Metadata.Operations.enqueueDeployment(deployment, null);
System.debug(LoggingLevel.INFO, 'Deployment Job ID: ' + jobId);