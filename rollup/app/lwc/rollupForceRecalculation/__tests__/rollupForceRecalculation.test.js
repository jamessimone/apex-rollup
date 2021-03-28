import { createElement } from 'lwc';

import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import RollupForceRecalculation from 'c/rollupForceRecalculation';

async function assertForTestConditions() {
  const resolvedPromise = Promise.resolve();
  return resolvedPromise.then.apply(resolvedPromise, arguments);
}

jest.mock(
  '@salesforce/apex/Rollup.performFullRecalculation',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

function setElementValue(element, value) {
  element.value = value;
  element.dispatchEvent(new CustomEvent('change'));
}

describe('Rollup force recalc tests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sends form data to apex', () => {
    const fullRecalc = createElement('c-rollup-force-recalculation', {
      is: RollupForceRecalculation
    });
    document.body.appendChild(fullRecalc);

    // validate that toggle is not checked
    const toggle = fullRecalc.shadowRoot.querySelector('lightning-input[data-id="cmdt-toggle"]');
    expect(toggle).not.toBeNull();
    expect(toggle.type).toBe('toggle');
    expect(toggle.checked).toBeFalsy();

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
        potentialWhereClause: ''
      });
    });
  });
});
