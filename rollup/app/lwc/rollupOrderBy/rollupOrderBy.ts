import { api, LightningElement, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import type { 
  RollupOrderByRecord, 
  NamespaceInfo, 
  ObjectInfo, 
  DataTableColumn,
  PicklistValue 
} from '../../../../types/rollup-types';

interface OrderBySchema {
  [fieldName: string]: any;
}

interface FieldDescribe {
  label: string;
  dataType: string;
  apiName: string;
}

// the @salesforce/schema info for CMDT records doesn't work too well ...
let ORDER_BY_SCHEMA: OrderBySchema = {
  FieldName__c: {},
  Ranking__c: {},
  SortOrder__c: {},
  NullSortOrder__c: {}
};

export default class RollupOrderBy extends LightningElement {
  @api
  orderBys: RollupOrderByRecord[] = [];

  columns: DataTableColumn[] = [];
  dataHasLoaded: boolean = false;
  records: RollupOrderByRecord[] = [];
  showModal: boolean = false;

  private _orderByInfo: ObjectInfo | undefined;
  private _currentRecord: Partial<RollupOrderByRecord> = this.getDefaultOrderByObject;
  private _namespaceName: string = '';
  private _objectApiName: string = 'RollupOrderBy__mdt';

  sortOrderOptions: PicklistValue[] = [
    { label: 'Ascending', value: 'Ascending' },
    { label: 'Descending', value: 'Descending' }
  ];

  nullSortOrderOptions: PicklistValue[] = [
    { label: 'Nulls First', value: 'NULLS FIRST' },
    { label: 'Nulls Last', value: 'NULLS LAST' }
  ];

  async connectedCallback(): Promise<void> {
    await this._getNamespaceRollupInfo();
  }

  private async _getNamespaceRollupInfo(): Promise<void> {
    const namespaceInfo: NamespaceInfo = await getNamespaceInfo();
    if (namespaceInfo.namespace) {
      this._namespaceName = namespaceInfo.namespace;
      this._objectApiName = namespaceInfo.safeObjectName;
      ORDER_BY_SCHEMA = Object.assign({}, ...Object.keys(ORDER_BY_SCHEMA).map(key => ({ [this._namespaceName + key]: ORDER_BY_SCHEMA[key] })));
    }
  }

  @wire(getObjectInfo, { objectApiName: '$_objectApiName' })
  getRollupOrderBySchemaData({ data }: { data?: ObjectInfo }): void {
    if (data) {
      this.dataHasLoaded = true;
      this._orderByInfo = data;
      this.columns = this._getDatatableColumns();
    }
  }

  createNewRecord(): void {
    this.showModal = true;
  }

  handleRecordChange(event: Event): void {
    const target = event.target as HTMLElement;
    const input = event.target as HTMLInputElement;
    const detail = (event as any).detail;
    
    if (target.dataset.id) {
      this._currentRecord[target.dataset.id] = detail ? detail.value : input.value;
    }
  }

  closeModal(): void {
    this.showModal = false;
  }

  handleKeyDown(event: KeyboardEvent): void {
    if (event.code === 'Escape') {
      this.closeModal();
    } else if (event.ctrlKey === true && event.code === 'KeyS') {
      this.handleCreate();
    }
  }

  handleCreate(): void {
    const rankingField = this.ranking;
    if (!this._currentRecord[rankingField.apiName]) {
      this._currentRecord[rankingField.apiName] = this.currentOrderBySize;
    }
    const flattenedRankings: number[] = this.orderBys.map(ordering => ordering[rankingField.apiName]);
    const hasRankingAlreadyBeenUsed: boolean = flattenedRankings.includes(Number(this._currentRecord[rankingField.apiName]));
    if (hasRankingAlreadyBeenUsed) {
      this._currentRecord[rankingField.apiName] = flattenedRankings.includes(this.currentOrderBySize) ? this.currentOrderBySize + 1 : this.currentOrderBySize;
    }
    this.orderBys = [...this.orderBys, this._currentRecord as RollupOrderByRecord].sort((first, second) => {
      let sortIndex = 0;
      if (first[rankingField.apiName] < second[rankingField.apiName]) {
        sortIndex = -1;
      } else if (first[rankingField.apiName] > second[rankingField.apiName]) {
        sortIndex = 1;
      }
      return sortIndex;
    });
    this._currentRecord = this.getDefaultOrderByObject;
    this.closeModal();
  }

  get ranking(): FieldDescribe {
    return ORDER_BY_SCHEMA[this._namespaceName + 'Ranking__c'];
  }

  get fieldName(): FieldDescribe {
    return ORDER_BY_SCHEMA[this._namespaceName + 'FieldName__c'];
  }

  get sortOrder(): FieldDescribe {
    return ORDER_BY_SCHEMA[this._namespaceName + 'SortOrder__c'];
  }

  get nullSortOrder(): FieldDescribe {
    return ORDER_BY_SCHEMA[this._namespaceName + 'NullSortOrder__c'];
  }

  get currentOrderBySize(): number {
    return this.orderBys.length;
  }

  get getDefaultOrderByObject(): Partial<RollupOrderByRecord> {
    return {};
  }

  private _getDatatableColumns(): DataTableColumn[] {
    return Object.keys(ORDER_BY_SCHEMA).map((fieldKey: string) => {
      const fieldDescribe = this._orderByInfo!.fields[fieldKey];
      ORDER_BY_SCHEMA[fieldKey] = fieldDescribe;
      const column: DataTableColumn = { 
        fieldName: fieldKey, 
        label: fieldDescribe.label, 
        sortable: true,
        type: fieldDescribe.dataType?.toLowerCase() 
      };
      if (column.type === 'string') {
        column.type = 'text';
      }
      return column;
    });
  }
}
