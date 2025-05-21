import { api, LightningElement } from 'lwc';

import { isValidAsyncJob } from 'c/rollupUtils';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';

const RESOLVED_JOB_STATUSES = ['Completed', 'Failed', 'Aborted'];

export default class RollupJobPoller extends LightningElement {
  @api
  async runJobPoller(jobId) {
    return this._poll(jobId);
  }

  jobIdToDisplay;
  rollupStatus;

  async _poll(jobId) {
    if (!jobId) {
      this.rollupStatus = 'failed to enqueue, check Apex Debug Logs for more info';
      return;
    }

    this.jobIdToDisplay = jobId;
    if (this.jobIdToDisplay) {
      this.jobIdToDisplay = ' for job: ' + this.jobIdToDisplay;
    }

    this.rollupStatus = await getBatchRollupStatus({ jobId });

    if (RESOLVED_JOB_STATUSES.includes(this.rollupStatus) === false && this._validateAsyncJob(jobId)) {
      // some arbitrary wait time - for a huge recalculation job, it could take a while to finish
      const waitTimeMs = 10000;
      /* eslint-disable-next-line */
      await new Promise(innerRes => setTimeout(innerRes, waitTimeMs));
      await this._poll(jobId);
    }
  }

  _validateAsyncJob = val => {
    const isValid = isValidAsyncJob(val);
    if (!isValid) {
      this.jobId = '';
      this.rollupStatus = val;
    }
    return isValid;
  };
}
