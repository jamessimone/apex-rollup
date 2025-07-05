import { isValidAsyncJob, getRollupMetadata } from 'c/rollupUtils';
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
    delete mockMetadata.Contact[1].CalcItem__r;
    expect(returnedMetadata).toEqual(mockMetadata);
  });

  it('knows a valid async job id from an invalid one using key prefix', () => {
    expect(isValidAsyncJob('707...')).toBeTruthy();
    expect(isValidAsyncJob('No process Id')).toBeFalsy();
  });
});
