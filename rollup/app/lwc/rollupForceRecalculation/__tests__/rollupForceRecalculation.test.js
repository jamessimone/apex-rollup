import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';

import { mockMetadata } from '../../__mockData__';
import RollupForceRecalculation from 'c/rollupForceRecalculation';

const mockGetObjectInfo = require('./data/rollupCMDTWireAdapter.json');

function flushPromises() {
  return new Promise(resolve => setTimeout(resolve, 0));
}

jest.mock(
  '@salesforce/apex/Rollup.getRollupMetadataByCalcItem',
  () => {
    return {
      default: () => mockMetadata
    };
  },
  { virtual: true }
);

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

// jest.mock(
//   '@salesforce/apex/Rollup.getBatchRollupStatus',
//   () => {
//     return {
//       default: () => jest.fn()
//     };
//   },
//   { virtual: true }
// );

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

    return flushPromises().then(() => {
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

    const operationName = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="RollupOperation__c"]');
    setElementValue(operationName, 'CONCAT');

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    return flushPromises().then(() => {
      expect(performFullRecalculation.mock.calls[0][0]).toEqual({
        metadata: {
          RollupFieldOnCalcItem__c: 'FirstName',
          LookupFieldOnCalcItem__c: 'AccountId',
          LookupFieldOnLookupObject__c: 'Id',
          RollupFieldOnLookupObject__c: 'Name',
          LookupObject__c: 'Account',
          CalcItem__c: 'Contact',
          RollupOperation__c: 'CONCAT',
          CalcItemWhereClause__c: '',
          OrderByFirstLast__c: '',
          ConcatDelimiter__c: ''
        }
      });
    });
  });

  it('sends CMDT data to apex', async () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    // flush to re-render, post-click
    return (
      flushPromises().then(() => {
        const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
          new CustomEvent('change', {
            detail: {
              value: 'Contact'
            }
          })
        );
      })
        .then(() => {
          // flush to get the datatable to render post selection
          const datatable = fullRecalc.shadowRoot.querySelector('lightning-datatable[data-id="datatable"]');
          datatable.dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: mockMetadata.Contact } }));

          const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
          submitButton.click();
        })
        // flush again to handle the click action ....
        .then(() => {
          const expectedList = mockMetadata['Contact'];
          delete expectedList[0]['CalcItem__r.QualifiedApiName'];
          expect(performBulkFullRecalc.mock.calls[0][0]).toEqual({ matchingMetadata: expectedList, invokePointName: "FROM_LWC" });
        })
    );
  });

  it('renders CMDT datatable with selected metadata', async () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle gets checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfo.emit(mockGetObjectInfo);

    // flush to re-render
    return flushPromises().then(() => {
      const combobox = fullRecalc.shadowRoot.querySelector('lightning-combobox');
      combobox.dispatchEvent(
        new CustomEvent('change', {
          detail: {
            value: 'Contact'
          }
        })
      );

      return (
        flushPromises()
          .then(() => {
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
  });

  it('sets error when CMDT is not returned', () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfo.emitError();

    return flushPromises().then(() => {

      const errorDiv = fullRecalc.shadowRoot.querySelector('div[data-id="rollupError"]')
      expect(errorDiv).toBeTruthy();
    })
  })

  it('succeeds even when exception is thrown', () => {
    performFullRecalculation.mockRejectedValue('error!');
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    return flushPromises()
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
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
    return flushPromises()
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });

  it('polls when process Id given', () => {
    // simulate second poll receiving one of the completed values
    getBatchRollupStatus.mockResolvedValueOnce('test').mockResolvedValueOnce('Completed');
    performFullRecalculation.mockResolvedValueOnce('someProcessId');

    performBulkFullRecalc.mock
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    let hasError = false;
    return flushPromises()
      .catch(() => {
        hasError = true;
      })
      .finally(() => {
        expect(hasError).toBeFalsy();
      });
  });
});
