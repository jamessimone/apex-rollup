import { createElement } from '@lwc/engine-dom';

import getBatchRollupStatus from '@salesforce/apex/Rollup.getBatchRollupStatus';
import RollupJobPoller from 'c/rollupJobPoller';

jest.mock(
  '@salesforce/apex/Rollup.getBatchRollupStatus',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

describe('recalc parent rollup from flexipage tests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('should handle error on load gracefully', async () => {
    const element = createElement('c-rollup-job-poller', {
      is: RollupJobPoller
    });
    document.body.appendChild(element);

    element.runJobPoller();
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('div').textContent).toBe('Rollup job status: failed to enqueue, check Apex Debug Logs for more info');
  });

  it('should display the rollup job status', async () => {
    getBatchRollupStatus.mockResolvedValue('Queued');
    const element = createElement('c-rollup-job-poller', {
      is: RollupJobPoller
    });
    document.body.appendChild(element);

    element.runJobPoller('707somethingValid');
    await Promise.resolve('Mount re-render');
    await Promise.resolve('Poll re-render');

    expect(element.shadowRoot.querySelector('div').textContent).toBe('Rollup job status: Queued for job: 707somethingValid');
  });
});
