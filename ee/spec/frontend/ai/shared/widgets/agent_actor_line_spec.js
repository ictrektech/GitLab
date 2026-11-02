import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AgentActorLine from 'ee/ai/shared/widgets/agent_actor_line.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import { mockAgentActorLineProps, mockAgentActorLinePropsWithoutAgentName } from './mock_data';

Vue.use(VueApollo);

describe('AgentActorLine component', () => {
  let wrapper;

  const duoChatAvailableResponse = (duoChatAvailable = true) => ({
    data: { currentUser: { id: 'gid://gitlab/User/1', duoChatAvailable } },
  });

  const createComponent = async ({
    duoChatAvailable = true,
    baseProps = mockAgentActorLineProps,
    ...props
  } = {}) => {
    wrapper = shallowMountExtended(AgentActorLine, {
      propsData: { ...baseProps, ...props },
      stubs: { GlSprintf },
      apolloProvider: createMockApollo([
        [
          duoChatAvailableQuery,
          jest.fn().mockResolvedValue(duoChatAvailableResponse(duoChatAvailable)),
        ],
      ]),
    });
    await waitForPromises();
  };

  const findSessionButton = () => wrapper.findComponentByTestId('session-button');
  const findNoAccess = () => wrapper.findByTestId('session-no-access');
  const findAgentLink = () => wrapper.findByTestId('agent-link');
  const findAgentName = () => wrapper.findByTestId('agent-name');
  const findInitiatorLink = () => wrapper.findByTestId('initiator-link');
  const findInitiatorName = () => wrapper.findByTestId('initiator-name');

  describe('when the current user can view the session', () => {
    beforeEach(() => createComponent());

    it('reads as one sentence naming the agent and the user', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe(
        'Session by Developer Agent on behalf of @nokafor',
      );
    });

    it('opens the session panel when the session is activated', () => {
      jest.spyOn(eventHub, '$emit');

      findSessionButton().vm.$emit('click');

      expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
    });

    it('does not render the no-access state', () => {
      expect(findNoAccess().exists()).toBe(false);
    });
  });

  describe('when the current user cannot view the session', () => {
    beforeEach(() => createComponent({ canViewSession: false }));

    it('still names the agent and the user', () => {
      expect(wrapper.text()).toContain('Developer Agent');
      expect(wrapper.text()).toContain('@nokafor');
    });

    it('offers no way to open the session', () => {
      expect(findSessionButton().exists()).toBe(false);
    });

    it('explains why the session cannot be opened', () => {
      expect(findNoAccess().attributes('title')).toBe('You do not have access to this session.');
    });

    describe('and Duo is unavailable to them as well', () => {
      beforeEach(() => createComponent({ canViewSession: false, duoChatAvailable: false }));

      it('still blames the missing access, not the platform', () => {
        expect(findNoAccess().attributes('title')).toBe('You do not have access to this session.');
      });
    });
  });

  describe('agent name', () => {
    describe('when the agent has a catalog profile', () => {
      beforeEach(() => createComponent({ agentCatalogPath: '/-/ai/catalog/agents/3' }));

      it('links to the profile', () => {
        expect(findAgentLink().attributes('href')).toBe('/-/ai/catalog/agents/3');
      });
    });

    describe('when the agent has no catalog profile', () => {
      beforeEach(() => createComponent());

      it('renders as plain text', () => {
        expect(findAgentLink().exists()).toBe(false);
        expect(findAgentName().text()).toBe('Developer Agent');
      });
    });
  });

  describe('when a person started the session', () => {
    beforeEach(() => createComponent());

    it('links them by their profile path', () => {
      expect(findInitiatorLink().attributes('href')).toBe('/nokafor');
    });

    it('attaches the user popover to their link', () => {
      expect(findInitiatorLink().classes()).toContain('js-user-link');
      expect(findInitiatorLink().attributes()).toMatchObject({
        'data-user-id': '7',
        'data-username': 'nokafor',
      });
    });
  });

  describe('when the person has no user id or profile path', () => {
    beforeEach(() => createComponent({ user: { username: 'nokafor' } }));

    it('names them without a link or user popover', () => {
      expect(findInitiatorLink().exists()).toBe(false);
      expect(findInitiatorName().text()).toBe('@nokafor');
    });
  });

  describe('when a known trigger source started the session', () => {
    it.each`
      triggerSource     | withAgentName | text
      ${'SCHEDULED'}    | ${true}       | ${'Session by Developer Agent triggered by a schedule'}
      ${'FLOW'}         | ${true}       | ${'Session by Developer Agent triggered by another session'}
      ${'VERIFICATION'} | ${true}       | ${'Session by Developer Agent triggered by a verification check'}
      ${'SYSTEM'}       | ${true}       | ${'Session by Developer Agent triggered by GitLab'}
      ${'SCHEDULED'}    | ${false}      | ${'Session triggered by a schedule'}
      ${'FLOW'}         | ${false}      | ${'Session triggered by another session'}
      ${'VERIFICATION'} | ${false}      | ${'Session triggered by a verification check'}
      ${'SYSTEM'}       | ${false}      | ${'Session triggered by GitLab'}
    `(
      'reads "$text" for $triggerSource when withAgentName is $withAgentName',
      async ({ triggerSource, withAgentName, text }) => {
        await createComponent({ triggerSource, withAgentName });

        expect(wrapper.text().replace(/\s+/g, ' ')).toBe(text);
      },
    );

    it('does not name the account the trigger runs as', async () => {
      await createComponent({ triggerSource: 'SCHEDULED' });

      expect(findInitiatorLink().exists()).toBe(false);
      expect(wrapper.text()).not.toContain('@nokafor');
    });

    it('drops the trigger along with the initiator', async () => {
      await createComponent({
        triggerSource: 'SCHEDULED',
        withAgentName: false,
        withInitiator: false,
      });

      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session');
    });

    it('drops the trigger for a source it has no wording for', async () => {
      await createComponent({ triggerSource: 'UNKNOWN', withAgentName: false });

      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session');
    });
  });

  describe('when the session had no triggering user', () => {
    beforeEach(() => createComponent({ user: null }));

    it('drops the on-behalf-of clause', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session by Developer Agent');
    });

    it('renders no user link', () => {
      expect(findInitiatorLink().exists()).toBe(false);
    });
  });

  describe('while the Duo availability answer is still in flight', () => {
    beforeEach(() => {
      wrapper = shallowMountExtended(AgentActorLine, {
        propsData: mockAgentActorLineProps,
        stubs: { GlSprintf },
        apolloProvider: createMockApollo([[duoChatAvailableQuery, jest.fn()]]),
      });
    });

    it('does not yet render the session as unavailable', () => {
      expect(findNoAccess().exists()).toBe(false);
      expect(findSessionButton().exists()).toBe(false);
    });

    it('still names the agent and the user', () => {
      expect(wrapper.text()).toContain('Developer Agent');
      expect(wrapper.text()).toContain('@nokafor');
    });
  });

  describe('when the viewer can read the session but Duo is unavailable', () => {
    beforeEach(() => createComponent({ duoChatAvailable: false }));

    it('offers no way to open the session, which could not open anyway', () => {
      expect(findSessionButton().exists()).toBe(false);
    });

    it('blames the unavailable platform rather than the viewer', () => {
      expect(findNoAccess().attributes('title')).toBe(
        'GitLab Duo Agent Platform is not available.',
      );
    });

    it('still names the agent and the user', () => {
      expect(wrapper.text()).toContain('Developer Agent');
      expect(wrapper.text()).toContain('@nokafor');
    });
  });

  describe('when no agent name is given', () => {
    beforeEach(() => createComponent({ baseProps: mockAgentActorLinePropsWithoutAgentName }));

    it('leaves the agent out of the sentence', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session on behalf of @nokafor');
    });

    it('renders no agent name', () => {
      expect(findAgentLink().exists()).toBe(false);
      expect(findAgentName().exists()).toBe(false);
    });
  });

  describe('when the agent name is suppressed', () => {
    beforeEach(() => createComponent({ withAgentName: false }));

    it('drops it from the sentence', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session on behalf of @nokafor');
    });
  });

  describe('when the initiator is suppressed', () => {
    beforeEach(() => createComponent({ withInitiator: false }));

    it('drops it from the sentence', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session by Developer Agent');
    });
  });

  describe('when both are suppressed', () => {
    beforeEach(() => createComponent({ withAgentName: false, withInitiator: false }));

    it('keeps the session label and its button', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Session');
      expect(findSessionButton().exists()).toBe(true);
    });
  });
});
