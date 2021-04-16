import { api, LightningElement, wire } from 'lwc';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';
import performFullRecalculation from '@salesforce/apex/Rollup.performFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

const NO_PROCESS_ID = 'No process Id';

export default class RollupForceRecalculation extends LightningElement {
  rollupData = {
    opFieldOnCalcItem: '',
    lookupFieldOnCalcItem: '',
    lookupFieldOnLookupObject: '',
    rollupFieldOnLookupObject: '',
    lookupSObjectName: '',
    calcItemSObjectName: '',
    operationName: '',
    potentialWhereClause: '',
    potentialConcatDelimiter: ''
  };
  @api isCMDTRecalc = false;
  rollupMetadataOptions = [];
  selectedMetadata;
  selectedMetadataCMDTRecords;

  isRollingUp = false;
  rollupStatus;
  error = '';
  cmdtColumns = [];

  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];
  _hasRendered = false;
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

  async renderedCallback() {
    if (!this._hasRendered) {
      document.title = 'Recalculate Rollup';
      this._hasRendered = true;
      await this._fetchAvailableCMDT();
    }
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
    this.rollupData[event.target.name] = event.target.value;
  }

  handleToggle() {
    this.rollupStatus = null;
    this.isCMDTRecalc = !this.isCMDTRecalc;
  }

  async _fetchAvailableCMDT() {
    this._localMetadata = await getRollupMetadataByCalcItem();
    Object.keys(this._localMetadata)
      .sort()
      .forEach(localMeta => {
        this.rollupMetadataOptions.push({ label: localMeta, value: localMeta });
      });
  }

  async handleSubmit(event) {
    this.error = '';
    event.preventDefault();

    try {
      let jobId;
      if (this.isCMDTRecalc) {
        if (!this.selectedMetadata) {
          this._displayErrorToast('Select a valid option', 'Calc item must be selected!');
          return;
        }

        const localMetas = this._localMetadata[this.selectedMetadata];
        const matchingMetadata = [];
        // we have to transform the data slightly to conform to what the Apex deserializer expects by removing relationship fields
        for (let localMeta of localMetas) {
          const copiedMetadata = {};
          Object.keys(localMeta).forEach(key => {
            if (key.indexOf('__r') === -1) {
              copiedMetadata[key] = localMeta[key];
            }
          });
          matchingMetadata.push(copiedMetadata);
        }
        jobId = await performBulkFullRecalc({ matchingMetadata });
      } else {
        jobId = await performFullRecalculation(this.rollupData);
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
        clearInterval(timeoutId);
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
