import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { screen } from '@testing-library/vue';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { waitForAssertion, waitAndSetValue } from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { mountWorkItemCreatePage } from 'ee_jest/integration/work_items/test_setup';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

Vue.use(VueApollo);

describe('Work items - create from new page', () => {
  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  it('renders expected widgets for an issue', async () => {
    await mountWorkItemCreatePage();

    expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
    expect(screen.queryByTestId('work-item-description-wrapper')).not.toBe(null);
    expect(screen.queryByTestId('work-item-assignees')).not.toBe(null);
    expect(screen.queryByTestId('work-item-labels')).not.toBe(null);
    expect(screen.queryByTestId('work-item-milestone')).not.toBe(null);
  });

  it('supports label keyboard shortcut', async () => {
    await mountWorkItemCreatePage();

    const labelsWidget = screen.queryByTestId('work-item-labels');
    expect(labelsWidget).not.toBe(null);

    const editButton = labelsWidget.querySelector('[data-testid="edit-button"]');
    expect(editButton).not.toBe(null);

    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'l', bubbles: true }));

    await waitForAssertion(() => {
      const dropdown = document.querySelector('.gl-new-dropdown-panel');
      expect(dropdown).not.toBe(null);
    });
  });

  it('creates work item with title', async () => {
    await mountWorkItemCreatePage();

    const findTitleInput = () => screen.queryByTestId('work-item-title-input');
    await waitAndSetValue(findTitleInput, 'New test issue');

    const createButton = screen.queryByRole('button', { name: /create issue/i });
    expect(createButton).not.toBe(null);
    createButton.click();

    await waitForAssertion(() => {
      const variables = lastRequestVariables('createWorkItem');
      expect(variables).toMatchObject({
        input: expect.objectContaining({
          title: 'New test issue',
        }),
      });
    });

    await waitForAssertion(() => {
      expect(screen.queryByRole('heading', { name: 'New test issue' })).not.toBe(null);
    });
  });
});
