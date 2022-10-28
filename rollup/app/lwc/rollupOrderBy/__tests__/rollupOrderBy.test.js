import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import RollupOrderBy from 'c/rollupOrderBy';

import { mockNamespaceInfo } from '../../__mockData__';

jest.mock(
  '@salesforce/apex/Rollup.getNamespaceInfo',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

const mockOrderByInfo = {
  fields: {
    Ranking__c: {
      dataType: 'number',
      apiName: 'Ranking__c',
      inlineHelpText: 'Ranking help text',
      label: 'Ranking'
    },
    FieldName__c: {
      dataType: 'string',
      apiName: 'FieldName__c',
      inlineHelpText: 'Field Name help text',
      label: 'Field Name'
    },
    SortOrder__c: {
      dataType: 'string',
      apiName: 'SortOrder__c',
      inlineHelpText: 'Sort Order help text',
      label: 'Sort Order'
    },
    NullSortOrder__c: {
      dataType: 'string',
      apiName: 'NullSortOrder__c',
      inlineHelpText: 'Null Sort Order help text',
      label: 'Null Sort Order'
    }
  }
};

function setElementValue(element, value) {
  element.value = value;
  element.dispatchEvent(new CustomEvent('change'));
}

async function mountOrderByElement() {
  const orderBy = createElement('c-rollup-order-by', {
    is: RollupOrderBy
  });
  document.body.appendChild(orderBy);

  await getObjectInfo.emit(mockOrderByInfo);
  await Promise.resolve();
  return orderBy;
}

describe('Rollup force recalc tests', () => {
  beforeEach(() => {
    getNamespaceInfo.mockResolvedValue({ ...mockNamespaceInfo });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders modal correctly', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();

    await Promise.resolve(); // wait for click to propagate ...

    expect(orderBy).not.toBeNull();
    expect(orderBy.shadowRoot.querySelector('.slds-modal__container')).not.toBeNull();
    expect(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]')).not.toBeNull();
    expect(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]')).not.toBeNull();
    expect(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]')).not.toBeNull();
    expect(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]')).not.toBeNull();
  });

  it('correctly sorts added elements', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]'), 3);
    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'TextField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]'), 'Ascending');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]'), 'NULLS LAST');

    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    expect(orderBy.orderBys.length).toEqual(1);
    expect(orderBy.orderBys[0]).toEqual({ FieldName__c: 'TextField__c', NullSortOrder__c: 'NULLS LAST', Ranking__c: 3, SortOrder__c: 'Ascending' });

    // now create another record sorted below it ...
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]'), 1);
    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'AnotherField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]'), 'Descending');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]'), 'NULLS FIRST');
    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    expect(orderBy.orderBys.length).toEqual(2);
    // validate that first element has changed due to sorting
    expect(orderBy.orderBys[0]).toEqual({ FieldName__c: 'AnotherField__c', NullSortOrder__c: 'NULLS FIRST', Ranking__c: 1, SortOrder__c: 'Descending' });
  });

  it('correctly closes modal based on key press', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    orderBy.shadowRoot.querySelector('.slds-modal').dispatchEvent(new KeyboardEvent('keydown', { code: 'Escape' }));
    await Promise.resolve();

    expect(orderBy.shadowRoot.querySelector('.slds-modal__container')).toBeNull();
  });

  it('saves records when ctrl + s is pressed', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]'), 3);
    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'TextField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]'), 'Ascending');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]'), 'NULLS LAST');

    orderBy.shadowRoot.querySelector('.slds-modal').dispatchEvent(new KeyboardEvent('keydown', { code: 'KeyS', ctrlKey: true }));
    await Promise.resolve();

    expect(orderBy.orderBys.length).toEqual(1);
  });

  it('sets ranking automatically when not filled out', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'TextField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]'), 'Ascending');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]'), 'NULLS LAST');

    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    expect(orderBy.orderBys[0].Ranking__c).toEqual(0);

    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'TextField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="SortOrder__c"]'), 'Ascending');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-combobox[data-id="NullSortOrder__c"]'), 'NULLS LAST');

    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    expect(orderBy.orderBys[0].Ranking__c).toEqual(0);
    expect(orderBy.orderBys[1].Ranking__c).toEqual(1);
  });

  it('reincrements ranking if submitted ranking already exists', async () => {
    const orderBy = await mountOrderByElement();
    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'TextField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]'), 0);

    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    orderBy.shadowRoot.querySelector('[data-id="create-new-button"]').click();
    await Promise.resolve();

    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="FieldName__c"]'), 'AnotherField__c');
    setElementValue(orderBy.shadowRoot.querySelector('lightning-input[data-id="Ranking__c"]'), 0);

    orderBy.shadowRoot.querySelector('[data-id="save-button"]').click();
    await Promise.resolve();

    expect(orderBy.orderBys[0].Ranking__c).toEqual(0);
    expect(orderBy.orderBys[1].Ranking__c).toEqual(1);
  });
});
