import { GlCollapse } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionsGroup from 'ee/ai/shared/widgets/agent_sessions_group.vue';
import AgentSessionRow from 'ee/ai/shared/widgets/agent_session_row.vue';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { buildSessionGroup } from 'ee_jest/ai/mocks';

describe('AgentSessionsGroup', () => {
  let wrapper;

  const createComponent = (group = buildSessionGroup()) => {
    wrapper = shallowMountExtended(AgentSessionsGroup, {
      propsData: { group, headerBgClass: 'gl-bg-feedback-warning' },
    });
  };

  const findHeading = () => wrapper.findByTestId('sessions-group-heading');
  const findStatusIcon = () => wrapper.findComponent(AgentStatusIcon);
  const findToggleButton = () =>
    wrapper.findComponentByTestId(`toggle-sessions-${buildSessionGroup().key}`);
  const findAllSessionRows = () => wrapper.findAllComponents(AgentSessionRow);
  const findCollapse = () => wrapper.findComponent(GlCollapse);
  const findSessionsBody = () => wrapper.findByTestId('sessions-group-body');

  beforeEach(() => {
    createComponent();
  });

  describe('header', () => {
    it('renders the heading with the correct bg class and title', () => {
      expect(findHeading().classes()).toContain('gl-bg-feedback-warning');
      expect(findHeading().text()).toContain('2 sessions awaiting your input');
    });

    it('passes status and humanStatus to AgentStatusIcon', () => {
      expect(findStatusIcon().props('status')).toBe('INPUT_REQUIRED');
      expect(findStatusIcon().props('humanStatus')).toBe('Input required');
    });
  });

  describe('collapse toggle', () => {
    it('is expanded with Collapse label by default', () => {
      expect(findToggleButton().attributes('aria-expanded')).toBe('true');
      expect(findToggleButton().attributes('aria-label')).toBe('Collapse');
      expect(findCollapse().props('visible')).toBe(true);
    });

    describe('when the toggle is clicked', () => {
      beforeEach(async () => {
        await findToggleButton().vm.$emit('click');
      });

      it('collapses with Expand label', () => {
        expect(findToggleButton().attributes('aria-expanded')).toBe('false');
        expect(findToggleButton().attributes('aria-label')).toBe('Expand');
        expect(findCollapse().props('visible')).toBe(false);
      });

      describe('when the toggle is clicked again', () => {
        beforeEach(async () => {
          await findToggleButton().vm.$emit('click');
        });

        it('expands again', () => {
          expect(findToggleButton().attributes('aria-expanded')).toBe('true');
          expect(findCollapse().props('visible')).toBe(true);
        });
      });
    });
  });

  describe('session rows', () => {
    it('renders a row for each session', () => {
      expect(findAllSessionRows()).toHaveLength(2);
    });

    it('uses a subtle divider between rows', () => {
      expect(findSessionsBody().classes()).toContain('gl-divide-subtle');
    });
  });
});
