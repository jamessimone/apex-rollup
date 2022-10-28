// when you use a preconfigured variable outside of a jest test as the return
// for a mock, it's required for that prop to be prefixed with the word "mock"
// and this variable will be used further downstream to that effect

const mockRollupMetadata = {
  Contact: [
    {
      CalcItem__c: 'Contact',
      LookupFieldOnCalcItem__c: 'AccountId',
      LookupFieldOnLookupObject__c: 'Id',
      LookupObject__c: 'Account',
      RollupFieldOnCalcItem__c: 'FirstName',
      RollupFieldOnLookupObject__c: 'Name',
      RollupOperation__c: 'CONCAT',
      CalcItem__r: { QualifiedApiName: 'Something we expect to be removed' },
      SplitConcatDelimiterOnCalcItem__c: '',
      RollupOrderBys__r: []
    }
  ]
};

export const mockNamespaceInfo = {
  namespace: '',
  safeRollupOperationField: 'Rollup__mdt.RollupOperation__c',
  safeObjectName: 'Rollup__mdt'
};

export const mockMetadata = mockRollupMetadata;
