import { LightningElement, wire, api } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RecalculateParentQuickAction extends LightningElement {
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
    if (!this.canBeClicked) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Waiting on rollup metadata...',
          message: 'Try clicking the button again in a few seconds.',
          variant: 'warning'
        })
      );
      return;
    } else if (this.isExecuting) {
      return;
    }

    this.isExecuting = true;

    if (this.isValid) {
      await this.template.querySelector('c-recalculate-parent-rollup-flexipage')?.handleClick();

      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Success',
          message: 'Rollup recalculation finished! You may need to refresh the page to see updated values.',
          variant: 'success'
        })
      );
    } else {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Rollup recalculation is not possible due to missing metadata.',
          message: 'No rollup metadata found for the selected object. Check with your administrator to ensure that the object has valid rollups configured.',
          variant: 'error'
        })
      );
    }

    this.isExecuting = false;
  }

  async handleLoadingFinished(event) {
    const { isValid } = event.detail;
    this.isValid = isValid;
    this.canBeClicked = true;
  }
}
