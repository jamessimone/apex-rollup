import getRollupMetadataByCalcItem from '@salesforce/apex/Rollup.getRollupMetadataByCalcItem';

const getRollupMetadata = async () => {
  const metadataByCalcItem = await getRollupMetadataByCalcItem();
  const cleanedMetaByCalcItem = {};
  Object.keys(metadataByCalcItem)
    .sort()
    .forEach(objectName => {
      const metaPerObject = [];
      metadataByCalcItem[objectName].forEach(rollupMetadata => {
        const cleanedMeta = {};
        // we have to transform the data slightly to conform to what the Apex deserializer expects
        // by removing relationship fields - this allows the Rollup__mdt records to be passed back
        // to Apex without issue
        Object.keys(rollupMetadata).forEach(propKey => {
          if (propKey.indexOf('__r') === -1) {
            cleanedMeta[propKey] = rollupMetadata[propKey];
          }
        });
        metaPerObject.push(cleanedMeta);
      });
      cleanedMetaByCalcItem[objectName] = metaPerObject;
    });

  return cleanedMetaByCalcItem;
};

export { getRollupMetadata };
