import { createElement } from 'lwc';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';

import RecalculateParentRollupFlexipage from 'c/recalculateParentRollupFlexipage';
import { mockMetadata } from '../../__mockData__';

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
  '@salesforce/apex/Rollup.performBulkFullRecalc',
  () => {
    return {
      default: jest.fn()
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

  it('should not render anything if object api name has no match for parent in retrieved metadata', async () => {
    const fakeObjectName = 'Lead';
    expect(mockMetadata[fakeObjectName]).toBeFalsy();

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

    parentRecalcEl.objectApiName = mockMetadata[Object.keys(mockMetadata)[0]][0].LookupObject__c;
    document.body.appendChild(parentRecalcEl);

    return flushPromises().then(() => {
      expect(parentRecalcEl.shadowRoot.querySelector('div')).toBeTruthy();
    });
  });

  // instead of passing the mock down through several promise layers
  // we'll keep it in the outer scope
  const mockFunction = jest.fn();

  it('should send CMDT to apex with parent record id when clicked', async () => {
    // set up pseudo-Aura on global window
    Object.defineProperty(global.window, '$A', {
      value: {
        get() {
          return {
            fire: mockFunction
          };
        }
      }
    });

    const FAKE_RECORD_ID = '00100000000001';

    const parentRecalcEl = createElement('c-recalculate-parent-rollup-flexipage', {
      is: RecalculateParentRollupFlexipage
    });

    const matchingMetadata = mockMetadata[Object.keys(mockMetadata)[0]];
    delete matchingMetadata[0]['CalcItem__r.QualifiedApiName'];
    parentRecalcEl.objectApiName = matchingMetadata[0].LookupObject__c;
    parentRecalcEl.recordId = FAKE_RECORD_ID;

    document.body.appendChild(parentRecalcEl);

    return flushPromises()
      .then(() => {
        parentRecalcEl.shadowRoot.querySelector('lightning-button').click();
      })
      .then(() => {
        expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeTruthy();
      })
      .then(() => {
        // once recalc has finished ...
        // we need to validate that what was sent includes our custom rollup invocation point
        matchingMetadata[0].CalcItemWhereClause__c = " ||| AccountId = '" + FAKE_RECORD_ID + "'";
        expect(parentRecalcEl.shadowRoot.querySelector('lightning-spinner')).toBeFalsy();
        expect(performBulkFullRecalc.mock.calls[0][0]).toEqual({ matchingMetadata, invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC' });

        // validate that aura refresh was called
        expect(mockFunction).toHaveBeenCalled();
      });
  });
});
