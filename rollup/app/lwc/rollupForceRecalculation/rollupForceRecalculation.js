import { api, LightningElement, wire } from 'lwc';
import getNamespaceSafeRollupOperationField from '@salesforce/apex/Rollup.getNamespaceSafeRollupOperationField';
import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import { getRollupMetadata } from 'c/rollupUtils';

const MAX_ROW_SELECTION = 200;

export default class RollupForceRecalculation extends LightningElement {
  @api
  isCMDTRecalc = false;

  selectedRows = [];
  rollupMetadataOptions = [];
  cmdtColumns = [];
  rollupOperationValues = [];

  maxRowSelection = MAX_ROW_SELECTION;
  selectedMetadata;
  selectedMetadataCMDTRecords;

  isRollingUp = false;
  isOrderByRollup = false;
  rollupStatus;
  jobIdToDisplay;
  error = '';
  canDisplayCmdtToggle = false;

  _resolvedBatchStatuses = ['Completed', 'Failed', 'Aborted'];
  _localMetadata = {};
  _rollupOperationFieldName = 'RollupOperation__c';
  _cmdtFieldNames = [
    'MasterLabel',
    'DeveloperName',
    this._rollupOperationFieldName,
    'RollupFieldOnCalcItem__c',
    'LookupFieldOnCalcItem__c',
    'LookupFieldOnLookupObject__c',
    'RollupFieldOnLookupObject__c',
    'LookupObject__c'
  ];
  _namespaceSafeRollupOperationField = '';
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

  get namespaceName() {
    const splitForUnderscores = this._namespaceSafeObjectName.split('__');
    return splitForUnderscores.length > 2 ? splitForUnderscores[0] + '__' : '';
  }

  get rollupOperation() {
    return this._metadata[this._getNamespacedFieldName(this._rollupOperationFieldName)] || '';
  }
  set rollupOperation(value) {
    this._setNamespaceSafeMetadata(this._rollupOperationFieldName, value);
  }

  // Technically each of these only requires a getter
  // but in order to be used as reactive wire props, a setter is also needed
  get _namespaceSafeRollupOperation() {
    return this._namespaceSafeRollupOperationField;
  }
  set _namespaceSafeRollupOperation(value) {
    this._namespaceSafeRollupOperationField = value;
  }

  get _namespaceSafeObjectName() {
    return this._namespaceSafeRollupOperationField.split('.')[0];
  }
  set _namespaceSafeObjectName(value) {
    this._namespaceSafeRollupOperationField = value;
  }

  async connectedCallback() {
    document.title = 'Recalculate Rollup';
    await Promise.all([this._fetchAvailableCMDT(), this._getNamespaceRollupInfo()]);
  }

  @wire(getObjectInfo, { objectApiName: '$_namespaceSafeObjectName' })
  getCMDTObjectInfo({ error, data }) {
    if (data) {
      this._cmdtFieldNames.forEach(fieldName => {
        this.cmdtColumns.push({ label: data.fields[fieldName].label, fieldName: fieldName });
      });
    } else if (error) {
      this.error = error;
    }
  }

  @wire(getPicklistValues, { recordTypeId: '012000000000000AAA', fieldApiName: '$_namespaceSafeRollupOperationField' })
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
    const limitAmountWithoutNamespace = 'LimitAmount__c';
    this._setNamespaceSafeMetadata(event.target.name, event.target.name === limitAmountWithoutNamespace ? Number(value) : value);
    this.isOrderByRollup =
      this.rollupOperation.indexOf('FIRST') !== -1 ||
      this.rollupOperation.indexOf('LAST') !== -1 ||
      this._getNamespaceSafeFieldValue(limitAmountWithoutNamespace) ||
      this.rollupOperation.indexOf('MOST') !== -1;
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
    this._localMetadata = await getRollupMetadata();

    Object.keys(this._localMetadata).forEach(localMeta => {
      if (!this.canDisplayCmdtToggle) {
        this.canDisplayCmdtToggle = true;
      }
      this.rollupMetadataOptions.push({ label: localMeta, value: localMeta });
    });
  }

  async _getNamespaceRollupInfo() {
    this._namespaceSafeRollupOperation = await getNamespaceSafeRollupOperationField();
    if (this.namespaceName) {
      this._metadata = Object.assign({}, ...Object.keys(this._metadata).map(key => ({ [this.namespaceName + key]: this._metadata[key] })));
      this._cmdtFieldNames = this._cmdtFieldNames.map(fieldName => this._getNamespacedFieldName(fieldName));
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

        const localMetas = [...this.selectedRows];
        this._getMetadataWithChildrenRecords(localMetas);
        jobId = await performSerializedBulkFullRecalc({ serializedMetadata: JSON.stringify(localMetas), invokePointName: 'FROM_FULL_RECALC_LWC' });
      } else {
        this._getMetadataWithChildrenRecords([this._metadata]);
        jobId = await performSerializedFullRecalculation({
          metadata: JSON.stringify(this._metadata)
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
    if (!jobId) {
      this.rollupStatus = 'Job failed to enqueue, check logs for more info';
      return Promise.resolve();
    }
    this.isRollingUp = true;

    this.jobIdToDisplay = jobId;
    this.rollupStatus = await getBatchRollupStatus({ jobId });

    // some arbitrary wait time - for a huge batch job, it could take ages to resolve
    const statusPromise = new Promise(resolve => {
      let timeoutId;
      if (this._resolvedBatchStatuses.includes(this.rollupStatus) === false && this._validateAsyncJob(jobId)) {
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
      if (children && !children.totalSize) {
        _metadata[rollupOrderByFieldName] = { totalSize: children?.length, done: true, records: children };
      }
    }
  }

  _validateAsyncJob(val) {
    const isValidAsyncJob = val?.slice(0, 3) === '707';
    if (!isValidAsyncJob) {
      this.jobIdToDisplay = 'no job Id';
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
    return this.namespaceName + fieldName;
  }
}
