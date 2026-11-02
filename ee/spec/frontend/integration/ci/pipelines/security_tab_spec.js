import { waitFor } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { apolloProvider } from '~/ci/pipeline_details/pipeline_shared_client';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import pipelineFindingsVariants, {
  FINDINGS_PAGE_SIZE,
  MANY_PAGES_FINDINGS_COUNT,
} from './fixture_variants/pipeline_findings';
import {
  findFindings,
  findNextButton,
  findPageDescription,
  mountPipelineSecurityTab,
} from './test_setup';

const expectFindingsCount = (count) =>
  waitFor(() => {
    expect(findFindings()).toHaveLength(count);
  });

describe('Pipeline security tab', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when the pipeline has security findings', () => {
    beforeEach(() => {
      mountPipelineSecurityTab();
    });

    it('describes the results as coming from the latest successful pipeline', async () => {
      const description = await waitForElement(findPageDescription);

      expect(getText(description)).toBe(
        'Results show vulnerability findings from the latest successful pipeline.',
      );
    });
  });

  describe('when the findings exceed one page', () => {
    beforeEach(() => {
      setQueryVariant(pipelineFindingsVariants).manyPages();
      mountPipelineSecurityTab();
    });

    it('shows the first page of findings', async () => {
      await expectFindingsCount(FINDINGS_PAGE_SIZE);
    });

    describe('when the next page is requested', () => {
      beforeEach(async () => {
        await expectFindingsCount(FINDINGS_PAGE_SIZE);
        await waitAndClick(findNextButton);
      });

      it('shows the remaining findings', async () => {
        await expectFindingsCount(MANY_PAGES_FINDINGS_COUNT - FINDINGS_PAGE_SIZE);
      });
    });
  });
});
