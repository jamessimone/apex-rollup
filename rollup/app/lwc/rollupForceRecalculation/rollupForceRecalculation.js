import { api, LightningElement, track } from 'lwc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RollupForceRecalculation extends LightningElement {
  @api rollupData = {
    opFieldOnCalcItem: '',
    lookupFieldOnCalcItem: '',
    lookupFieldOnLookupObject: '',
    rollupFieldOnLookupObject: '',
    lookupSObjectName: '',
    calcItemSObjectName: '',
    operationName: '',
    potentialWhereClause: ''
  };

  @track isRollingUp = false;
  @track rollupStatus;
  @track error = '';

  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];

  handleChange(event) {
    this.rollupData[event.target.name] = event.target.value;
  }

  async handleSubmit(event) {
    this.error = '';
    event.preventDefault();

    try {
      const jobId = await performFullRecalculation(this.rollupData);
      await this._getBatchJobStatus(jobId);
    } catch (e) {
      const event = new ShowToastEvent({
        title: 'An error occurred while rolling up',
        message: e.body.message,
        variant: 'error'
      });
      console.error(e); // in the event you dismiss the toast but still want to see the error
      this.dispatchEvent(event);
    }
  }

  async _getBatchJobStatus(jobId) {
    if (!jobId) {
      return;
    }
    this.isRollingUp = true;

    this.rollupStatus = await getBatchRollupStatus({ jobId });

    // some arbitrary wait time - for a huge batch job, it could take ages to resolve
    const statusPromise = new Promise(resolve => {
      let timeoutId;
      if (this._resolvedBatchStatuses.includes(this.rollupStatus) == false) {
        timeoutId = setTimeout(() => this._getBatchJobStatus(jobId), 3000);
      } else {
        this.isRollingUp = false;
        clearInterval(timeoutId);
        resolve();
      }
    });
    await statusPromise;
  }
}
