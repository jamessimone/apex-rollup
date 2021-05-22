import { api, LightningElement } from 'lwc';
import performBulkFullRecalc from '@salesforce/apex/Rollup.performBulkFullRecalc';

import { getRollupMetadata } from 'c/utils';

export default class RecalculateParentRollupFlexipage extends LightningElement {
  @api recordId;
  @api objectApiName;

  isRecalculating = false;
  isValid = false;

  _matchingMetas = [];

  async connectedCallback() {
    try {
      const metadata = await getRollupMetadata();
      this._fillValidMetadata(metadata);
    } catch (err) {
      console.error(err);
      this.isValid = false;
    }
  }

  async handleClick() {
    this.isRecalculating = true;

    if (this._matchingMetas.length > 0) {
      try {
        await performBulkFullRecalc({ matchingMetadata: this._matchingMetas, invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC' });
        // record detail pages / components still based on Aura need a little kickstart to properly show the updated values
        if(!!window["$A"]) {
          eval("$A.get('e.force:refreshView').fire();");
        }
      } catch(err) {
        console.error(err)
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
        if (rollupMetadata.LookupObject__c === this.objectApiName) {
          this.isValid = true;
          this._addMatchingMetadata(rollupMetadata);
        }
      });
    });
  }

  _addMatchingMetadata(metadata) {
    const equalsParent =
      metadata.LookupFieldOnCalcItem__c +
      " = '" +
      this.recordId +
      "'";
    if (metadata.CalcItemWhereClause__c && metadata.CalcItemWhereClause__c.length > 0) {
      metadata.CalcItemWhereClause__c = '(' + metadata.CalcItemWhereClause__c + ')' + ' AND ' + equalsParent;
    } else {
      metadata.CalcItemWhereClause__c = equalsParent;
    }
    this._matchingMetas.push(metadata);
  }
}
