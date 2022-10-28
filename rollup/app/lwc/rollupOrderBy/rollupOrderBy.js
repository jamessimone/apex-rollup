import { api, LightningElement, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';

// the @salesforce/schema info for CMDT records doesn't work too well ...
let ORDER_BY_SCHEMA = {
  FieldName__c: {},
  Ranking__c: {},
  SortOrder__c: {},
  NullSortOrder__c: {}
};

export default class RollupOrderBy extends LightningElement {
  @api
  orderBys = [];

  columns = [];
  dataHasLoaded = false;
  records = [];
  showModal = false;

  _orderByInfo;
  _currentRecord = this.getDefaultOrderByObject;
  _namespaceName = '';
  _objectApiName = 'RollupOrderBy__mdt';

  sortOrderOptions = [
    { label: 'Ascending', value: 'Ascending' },
    { label: 'Descending', value: 'Descending' }
  ];

  nullSortOrderOptions = [
    { label: 'Nulls First', value: 'NULLS FIRST' },
    { label: 'Nulls Last', value: 'NULLS LAST' }
  ];

  async connectedCallback() {
    await this._getNamespaceRollupInfo();
  }

  async _getNamespaceRollupInfo() {
    const namespaceInfo = await getNamespaceInfo();
    if (namespaceInfo.namespace) {
      this._namespaceName = namespaceInfo.namespace;
      this._objectApiName = namespaceInfo.safeObjectName;
      ORDER_BY_SCHEMA = Object.assign({}, ...Object.keys(ORDER_BY_SCHEMA).map(key => ({ [this._namespaceName + key]: ORDER_BY_SCHEMA[key] })));
    }
  }

  @wire(getObjectInfo, { objectApiName: '$_objectApiName' })
  getRollupOrderBySchemaData({ data }) {
    if (data) {
      this.dataHasLoaded = true;
      this._orderByInfo = data;
      this.columns = this._getDatatableColumns();
    }
  }

  createNewRecord() {
    this.showModal = true;
  }

  handleRecordChange(event) {
    this._currentRecord[event.target.dataset.id] = event.detail ? event.detail.value : event.target.value;
  }

  closeModal() {
    this.showModal = false;
  }

  handleKeyDown(event) {
    if (event.code === 'Escape') {
      this.closeModal();
    } else if (event.ctrlKey === true && event.code === 'KeyS') {
      this.handleCreate();
    }
  }

  handleCreate() {
    if (!this._currentRecord[this.ranking.apiName]) {
      this._currentRecord[this.ranking.apiName] = this.currentOrderBySize;
    }
    const flattenedRankings = this.orderBys.map(ordering => ordering[this.ranking.apiName]);
    const hasRankingAlreadyBeenUsed = flattenedRankings.includes(Number(this._currentRecord[this.ranking.apiName]));
    if (hasRankingAlreadyBeenUsed) {
      this._currentRecord[this.ranking.apiName] = flattenedRankings.includes(this.currentOrderBySize) ? this.currentOrderBySize + 1 : this.currentOrderBySize;
    }
    this.orderBys = [...this.orderBys, this._currentRecord].sort((first, second) => {
      let sortIndex = 0;
      if (first[this.ranking.apiName] < second[this.ranking.apiName]) {
        sortIndex = -1;
      } else if (first[this.ranking.apiName] > second[this.ranking.apiName]) {
        sortIndex = 1;
      }
      return sortIndex;
    });
    this._currentRecord = this.getDefaultOrderByObject;
    this.closeModal();
  }

  get ranking() {
    return ORDER_BY_SCHEMA[this._namespaceName + 'Ranking__c'];
  }

  get fieldName() {
    return ORDER_BY_SCHEMA[this._namespaceName + 'FieldName__c'];
  }

  get sortOrder() {
    return ORDER_BY_SCHEMA[this._namespaceName + 'SortOrder__c'];
  }

  get nullSortOrder() {
    return ORDER_BY_SCHEMA[this._namespaceName + 'NullSortOrder__c'];
  }

  get currentOrderBySize() {
    return this.orderBys.length;
  }

  get getDefaultOrderByObject() {
    return {};
  }

  _getDatatableColumns() {
    return Object.keys(ORDER_BY_SCHEMA).map(fieldKey => {
      const fieldDescribe = this._orderByInfo.fields[fieldKey];
      ORDER_BY_SCHEMA[fieldKey] = fieldDescribe;
      const column = { fieldName: fieldKey, label: fieldDescribe.label, type: fieldDescribe.dataType?.toLowerCase() };
      if (column.type === 'string') {
        column.type = 'text';
      }
      return column;
    });
  }
}
