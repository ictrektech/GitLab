import { screen } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { cdEnvironments } from 'ee_jest/integration/cd/fixture_variants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { expectListToShow, findPanel, mountCdApp } from './test_setup';

describe('CD environments index when the organization has no environments', () => {
  const findHeadingDescription = () => screen.queryByTestId('page-heading-description');
  const findRegisterFirstButton = () => screen.queryByTestId('register-first-environment-button');

  let captureException;

  beforeEach(() => {
    createPortalElement();
    // The list renders this same empty state when the query fails, so the test would
    // pass on a broken response without watching what the index reports to Sentry.
    captureException = jest.spyOn(Sentry, 'captureException');
    setQueryVariant(cdEnvironments).empty();

    mountCdApp();
  });

  it('shows the get started empty state instead of the list', async () => {
    await waitForElement(findRegisterFirstButton);

    await expectListToShow([]);
    expect(getText(document.body)).toContain('Get started with environments');
    expect(getText(findRegisterFirstButton())).toBe('Register your first environment');
    expect(getText(findHeadingDescription())).toBe('0 of 0 environments');
    expect(captureException).not.toHaveBeenCalled();
  });

  it('opens the register panel from the empty state', async () => {
    await waitAndClick(findRegisterFirstButton);

    await waitForElement(findPanel);
  });
});
