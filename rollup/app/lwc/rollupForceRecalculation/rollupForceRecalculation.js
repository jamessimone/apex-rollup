import { api, LightningElement, wire } from 'lwc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

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
    ConcatDelimiter__c: '',
    SplitConcatDelimiterOnCalcItem__c: false
  };

  @api isCMDTRecalc = false;

  selectedRows = [];
  rollupMetadataOptions = [];
  cmdtColumns = [];
  rollupOperationValues = [];

  maxRowSelection = MAX_ROW_SELECTION;
  selectedMetadata;
  selectedMetadataCMDTRecords;

  isRollingUp = false;
  isFirstLast = false;
  rollupStatus;
  error = '';

  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted', NO_PROCESS_ID];
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

  @wire(getPicklistValues, { recordTypeId: '012000000000000AAA', fieldApiName: 'Rollup__mdt.RollupOperation__c' })
  getRollupOperationValues({ error, data }) {
    if (data) {
      this.rollupOperationValues = data.values;
    } else if (error) {
      this.error = error;
    }
  }

  handleComboChange(event) {
    this.selectedMetadata = event.detail.value;
    this.selectedMetadataCMDTRecords = this._localMetadata[event.detail.value];
  }

  handleChange(event) {
    const value = event.detail ? event.detail.value : event.target.value;
    this.metadata[event.target.name] = value;
    this.isFirstLast = this.rollupOperation.indexOf('FIRST') !== -1 || this.rollupOperation.indexOf('LAST') !== -1;
  }

  handleToggle() {
    this.rollupStatus = null;
    this.rollupOperation = null;
    this.isCMDTRecalc = !this.isCMDTRecalc;
    this.error = '';
  }

  handleRowSelect(event) {
    this.selectedRows = event.detail.selectedRows;
  }

  get rollupOperation() {
    return this.metadata.RollupOperation__c;
  }
  set rollupOperation(value) {
    this.metadata.RollupOperation__c = value;
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
        this._getMetadataWithChildrenRecords(localMetas);
        jobId = await performSerializedBulkFullRecalc({ serializedMetadata: JSON.stringify(localMetas), invokePointName: 'FROM_FULL_RECALC_LWC' });
      } else {
        this._getMetadataWithChildrenRecords([this.metadata]);
        jobId = await performSerializedFullRecalculation({
          metadata: JSON.stringify(this.metadata)
        });
      }
      await this._getBatchJobStatus(jobId);
    } catch (e) {
      const errorMessage = !!e.body && e.body.message ? e.body.message : e.message;
      this._displayErrorToast('An error occurred while rolling up', errorMessage);
      console.error(e); // in the event you dismiss the toast but still want to see the error
    }
  }

  async _getBatchJobStatus(jobId) {
    if (!jobId || this._resolvedBatchStatuses.includes(jobId)) {
      this.rollupStatus = jobId;
      return Promise.resolve();
    }
    this.isRollingUp = true;

    this.rollupStatus = await getBatchRollupStatus({ jobId });

    // some arbitrary wait time - for a huge batch job, it could take ages to resolve
    const statusPromise = new Promise(resolve => {
      let timeoutId;
      if (this._resolvedBatchStatuses.includes(this.rollupStatus) === false) {
        timeoutId = setTimeout(() => this._getBatchJobStatus(jobId), 3000);
      } else {
        this.isRollingUp = false;
        clearTimeout(timeoutId);
        resolve();
      }
    });
    return statusPromise;
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

  _getMetadataWithChildrenRecords(metadatas) {
    for (const metadata of metadatas) {
      let children;
      if (this.isCMDTRecalc) {
        children = metadata.RollupOrderBys__r != null ? metadata.RollupOrderBys__r : children;
      } else {
        const possibleOrderByComponent = this.template.querySelector('c-rollup-order-by');
        if (possibleOrderByComponent) {
          children = possibleOrderByComponent.orderBys;
        }
      }
      if (children) {
        metadata.RollupOrderBys__r = { totalSize: children?.length, done: true, records: children };
      }
    }
  }
}
