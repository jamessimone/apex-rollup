import { api, LightningElement } from 'lwc';

import { getRollupMetadata } from "c/utils"

export default class RecalculateParentRollupFlexipage extends LightningElement {
  @api recordId;
  @api objectApiName;

  isRecalculating = false;
  isValid = false;

  _matchingMetas = [];

  async connectedCallback() {
    try {
      const metadata = await getRollupMetadata()
      this._fillValidMetadata(metadata);
    } catch(_) {
      this.isValid = false;
    }
  }

  handleClick() {
    this.isRecalculating = true;
  }

  _fillValidMetadata(metadata) {
    Object.keys(metadata).forEach(calcItemName => {
      metadata[calcItemName].forEach(rollupMetadata => {
        // there can be many different matches across metadata which share the same parent object
        // build up a list of matching metas and append to their CalcItemWhereClause__c the
        // parent recordId
        if (rollupMetadata.LookupObject__c === this.objectApiName) {
          this.isValid = true;

        }
      })
    })
  }
}