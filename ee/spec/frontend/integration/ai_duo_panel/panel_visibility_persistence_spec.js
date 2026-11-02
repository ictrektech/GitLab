import { waitFor, screen } from '@testing-library/vue';
import { waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { installDuoAIPanelHandlers } from './test_support/api_handlers';
import {
  buildChatConfiguration,
  mountAISidebar,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';

describe('AI panel visibility persists across reloads', () => {
  const findPanelContent = () => document.querySelector('#ai-panel-portal');
  const findDuoDisabledToggle = () => screen.queryByTestId('duo-disabled-toggle');
  const findChatToggle = () => screen.queryByTestId('ai-chat-toggle');

  const mountPanel = ({
    chatDisabledReason = '',
    shouldShowBlockedState = false,
    autoExpand = false,
  } = {}) =>
    mountAISidebar({
      chatConfiguration: buildChatConfiguration({
        autoExpand,
        defaultProps: { chatDisabledReason, shouldShowBlockedState },
      }),
    });

  const simulateReload = () => {
    document.body.innerHTML = '';
  };

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  describe('when GitLab Duo is disabled (admin)', () => {
    it('stays collapsed after reload when user closes the disabled Duo panel', async () => {
      mountPanel({ chatDisabledReason: 'project', shouldShowBlockedState: true });

      await waitForElement(findDuoDisabledToggle);
      expect(findPanelContent()).toBe(null);

      findDuoDisabledToggle().click();
      await waitFor(() => {
        expect(findPanelContent()).not.toBe(null);
      });

      findDuoDisabledToggle().click();
      await waitFor(() => {
        expect(findPanelContent()).toBe(null);
      });

      simulateReload();
      mountPanel({ chatDisabledReason: 'project', shouldShowBlockedState: true });

      await waitForElement(findDuoDisabledToggle);
      expect(findPanelContent()).toBe(null);
    });
  });

  describe('when Duo is enabled (regular user)', () => {
    it('stays collapsed after reload when the user closes the panel', async () => {
      mountPanel();

      await waitForElement(findChatToggle);

      findChatToggle().click();
      await waitFor(() => {
        expect(findPanelContent()).not.toBe(null);
      });

      findChatToggle().click();
      await waitFor(() => {
        expect(findPanelContent()).toBe(null);
      });

      simulateReload();
      mountPanel();

      await waitForElement(findChatToggle);
      expect(findPanelContent()).toBe(null);
    });
  });
});
