import { GlIcon, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { TEST_HOST } from 'helpers/test_constants';
import AgentSessionBadge from 'ee/commit/components/agent_session_badge.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { getChatPanelConfig } from 'ee/ai/utils/chat_panel_config';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';

jest.mock('ee/ai/utils/chat_panel_config');

describe('AgentSessionBadge', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const sessionPath = '/group/project/-/automate/agent-sessions/42';

  const createComponent = (description) => {
    wrapper = mountExtended(AgentSessionBadge, {
      propsData: { description },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const findBadge = () => wrapper.findByTestId('commit-agent-session-badge');
  const findLink = () => wrapper.findComponent(GlLink);
  const findIcon = () => wrapper.findComponent(GlIcon);
  const click = (options = {}) => {
    const event = { type: 'click', button: 0, preventDefault: jest.fn(), ...options };
    findLink().vm.$emit('click', event);
    return event;
  };

  beforeEach(() => {
    jest.spyOn(eventHub, '$emit');
    getChatPanelConfig.mockReturnValue({});
  });

  describe.each([
    ['without a session', 'Body'],
    ['with a session', `Duo-Session: ${TEST_HOST}${sessionPath}`],
  ])('%s', (_, description) => {
    beforeEach(() => {
      createComponent(description);
    });

    it('renders a labelled session icon with a tooltip', () => {
      expect(findIcon().props('name')).toBe('session-ai');
      expect(findIcon().attributes('aria-label')).toBe('GitLab Duo Agent session');
      expect(getBinding(findBadge().element, 'gl-tooltip')).not.toBeUndefined();
      expect(findBadge().attributes('title')).toBe('Commit authored in a GitLab Duo Agent session');
    });
  });

  describe.each([
    ['the trailer is in the body', `Body\n\nDuo-Session: ${TEST_HOST}${sessionPath}`],
    [
      'a squashed commit has several trailers',
      `Duo-Session: ${TEST_HOST}${sessionPath}\r\nDuo-Session: ${TEST_HOST}/group/project/-/automate/agent-sessions/7`,
    ],
  ])('when %s', (_, description) => {
    beforeEach(() => {
      createComponent(description);
    });

    it('links to the first session', () => {
      expect(findLink().attributes('href')).toBe(sessionPath);
    });
  });

  describe.each([
    ['the description is empty', null],
    ['there is no trailer', 'Body'],
    ['the trailer has no value', `Duo-Session:\n${TEST_HOST}${sessionPath}`],
    [
      'the trailer points to another instance',
      'Duo-Session: https://example.com/group/project/-/automate/agent-sessions/42',
    ],
    ['the trailer is not a session URL', `Duo-Session: ${TEST_HOST}/group/project`],
    ['the trailer is not an http URL', 'Duo-Session: javascript:alert(1)'],
  ])('when %s', (_, description) => {
    beforeEach(() => {
      createComponent(description);
    });

    it('renders the icon without a link', () => {
      expect(findIcon().exists()).toBe(true);
      expect(findLink().exists()).toBe(false);
    });

    it('does not open a session on click', async () => {
      await findBadge().trigger('click');

      expect(eventHub.$emit).not.toHaveBeenCalled();
    });

    it('does not track a click', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await findBadge().trigger('click');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });

  describe('when the link is clicked', () => {
    let trackEventSpy;

    const expectClickTracked = () =>
      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_agent_session_link',
        { label: 'repository_commits', property: 'badge' },
        undefined,
      );

    beforeEach(() => {
      createComponent(`Duo-Session: ${TEST_HOST}${sessionPath}`);
      ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
    });

    it('opens the session in the Duo panel', () => {
      const event = click();

      expect(event.preventDefault).toHaveBeenCalled();
      expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
      expectClickTracked();
    });

    it.each([
      ['metaKey', { metaKey: true }],
      ['ctrlKey', { ctrlKey: true }],
      ['shiftKey', { shiftKey: true }],
      ['altKey', { altKey: true }],
    ])('follows the link with %s', (_, options) => {
      const event = click(options);

      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(eventHub.$emit).not.toHaveBeenCalled();
      expectClickTracked();
    });

    describe('when the Duo panel is not available', () => {
      beforeEach(() => {
        getChatPanelConfig.mockReturnValue(null);
      });

      it('follows the link', () => {
        const event = click();

        expect(event.preventDefault).not.toHaveBeenCalled();
        expect(eventHub.$emit).not.toHaveBeenCalled();
        expectClickTracked();
      });
    });
  });
});
