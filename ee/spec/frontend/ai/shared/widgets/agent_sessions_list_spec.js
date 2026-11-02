import { GlAlert, GlCollapse } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionsList from 'ee/ai/shared/widgets/agent_sessions_list.vue';
import AgentSessionsGroup from 'ee/ai/shared/widgets/agent_sessions_group.vue';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { buildSession } from 'ee_jest/ai/mocks';
import { AWAITING_INPUT_HEADER_BG_CLASS } from 'ee/ai/shared/widgets/constants';

describe('AgentSessionsList', () => {
  let wrapper;

  const createComponent = ({ sessions = [], isLoading = false, ...props } = {}) => {
    wrapper = shallowMountExtended(AgentSessionsList, {
      propsData: { sessions, isLoading, ...props },
      stubs: { CrudComponent },
    });
  };

  const findCrudComponent = () => wrapper.findComponent(CrudComponent);
  const findAllSessionGroups = () => wrapper.findAllComponents(AgentSessionsGroup);
  const findAwaitingInputGroup = () => wrapper.findAllComponents(AgentSessionsGroup).at(0);
  const findOtherSessionsHeading = () => wrapper.findByTestId('other-sessions-heading');
  const findToggleOtherButton = () => wrapper.findComponentByTestId('toggle-sessions-other');
  const findOtherCollapse = () => wrapper.findComponent(GlCollapse);
  const findErrorAlert = () => wrapper.findComponent(GlAlert);
  const findEmptyState = () => wrapper.findByTestId('crud-empty');
  const findSessionsList = () => wrapper.findByTestId('agent-sessions-list');
  const findCrudBody = () => wrapper.findByTestId('crud-body');
  const findCollapseToggle = () => wrapper.findComponentByTestId('crud-collapse-toggle');

  describe('with no sessions', () => {
    it('does not render the crud component', () => {
      createComponent();

      expect(findCrudComponent().exists()).toBe(false);
    });

    describe('when showEmptyState is true', () => {
      beforeEach(() => {
        createComponent({ showEmptyState: true });
      });

      it('renders the crud component collapsed', () => {
        expect(findCrudComponent().exists()).toBe(true);
        expect(findCrudComponent().props('collapsed')).toBe(true);
        expect(findCrudBody().isVisible()).toBe(false);
      });

      it('shows the empty state text when manually expanded', async () => {
        await findCollapseToggle().vm.$emit('click');

        expect(findCrudBody().isVisible()).toBe(true);
        expect(findEmptyState().text()).toBe('No agent sessions');
      });

      it('does not render the error alert', () => {
        expect(findErrorAlert().exists()).toBe(false);
      });
    });
  });

  describe('when hasError is true', () => {
    describe('with no sessions', () => {
      beforeEach(() => {
        createComponent({
          hasError: true,
          showEmptyState: true,
          errorMessage: 'Failed to load sessions',
        });
      });

      it('renders the crud component expanded', () => {
        expect(findCrudComponent().exists()).toBe(true);
        expect(findCrudComponent().props('collapsed')).toBe(false);
      });

      it('renders a non-dismissible danger alert with the error message', () => {
        expect(findErrorAlert().props()).toMatchObject({
          variant: 'danger',
          dismissible: false,
        });
        expect(findErrorAlert().text()).toBe('Failed to load sessions');
      });

      it('does not render the empty state text', () => {
        expect(findEmptyState().exists()).toBe(false);
      });
    });

    describe('with no sessions and showEmptyState false', () => {
      beforeEach(() => {
        createComponent({ hasError: true, errorMessage: 'Failed to load sessions' });
      });

      it('renders the crud component expanded with the error alert', () => {
        expect(findCrudComponent().exists()).toBe(true);
        expect(findCrudComponent().props('collapsed')).toBe(false);
        expect(findErrorAlert().text()).toBe('Failed to load sessions');
      });
    });

    describe('with sessions', () => {
      beforeEach(() => {
        createComponent({ hasError: true, sessions: [buildSession()] });
      });

      it('renders the crud component expanded', () => {
        expect(findCrudComponent().props('collapsed')).toBe(false);
      });

      it('renders the error alert alongside the sessions list', () => {
        expect(findErrorAlert().exists()).toBe(true);
        expect(findSessionsList().exists()).toBe(true);
      });
    });
  });

  describe('with only awaiting-input sessions', () => {
    it('renders the crud component expanded', () => {
      createComponent({ sessions: [buildSession({ status: 'INPUT_REQUIRED' })] });

      expect(findCrudComponent().props('collapsed')).toBe(false);
    });

    it('renders a single AgentSessionsGroup for all awaiting-input statuses', () => {
      createComponent({
        sessions: [
          buildSession({ status: 'INPUT_REQUIRED' }),
          buildSession({ status: 'PLAN_APPROVAL_REQUIRED' }),
        ],
      });

      expect(findAllSessionGroups()).toHaveLength(1);
      expect(findAwaitingInputGroup().props('group')).toMatchObject({ key: 'INPUT_REQUIRED' });
      expect(findAwaitingInputGroup().props('headerBgClass')).toBe(AWAITING_INPUT_HEADER_BG_CLASS);
    });

    it('does not render the other-sessions heading', () => {
      createComponent({ sessions: [buildSession({ status: 'INPUT_REQUIRED' })] });

      expect(findOtherSessionsHeading().exists()).toBe(false);
    });
  });

  describe('with only non-awaiting-input sessions', () => {
    it('renders the crud component collapsed', () => {
      createComponent({ sessions: [buildSession()] });

      expect(findCrudComponent().props('collapsed')).toBe(true);
    });

    it('renders one AgentSessionsGroup per status group with sessions', () => {
      createComponent({
        sessions: [buildSession({ status: 'RUNNING' }), buildSession()],
      });

      expect(findAllSessionGroups()).toHaveLength(2);
    });

    it('does not render the other-sessions heading', () => {
      createComponent({ sessions: [buildSession({ status: 'RUNNING' })] });

      expect(findOtherSessionsHeading().exists()).toBe(false);
    });
  });

  describe('with an idle session', () => {
    it('groups it with the other sessions, not with those awaiting input', () => {
      createComponent({ sessions: [buildSession({ status: 'IDLE' })] });

      expect(findCrudComponent().props('collapsed')).toBe(true);
      expect(findAllSessionGroups()).toHaveLength(1);
      expect(findAllSessionGroups().at(0).props('group')).toMatchObject({ key: 'IDLE' });
    });
  });

  describe('with both awaiting-input and other sessions', () => {
    beforeEach(() => {
      createComponent({
        sessions: [
          buildSession({ status: 'INPUT_REQUIRED' }),
          buildSession({ status: 'RUNNING' }),
          buildSession(),
        ],
      });
    });

    it('renders the crud component expanded', () => {
      expect(findCrudComponent().props('collapsed')).toBe(false);
    });

    it('renders the other-sessions heading', () => {
      expect(findOtherSessionsHeading().exists()).toBe(true);
    });

    it('renders one group for awaiting-input and one per other status group', () => {
      // 1 awaiting-input group + 2 other groups (RUNNING, FINISHED)
      expect(findAllSessionGroups()).toHaveLength(3);
    });

    it('other sessions are collapsed by default and shows "Show" label', () => {
      expect(findToggleOtherButton().attributes('aria-expanded')).toBe('false');
      expect(findToggleOtherButton().text()).toContain('Show');
      expect(findOtherCollapse().props('visible')).toBe(false);
    });

    it('toggles other sessions on button click and shows "Hide" label', async () => {
      await findToggleOtherButton().vm.$emit('click');

      expect(findToggleOtherButton().attributes('aria-expanded')).toBe('true');
      expect(findToggleOtherButton().text()).toContain('Hide');
      expect(findOtherCollapse().props('visible')).toBe(true);
    });

    it('shows a dot-separated summary with counts and status labels', () => {
      expect(findOtherSessionsHeading().text()).toContain('1 running');
      expect(findOtherSessionsHeading().text()).toContain('·');
      expect(findOtherSessionsHeading().text()).toContain('1 completed');
    });
  });

  describe('isLoading', () => {
    it('passes isLoading to CrudComponent', () => {
      createComponent({ sessions: [buildSession()], isLoading: true });

      expect(findCrudComponent().props('isLoading')).toBe(true);
    });
  });
});
