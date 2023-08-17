// This script converts all DLRS rules (stored in dlrs__LookupRollupSummary2__mdt) to please__Rollup__mdt records and deploys them to the current org

// Use the org defaults for all converted rules
static final please__RollupControl__mdt ROLLUP_CONTROL = please__RollupControl__mdt.getInstance('Org_Defaults');

// Prepare the converted Rollup__mdt CMDT records for deployment
String customMetadataTypePrefix = Schema.please__Rollup__mdt.SObjectType.getDescribe().getName().replace('__mdt', '');
Metadata.DeployContainer deployment = new Metadata.DeployContainer();

// Field/Entity Definition particles in CMDT don't currently support these three objects
// so we'll print out the info necessary to set up invocables for them if there are any matching DLRS rules
// for those objects
Set<String> invalidChildren = new Set<String>{
  Event.SObjectType.getDescribe().getName(),
  Task.SObjectType.getDescribe().getName(),
  User.SObjectType.getDescribe().getName()
};
List<Map<String, String>> unmigrateableRules = new List<Map<String, String>>();
Boolean shouldDeploy = false;

for (dlrs__LookupRollupSummary2__mdt dlrsRule : dlrs__LookupRollupSummary2__mdt.getAll().values()) {
  if (dlrsRule.dlrs__Active__c == false) {
    // we won't migrate inactive rules
    continue;
  }

  Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
  customMetadata.fullName = customMetadataTypePrefix + '.' + dlrsRule.DeveloperName;
  customMetadata.label = dlrsRule.MasterLabel;

  String operation;
  switch on dlrsRule.dlrs__AggregateOperation__c {
    when 'Avg' {
      operation = 'AVERAGE';
    }
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

  if (invalidChildren.contains(dlrsRule.dlrs__ChildObject__c)) {
    // build up a list of unmigrateable rules to assist with the creation of the flow actions

    Map<String, String> unmigratableRule = new Map<String, String>();
    unmigratableRule.put('Action label', customMetadata.label);
    unmigratableRule.put(
      'Records to rollup',
      'Provide the collection of rollup records (if the rollup starts from parent records, set Is Rollup Started From Parent to {!$GlobalConstant.True})'
    );
    unmigratableRule.put(
      'Prior records to rollup',
      'A collection variable with {!$Record__Prior} in it, when using after update or after create and update flows'
    );
    unmigratableRule.put('Object for \"Prior records to rollup\" and \"Records to rollup\"', dlrsRule.dlrs__ChildObject__c);

    unmigratableRule.put('Child Object Calc Field', dlrsRule.dlrs__FieldToAggregate__c);
    unmigratableRule.put('Child Object Lookup Field', dlrsRule.dlrs__RelationshipField__c);
    unmigratableRule.put('Rollup Object API Name', dlrsRule.dlrs__ParentObject__c);
    unmigratableRule.put('Rollup Object Calc Field', dlrsRule.dlrs__AggregateResultField__c);
    unmigratableRule.put('Rollup Object Lookup Field', 'Id');
    unmigratableRule.put('Rollup Operation', operation.toUpperCase());
    unmigratableRule.put('Rollup Operation Context', 'INSERT / UPDATE / UPSERT / DELETE: see README for more info');
    if (operation.startsWith('CONCAT')) {
      unmigratableRule.put('Concat Delimiter', dlrsRule.dlrs__ConcatenateDelimiter__c);
    }
    if (dlrsRule.dlrs__FieldToOrderBy__c != null) {
      unmigratableRule.put('Order By (First/Last)', dlrsRule.dlrs__FieldToOrderBy__c);
    }
    if (dlrsRule.dlrs__RelationshipCriteria__c != null) {
      unmigratableRule.put('SOQL Where Clause To Exclude Calc Items', dlrsRule.dlrs__RelationshipCriteria__c);
    }
    unmigrateableRules.add(unmigratableRule);
  } else {
    // This code uses instances of Metadata.CustomMetadataValue for the deployment - not instances of Rollup__mdt
    // So, use a map & field tokens to store the expected values - Salesforce will store the data as Rollup__mdt records when deployed
    Map<String, Object> fieldValuesToCopy = new Map<String, Object>{
      please__Rollup__mdt.please__CalcItem__c.getDescribe().getName() => dlrsRule.dlrs__ChildObject__c,
      please__Rollup__mdt.please__CalcItemWhereClause__c.getDescribe().getName() => dlrsRule.dlrs__RelationshipCriteria__c,
      please__Rollup__mdt.please__ConcatDelimiter__c.getDescribe().getName() => operation.startsWith('CONCAT') ? dlrsRule.dlrs__ConcatenateDelimiter__c : null,
      please__Rollup__mdt.please__Description__c.getDescribe().getName() => dlrsRule.dlrs__Description__c,
      please__Rollup__mdt.please__LimitAmount__c.getDescribe().getName() => dlrsRule.dlrs__RowLimit__c,
      please__Rollup__mdt.please__LookupFieldOnCalcItem__c.getDescribe().getName() => dlrsRule.dlrs__RelationshipField__c,
      please__Rollup__mdt.please__LookupFieldOnLookupObject__c.getDescribe().getName() => 'Id',
      please__Rollup__mdt.please__LookupObject__c.getDescribe().getName() => dlrsRule.dlrs__ParentObject__c,
      please__Rollup__mdt.please__OrderByFirstLast__c.getDescribe().getName() => dlrsRule.dlrs__FieldToOrderBy__c,
      please__Rollup__mdt.please__RollupControl__c.getDescribe().getName() => ROLLUP_CONTROL.DeveloperName,
      please__Rollup__mdt.please__RollupFieldOnCalcItem__c.getDescribe().getName() => dlrsRule.dlrs__FieldToAggregate__c,
      please__Rollup__mdt.please__RollupFieldOnLookupObject__c.getDescribe().getName() => dlrsRule.dlrs__AggregateResultField__c,
      please__Rollup__mdt.please__RollupOperation__c.getDescribe().getName() => operation.toUpperCase(),
      please__Rollup__mdt.please__SharingMode__c.getDescribe().getName() => dlrsRule.dlrs__CalculationSharingMode__c

      // Additional DLRS fields that are not supported/used by Rollup
      // dlrs__AggregateAllRows__c
      // dlrs__CalculationMode__c
      // dlrs__RelationshipCriteriaFields__c
    };

    // Create the instance of Metadata.CustomMetadataValue for the current DLRS rule
    for (String fieldName : fieldValuesToCopy.keySet()) {
      Metadata.CustomMetadataValue customField = new Metadata.CustomMetadataValue();
      customField.field = fieldName;
      if (fieldName == please__Rollup__mdt.please__Description__c.getDescribe().getName()) {
        customField.value = 'Generated by migration script:\n' + fieldValuesToCopy.get(fieldName);
      } else {
        customField.value = fieldValuesToCopy.get(fieldName);
      }

      customMetadata.values.add(customField);
    }

    shouldDeploy = true;
    deployment.addMetadata(customMetadata);
  }
}

// TODO refactor to use LOGGER constant and remove System.debug statements
if (shouldDeploy) {
  // Deploy the converted Rollup__mdt CMDT records - these will be treated like an upsert based on DeveloperName
  System.debug(LoggingLevel.INFO, 'Deployment metadata==' + JSON.serialize(deployment));
  Id jobId = Metadata.Operations.enqueueDeployment(deployment, null);
  System.debug(LoggingLevel.INFO, 'Deployment Job ID: ' + jobId);
} else {
  System.debug(LoggingLevel.INFO, 'No DLRS rules to migrate, skipping metadata deploy');
}

if (unmigrateableRules.isEmpty() == false) {
  // Debug the information necessary for rules that couldn't be created due to lack of support for certain objects
  System.debug(LoggingLevel.INFO, 'The following DLRS rules could not be migrated, please create Rollup flow actions for them!');
  for (Map<String, String> unmigrateableRule : unmigrateableRules) {
    System.debug(LoggingLevel.INFO, JSON.serializePretty(unmigrateableRule));
  }
} else {
  System.debug(LoggingLevel.INFO, 'All DLRS rules were migrated to Rollup metadata successfully');
}
