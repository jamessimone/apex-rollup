import { api, LightningElement, wire } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import performSerializedBulkFullRecalc from '@salesforce/apex/Rollup.performSerializedBulkFullRecalc';
import getNamespaceInfo from '@salesforce/apex/Rollup.getNamespaceInfo';
import { getRecord } from 'lightning/uiRecordApi';

import { getRollupMetadata, transformToSerializableChildren } from 'c/rollupUtils';
import type { 
  RollupMetadata, 
  NamespaceInfo, 
  RollupMetadataByCalcItem 
} from '../../../../types/rollup-types';

const DELIMITER: string = ' ||| ';

interface AlternativeField {
  fieldApiName: string;
  objectApiName: string;
}

export default class RecalculateParentRollupFlexipage extends LightningElement {
  @api recordId: string | undefined;
  @api objectApiName: string | undefined;
  @api alternativeParentFieldName: string | undefined;

  isRecalculating: boolean = false;
  isValid: boolean = false;
  alternativeField: AlternativeField | undefined;

  private _hasPopulatedAdditionalFields: boolean = false;
  private _matchingMetas: RollupMetadata[] = [];
  private _namespaceInfo: NamespaceInfo = {} as NamespaceInfo;

  async connectedCallback(): Promise<void> {
    await this._setup();
  }

  renderedCallback(): void {
    if (this.alternativeParentFieldName && !this._hasPopulatedAdditionalFields) {
      this._hasPopulatedAdditionalFields = true;
      this.alternativeField = { 
        fieldApiName: this.alternativeParentFieldName, 
        objectApiName: this.objectApiName! 
      };
    }
  }

  @wire(getRecord, { recordId: '$recordId', fields: [], optionalFields: '$alternativeField' })
  wiredRecord({ data }: { data?: any }): void {
    if (data && this.alternativeParentFieldName) {
      this.recordId = data.fields[this.alternativeParentFieldName]?.value ?? this.recordId;
      this._setup();
    }
  }

  @api
  async handleClick(): Promise<void> {
    this.isRecalculating = true;

    if (this._matchingMetas.length > 0) {
      try {
        const serverResponse: string = await performSerializedBulkFullRecalc({
          serializedMetadata: JSON.stringify(this._matchingMetas),
          invokePointName: 'FROM_SINGULAR_PARENT_RECALC_LWC'
        });
        const jobPoller = this.template?.querySelector('c-rollup-job-poller') as any;
        if (jobPoller) {
          await jobPoller.runJobPoller(serverResponse);
        }
        this.dispatchEvent(new RefreshEvent());
      } catch (err: any) {
        this.logErrorToConsole(err);
      }
    }

    this.isRecalculating = false;
  }

  private async _setup(): Promise<void> {
    try {
      if (!this._namespaceInfo?.namespace) {
        this._namespaceInfo = await getNamespaceInfo();
      }
      const metas: RollupMetadataByCalcItem = await getRollupMetadata();
      this._fillValidMetadata(metas);
    } catch (err: any) {
      this.isValid = false;
      this.logErrorToConsole(err);
    }
  }

  private _fillValidMetadata(metadata: RollupMetadataByCalcItem): void {
    Object.keys(metadata).forEach((calcItemName: string) => {
      metadata[calcItemName].forEach((rollupMetadata: RollupMetadata) => {
        // there can be many different matches across metadata which share the same parent object
        // build up a list of matching metas and append to their CalcItemWhereClause__c the
        // parent recordId
        if (rollupMetadata[this._getNamespaceSafeFieldName('LookupObject__c')] === this.objectApiName) {
          this._addMatchingMetadata(rollupMetadata);
        }
      });
    });

    this.isValid = this._matchingMetas.length > 0;
    this.dispatchEvent(new CustomEvent('loadingfinished', { detail: { isValid: this.isValid } }));
  }

  private _addMatchingMetadata(metadata: RollupMetadata): void {
    const grandparentRelationshipFieldPath: string = this._getNamespaceSafeFieldName('GrandparentRelationshipFieldPath__c');
    const lookupFieldOnCalcItem: string = this._getNamespaceSafeFieldName('LookupFieldOnCalcItem__c');
    const parentLookup: string = metadata[grandparentRelationshipFieldPath]
      ? metadata[grandparentRelationshipFieldPath].substring(0, metadata[grandparentRelationshipFieldPath].lastIndexOf('.')) + '.Id'
      : metadata[lookupFieldOnCalcItem];
    const equalsParent: string = parentLookup + " = '" + this.recordId + "'";

    const calcItemWhereClause: string = this._getNamespaceSafeFieldName('CalcItemWhereClause__c');
    if (metadata[calcItemWhereClause] && metadata[calcItemWhereClause].length > 0) {
      metadata[calcItemWhereClause] = metadata[calcItemWhereClause] + DELIMITER + equalsParent;
    } else {
      metadata[calcItemWhereClause] = DELIMITER + equalsParent;
    }
    const orderByFieldName: string = this._getNamespaceSafeFieldName('RollupOrderBys__r');
    const children = metadata[orderByFieldName];
    transformToSerializableChildren(metadata, orderByFieldName, children);

    this._matchingMetas.push(metadata);
  }

  private logErrorToConsole(err: any): void {
    // eslint-disable-next-line
    console.error(err);
  }

  private _getNamespaceSafeFieldName = (fieldName: string): string => `${(this._namespaceInfo?.namespace ?? '') + fieldName}`;
}
