import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import RecalculateParentQuickAction from 'c/recalculateParentQuickAction';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';
import { mockNamespaceInfo, mockMetadata } from '../../__mockData__';

jest.mock(
  'lightning/refresh',
  () => ({
    // eslint-disable-next-line
    RefreshEvent: CustomEvent
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

const SHOW_TOAST_NAME = 'lightning__showtoast';

describe('c-recalculate-parent-quick-action', () => {
  beforeEach(() => {
    getRollupMetadataByCalcItem.mockResolvedValue({ ...mockMetadata });
    getNamespaceInfo.mockResolvedValue({ ...mockNamespaceInfo });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.resetModules();
  });

  it('calls handleClick on the child component when loadingfinished event is dispatched happy path', async () => {
    const element = createElement('c-recalculate-parent-quick-action', {
      is: RecalculateParentQuickAction
    });
    document.body.appendChild(element);
    const toastHandler = jest.fn();
    element.addEventListener(SHOW_TOAST_NAME, toastHandler);

    CurrentPageReference.emit({
      attributes: {
        recordId: '123',
        objectApiName: 'Account'
      }
    });

    const childComponent = element.shadowRoot.querySelector('c-recalculate-parent-rollup-flexipage');

    // the component lifecycle in Jest happens too fast for the getRollupMetadataByCalcItem adapter to resolve fully (same with the namespaceInfo call)
    // so by manually dispatching the child -> parent event a second time, we can actually get to the _valid_ state and test the happy path
    const handleClickSpy = jest.spyOn(childComponent, 'handleClick');
    const loadingFinishedEvent = new CustomEvent('loadingfinished', {
      detail: { isValid: true }
    });
    childComponent.dispatchEvent(loadingFinishedEvent);

    element.invoke();
    await Promise.resolve();
    expect(handleClickSpy).toHaveBeenCalled();

    const showToastEvent = toastHandler.mock.calls[0][0];
    expect(showToastEvent.detail).toMatchObject({
      title: 'Success',
      message: 'Rollup recalculation finished! You may need to refresh the page to see updated values.',
      variant: 'success'
    });
    expect(showToastEvent.type).toBe(SHOW_TOAST_NAME);
  });

  it('calls toast handler no valid rollups', async () => {
    const element = createElement('c-recalculate-parent-quick-action', {
      is: RecalculateParentQuickAction
    });
    document.body.appendChild(element);
    const toastHandler = jest.fn();
    element.addEventListener(SHOW_TOAST_NAME, toastHandler);
    CurrentPageReference.emit({
      attributes: {
        recordId: '123',
        objectApiName: 'Account'
      }
    });

    element.invoke();
    await Promise.resolve();

    expect(toastHandler).toHaveBeenCalled();
  });
});
