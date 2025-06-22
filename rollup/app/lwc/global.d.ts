// Global type declarations for Salesforce LWC modules

declare module 'lightning/refresh' {
  /** Event to refresh view data in Lightning components */
  export class RefreshEvent extends Event {
    constructor();
  }
}

declare module 'lightning/navigation' {
  /** Page reference for navigation context */
  export interface CurrentPageReference {
    type?: string;
    attributes?: {
      recordId?: string;
      objectApiName?: string;
      actionName?: string;
    };
    state?: {
      [key: string]: string;
    };
  }
  
  /** Current page reference wire adapter */
  export const CurrentPageReference: any;
}

declare module 'lightning/platformShowToastEvent' {
  import type { ToastVariant } from '../../../../types/rollup-types';
  
  /** Parameters for showing toast notifications */
  export interface ShowToastEventParams {
    title: string;
    message: string;
    variant: ToastVariant;
    mode?: 'dismissable' | 'pester' | 'sticky';
    messageData?: string[];
  }
  
  /** Toast event for user notifications */
  export class ShowToastEvent extends Event {
    constructor(params: ShowToastEventParams);
  }
}

declare module 'lightning/uiObjectInfoApi' {
  import type { ObjectInfo, PicklistValue } from '../../../../types/rollup-types';
  
  /** Wire adapter for getting object information */
  export const getObjectInfo: any;
  
  /** Wire adapter for getting picklist values */
  export const getPicklistValues: any;
}

declare module 'lightning/uiRecordApi' {
  /** Wire adapter for getting record data */
  export const getRecord: any;
}

declare module 'lightning/navigation' {
  /** Page reference for navigation context */
  export interface CurrentPageReference {
    type?: string;
    attributes?: {
      recordId?: string;
      objectApiName?: string;
      actionName?: string;
    };
    state?: {
      [key: string]: string;
    };
  }
  
  /** Current page reference wire adapter */
  export const CurrentPageReference: any;
}

declare module '@salesforce/apex/Rollup.getNamespaceInfo' {
  import type { NamespaceInfo } from '../../../../types/rollup-types';
  
  /** Get namespace information for the current org */
  export default function getNamespaceInfo(): Promise<NamespaceInfo>;
}

declare module '@salesforce/apex/Rollup.getRollupMetadataByCalcItem' {
  import type { RollupMetadataByCalcItem } from '../../../../types/rollup-types';
  
  /** Get rollup metadata grouped by calculation item */
  export default function getRollupMetadataByCalcItem(): Promise<RollupMetadataByCalcItem>;
}

declare module '@salesforce/apex/Rollup.performSerializedBulkFullRecalc' {
  /** Perform bulk full recalculation with serialized metadata */
  export default function performSerializedBulkFullRecalc(params: {
    serializedMetadata: string;
    invokePointName: string;
  }): Promise<string>;
}

declare module '@salesforce/apex/Rollup.performSerializedFullRecalculation' {
  /** Perform single full recalculation with serialized metadata */
  export default function performSerializedFullRecalculation(params: {
    metadata: string;
  }): Promise<string>;
}

declare module '@salesforce/apex/Rollup.getBatchRollupStatus' {
  /** Get status of batch rollup job */
  export default function getBatchRollupStatus(params: {
    jobId: string;
  }): Promise<string>;
}

declare module 'c/rollupUtils' {
  import type { 
    RollupMetadata, 
    RollupOrderByRecord, 
    RollupMetadataByCalcItem 
  } from '../../../../types/rollup-types';
  
  /** Check if value is a valid async job ID */
  export function isValidAsyncJob(val: string | null | undefined): boolean;
  
  /** Get rollup metadata from Apex */
  export function getRollupMetadata(): Promise<RollupMetadataByCalcItem>;
  
  /** Transform children to serializable format for Apex */
  export function transformToSerializableChildren(
    record: RollupMetadata, 
    key: string, 
    children?: RollupOrderByRecord[]
  ): void;
}