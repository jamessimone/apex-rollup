import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';

import { mockMetadata, mockNamespaceInfo } from '../../__mockData__';
import RollupForceRecalculation from 'c/rollupForceRecalculation';

const mockGetObjectInfo = require('./data/rollupCMDTWireAdapter.json');

function flushPromises() {
  // eslint-disable-next-line
  return new Promise(resolve => setTimeout(resolve, 0));
}

async function mountComponent() {
  const fullRecalc = createElement('c-rollup-force-recalculation', {
    is: RollupForceRecalculation
  });
  document.body.appendChild(fullRecalc);
  await flushPromises('initial rendering cycle');
  return fullRecalc;
}

jest.mock(
  '@salesforce/apex/Rollup.getBatchRollupStatus',
  () => {
    return {
      default: jest.fn()
    };
  },
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
  '@salesforce/apex/Rollup.performSerializedFullRecalculation',
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

function setElementValue(element, value, isCombobox = false) {
  let eventName = 'commit';
  if (isCombobox) {
    eventName = 'change';
  }
  element.value = value;
  element.dispatchEvent(new CustomEvent(eventName, isCombobox ? { detail: { value: element.value } } : undefined));
}

async function submitsFormDataWithNamespace(namespace = '') {
  const fullRecalc = await mountComponent();

  // validate that toggle is not checked
  const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
  expect(toggle).not.toBeNull();
  expect(fullRecalc.isCMDTRecalc).toBeFalsy();

  const calcItemSObjectName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="CalcItem__c"]');
  setElementValue(calcItemSObjectName, 'Contact');

  const opFieldOnCalcItem = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="RollupFieldOnCalcItem__c"]');
  setElementValue(opFieldOnCalcItem, 'FirstName');

  const lookupFieldOnCalcItem = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="LookupFieldOnCalcItem__c"]');
  setElementValue(lookupFieldOnCalcItem, 'AccountId');

  const lookupFieldOnLookupObject = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="LookupFieldOnLookupObject__c"]');
  setElementValue(lookupFieldOnLookupObject, 'Id');

  const rollupFieldOnLookupObject = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="RollupFieldOnLookupObject__c"]');
  setElementValue(rollupFieldOnLookupObject, 'Name');

  const lookupSObjectName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="LookupObject__c"]');
  setElementValue(lookupSObjectName, 'Account');

  const operationName = fullRecalc.shadowRoot.querySelector('lightning-combobox[data-id="RollupOperation__c"]');
  setElementValue(operationName, 'CONCAT', true);

  const grandparentFieldPath = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="GrandparentRelationshipFieldPath__c"]');
  setElementValue(grandparentFieldPath, 'Something__r.SomethingElse__r.Name');

  const oneToManyGrandparentFields = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="OneToManyGrandparentFields__c"]');
  setElementValue(oneToManyGrandparentFields, 'Something__c.SomethingElse__c, SomethingElse__c.Name');

  const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
  submitButton.click();

  await flushPromises('apex controller call');
  let defaultNamespaceObject = {
    RollupFieldOnCalcItem__c: 'FirstName',
    LookupFieldOnCalcItem__c: 'AccountId',
    LookupFieldOnLookupObject__c: 'Id',
    RollupFieldOnLookupObject__c: 'Name',
    LookupObject__c: 'Account',
    CalcItem__c: 'Contact',
    RollupOperation__c: 'CONCAT',
    CalcItemWhereClause__c: '',
    ConcatDelimiter__c: '',
    SplitConcatDelimiterOnCalcItem__c: false,
    LimitAmount__c: null,
    GrandparentRelationshipFieldPath__c: 'Something__r.SomethingElse__r.Name',
    OneToManyGrandparentFields__c: 'Something__c.SomethingElse__c, SomethingElse__c.Name'
  };
  if (namespace) {
    defaultNamespaceObject = Object.assign({}, ...Object.keys(defaultNamespaceObject).map(key => ({ [namespace + key]: defaultNamespaceObject[key] })));
  }
  expect(performSerializedFullRecalculation.mock.calls[0][0].metadata).toMatch(JSON.stringify(defaultNamespaceObject));
}

describe('Rollup force recalc tests', () => {
  beforeEach(() => {
    getRollupMetadataByCalcItem.mockResolvedValue({ ...mockMetadata });
    getNamespaceInfo.mockResolvedValue({ ...mockNamespaceInfo });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sets document title', async () => {
    await mountComponent();

    expect(document.title).toEqual('Recalculate Rollup');
  });

  it('sends form data to apex', async () => {
    await submitsFormDataWithNamespace();
  });

  it('sends namespaced form data to apex', async () => {
    const namespace = 'please__';
    getNamespaceInfo.mockReset();
    getNamespaceInfo.mockResolvedValue({
      namespace,
      safeRollupOperationField: `${namespace + mockNamespaceInfo.safeRollupOperationField}`,
      safeObjectName: `${namespace + mockNamespaceInfo.safeObjectName}`
    });
    await submitsFormDataWithNamespace(namespace);
  });

  it('sends CMDT data to apex', async () => {
    const fullRecalc = await mountComponent();

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    await flushPromises('flush to re-render, post-click');

    const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
    combobox.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          value: 'Contact'
        }
      })
    );

    await flushPromises('flush to get the datatable to render post selection');
    // flush to get the datatable to render post selection
    const datatable = fullRecalc.shadowRoot.querySelector('lightning-datatable[data-id="datatable"]');
    datatable.dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: mockMetadata.Contact } }));
    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();
    await flushPromises('apex controller call');

    const expectedList = mockMetadata.Contact;
    delete expectedList[0]['CalcItem__r.QualifiedApiName'];
    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(expectedList),
      invokePointName: 'FROM_FULL_RECALC_LWC'
    });
  });

  it('renders CMDT datatable with selected metadata', async () => {
    const fullRecalc = await mountComponent();

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // it's awkward that this is the "click" for a toggle

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfo.emit(mockGetObjectInfo);

    await flushPromises('getObjectInfo re-render');
    const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
    combobox.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          value: 'Contact'
        }
      })
    );
    await flushPromises('change handler');

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();
    await flushPromises('click handler');
    const tableRows = fullRecalc.shadowRoot.querySelector('lightning-datatable').data;
    expect(tableRows.length).toBe(mockMetadata.Contact.length);
  });

  it('sets error when CMDT is not returned', async () => {
    const fullRecalc = await mountComponent();

    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change'));

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfo.emitError({ body: { message: 'oh no' } });

    await flushPromises('re-render for CMDT toggle');
    const errorDiv = fullRecalc.shadowRoot.querySelector('div[data-id="rollupError"]');
    expect(errorDiv).toBeTruthy();
  });

  it('succeeds even when controller returns rejected promise', async () => {
    performSerializedFullRecalculation.mockRejectedValue('error!');
    const fullRecalc = await mountComponent();

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    await flushPromises('controller call')
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });

  it('succeeds even when no process id', async () => {
    performSerializedFullRecalculation.mockResolvedValue('No process Id');

    const fullRecalc = await mountComponent();

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    await flushPromises('controller call')
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });

  it('polls when process Id given', async () => {
    // simulate second poll receiving one of the completed values
    getBatchRollupStatus.mockResolvedValueOnce('Completed').mockResolvedValueOnce('test');
    performSerializedFullRecalculation.mockResolvedValueOnce('someProcessId');

    const fullRecalc = await mountComponent();

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    await flushPromises('controller call')
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });

  it('returns immediately when first poll is success', async () => {
    getBatchRollupStatus.mockResolvedValue('Completed');
    performSerializedFullRecalculation.mockResolvedValueOnce('someProcessId');

    const fullRecalc = await mountComponent();

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    await flushPromises()
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });

  it('only sets up rollup order by children once', async () => {
    getRollupMetadataByCalcItem.mockClear();
    mockMetadata.Contact[0].RollupOrderBys__r = [
      {
        Rollup__c: 'someId',
        Id: 'someOtherId',
        FieldName__c: 'CreatedDate',
        NullSortOrder__c: 'NULLS FIRST',
        Ranking__c: 0,
        SortOrder__c: 'Ascending'
      }
    ];
    getRollupMetadataByCalcItem.mockResolvedValue(mockMetadata);
    const fullRecalc = await mountComponent();

    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change'));
    await flushPromises('flush to re-render, post-click');
    const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
    combobox.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          value: 'Contact'
        }
      })
    );
    await flushPromises('flush to get the datatable to render post selection');
    // flush to get the datatable to render post selection
    const datatable = fullRecalc.shadowRoot.querySelector('lightning-datatable[data-id="datatable"]');
    datatable.dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: mockMetadata.Contact } }));
    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();
    await flushPromises('apex controller call');

    const expectedList = mockMetadata.Contact;
    delete expectedList[0]['CalcItem__r.QualifiedApiName'];
    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(expectedList),
      invokePointName: 'FROM_FULL_RECALC_LWC'
    });

    // once more!
    submitButton.click();
    await flushPromises('apex controller call');

    expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
      serializedMetadata: JSON.stringify(expectedList),
      invokePointName: 'FROM_FULL_RECALC_LWC'
    });
  });
});
