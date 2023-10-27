import { api, LightningElement, wire } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import { getRecord } from 'lightning/uiRecordApi';

import { getRollupMetadata, transformToSerializableChildren } from 'c/rollupUtils';

const DELIMITER = ' ||| ';

export default class RecalculateParentRollupFlexipage extends LightningElement {
  @api recordId;
  @api objectApiName;
  @api alternativeParentFieldName;

  isRecalculating = false;
  isValid = false;

  _hasPopulatedAdditionalFields = false;
  _matchingMetas = [];
  _namespaceInfo = {};

  async connectedCallback() {
    await this._setup();
  }

  renderedCallback() {
    if (this.alternativeParentFieldName && !this._hasPopulatedAdditionalFields) {
      this._hasPopulatedAdditionalFields = true;
      this.alternativeField = { fieldApiName: this.alternativeParentFieldName, objectApiName: this.objectApiName };
    }
  }

  @wire(getRecord, { recordId: '$recordId', fields: [], optionalFields: '$alternativeField' })
  wiredRecord({ data }) {
    if (data && this.alternativeParentFieldName) {
      this.recordId = data.fields[this.alternativeParentFieldName]?.value ?? this.recordId;
      this._setup();
    }
  }

  async handleClick() {
    this.isRecalculating = true;

    if (this._matchingMetas.length > 0) {
      try {
        await performSerializedBulkFullRecalc({ serializedMetadata: JSON.stringify(this._matchingMetas), invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC' });
        this.dispatchEvent(new RefreshEvent());
      } catch (err) {
        // eslint-disable-next-line
        console.error(err);
      }
    }

    this.isRecalculating = false;
  }

  async _setup() {
    try {
      if (!this._namespaceInfo.namespace) {
        this._namespaceInfo = await getNamespaceInfo();
      }
      const metas = await getRollupMetadata();
      this._fillValidMetadata(metas);
    } catch (err) {
      this.isValid = false;
    }
  }

  _fillValidMetadata(metadata) {
    Object.keys(metadata).forEach(calcItemName => {
      metadata[calcItemName].forEach(rollupMetadata => {
        // there can be many different matches across metadata which share the same parent object
        // build up a list of matching metas and append to their CalcItemWhereClause__c the
        // parent recordId
        if (rollupMetadata[this._getNamespaceSafeFieldName('LookupObject__c')] === this.objectApiName) {
          this._addMatchingMetadata(rollupMetadata);
        }
      });
    });

    this.isValid = this._matchingMetas.length > 0;
  }

  _addMatchingMetadata(metadata) {
    const grandparentRelationshipFieldPath = this._getNamespaceSafeFieldName('GrandparentRelationshipFieldPath__c');
    const lookupFieldOnCalcItem = this._getNamespaceSafeFieldName('LookupFieldOnCalcItem__c');
    const parentLookup = metadata[grandparentRelationshipFieldPath]
      ? metadata[grandparentRelationshipFieldPath].substring(0, metadata[grandparentRelationshipFieldPath].lastIndexOf('.')) + '.Id'
      : metadata[lookupFieldOnCalcItem];
    const equalsParent = parentLookup + " = '" + this.recordId + "'";

    const calcItemWhereClause = this._getNamespaceSafeFieldName('CalcItemWhereClause__c');
    if (metadata[calcItemWhereClause] && metadata[calcItemWhereClause].length > 0) {
      metadata[calcItemWhereClause] = metadata[calcItemWhereClause] + DELIMITER + equalsParent;
    } else {
      metadata[calcItemWhereClause] = DELIMITER + equalsParent;
    }
    const orderByFieldName = this._getNamespaceSafeFieldName('RollupOrderBys__r');
    const children = metadata[orderByFieldName];
    transformToSerializableChildren(metadata, orderByFieldName, children);

    this._matchingMetas.push(metadata);
  }

  _getNamespaceSafeFieldName = fieldName => `${this._namespaceInfo.namespace + fieldName}`;
}
