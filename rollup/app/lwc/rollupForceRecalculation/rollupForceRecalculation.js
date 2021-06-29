import { api, LightningElement, wire } from 'lwc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import { getRollupMetadata } from 'c/rollupUtils';

const NO_PROCESS_ID = 'No process Id';
const MAX_ROW_SELECTION = 200;

export default class RollupForceRecalculation extends LightningElement {
  metadata = {
    RollupFieldOnCalcItem__c: '',
    LookupFieldOnCalcItem__c: '',
    LookupFieldOnLookupObject__c: '',
    RollupFieldOnLookupObject__c: '',
    LookupObject__c: '',
    CalcItem__c: '',
    RollupOperation__c: '',
    CalcItemWhereClause__c: '',
    OrderByFirstLast__c: '',
    ConcatDelimiter__c: ''
  };

  @api isCMDTRecalc = false;

  selectedRows = [];
  rollupMetadataOptions = [];
  cmdtColumns = [];

  maxRowSelection = MAX_ROW_SELECTION;
  selectedMetadata;
  selectedMetadataCMDTRecords;

  isRollingUp = false;
  rollupStatus;
  error = '';

  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];
  _localMetadata = {};
  _cmdtFieldNames = [
    'MasterLabel',
    'DeveloperName',
    'RollupOperation__c',
    'RollupFieldOnCalcItem__c',
    'LookupFieldOnCalcItem__c',
    'LookupFieldOnLookupObject__c',
    'RollupFieldOnLookupObject__c',
    'LookupObject__c'
  ];

  async connectedCallback() {
    document.title = 'Recalculate Rollup';
    await this._fetchAvailableCMDT();
  }

  @wire(getObjectInfo, { objectApiName: 'Rollup__mdt' })
  getCMDTObjectInfo({ error, data }) {
    if (data) {
      this._cmdtFieldNames.forEach(fieldName => {
        this.cmdtColumns.push({ label: data.fields[fieldName].label, fieldName: fieldName });
      });
    } else if (error) {
      this.error = error;
    }
  }

  handleComboChange(event) {
    this.selectedMetadata = event.detail.value;
    this.selectedMetadataCMDTRecords = this._localMetadata[event.detail.value];
  }

  handleChange(event) {
    this.metadata[event.target.name] = event.target.value;
  }

  handleToggle() {
    this.rollupStatus = null;
    this.isCMDTRecalc = !this.isCMDTRecalc;
    this.error = '';
  }

  handleRowSelect(event) {
    this.selectedRows = event.detail.selectedRows;
  }

  async _fetchAvailableCMDT() {
    this._localMetadata = await getRollupMetadata();

    Object.keys(this._localMetadata).forEach(localMeta => {
      this.rollupMetadataOptions.push({ label: localMeta, value: localMeta });
    });
  }

  async handleSubmit(event) {
    this.error = '';
    event.preventDefault();

    try {
      let jobId;
      if (this.isCMDTRecalc) {
        if (!this.selectedMetadata || this.selectedRows.length === 0) {
          this._displayErrorToast('Select a valid option', 'Calc item(s) must be selected!');
          return;
        }

        const localMetas = [...this.selectedRows];

        jobId = await performBulkFullRecalc({ matchingMetadata: localMetas, invokePointName: 'FROM_LWC' });
      } else {
        jobId = await performFullRecalculation({ metadata: this.metadata });
      }
      await this._getBatchJobStatus(jobId);
    } catch (e) {
      const errorMessage = !!e.body && e.body.message ? e.body.message : e.message;
      this._displayErrorToast('An error occurred while rolling up', errorMessage);
      console.error(e); // in the event you dismiss the toast but still want to see the error
    }
  }

  async _getBatchJobStatus(jobId) {
    if (!jobId || jobId === NO_PROCESS_ID) {
      this.rollupStatus = 'Completed';
      return Promise.resolve();
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
        clearTimeout(timeoutId);
        resolve();
      }
    });
    await statusPromise;
  }

  _displayErrorToast(title, message) {
    const event = new ShowToastEvent({
      title,
      message,
      variant: 'error'
    });
    this.dispatchEvent(event);
    this.error = message;
  }
}
