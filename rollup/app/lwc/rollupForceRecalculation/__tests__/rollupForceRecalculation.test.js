import { createElement } from 'lwc';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';
import RollupForceRecalculation from 'c/rollupForceRecalculation';
import { registerLdsTestWireAdapter } from '@salesforce/sfdx-lwc-jest';

const mockGetObjectInfo = require('./data/rollupCMDTWireAdapter.json');
const getObjectInfoWireAdapter = registerLdsTestWireAdapter(getObjectInfo);

async function assertForTestConditions() {
  const resolvedPromise = Promise.resolve();
  return resolvedPromise.then.apply(resolvedPromise, arguments);
}

// when you use a preconfigured variable outside of a jest test as the return
// for a mock, it's required for that prop to be prefixed with the word "mock"
const mockMetadata = {
  Contact: [
    {
      CalcItem__c: 'Contact',
      LookupFieldOnCalcItem__c: 'AccountId',
      LookupFieldOnLookupObject__c: 'Id',
      LookupObject__c: 'Account',
      RollupFieldOnCalcItem__c: 'FirstName',
      RollupFieldOnLookupObject__c: 'Name',
      RollupOperation__c: 'CONCAT',
      'CalcItem__r.QualifiedApiName': 'Something we expect to be removed'
    }
  ]
};

jest.mock(
  '@salesforce/apex/Rollup.performFullRecalculation',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.performBulkFullRecalc',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.getBatchRollupStatus',
  () => {
    return {
      default: () => jest.fn()
    };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/Rollup.getRollupMetadataByCalcItem',
  () => {
    return {
      default: () => mockMetadata
    };
  },
  { virtual: true }
);

function setElementValue(element, value) {
  element.value = value;
  element.dispatchEvent(new CustomEvent('commit'));
}

describe('Rollup force recalc tests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sets document title', async () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    return assertForTestConditions(() => {
      expect(document.title).toEqual('Recalculate Rollup');
    });
  });

  it('sends form data to apex', async () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle is not checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    expect(toggle).not.toBeNull();
    expect(fullRecalc.isCMDTRecalc).toBeFalsy();

    const calcItemSObjectName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="calcItemSObjectName"]');
    setElementValue(calcItemSObjectName, 'Contact');

    const opFieldOnCalcItem = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="opFieldOnCalcItem"]');
    setElementValue(opFieldOnCalcItem, 'FirstName');

    const lookupFieldOnCalcItem = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="lookupFieldOnCalcItem"]');
    setElementValue(lookupFieldOnCalcItem, 'AccountId');

    const lookupFieldOnLookupObject = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="lookupFieldOnLookupObject"]');
    setElementValue(lookupFieldOnLookupObject, 'Id');

    const rollupFieldOnLookupObject = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="rollupFieldOnLookupObject"]');
    setElementValue(rollupFieldOnLookupObject, 'Name');

    const lookupSObjectName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="lookupSObjectName"]');
    setElementValue(lookupSObjectName, 'Account');

    const operationName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="operationName"]');
    setElementValue(operationName, 'CONCAT');

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    return assertForTestConditions(() => {
      expect(performFullRecalculation.mock.calls[0][0]).toEqual({
        opFieldOnCalcItem: 'FirstName',
        lookupFieldOnCalcItem: 'AccountId',
        lookupFieldOnLookupObject: 'Id',
        rollupFieldOnLookupObject: 'Name',
        lookupSObjectName: 'Account',
        calcItemSObjectName: 'Contact',
        operationName: 'CONCAT',
        potentialWhereClause: '',
        potentialConcatDelimiter: ''
      });
    });
  });

  it('sends CMDT data to apex with relationship names removed', async () => {
    // calling getRollupMetadataByCalcItem.mockResolvedValue() here didn't work
    // (as it does in the next test) and I have no idea why ...

    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    // flush to re-render
    return (
      Promise.resolve()
        .then(() => {
          const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
          combobox.dispatchEvent(
            new CustomEvent('change', {
              detail: {
                value: 'Contact'
              }
            })
          );

          const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
          submitButton.click();
        })
        // then flush again ....
        .then(() => {
          const expectedList = mockMetadata['Contact'];
          delete expectedList[0]['CalcItem__r.QualifiedApiName'];
          expect(performBulkFullRecalc.mock.calls[0][0]).toEqual({ matchingMetadata: expectedList });
        })
    );
  });

  it('renders CMDT datatable with selected metadata', async () => {
    // calling getRollupMetadataByCalcItem.mockResolvedValue() here didn't work
    // (as it does in the next test) and I have no idea why ...

    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfoWireAdapter.emit(mockGetObjectInfo);

    // flush to re-render
    return (
      Promise.resolve()
        .then(() => {
          const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
          combobox.dispatchEvent(
            new CustomEvent('change', {
              detail: {
                value: 'Contact'
              }
            })
          );

          const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
          submitButton.click();
        })
        // then flush again ....
        .then(() => {
          const tableRows = fullRecalc.shadowRoot.querySelector('lightning-datatable').data;
          expect(tableRows.length).toBe(mockMetadata.Contact.length);
        })
    );
  });

  it('succeeds even when no process id', () => {
    performFullRecalculation.mockResolvedValue('No process Id');
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    return assertForTestConditions()
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });
});
