import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAvatar, GlAvatarLink, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { useConfigurePathHelpers } from 'helpers/configure_path_helpers';
import AgentSessionRow from 'ee/ai/shared/widgets/agent_session_row.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { buildSession, mockUser1 } from 'ee_jest/ai/mocks';

Vue.use(VueApollo);

describe('AgentSessionRow', () => {
  let wrapper;

  useConfigurePathHelpers();

  const createComponent = (session, props = {}, { duoChatAvailable = false } = {}) => {
    wrapper = shallowMountExtended(AgentSessionRow, {
      propsData: { session, ...props },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      apolloProvider: createMockApollo([
        [
          duoChatAvailableQuery,
          jest.fn().mockResolvedValue({
            data: { currentUser: { id: 'gid://gitlab/User/1', duoChatAvailable } },
          }),
        ],
      ]),
    });

    return waitForPromises();
  };

  const findTitle = () => wrapper.findByTestId('session-title');
  const findTitleLink = () => wrapper.findComponent(GlLink);
  const findViewDetailsButton = () => wrapper.findByTestId('session-view-details-button');
  const findTitleButtonComponent = () => wrapper.findComponentByTestId('session-title');
  const findViewDetailsButtonComponent = () =>
    wrapper.findComponentByTestId('session-view-details-button');
  const findTimeAgoTooltip = () => wrapper.findComponent(TimeAgoTooltip);
  const findAvatarLink = () => wrapper.findComponent(GlAvatarLink);
  const findAvatar = () => wrapper.findComponent(GlAvatar);

  describe('opening a session', () => {
    const clickEvent = (modifiers = {}) => ({ preventDefault: jest.fn(), ...modifiers });
    const clickTargets = {
      title: () => findTitleLink(),
      'View details': () => findViewDetailsButtonComponent(),
    };

    beforeEach(() => {
      jest.spyOn(eventHub, '$emit');
    });

    describe('when the Duo panel is available', () => {
      beforeEach(() =>
        createComponent(buildSession(), { showViewDetails: true }, { duoChatAvailable: true }),
      );

      it.each(Object.keys(clickTargets))('opens the session in the panel from the %s', (target) => {
        const event = clickEvent();
        clickTargets[target]().vm.$emit('click', event);

        expect(event.preventDefault).toHaveBeenCalled();
        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 1 });
      });

      describe.each(['metaKey', 'ctrlKey', 'shiftKey'])('when the click uses %s', (modifier) => {
        let event;

        beforeEach(() => {
          event = clickEvent({ [modifier]: true });
          findTitleLink().vm.$emit('click', event);
        });

        it('follows the link', () => {
          expect(event.preventDefault).not.toHaveBeenCalled();
          expect(eventHub.$emit).not.toHaveBeenCalled();
        });
      });
    });

    describe('when the session has no project, but the Duo panel is available', () => {
      beforeEach(() =>
        createComponent(
          buildSession({ project: null }),
          { showViewDetails: true },
          { duoChatAvailable: true },
        ),
      );

      it('renders the title as a link-style button', () => {
        expect(findTitleLink().exists()).toBe(false);
        expect(findTitleButtonComponent().props('variant')).toBe('link');
      });

      it.each`
        target            | find
        ${'title'}        | ${() => findTitleButtonComponent()}
        ${'View details'} | ${() => findViewDetailsButtonComponent()}
      `('opens the session in the panel from the $target', ({ find }) => {
        find().vm.$emit('click', clickEvent());

        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 1 });
      });
    });

    describe('when the Duo panel is not available', () => {
      beforeEach(() => createComponent(buildSession(), { showViewDetails: true }));

      it.each(Object.keys(clickTargets))('follows the link from the %s', (target) => {
        const event = clickEvent();
        clickTargets[target]().vm.$emit('click', event);

        expect(event.preventDefault).not.toHaveBeenCalled();
        expect(eventHub.$emit).not.toHaveBeenCalled();
      });
    });
  });

  describe('title', () => {
    describe('when project fullPath is available', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title' }));
      });

      it('links to the session page', () => {
        expect(findTitleLink().text()).toBe('Custom generated title');
        expect(findTitleLink().attributes('href')).toContain('group/project');
      });

      it('shows the title and id in a tooltip', () => {
        expect(getBinding(findTitle().element, 'gl-tooltip')).toBeDefined();
        expect(findTitle().attributes('title')).toBe('Custom generated title 1');
      });
    });

    describe('when project fullPath is not available', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title', project: null }));
      });

      it('renders the title as plain text', () => {
        expect(findTitleLink().exists()).toBe(false);
        expect(findTitle().text()).toBe('Custom generated title');
      });

      it('keeps the tooltip reachable by keyboard', () => {
        expect(getBinding(findTitle().element, 'gl-tooltip')).toBeDefined();
        expect(findTitle().attributes('tabindex')).toBe('0');
        expect(findTitle().attributes('title')).toBe('Custom generated title 1');
      });
    });

    describe('when the session has a title', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title' }));
      });

      it('renders the title', () => {
        expect(findTitle().text()).toBe('Custom generated title');
      });
    });

    describe('when the session has no title', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: null }));
      });

      it('falls back to the humanized workflow definition', () => {
        expect(findTitle().text()).toBe('Planner');
      });
    });
  });

  describe('updated at', () => {
    describe('when updatedAt is present', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('renders TimeAgoTooltip', () => {
        expect(findTimeAgoTooltip().props('time')).toBe('2026-01-15T10:00:00Z');
      });
    });

    describe('when updatedAt is absent', () => {
      beforeEach(() => {
        createComponent(buildSession({ updatedAt: null }));
      });

      it('does not render TimeAgoTooltip', () => {
        expect(findTimeAgoTooltip().exists()).toBe(false);
      });
    });
  });

  describe('"View details" button', () => {
    describe('when showViewDetails is true', () => {
      beforeEach(() => {
        createComponent(buildSession(), { showViewDetails: true });
      });

      it('renders as a confirm/tertiary link to the session URL', () => {
        expect(findViewDetailsButton().exists()).toBe(true);
        expect(findViewDetailsButton().text()).toBe('View details');
        expect(findViewDetailsButton().attributes('variant')).toBe('confirm');
        expect(findViewDetailsButton().attributes('category')).toBe('tertiary');
        expect(findViewDetailsButton().attributes('href')).toContain('group/project');
      });
    });

    describe('when there is no project and the Duo panel is not available', () => {
      beforeEach(() => {
        createComponent(buildSession({ project: null }), { showViewDetails: true });
      });

      it('does not render', () => {
        expect(findViewDetailsButton().exists()).toBe(false);
      });
    });

    describe('when showViewDetails is false', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('does not render', () => {
        expect(findViewDetailsButton().exists()).toBe(false);
      });
    });
  });

  describe('user avatar', () => {
    describe('when the session has a user', () => {
      beforeEach(() => {
        createComponent(buildSession({ user: mockUser1 }));
      });

      it('renders GlAvatarLink with the correct attributes', () => {
        expect(findAvatarLink().attributes('href')).toBe(mockUser1.webPath);
        expect(findAvatarLink().attributes('title')).toBe(mockUser1.name);
        expect(findAvatarLink().attributes('data-username')).toBe(mockUser1.username);
        expect(findAvatarLink().attributes('data-user-id')).toBe('1');
      });

      it('renders GlAvatar with the correct props', () => {
        expect(findAvatar().props('src')).toBe(mockUser1.avatarUrl);
        expect(findAvatar().props('entityName')).toBe(mockUser1.name);
        expect(findAvatar().props('size')).toBe(16);
      });
    });

    describe('when the session has no user', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('does not render', () => {
        expect(findAvatarLink().exists()).toBe(false);
      });
    });
  });
});
