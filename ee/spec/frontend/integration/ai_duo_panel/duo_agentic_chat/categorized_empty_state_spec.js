import { waitFor } from '@testing-library/vue';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setFeatureFlags } from 'ee_jest/integration/helpers/setup_utils';
import { getAiChatContextPresets, installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  findEmptyState,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import { waitForSocket } from '../test_support/websocket_mock';

const byTestId = (id) => document.querySelector(`[data-testid="${id}"]`);
const findRedesignedEmptyState = () => byTestId('chat-redesigned-empty-state');
const findHeading = () => byTestId('chat-empty-state-heading');
const findCategoryToggle = () => byTestId('prompt-category-dropdown').querySelector('button');
const findQuestions = () =>
  [...document.querySelectorAll('[data-testid="prompt-category-question"]')].map((button) =>
    button.textContent.trim(),
  );

const categoryWithKey = (key) =>
  getAiChatContextPresets.categories().find((category) => category.key === key);

describe('Duo Agentic Chat | the categorized empty state', () => {
  const mountChat = (duoChatRedesign) => {
    setFeatureFlags({ duoChatRedesign });
    mountDuoAgenticChatStateManager({ propsData: { projectId: PROJECT_ID } });
  };

  // The composer stays disabled until the initial queries resolve.
  const waitForChat = () =>
    waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  describe('with the redesign enabled', () => {
    beforeEach(async () => {
      mountChat(true);
      await waitForChat();
    });

    // The recorded `firstChatThread` has no rows, so this is a first-time user.
    it('introduces GitLab Duo to a user with no chat threads yet', async () => {
      await waitFor(() => {
        expect(findHeading().textContent.trim()).toBe('Hello from GitLab Duo');
      });
    });

    it('opens on the Get started suggestions', async () => {
      const getStarted = categoryWithKey('get_started');

      await waitFor(() => {
        expect(findCategoryToggle().textContent.trim()).toBe(getStarted.title);
      });
      expect(findQuestions()).toEqual(getStarted.questions);
    });

    it('swaps in the suggestions of the category the user picks', async () => {
      const pipelines = categoryWithKey('pipelines');
      await waitFor(() => {
        expect(findQuestions()).not.toHaveLength(0);
      });

      findCategoryToggle().click();
      byTestId('listbox-item-pipelines').click();

      await waitFor(() => {
        expect(findQuestions()).toEqual(pipelines.questions);
      });
    });

    it('sends a suggestion as the goal of a new chat', async () => {
      const [question] = categoryWithKey('get_started').questions;
      await waitFor(() => {
        expect(findQuestions()).toContain(question);
      });

      byTestId('prompt-category-question').click();
      await waitForSocket();

      expect(lastRequestVariables('createAiDuoWorkflow')).toMatchObject({ goal: question });
    });
  });

  describe('with the redesign disabled', () => {
    beforeEach(async () => {
      mountChat(false);
      await waitForChat();
    });

    it('keeps the classic empty state', () => {
      expect(findEmptyState()).not.toBe(null);
      expect(findRedesignedEmptyState()).toBe(null);
    });
  });
});
