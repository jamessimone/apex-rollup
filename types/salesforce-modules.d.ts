// Type definitions for Salesforce Lightning platform modules

declare module 'lightning/refresh' {
  export class RefreshEvent extends Event {
    constructor();
  }
}

declare module 'lightning/navigation' {
  export interface CurrentPageReference {
    attributes?: {
      recordId?: string;
      objectApiName?: string;
    };
  }
  
  export const CurrentPageReference: any;
}

declare module 'lightning/platformShowToastEvent' {
  export interface ShowToastEventParams {
    title: string;
    message: string;
    variant: 'success' | 'warning' | 'error' | 'info';
  }
  
  export class ShowToastEvent extends Event {
    constructor(params: ShowToastEventParams);
  }
}

declare module 'lightning/uiObjectInfoApi' {
  export interface ObjectInfo {
    fields: {
      [fieldName: string]: {
        label: string;
        dataType: string;
      };
    };
  }
  
  export const getObjectInfo: any;
  
  export interface PicklistValuesResult {
    values: Array<{
      label: string;
      value: string;
    }>;
  }
  
  export const getPicklistValues: any;
}

declare module 'lightning/uiRecordApi' {
  export const getRecord: any;
}

declare module '@salesforce/apex/Rollup.getNamespaceInfo' {
  interface NamespaceInfo {
    namespace: string;
    safeObjectName: string;
    safeRollupOperationField: string;
  }
  
  export default function getNamespaceInfo(): Promise<NamespaceInfo>;
}

declare module '@salesforce/apex/Rollup.getRollupMetadataByCalcItem' {
  export default function getRollupMetadataByCalcItem(): Promise<any>;
}

declare module '@salesforce/apex/Rollup.performSerializedBulkFullRecalc' {
  export default function performSerializedBulkFullRecalc(params: {
    serializedMetadata: string;
    invokePointName: string;
  }): Promise<string>;
}

declare module '@salesforce/apex/Rollup.performSerializedFullRecalculation' {
  export default function performSerializedFullRecalculation(params: {
    metadata: string;
  }): Promise<string>;
}

declare module '@salesforce/apex/Rollup.getBatchRollupStatus' {
  export default function getBatchRollupStatus(params: {
    jobId: string;
  }): Promise<string>;
}

declare module 'c/rollupUtils' {
  export function isValidAsyncJob(val: string | null | undefined): boolean;
  export function getRollupMetadata(): Promise<any>;
  export function transformToSerializableChildren(
    record: any, 
    key: string, 
    children?: any[]
  ): void;
}