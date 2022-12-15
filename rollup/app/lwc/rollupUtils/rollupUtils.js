import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';

/**
 *
 * @param {object} record
 * @param {string} key
 * We have to transform the data slightly to conform to what the Apex deserializer expects
 * by removing relationship fields - this allows the Rollup__mdt records to be passed back
 * to Apex without issue
 */
const isSafeToSerialize = (record, key) => key.indexOf('__r') === -1 || Array.isArray(record[key]);

const getRollupMetadata = async () => {
  const metadataByCalcItem = await getRollupMetadataByCalcItem();
  const cleanedMetaByCalcItem = {};
  Object.keys(metadataByCalcItem)
    .sort()
    .forEach(objectName => {
      const metaPerObject = [];
      metadataByCalcItem[objectName].forEach(rollupMetadata => {
        const cleanedMeta = {};
        Object.keys(rollupMetadata).forEach(propKey => {
          if (isSafeToSerialize(rollupMetadata, propKey)) {
            cleanedMeta[propKey] = rollupMetadata[propKey];
          }
        });
        metaPerObject.push(cleanedMeta);
      });
      cleanedMetaByCalcItem[objectName] = metaPerObject;
    });

  return cleanedMetaByCalcItem;
};

const transformToSerializableChildren = (record, key, children) => {
  if (children && !children.totalSize) {
    record[key] = { totalSize: children?.length ?? 0, done: true, records: children ?? [] };
  }
};

export { getRollupMetadata, transformToSerializableChildren };
