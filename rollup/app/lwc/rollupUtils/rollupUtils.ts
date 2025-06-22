import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';
import type { 
  RollupMetadata, 
  RollupOrderByRecord, 
  RollupMetadataByCalcItem, 
  SerializableChildRelationship 
} from '../../../../types/rollup-types';

const isValidAsyncJob = (val: string | null | undefined): boolean => 
  val?.slice(0, 3) === '707';

/**
 * We have to transform the data slightly to conform to what the Apex deserializer expects
 * by removing relationship fields - this allows the Rollup__mdt records to be passed back
 * to Apex without issue
 */
const isSafeToSerialize = (record: RollupMetadata, key: string): boolean => 
  key.indexOf('__r') === -1 || Array.isArray(record[key]);

const getRollupMetadata = async (): Promise<RollupMetadataByCalcItem> => {
  const metadataByCalcItem: any = await getRollupMetadataByCalcItem();
  const cleanedMetaByCalcItem: RollupMetadataByCalcItem = {};
  
  Object.keys(metadataByCalcItem)
    .sort()
    .forEach((objectName: string) => {
      const metaPerObject: RollupMetadata[] = [];
      metadataByCalcItem[objectName].forEach((rollupMetadata: RollupMetadata) => {
        const cleanedMeta: Partial<RollupMetadata> = {};
        Object.keys(rollupMetadata).forEach((propKey: string) => {
          if (isSafeToSerialize(rollupMetadata, propKey)) {
            cleanedMeta[propKey] = rollupMetadata[propKey];
          }
        });
        metaPerObject.push(cleanedMeta as RollupMetadata);
      });
      cleanedMetaByCalcItem[objectName] = metaPerObject;
    });

  return cleanedMetaByCalcItem;
};

const transformToSerializableChildren = (
  record: RollupMetadata, 
  key: string, 
  children?: RollupOrderByRecord[]
): void => {
  if (children && !(children as any).totalSize) {
    const serializableChildren: SerializableChildRelationship = {
      totalSize: children?.length ?? 0,
      done: true,
      records: children ?? []
    };
    record[key] = serializableChildren;
  }
};

export { isValidAsyncJob, getRollupMetadata, transformToSerializableChildren };
