import { createElement } from 'lwc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';

import RecalculateParentRollupFlexipage from 'c/recalculateParentRollupFlexipage';
import { mockMetadata, mockNamespaceInfo } from '../../__mockData__';

jest.mock(
  'lightning/refresh',
  () => ({
    // eslint-disable-next-line
    RefreshEvent: new Event("RefreshEventMock")
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.getNamespaceInfo',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.getRollupMetadataByCalcItem',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.performSerializedBulkFullRecalc',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

function flushPromises() {
  // eslint-disable-next-line
  return new Promise(resolve => setTimeout(resolve, 0));
}

// instead of passing the mock down through several promise layers
// we'll keep it in the outer scope
let metadata;

describe('recalc parent rollup from flexipage tests', () => {
  beforeEach(() => {
    metadata = JSON.parse(JSON.stringify(mockMetadata));
    getRollupMetadataByCalcItem.mockResolvedValue(metadata);
    performSerializedBulkFullRecalc.mockReset();
    getNamespaceInfo.mockResolvedValue({ ...mockNamespaceInfo });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('should handle error on load gracefully', async () => {
    getRollupMetadataByCalcItem.mockRejectedValue('error!');

    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });
    parentRecalcEl.objectApiName = metadata[Object.keys(metadata)[0]][0].LookupObject__c;
    document.body.appendChild(parentRecalcEl);

    return flushPromises().then(() => {
      expect(parentRecalcEl.shadowRoot.querySelector('div')).toBeFalsy();
    });
  });

  it('should not render anything if object api name has no match for parent in retrieved metadata', async () => {
    const fakeObjectName = 'Lead';
    expect(metadata[fakeObjectName]).toBeFalsy();

    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });
    parentRecalcEl.objectApiName = fakeObjectName;
    document.body.appendChild(parentRecalcEl);

    return flushPromises().then(() => {
      expect(parentRecalcEl.shadowRoot.querySelector('div')).toBeFalsy();
    });
  });

  it('should render if object api name matches parent in retrieved metadata', async () => {
    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    parentRecalcEl.objectApiName = metadata[Object.keys(metadata)[0]][0].LookupObject__c;
    document.body.appendChild(parentRecalcEl);

    return flushPromises().then(() => {
      expect(parentRecalcEl.shadowRoot.querySelector('div')).toBeTruthy();
    });
  });

  it('should fail gracefully if server fails to process', async () => {
    performSerializedBulkFullRecalc.mockRejectedValue('ERROR!!');
    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    const FAKE_RECORD_ID = '00100000000001';
    const matchingMetadata = metadata[Object.keys(metadata)[0]];
    delete matchingMetadata[0].CalcItem__r;
    parentRecalcEl.objectApiName = matchingMetadata[0].LookupObject__c;
    parentRecalcEl.recordId = FAKE_RECORD_ID;
    document.body.appendChild(parentRecalcEl);

    await flushPromises();
    parentRecalcEl.shadowRoot.querySelector('lightning-button').click();
    await flushPromises();
    expect(parentRecalcEl.shadowRoot.querySelector('div')).toBeTruthy();
  });

  it('should send CMDT to apex with parent record id when clicked', async () => {
    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    const FAKE_RECORD_ID = '00100000000001';
    const matchingMetadata = metadata[Object.keys(metadata)[0]];
    delete matchingMetadata[0].CalcItem__r;
    parentRecalcEl.objectApiName = matchingMetadata[0].LookupObject__c;
    parentRecalcEl.recordId = FAKE_RECORD_ID;
    document.body.appendChild(parentRecalcEl);

    await flushPromises()
      .then(() => {
        parentRecalcEl.shadowRoot.querySelector('lightning-button').click();
      })
      .then(() => {
        expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeTruthy();
      });
    await flushPromises();

    // once recalc has finished ...
    // we need to validate that what was sent includes our custom rollup invocation point
    matchingMetadata[0].CalcItemWhereClause__c = " ||| AccountId = '" + FAKE_RECORD_ID + "'";
    matchingMetadata[0].RollupOrderBys__r = { totalSize: 0, done: true, records: [] };
    expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeFalsy();
    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(matchingMetadata),
      invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC'
    });
  });

  it('should properly massage delimited parent Id string for grandparent rollups', async () => {
    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    const FAKE_RECORD_ID = '00100000000001';
    const matchingMetadata = metadata[Object.keys(metadata)[0]];
    delete matchingMetadata[0].CalcItem__r;
    matchingMetadata[0].GrandparentRelationshipFieldPath__c = 'RollupParent__r.RollupGrandparent__r.Name';
    matchingMetadata[0].LookupObject__c = 'RollupGrandparent__c';
    parentRecalcEl.objectApiName = matchingMetadata[0].LookupObject__c;
    parentRecalcEl.recordId = FAKE_RECORD_ID;
    document.body.appendChild(parentRecalcEl);
    await flushPromises().then(() => {
      parentRecalcEl.shadowRoot.querySelector('lightning-button').click();
    });
    await flushPromises();

    matchingMetadata[0].CalcItemWhereClause__c = " ||| RollupParent__r.RollupGrandparent__r.Id = '" + FAKE_RECORD_ID + "'";
    matchingMetadata[0].RollupOrderBys__r = { totalSize: 0, done: true, records: [] };
    expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeFalsy();
    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(matchingMetadata),
      invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC'
    });
  });

  it('detects namespace properly', async () => {
    const namespace = 'please__';
    getNamespaceInfo.mockReset();
    getNamespaceInfo.mockResolvedValue({
      namespace,
      safeRollupOperationField: `${namespace + mockNamespaceInfo.safeRollupOperationField}`,
      safeObjectName: `${namespace + mockNamespaceInfo.safeObjectName}`
    });
    getRollupMetadataByCalcItem.mockClear();
    const namespaceMeta = { ...mockMetadata };
    namespaceMeta.Contact[0] = Object.assign({}, ...Object.keys(namespaceMeta.Contact[0]).map(key => ({ [namespace + key]: namespaceMeta.Contact[0][key] })));
    getRollupMetadataByCalcItem.mockResolvedValue(namespaceMeta);

    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    const FAKE_RECORD_ID = '00100000000001';
    const matchingMetadata = namespaceMeta[Object.keys(metadata)[0]];
    delete matchingMetadata[0].please__CalcItem__r;
    parentRecalcEl.objectApiName = matchingMetadata[0].please__LookupObject__c;
    parentRecalcEl.recordId = FAKE_RECORD_ID;

    document.body.appendChild(parentRecalcEl);
    await flushPromises('mount on page');
    parentRecalcEl.shadowRoot.querySelector('lightning-button').click();
    await flushPromises('wait for click event to call controller');

    matchingMetadata[0].please__CalcItemWhereClause__c = " ||| AccountId = '" + FAKE_RECORD_ID + "'";
    matchingMetadata[0].please__RollupOrderBys__r = { totalSize: 0, done: true, records: [] };
    expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeFalsy();
    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(matchingMetadata),
      invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC'
    });
  });
});
