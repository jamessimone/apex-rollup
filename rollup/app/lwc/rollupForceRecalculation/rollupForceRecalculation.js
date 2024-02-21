import { api, LightningElement, wire } from 'lwc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import { getRollupMetadata, transformToSerializableChildren } from 'c/rollupUtils';

const MAX_ROW_SELECTION = 200;

export default class RollupForceRecalculation extends LightningElement {
  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];
  _localMetadata = {};
  _metadata = {
    RollupFieldOnCalcItem__c: '',
    LookupFieldOnCalcItem__c: '',
    LookupFieldOnLookupObject__c: '',
    RollupFieldOnLookupObject__c: '',
    LookupObject__c: '',
    CalcItem__c: '',
    RollupOperation__c: '',
    CalcItemWhereClause__c: '',
    ConcatDelimiter__c: '',
    SplitConcatDelimiterOnCalcItem__c: false,
    LimitAmount__c: null
  };
  _cmdtFieldNames = [
    'MasterLabel',
    'DeveloperName',
    'RollupFieldOnCalcItem__c',
    'LookupFieldOnCalcItem__c',
    'LookupFieldOnLookupObject__c',
    'RollupFieldOnLookupObject__c',
    'LookupObject__c'
  ];

  canDisplayCmdtToggle = false;
  cmdtColumns = [];
  defaultSortDirection = 'asc';
  error = '';
  isOrderByRollup = false;
  isRollingUp = false;
  jobIdToDisplay;
  maxRowSelection = MAX_ROW_SELECTION;
  namespace = '';
  rollupMetadataOptions = [];
  rollupOperationValues = [];
  rollupStatus;
  safeObjectName = '';
  safeRollupOperationField = '';
  selectedMetadata;
  selectedMetadataCMDTRecords;
  selectedRows = [];
  sortDirection = 'asc';

  @api
  isCMDTRecalc = false;

  get rollupOperation() {
    return this._metadata[this._getNamespacedFieldName(this.safeRollupOperationField)] || '';
  }
  set rollupOperation(value) {
    this._setNamespaceSafeMetadata(this.safeRollupOperationField, value);
  }

  async connectedCallback() {
    document.title = 'Recalculate Rollup';
    await Promise.all([this._getNamespaceRollupInfo(), this._fetchAvailableCMDT()]);
  }

  @wire(getObjectInfo, { objectApiName: '$safeObjectName' })
  getCMDTObjectInfo({ error, data }) {
    if (data) {
      this._cmdtFieldNames.forEach(fieldName => {
        if (data.fields[fieldName]) {
          this.cmdtColumns.push({ label: data.fields[fieldName].label, fieldName: fieldName, sortable: true });
        }
      });
    } else if (error) {
      this.error = this._formatWireErrors(error);
    }
  }

  @wire(getPicklistValues, { recordTypeId: '012000000000000AAA', fieldApiName: '$safeRollupOperationField' })
  getRollupOperationValues({ error, data }) {
    if (data) {
      this.rollupOperationValues = data.values;
    } else if (error) {
      this.error = this._formatWireErrors(error);
    }
  }

  handleComboChange(event) {
    this.selectedMetadata = event.detail.value;
    this.selectedMetadataCMDTRecords = this._localMetadata[event.detail.value];
  }

  handleChange(event) {
    const value = event.detail ? event.detail.value : event.target.value;
    const limitAmountWithoutNamespace = 'LimitAmount__c';
    this._setNamespaceSafeMetadata(event.target.name, event.target.name === limitAmountWithoutNamespace ? Number(value) : value);
    this.isOrderByRollup =
      this.rollupOperation.indexOf('FIRST') !== -1 ||
      this.rollupOperation.indexOf('LAST') !== -1 ||
      this._getNamespaceSafeFieldValue(limitAmountWithoutNamespace) ||
      this.rollupOperation.indexOf('MOST') !== -1;
  }

  handleSort(event) {
    const { fieldName, sortDirection } = event.detail;

    this.selectedMetadataCMDTRecords.sort((a, b) => {
      let sort = 0;
      if (a[fieldName] > b[fieldName]) {
        sort = 1;
      } else if (b[fieldName] > a[fieldName]) {
        sort = -1;
      }
      return sortDirection === 'asc' ? sort : -sort;
    });
    this.selectedMetadataCMDTRecords = [...this.selectedMetadataCMDTRecords];
    this.sortDirection = sortDirection;
    this.sortedBy = fieldName;
  }

  handleToggle() {
    this.jobIdToDisplay = null;
    this.rollupStatus = null;
    this.rollupOperation = null;
    this.isCMDTRecalc = !this.isCMDTRecalc;
    this.error = '';
  }

  handleRowSelect(event) {
    this.selectedRows = event.detail.selectedRows;
  }

  async _fetchAvailableCMDT() {
    this.isLoadingCustomMetadata = true;
    this._localMetadata = await getRollupMetadata();
    this.isLoadingCustomMetadata = false;

    Object.keys(this._localMetadata).forEach(localMeta => {
      if (!this.canDisplayCmdtToggle) {
        this.canDisplayCmdtToggle = true;
      }
      this.rollupMetadataOptions.push({ label: localMeta, value: localMeta });
    });
  }

  async _getNamespaceRollupInfo() {
    const namespaceInfo = await getNamespaceInfo();
    if (!this._cmdtFieldNames.find(fieldName => this.safeRollupOperationField === fieldName)) {
      this._cmdtFieldNames.push(this.safeRollupOperationField);
    }
    Object.keys(namespaceInfo).forEach(key => (this[key] = namespaceInfo[key]));
    if (this.namespace) {
      this._metadata = Object.assign({}, ...Object.keys(this._metadata).map(key => ({ [this.namespace + key]: this._metadata[key] })));
      this._cmdtFieldNames = this._cmdtFieldNames.map(fieldName => (fieldName.endsWith('__c') ? this._getNamespacedFieldName(fieldName) : fieldName));
    }
  }

  async handleSubmit(event) {
    this.error = '';
    event.preventDefault();

    try {
      let jobId;
      if (this.isCMDTRecalc) {
        if (!this.selectedMetadata || this.selectedRows.length === 0) {
          this._displayErrorToast('Select a valid option', 'Child Object(s) must be selected!');
          return;
        }
        this.isRollingUp = true;
        const localMetas = [...this.selectedRows];
        this._getMetadataWithChildrenRecords(localMetas);
        jobId = await performSerializedBulkFullRecalc({ serializedMetadata: JSON.stringify(localMetas), invokePointName: 'FROM_FULL_RECALC_LWC' });
      } else {
        this.isRollingUp = true;
        this._getMetadataWithChildrenRecords([this._metadata]);
        jobId = await performSerializedFullRecalculation({
          metadata: JSON.stringify(this._metadata)
        });
      }
      await this._getBatchJobStatus(jobId);
    } catch (e) {
      const errorMessage = Boolean(e.body) && e.body.message ? e.body.message : e.message;
      this._displayErrorToast('An error occurred while rolling up', errorMessage);
      // eslint-disable-next-line
      console.error(e); // in the event you dismiss the toast but still want to see the error
    }
  }

  async _getBatchJobStatus(jobId) {
    if (!jobId) {
      this.rollupStatus = 'Job failed to enqueue, check logs for more info';
      return Promise.resolve();
    }

    this.jobIdToDisplay = jobId;
    if (this.jobIdToDisplay) {
      this.jobIdToDisplay = ' for job: ' + this.jobIdToDisplay;
    }
    this.rollupStatus = await getBatchRollupStatus({ jobId });

    const statusPromise = new Promise(resolve => {
      let timeoutId;
      if (this._resolvedBatchStatuses.includes(this.rollupStatus) === false && this._validateAsyncJob(jobId)) {
        // some arbitrary wait time - for a huge batch job, it could take ages to resolve
        const waitTimeMs = 10000;
        /* eslint-disable-next-line */
        timeoutId = setTimeout(() => this._getBatchJobStatus(jobId), waitTimeMs);
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
    const rollupOrderByFieldName = this._getNamespacedFieldName(`RollupOrderBys__r`);
    for (const _metadata of metadatas) {
      let children;
      if (this.isCMDTRecalc) {
        children = _metadata[rollupOrderByFieldName] != null ? _metadata[rollupOrderByFieldName] : children;
      } else {
        const possibleOrderByComponent = this.template.querySelector('c-rollup-order-by');
        if (possibleOrderByComponent) {
          children = possibleOrderByComponent.orderBys;
        }
      }
      transformToSerializableChildren(_metadata, rollupOrderByFieldName, children);
    }
  }

  _validateAsyncJob(val) {
    const isValidAsyncJob = val?.slice(0, 3) === '707';
    if (!isValidAsyncJob) {
      this.jobIdToDisplay = '';
      this.rollupStatus = val;
    }
    return isValidAsyncJob;
  }

  _getNamespaceSafeFieldValue(fieldName) {
    return this._metadata[this._getNamespacedFieldName(fieldName)];
  }

  _setNamespaceSafeMetadata(fieldName, value) {
    this._metadata[this._getNamespacedFieldName(fieldName)] = value;
  }

  _getNamespacedFieldName(fieldName) {
    return this.namespace + fieldName;
  }

  _formatWireErrors = error => error.body.message;
}
