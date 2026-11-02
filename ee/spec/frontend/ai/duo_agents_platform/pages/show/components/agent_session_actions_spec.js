import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import AgentSessionActions from 'ee/ai/duo_agents_platform/pages/show/components/agent_session_actions.vue';
import { CANCEL_SESSION_ICON, RETRY_SESSION_ICON } from 'ee/ai/duo_agents_platform/constants';

describe('AgentSessionActions', () => {
  let wrapper;

  const createComponent = ({ dapSessionRestarts = true, ...props } = {}) => {
    wrapper = shallowMountExtended(AgentSessionActions, {
      propsData: { status: 'CREATED', canUpdateWorkflow: true, ...props },
      provide: { glFeatures: { dapSessionRestarts } },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findAllButtons = () => wrapper.findAllComponents(GlButton);
  const findIconButton = () => wrapper.findComponentByTestId('cancel-session-icon-button');
  const findTextButton = () => wrapper.findComponentByTestId('cancel-session-button');
  const findDetailsToggle = () => wrapper.findComponentByTestId('toggle-session-details-button');
  const findRetryIconButton = () => wrapper.findComponentByTestId('retry-session-icon-button');
  const findRetryTextButton = () => wrapper.findComponentByTestId('retry-session-button');

  describe('when session is not cancelable', () => {
    it.each(['FINISHED', 'FAILED', 'STOPPED', 'IDLE'])(
      'does not render for %s status',
      (status) => {
        createComponent({ status });
        expect(findTextButton().exists()).toBe(false);
      },
    );
  });

  describe('session details toggle', () => {
    describe('when showDetailsToggle is false', () => {
      beforeEach(() => createComponent());

      it('does not render the toggle', () => {
        expect(findDetailsToggle().exists()).toBe(false);
      });
    });

    describe('when showDetailsToggle is true', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true }));

      it('renders the toggle alongside the cancel button', () => {
        expect(findDetailsToggle().exists()).toBe(true);
        expect(findAllButtons()).toHaveLength(2);
      });

      it('renders a fixed icon and label', () => {
        expect(findDetailsToggle().props('icon')).toBe('chevron-double-lg-left');
        expect(findDetailsToggle().attributes('aria-label')).toBe('Session details');
      });

      describe('when clicked', () => {
        beforeEach(() => findDetailsToggle().vm.$emit('click'));

        it('emits toggle-details', () => {
          expect(wrapper.emitted('toggle-details')).toHaveLength(1);
        });
      });

      describe('when the session is not cancelable', () => {
        beforeEach(() => createComponent({ status: 'FINISHED', showDetailsToggle: true }));

        it('still renders the toggle', () => {
          expect(findTextButton().exists()).toBe(false);
          expect(findDetailsToggle().exists()).toBe(true);
        });
      });
    });

    describe('when detailsDrawerId is provided', () => {
      beforeEach(() =>
        createComponent({
          showDetailsToggle: true,
          detailsDrawerId: 'session-details-info-drawer-1',
        }),
      );

      it('points aria-controls at the drawer', () => {
        expect(findDetailsToggle().attributes('aria-controls')).toBe(
          'session-details-info-drawer-1',
        );
      });
    });

    describe('when details are expanded', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true, detailsExpanded: true }));

      it('reports the expanded state', () => {
        expect(findDetailsToggle().attributes('aria-expanded')).toBe('true');
      });
    });

    describe('when details are collapsed', () => {
      beforeEach(() => createComponent({ showDetailsToggle: true, detailsExpanded: false }));

      it('reports the collapsed state', () => {
        expect(findDetailsToggle().attributes('aria-expanded')).toBe('false');
      });
    });
  });

  describe('when session is cancelable', () => {
    describe('when isSidePanel is false', () => {
      beforeEach(() => createComponent());

      it('renders only the text cancel button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findTextButton().exists()).toBe(true);
        expect(findIconButton().exists()).toBe(false);
      });

      it('emits cancel-session when clicked', () => {
        findTextButton().vm.$emit('click');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });

      describe('when user has permission', () => {
        it('enables the button', () => {
          expect(findTextButton().props('disabled')).toBe(false);
        });

        it('has the gl-tooltip directive bound', () => {
          expect(getBinding(findTextButton().element, 'gl-tooltip')).toBeDefined();
        });

        it('shows no tooltip text', () => {
          expect(findTextButton().attributes('title')).toBe('');
        });
      });

      describe('when user lacks permission', () => {
        beforeEach(() => createComponent({ canUpdateWorkflow: false }));

        it('disables the button', () => {
          expect(findTextButton().props('disabled')).toBe(true);
        });

        it('shows the no-permission tooltip', () => {
          expect(findTextButton().attributes('title')).toBe(
            'You do not have permission to cancel this session.',
          );
        });
      });
    });

    describe('when isSidePanel is true', () => {
      beforeEach(() => createComponent({ isSidePanel: true }));

      it('renders only the icon cancel button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findIconButton().exists()).toBe(true);
        expect(findTextButton().exists()).toBe(false);
      });

      it('uses the cancel session icon', () => {
        expect(findIconButton().props('icon')).toBe(CANCEL_SESSION_ICON);
      });

      it('emits cancel-session when clicked', () => {
        findIconButton().vm.$emit('click');
        expect(wrapper.emitted('cancel-session')).toHaveLength(1);
      });

      describe('when user has permission', () => {
        it('enables the button', () => {
          expect(findIconButton().props('disabled')).toBe(false);
        });

        it('shows the cancel tooltip', () => {
          expect(getBinding(findIconButton().element, 'gl-tooltip')).toBeDefined();
          expect(findIconButton().attributes('title')).toBe('Cancel session');
        });
      });

      describe('when user lacks permission', () => {
        beforeEach(() => createComponent({ isSidePanel: true, canUpdateWorkflow: false }));

        it('disables the button', () => {
          expect(findIconButton().props('disabled')).toBe(true);
        });

        it('binds the tooltip to the button', () => {
          expect(getBinding(findIconButton().element, 'gl-tooltip')).toBeDefined();
        });

        it('shows the no-permission tooltip', () => {
          expect(findIconButton().attributes('title')).toBe(
            'You do not have permission to cancel this session.',
          );
        });
      });
    });
  });

  describe('when the session cannot be restarted', () => {
    beforeEach(() => createComponent({ status: 'FAILED', canRestartWorkflow: false }));

    it('does not render the retry button', () => {
      expect(findRetryTextButton().exists()).toBe(false);
    });
  });

  describe('when dapSessionRestarts is disabled', () => {
    describe('and the session is restartable', () => {
      beforeEach(() =>
        createComponent({
          status: 'FAILED',
          canRestartWorkflow: true,
          dapSessionRestarts: false,
        }),
      );

      it('does not render the retry button', () => {
        expect(findRetryTextButton().exists()).toBe(false);
      });
    });

    describe('and the session is cancelable', () => {
      beforeEach(() => createComponent({ status: 'RUNNING', dapSessionRestarts: false }));

      it('still renders the cancel button', () => {
        expect(findTextButton().exists()).toBe(true);
      });
    });
  });

  describe('when session is restartable', () => {
    it('renders the retry button', () => {
      createComponent({ status: 'FAILED', canRestartWorkflow: true });
      expect(findRetryTextButton().exists()).toBe(true);
    });

    it('does not render the cancel button alongside it', () => {
      createComponent({ status: 'FAILED', canRestartWorkflow: true });
      expect(findTextButton().exists()).toBe(false);
    });

    describe('when isSidePanel is false', () => {
      beforeEach(() => createComponent({ status: 'FAILED', canRestartWorkflow: true }));

      it('renders only the text retry button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findRetryTextButton().exists()).toBe(true);
        expect(findRetryIconButton().exists()).toBe(false);
      });

      it('emits retry-session when clicked', () => {
        findRetryTextButton().vm.$emit('click');
        expect(wrapper.emitted('retry-session')).toHaveLength(1);
      });

      it('does not need a tooltip, since the label is visible', () => {
        expect(findRetryTextButton().attributes('title')).toBeUndefined();
      });
    });

    describe('when isSidePanel is true', () => {
      beforeEach(() =>
        createComponent({ status: 'FAILED', canRestartWorkflow: true, isSidePanel: true }),
      );

      it('renders only the icon retry button', () => {
        expect(findAllButtons()).toHaveLength(1);
        expect(findRetryIconButton().exists()).toBe(true);
        expect(findRetryTextButton().exists()).toBe(false);
      });

      it('renders the retry icon', () => {
        expect(findRetryIconButton().props('icon')).toBe(RETRY_SESSION_ICON);
      });

      it('labels the icon-only button', () => {
        expect(findRetryIconButton().attributes('aria-label')).toBe('Retry session');
      });

      it('emits retry-session when clicked', () => {
        findRetryIconButton().vm.$emit('click');
        expect(wrapper.emitted('retry-session')).toHaveLength(1);
      });

      it('shows the retry tooltip on the button itself', () => {
        expect(getBinding(findRetryIconButton().element, 'gl-tooltip')).toBeDefined();
        expect(findRetryIconButton().attributes('title')).toBe('Retry session');
      });
    });

    describe('when a retry is in flight', () => {
      beforeEach(() =>
        createComponent({ status: 'FAILED', canRestartWorkflow: true, isRetrying: true }),
      );

      it('shows the button as loading', () => {
        expect(findRetryTextButton().props('loading')).toBe(true);
      });
    });
  });
});
