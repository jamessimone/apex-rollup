import { LightningElement, wire, api } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

interface ToastEventParams {
  title: string;
  message: string;
  variant: 'success' | 'warning' | 'error' | 'info';
}

interface LoadingFinishedEvent {
  detail: {
    isValid: boolean;
  };
}

export default class RecalculateParentRollupQuickAction extends LightningElement {
  fetchedRecordId: string | undefined;
  computedObjectApiName: string | undefined;

  canBeClicked: boolean = false;
  isExecuting: boolean = false;
  isValid: boolean = false;

  @wire(CurrentPageReference)
  setRollupValues(currentPageReference: any): void {
    this.fetchedRecordId = currentPageReference?.attributes?.recordId;
    this.computedObjectApiName = currentPageReference?.attributes?.objectApiName;
  }

  @api
  async invoke(): Promise<void> {
    const toastEventParams: ToastEventParams = {
      title: 'Waiting on rollup metadata...',
      message: 'Try clicking the button again in a few seconds.',
      variant: 'warning'
    };
    if (!this.canBeClicked) {
      this.dispatchEvent(new ShowToastEvent(toastEventParams));
      return;
    } else if (this.isExecuting) {
      return;
    }

    this.isExecuting = true;

    if (this.isValid) {
      const flexipageComponent = this.template?.querySelector('c-recalculate-parent-rollup-flexipage') as any;
      if (flexipageComponent) {
        await flexipageComponent.handleClick();
      }
      toastEventParams.title = 'Success';
      toastEventParams.message = 'Rollup recalculation finished! You may need to refresh the page to see updated values.';
      toastEventParams.variant = 'success';
    } else {
      toastEventParams.title = 'Rollup recalculation is not possible due to missing metadata.';
      toastEventParams.message =
        'No rollup metadata found for the selected object. Check with your administrator to ensure that the object has valid rollups configured.';
      toastEventParams.variant = 'error';
    }
    this.dispatchEvent(new ShowToastEvent(toastEventParams));

    this.isExecuting = false;
  }

  handleLoadingFinished(event: LoadingFinishedEvent): void {
    const { isValid } = event.detail;
    this.isValid = isValid;
    this.canBeClicked = true;
  }
}
