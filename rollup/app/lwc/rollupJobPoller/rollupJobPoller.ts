import { api, LightningElement } from 'lwc';

import { isValidAsyncJob } from 'c/rollupUtils';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';

const RESOLVED_JOB_STATUSES: string[] = ['Completed', 'Failed', 'Aborted'];

export default class RollupJobPoller extends LightningElement {
  jobIdToDisplay: string | undefined;
  rollupStatus: string | undefined;

  @api
  async runJobPoller(jobId: string | null | undefined): Promise<void> {
    return this._poll(jobId);
  }

  private async _poll(jobId: string | null | undefined): Promise<void> {
    if (!jobId) {
      this.rollupStatus = 'failed to enqueue, check Apex Debug Logs for more info';
      return;
    }

    this.jobIdToDisplay = jobId;
    if (this.jobIdToDisplay) {
      this.jobIdToDisplay = ' for job: ' + this.jobIdToDisplay;
    }

    this.rollupStatus = await getBatchRollupStatus({ jobId });

    if (this.rollupStatus && RESOLVED_JOB_STATUSES.includes(this.rollupStatus) === false && this._validateAsyncJob(jobId)) {
      // some arbitrary wait time - for a huge recalculation job, it could take a while to finish
      const waitTimeMs: number = 10000;
      /* eslint-disable-next-line */
      await new Promise<void>(innerRes => setTimeout(innerRes, waitTimeMs));
      await this._poll(jobId);
    }
  }

  private _validateAsyncJob = (val: string | null | undefined): boolean => {
    const isValid: boolean = isValidAsyncJob(val);
    if (!isValid) {
      this.jobIdToDisplay = '';
      this.rollupStatus = val ?? '';
    }
    return isValid;
  };
}
