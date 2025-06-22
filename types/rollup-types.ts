// Type definitions for rollup interfaces

/** Branded type for Salesforce record IDs */
export type SalesforceId = string & { __brand: 'SalesforceId' };

/** Sort order values for rollup ordering */
export type SortOrder = 'ASC' | 'DESC';

/** Null sort order values for rollup ordering */
export type NullSortOrder = 'NULLS FIRST' | 'NULLS LAST';

/** Rollup order by record interface */
export interface RollupOrderByRecord {
  Id?: SalesforceId;
  MasterLabel: string;
  DeveloperName: string;
  FieldName__c: string;
  SortOrder__c?: SortOrder;
  NullSortOrder__c?: NullSortOrder;
  Ranking__c: number;
  Rollup__c: SalesforceId;
  // Allow dynamic property access for Salesforce fields
  [key: string]: any;
}

/** Rollup operation types */
export type RollupOperation = 
  | 'SUM' 
  | 'COUNT' 
  | 'AVERAGE' 
  | 'MIN' 
  | 'MAX' 
  | 'CONCAT' 
  | 'CONCAT_DISTINCT'
  | 'FIRST'
  | 'LAST'
  | 'MOST'
  | 'LEAST';

/** Toast event variant types */
export type ToastVariant = 'success' | 'warning' | 'error' | 'info';

/** Rollup metadata interface */
export interface RollupMetadata {
  Id?: SalesforceId;
  MasterLabel?: string;
  DeveloperName?: string;
  RollupFieldOnCalcItem__c?: string;
  LookupFieldOnCalcItem__c?: string;
  LookupFieldOnLookupObject__c?: string;
  RollupFieldOnLookupObject__c?: string;
  LookupObject__c?: string;
  CalcItem__c?: string;
  RollupOperation__c?: RollupOperation | string; // Allow string for unknown operations
  CalcItemWhereClause__c?: string;
  ConcatDelimiter__c?: string;
  SplitConcatDelimiterOnCalcItem__c?: boolean;
  LimitAmount__c?: number | null;
  GrandparentRelationshipFieldPath__c?: string;
  RollupOrderBys__r?: RollupOrderByRecord[];
  // Allow dynamic property access for namespaced fields
  [key: string]: any;
}

/** Mapping of object names to their rollup metadata */
export interface RollupMetadataByCalcItem {
  [objectName: string]: RollupMetadata[];
}

/** Serializable child relationship structure for Apex */
export interface SerializableChildRelationship {
  totalSize: number;
  done: boolean;
  records: RollupOrderByRecord[];
}

/** Namespace information from Salesforce org */
export interface NamespaceInfo {
  namespace: string;
  safeObjectName: string;
  safeRollupOperationField: string;
}

/** Field descriptor for Salesforce objects */
export interface FieldDescriptor {
  label: string;
  dataType: string;
  apiName: string;
}

/** Object information from Salesforce metadata */
export interface ObjectInfo {
  fields: {
    [fieldName: string]: FieldDescriptor;
  };
}

/** Picklist value structure */
export interface PicklistValue {
  label: string;
  value: string;
}

/** Wire service error structure */
export interface WireError {
  body: {
    message: string;
    errorCode?: string;
    fieldErrors?: string[];
  };
}

/** Data table column configuration */
export interface DataTableColumn {
  label: string;
  fieldName: string;
  sortable?: boolean;
  type?: string; // Allow any string type for flexibility
}

/** Event interfaces for Lightning components */
export interface ComboboxChangeEvent {
  detail: {
    value: string;
  };
}

export interface DataTableSortEvent {
  detail: {
    fieldName: string;
    sortDirection: 'asc' | 'desc';
  };
}

export interface DataTableRowSelectionEvent {
  detail: {
    selectedRows: RollupMetadata[];
  };
}

/** Alternative field configuration */
export interface AlternativeField {
  fieldApiName: string;
  objectApiName: string;
}