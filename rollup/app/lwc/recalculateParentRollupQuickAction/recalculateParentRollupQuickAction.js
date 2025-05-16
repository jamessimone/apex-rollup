import { LightningElement, wire, api } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RecalculateParentRollupQuickAction extends LightningElement {
  fetchedRecordId;
  computedObjectApiName;

  canBeClicked = false;
  isExecuting = false;

  @wire(CurrentPageReference)
  setRollupValues(currentPageReference) {
    this.fetchedRecordId = currentPageReference?.attributes?.recordId;
    this.computedObjectApiName = currentPageReference?.attributes?.objectApiName;
  }

  @api
  async invoke() {
    const toastEventParams = {
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
      await this.template.querySelector('c-recalculate-parent-rollup-flexipage')?.handleClick();
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

  async handleLoadingFinished(event) {
    const { isValid } = event.detail;
    this.isValid = isValid;
    this.canBeClicked = true;
  }
}
