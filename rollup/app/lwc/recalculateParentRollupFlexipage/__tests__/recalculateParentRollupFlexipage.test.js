import { createElement } from 'lwc';

import RecalculateParentRollupFlexipage from "c/recalculateParentRollupFlexipage"
import { mockMetadata } from "../../__mockData__"

jest.mock(
  '@salesforce/apex/Rollup.getRollupMetadataByCalcItem',
  () => {
    return {
      default: () => mockMetadata
    };
  },
  { virtual: true }
);

function flushPromises() {
  return new Promise(resolve => setTimeout(resolve, 0));
}

describe('recalc parent rollup from flexipage tests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('should not render anything if object api name has no match for parent in retrieved metadata', () => {
    const fakeObjectName = 'Lead';
    expect(mockMetadata[fakeObjectName]).toBeFalsy();

    const parentRecalcButton = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });
    parentRecalcButton.objectApiName = fakeObjectName;
    document.body.appendChild(parentRecalcButton);

    return flushPromises().then(() => {
      expect(parentRecalcButton.shadowRoot.querySelector('div')).toBeFalsy();
    })
  })

  it('should render if object api name matches parent in retrieved metadata', () => {
    const parentRecalcButton = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    parentRecalcButton.objectApiName = mockMetadata[Object.keys(mockMetadata)[0]][0].LookupObject__c
    document.body.appendChild(parentRecalcButton);

    return flushPromises().then(() => {
      expect(parentRecalcButton.shadowRoot.querySelector('div')).toBeTruthy();
    })
  })

  it('should send CMDT to apex with parent record id when clicked', () => {
    expect(true).toBeFalsy();
  })
})