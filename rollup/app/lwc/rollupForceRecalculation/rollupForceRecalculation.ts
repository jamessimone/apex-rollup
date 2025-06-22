import { api, LightningElement, wire } from 'lwc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import performSerializedFullRecalculation from '@salesforce/apex/Rollup.performSerializedFullRecalculation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import { getRollupMetadata, transformToSerializableChildren } from 'c/rollupUtils';
import type { 
  RollupMetadata, 
  NamespaceInfo, 
  ObjectInfo, 
  PicklistValue,
  WireError,
  DataTableColumn,
  ComboboxChangeEvent,
  DataTableSortEvent,
  DataTableRowSelectionEvent,
  RollupMetadataByCalcItem
} from '../../../../types/rollup-types';

const MAX_ROW_SELECTION: number = 200;

export default class RollupForceRecalculation extends LightningElement {
  private _resolvedBatchStatuses: string[] = ['Completed', 'Failed', 'Aborted'];
  private _localMetadata: RollupMetadataByCalcItem = {};
  private _metadata: Partial<RollupMetadata> = {
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
  private _cmdtFieldNames: string[] = [
    'MasterLabel',
    'DeveloperName',
    'RollupFieldOnCalcItem__c',
    'LookupFieldOnCalcItem__c',
    'LookupFieldOnLookupObject__c',
    'RollupFieldOnLookupObject__c',
    'LookupObject__c'
  ];

  canDisplayCmdtToggle: boolean = false;
  cmdtColumns: DataTableColumn[] = [];
  defaultSortDirection: string = 'asc';
  error: string = '';
  isOrderByRollup: boolean = false;
  isRollingUp: boolean = false;
  maxRowSelection: number = MAX_ROW_SELECTION;
  namespace: string = '';
  rollupMetadataOptions: PicklistValue[] = [];
  rollupOperationValues: PicklistValue[] = [];
  safeObjectName: string = '';
  safeRollupOperationField: string = '';
  selectedMetadata: string | undefined;
  selectedMetadataCMDTRecords: RollupMetadata[] | undefined;
  selectedRows: RollupMetadata[] = [];
  sortDirection: string = 'asc';

  @api
  isCMDTRecalc: boolean = false;

  get rollupOperation(): string {
    return this._metadata[this._getNamespacedFieldName(this.safeRollupOperationField)] || '';
  }
  set rollupOperation(value: string) {
    this._setNamespaceSafeMetadata(this.safeRollupOperationField, value);
  }

  async connectedCallback(): Promise<void> {
    document.title = 'Recalculate Rollup';
    await Promise.all([this._getNamespaceRollupInfo(), this._fetchAvailableCMDT()]);
  }

  @wire(getObjectInfo, { objectApiName: '$safeObjectName' })
  getCMDTObjectInfo({ error, data }: { error?: WireError; data?: ObjectInfo }): void {
    if (data) {
      this._cmdtFieldNames.forEach((fieldName: string) => {
        if (data.fields[fieldName]) {
          this.cmdtColumns.push({ 
            label: data.fields[fieldName].label, 
            fieldName: fieldName, 
            sortable: true 
          });
        }
      });
    } else if (error) {
      this.error = this._formatWireErrors(error);
    }
  }

  @wire(getPicklistValues, { recordTypeId: '012000000000000AAA', fieldApiName: '$safeRollupOperationField' })
  getRollupOperationValues({ error, data }: { error?: WireError; data?: { values: PicklistValue[] } }): void {
    if (data) {
      this.rollupOperationValues = data.values;
    } else if (error) {
      this.error = this._formatWireErrors(error);
    }
  }

  handleComboChange(event: ComboboxChangeEvent): void {
    this.selectedMetadata = event.detail.value;
    this.selectedMetadataCMDTRecords = this._localMetadata[event.detail.value];
  }

  handleChange(event: Event): void {
    const target = event.target as HTMLInputElement;
    const detail = (event as any).detail;
    const value = detail ? detail.value : target.value;
    const limitAmountWithoutNamespace = 'LimitAmount__c';
    this._setNamespaceSafeMetadata(target.name, target.name === limitAmountWithoutNamespace ? Number(value) : value);
    this.isOrderByRollup =
      this.rollupOperation.indexOf('FIRST') !== -1 ||
      this.rollupOperation.indexOf('LAST') !== -1 ||
      this._getNamespaceSafeFieldValue(limitAmountWithoutNamespace) ||
      this.rollupOperation.indexOf('MOST') !== -1;
  }

  handleSort(event: DataTableSortEvent): void {
    const { fieldName, sortDirection } = event.detail;

    if (this.selectedMetadataCMDTRecords) {
      this.selectedMetadataCMDTRecords.sort((a: RollupMetadata, b: RollupMetadata) => {
        let sort = 0;
        if (a[fieldName] > b[fieldName]) {
          sort = 1;
        } else if (b[fieldName] > a[fieldName]) {
          sort = -1;
        }
        return sortDirection === 'asc' ? sort : -sort;
      });
      this.selectedMetadataCMDTRecords = [...this.selectedMetadataCMDTRecords];
    }
    this.sortDirection = sortDirection;
    (this as any).sortedBy = fieldName;
  }

  handleToggle(): void {
    this.rollupOperation = '';
    this.isCMDTRecalc = !this.isCMDTRecalc;
    this.error = '';
  }

  handleRowSelect(event: DataTableRowSelectionEvent): void {
    this.selectedRows = event.detail.selectedRows;
  }

  private async _fetchAvailableCMDT(): Promise<void> {
    (this as any).isLoadingCustomMetadata = true;
    this._localMetadata = await getRollupMetadata();
    (this as any).isLoadingCustomMetadata = false;

    Object.keys(this._localMetadata).forEach((localMeta: string) => {
      if (!this.canDisplayCmdtToggle) {
        this.canDisplayCmdtToggle = true;
      }
      this.rollupMetadataOptions.push({ label: localMeta, value: localMeta });
    });
  }

  private async _getNamespaceRollupInfo(): Promise<void> {
    const namespaceInfo: NamespaceInfo = await getNamespaceInfo();
    if (!this._cmdtFieldNames.find((fieldName: string) => this.safeRollupOperationField === fieldName)) {
      this._cmdtFieldNames.push(this.safeRollupOperationField);
    }
    Object.keys(namespaceInfo).forEach((key: string) => ((this as any)[key] = (namespaceInfo as any)[key]));
    if (this.namespace) {
      this._metadata = Object.assign({}, ...Object.keys(this._metadata).map((key: string) => ({ [this.namespace + key]: this._metadata[key] })));
      this._cmdtFieldNames = this._cmdtFieldNames.map((fieldName: string) => (fieldName.endsWith('__c') ? this._getNamespacedFieldName(fieldName) : fieldName));
    }
  }

  async handleSubmit(event: Event): Promise<void> {
    this.error = '';
    event.preventDefault();

    try {
      let jobId: string;
      if (this.isCMDTRecalc) {
        if (!this.selectedMetadata || this.selectedRows.length === 0) {
          this._displayErrorToast('Select a valid option', 'Child Object(s) must be selected!');
          return;
        }
        this.isRollingUp = true;
        const localMetas: RollupMetadata[] = [...this.selectedRows];
        this._getMetadataWithChildrenRecords(localMetas);
        jobId = await performSerializedBulkFullRecalc({ 
          serializedMetadata: JSON.stringify(localMetas), 
          invokePointName: 'FROM_FULL_RECALC_LWC' 
        });
      } else {
        this.isRollingUp = true;
        this._getMetadataWithChildrenRecords([this._metadata as RollupMetadata]);
        jobId = await performSerializedFullRecalculation({
          metadata: JSON.stringify(this._metadata)
        });
      }

      if (jobId) {
        const jobPoller = this.template?.querySelector('c-rollup-job-poller') as any;
        if (jobPoller) {
          await jobPoller.runJobPoller(jobId);
        }
        this.isRollingUp = false;
      }
    } catch (e: any) {
      const errorMessage: string = Boolean(e.body) && e.body.message ? e.body.message : e.message;
      this._displayErrorToast('An error occurred while rolling up', errorMessage);
      // eslint-disable-next-line
      console.error(e); // in the event you dismiss the toast but still want to see the error
    }
  }

  private _displayErrorToast(title: string, message: string): void {
    const event = new ShowToastEvent({
      title,
      message,
      variant: 'error'
    });
    this.dispatchEvent(event);
    this.error = message;
  }

  private _getMetadataWithChildrenRecords(metadatas: RollupMetadata[]): void {
    const rollupOrderByFieldName: string = this._getNamespacedFieldName(`RollupOrderBys__r`);
    for (const _metadata of metadatas) {
      let children;
      if (this.isCMDTRecalc) {
        children = _metadata[rollupOrderByFieldName] != null ? _metadata[rollupOrderByFieldName] : children;
      } else {
        const possibleOrderByComponent = this.template?.querySelector('c-rollup-order-by') as any;
        if (possibleOrderByComponent) {
          children = possibleOrderByComponent.orderBys;
        }
      }
      transformToSerializableChildren(_metadata, rollupOrderByFieldName, children);
    }
  }

  private _getNamespaceSafeFieldValue(fieldName: string): any {
    return this._metadata[this._getNamespacedFieldName(fieldName)];
  }

  private _setNamespaceSafeMetadata(fieldName: string, value: any): void {
    this._metadata[this._getNamespacedFieldName(fieldName)] = value;
  }

  private _getNamespacedFieldName(fieldName: string): string {
    return this.namespace + fieldName;
  }

  private _formatWireErrors = (error: WireError): string => error.body.message;
}
