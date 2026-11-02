import { waitFor } from '@testing-library/vue';
import { installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  findChatMessages,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// Exercises the real path: streamed markdown, duo-ui's sanitizer and morphdom, the
// chat's delegated listener, and the shared popover helper. jsdom has no layout, so
// GlPopover never opens; the helper's `data-popover-mounted` marker is the signal.

const GOAL = 'Link me to issue 1';
const issueUrl = () => `${window.location.origin}/group/project-1/-/issues/1`;
const reply = (suffix = '') =>
  `See [the issue](${issueUrl()}) and [elsewhere](https://example.com/group/project-1/-/issues/1).${suffix}`;

const findIssueLink = () => findChatMessages().querySelector(`a[href="${issueUrl()}"]`);
const findExternalLink = () =>
  findChatMessages().querySelector('[data-href^="https://example.com"]').closest('a');

const hover = (el) => el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
const leave = (el) => el.dispatchEvent(new MouseEvent('mouseleave'));
// Absence has no event to wait for, so wait out the 200 ms mount delay instead.
const waitPastMountDelay = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 300);
  });

describe('Duo Agentic Chat | reference popovers on links in a streamed reply', () => {
  beforeEach(async () => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();

    mountDuoAgenticChatStateManager({ propsData: { projectId: PROJECT_ID } });
    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

    sendPrompt(GOAL);
    await waitForSocket();
    await pushCheckpoint(
      [
        userLogEntry({ id: 'msg-user-1', content: GOAL }),
        agentLogEntry({ id: 'msg-agent-1', content: reply() }),
      ],
      { goal: GOAL },
    );
    await waitFor(() => {
      expect(findIssueLink()).not.toBeNull();
    });
  });

  afterEach(() => teardownDuoChatTest());

  it('mounts the popover when an issue link is hovered', async () => {
    hover(findIssueLink());

    await waitFor(() => {
      expect(findIssueLink().dataset.popoverMounted).toBe('true');
    });
  });

  it('renders a link to another host without an href, so nothing can mount', async () => {
    expect(findExternalLink().hasAttribute('href')).toBe(false);

    hover(findExternalLink());
    await waitPastMountDelay();

    expect(findExternalLink().dataset.popoverMounted).toBeUndefined();
  });

  describe('when the reply re-renders after the popover mounted', () => {
    let linkBeforeRerender;

    beforeEach(async () => {
      linkBeforeRerender = findIssueLink();
      hover(linkBeforeRerender);
      await waitFor(() => {
        expect(linkBeforeRerender.dataset.popoverMounted).toBe('true');
      });
      leave(linkBeforeRerender);

      await pushCheckpoint(
        [
          userLogEntry({ id: 'msg-user-1', content: GOAL }),
          agentLogEntry({ id: 'msg-agent-1', content: reply(' It is still open.') }),
        ],
        { goal: GOAL },
      );
      await waitFor(() => {
        expect(findChatMessages().textContent).toContain('It is still open.');
      });
    });

    it('keeps the same link element but strips the mounted marker', () => {
      expect(findIssueLink()).toBe(linkBeforeRerender);
      expect(findIssueLink().dataset.popoverMounted).toBeUndefined();
    });

    it('does not mount a second popover on the next hover', async () => {
      hover(findIssueLink());
      await waitPastMountDelay();

      expect(findIssueLink().dataset.popoverMounted).toBeUndefined();
    });
  });
});
