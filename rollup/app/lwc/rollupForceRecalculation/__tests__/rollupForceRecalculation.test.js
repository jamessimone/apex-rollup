import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';

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

describe('Rollup force recalc tests', () => {
  beforeEach(() => {
    getRollupMetadataByCalcItem.mockResolvedValue(mockMetadata);
  });
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

    const operationName = fullRecalc.shadowRoot.querySelector('lightning-combobox[data-id="RollupOperation__c"]');
    setElementValue(operationName, 'CONCAT', true);

    const grandparentFieldPath = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="GrandparentRelationshipFieldPath__c"]');
    setElementValue(grandparentFieldPath, 'Something__r.SomethingElse__r.Name');

    const oneToManyGrandparentFields = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="OneToManyGrandparentFields__c"]');
    setElementValue(oneToManyGrandparentFields, 'Something__c.SomethingElse__c, SomethingElse__c.Name');

    const submitButton = fullRecalc.shadowRoot.querySelector('lightning-button');
    submitButton.click();

    return flushPromises().then(() => {
      expect(performSerializedFullRecalculation.mock.calls[0][0].metadata).toMatch(
        JSON.stringify({
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
          GrandparentRelationshipFieldPath__c: 'Something__r.SomethingElse__r.Name',
          OneToManyGrandparentFields__c: 'Something__c.SomethingElse__c, SomethingElse__c.Name'
        })
      );
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
      flushPromises()
        .then(() => {
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
          expect(performSerializedBulkFullRecalc.mock.calls[0][0]).toEqual({
            serializedMetadata: JSON.stringify(expectedList),
            invokePointName: 'FROM_FULL_RECALC_LWC'
          });
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

  it('sets error when CMDT is not returned', async () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    toggle.dispatchEvent(new CustomEvent('change')); // _like_ a click ...

    expect(fullRecalc.isCMDTRecalc).toBeTruthy();

    getObjectInfo.emitError();

    return flushPromises().then(() => {
      const errorDiv = fullRecalc.shadowRoot.querySelector('div[data-id="rollupError"]');
      expect(errorDiv).toBeTruthy();
    });
  });

  it('succeeds even when exception is thrown', async () => {
    performSerializedFullRecalculation.mockRejectedValue('error!');
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

  it('succeeds even when no process id', async () => {
    performSerializedFullRecalculation.mockResolvedValue('No process Id');

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

  it('polls when process Id given', async () => {
    // simulate second poll receiving one of the completed values
    getBatchRollupStatus.mockResolvedValueOnce('Completed').mockResolvedValueOnce('test');
    performSerializedFullRecalculation.mockResolvedValueOnce('someProcessId');

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

  it('returns immediately when first poll is success', async () => {
    getBatchRollupStatus.mockResolvedValue('Completed');
    performSerializedFullRecalculation.mockResolvedValueOnce('someProcessId');

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
