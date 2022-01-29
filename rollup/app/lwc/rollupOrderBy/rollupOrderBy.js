import { api, LightningElement, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

// the @salesforce/schema info for CMDT records doesn't work too well ...
const ORDER_BY_SCHEMA = {
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

  sortOrderOptions = [
    { label: 'Ascending', value: 'Ascending' },
    { label: 'Descending', value: 'Descending' }
  ];

  nullSortOrderOptions = [
    { label: 'Nulls First', value: 'NULLS FIRST' },
    { label: 'Nulls Last', value: 'NULLS LAST' }
  ];

  @wire(getObjectInfo, { objectApiName: 'RollupOrderBy__mdt' })
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
    if (!this._currentRecord[this.ranking.fieldName]) {
      this._currentRecord[this.ranking.fieldName] = this.currentOrderBySize;
    }
    if (this.orderBys.length > 0) {
      // TODO - update ranking if the one being submitted has already been chosen?
    }
    this.orderBys = [...this.orderBys, this._currentRecord].sort((first, second) => {
      let sortIndex = 0;
      if (first.Ranking__c < second.Ranking__c) {
        sortIndex = -1;
      } else if (first.Ranking__c > second.Ranking__c) {
        sortIndex = 1;
      }
      return sortIndex;
    });
    this._currentRecord = this.getDefaultOrderByObject;
    this.closeModal();
  }

  get ranking() {
    return ORDER_BY_SCHEMA.Ranking__c;
  }

  get fieldName() {
    return ORDER_BY_SCHEMA.FieldName__c;
  }

  get sortOrder() {
    return ORDER_BY_SCHEMA.SortOrder__c;
  }

  get nullSortOrder() {
    return ORDER_BY_SCHEMA.NullSortOrder__c;
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
