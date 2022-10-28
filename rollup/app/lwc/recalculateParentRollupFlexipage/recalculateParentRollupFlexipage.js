import { api, LightningElement } from 'lwc';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';

import { getRollupMetadata } from 'c/rollupUtils';

const DELIMITER = ' ||| ';

export default class RecalculateParentRollupFlexipage extends LightningElement {
  @api recordId;
  @api objectApiName;

  isRecalculating = false;
  isValid = false;

  _matchingMetas = [];
  _namespaceInfo = {};

  async connectedCallback() {
    try {
      this._namespaceInfo = await getNamespaceInfo();
      const metadata = await getRollupMetadata();
      this._fillValidMetadata(metadata);
    } catch (err) {
      this.isValid = false;
    }
  }

  async handleClick() {
    this.isRecalculating = true;

    if (this._matchingMetas.length > 0) {
      try {
        await performSerializedBulkFullRecalc({ serializedMetadata: JSON.stringify(this._matchingMetas), invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC' });
        // record detail pages / components still based on Aura need a little kickstart to properly show the updated values
        if (!!window['$A']) {
          eval("$A.get('e.force:refreshView').fire();");
        }
      } catch (err) {
        console.error(err);
      }
    }

    this.isRecalculating = false;
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
    this._matchingMetas.push(metadata);
  }

  _getNamespaceSafeFieldName = fieldName => `${this._namespaceInfo.namespace + fieldName}`;
}
