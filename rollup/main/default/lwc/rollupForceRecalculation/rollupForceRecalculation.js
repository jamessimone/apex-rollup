import { api, LightningElement, track } from 'lwc';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';

export default class RollupForceRecalculation extends LightningElement {
  @api opFieldOnCalcItem;
  @api lookupFieldOnCalcItem;
  @api lookupFieldOnLookupObject;
  @api rollupFieldOnLookupObject;
  @api lookupSObjectName;
  @api calcItemSObjectName;
  @api operationName;

  @track isRollingUp = false;
  @track rollupStatus;

  waitCounter = 0;
  resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];

  async handleSubmit(event) {
    event.preventDefault();

    const jobId = await performFullRecalculation({
      opFieldOnCalcItem,
      lookupFieldOnCalcItem,
      lookupFieldOnLookupObject,
      rollupFieldOnLookupObject,
      lookupSObjectName,
      calcItemSObjectName,
      operationName
    });
    await this._getBatchJobStatus(jobId, this.waitCounter);
  }

  async _getBatchJobStatus(jobId, waitCounter) {
    if (!jobId) {
      return;
    }
    this.isRollingUp = true;
    this.rollupStatus = await getBatchRollupStatus({ jobId });

    // some arbitrary wait time - for a huge batch job, it could take ages to resolve
    while (waitCounter < 200 && this.resolvedBatchStatuses.includes(this.rollupStatus) == false) {
      waitCounter++;
      setInterval(() => {
        this._getBatchJobStatus(jobId, waitCounter);
      }, 5000);
    }
  }
}
