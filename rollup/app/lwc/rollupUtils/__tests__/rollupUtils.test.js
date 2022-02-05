import { getRollupMetadata } from 'c/rollupUtils';
import { mockMetadata } from '../../__mockData__';

jest.mock(
  '@salesforce/apex/Rollup.getRollupMetadataByCalcItem',
  () => {
    return {
      default: () => mockMetadata
    };
  },
  { virtual: true }
);

describe('utils tests', () => {
  it('should remove relationship fields before returning metadata', async () => {
    const returnedMetadata = await getRollupMetadata();

    delete mockMetadata.Contact[0].CalcItem__r;
    expect(returnedMetadata).toEqual(mockMetadata);
  });
});
