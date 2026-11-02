import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionLink from 'ee/blob/components/agent_session_link.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { getChatPanelConfig } from 'ee/ai/utils/chat_panel_config';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';

jest.mock('ee/ai/utils/chat_panel_config', () => ({ getChatPanelConfig: jest.fn() }));

describe('AgentSessionLink', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const localHref = `${window.location.origin}/group/project/-/automate/agent-sessions/42`;
  const remoteHref = 'https://gitlab.com/group/project/-/automate/agent-sessions/42';

  const createComponent = (href = localHref) => {
    wrapper = shallowMountExtended(AgentSessionLink, {
      propsData: { href, trackingProperty: 'gutter_icon' },
      slots: { default: 'View session' },
    });
  };

  const findLink = () => wrapper.findComponent(GlLink);
  const click = (options = {}) => {
    const event = { preventDefault: jest.fn(), ...options };
    findLink().vm.$emit('click', event);
    return event;
  };

  beforeEach(() => {
    jest.spyOn(eventHub, '$emit');
    getChatPanelConfig.mockReturnValue({ scope: {} });
  });

  it('renders a link to the session with the slot content', () => {
    createComponent();

    expect(findLink().attributes('href')).toBe(localHref);
    expect(findLink().text()).toBe('View session');
  });

  describe('on a plain click', () => {
    it('opens the session in the Duo side panel instead of navigating', () => {
      createComponent();

      const event = click();

      expect(event.preventDefault).toHaveBeenCalled();
      expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
    });

    it('tracks the click', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      click();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_agent_session_link',
        { label: 'blame', property: 'gutter_icon' },
        undefined,
      );
    });
  });

  describe.each`
    reason                         | href          | options              | panelConfig
    ${'a modifier key is held'}    | ${localHref}  | ${{ metaKey: true }} | ${{ scope: {} }}
    ${'the session is elsewhere'}  | ${remoteHref} | ${{}}                | ${{ scope: {} }}
    ${'the page has no Duo panel'} | ${localHref}  | ${{}}                | ${null}
    ${'the URL is not a session'}  | ${'/foo'}     | ${{}}                | ${{ scope: {} }}
  `('when $reason', ({ href, options, panelConfig }) => {
    beforeEach(() => {
      getChatPanelConfig.mockReturnValue(panelConfig);
      createComponent(href);
    });

    it('follows the link', () => {
      const event = click(options);

      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(eventHub.$emit).not.toHaveBeenCalled();
    });

    it('tracks the click', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      click(options);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_agent_session_link',
        { label: 'blame', property: 'gutter_icon' },
        undefined,
      );
    });
  });
});
