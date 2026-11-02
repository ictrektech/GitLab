import { GlModal } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import AgentFlowCancelationModal from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_cancelation_modal.vue';

describe('AgentFlowCancelationModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(AgentFlowCancelationModal, {
      propsData: {
        visible: false,
        loading: false,
        ...props,
      },
      stubs: {
        GlModal,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);

  describe('when component has rendered', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the modal with correct props', () => {
      expect(findModal().exists()).toBe(true);
      expect(findModal().props('modalId')).toBe('cancel-session-confirmation-modal');
      expect(findModal().props('title')).toBe('Cancel session?');
      expect(findModal().props('size')).toBe('sm');
    });

    it('renders the confirmation message', () => {
      expect(wrapper.text()).toContain(
        'Are you sure you want to cancel this session? This action cannot be undone.',
      );
    });

    it('renders action-cancel with correct text and testid', () => {
      const actionCancel = findModal().props('actionCancel');

      expect(actionCancel).toMatchObject({
        text: 'Dismiss',
        attributes: {
          'data-testid': 'cancel-session-modal-dismiss',
        },
      });
    });

    it('renders action-primary with correct text, variant, and testid', () => {
      const actionPrimary = findModal().props('actionPrimary');

      expect(actionPrimary).toMatchObject({
        text: 'Cancel session',
        attributes: {
          variant: 'danger',
          'data-testid': 'cancel-session-modal-confirm',
        },
      });
    });
  });

  describe('visibility', () => {
    it.each`
      visible  | expected
      ${true}  | ${true}
      ${false} | ${false}
    `('passes visible=$visible prop to modal', ({ visible, expected }) => {
      createComponent({ visible });

      expect(findModal().props('visible')).toBe(expected);
    });
  });

  describe('loading state', () => {
    it.each`
      loading  | expected
      ${true}  | ${true}
      ${false} | ${false}
    `('passes loading=$loading to action-primary', ({ loading, expected }) => {
      createComponent({ loading });

      expect(findModal().props('actionPrimary').attributes.loading).toBe(expected);
    });
  });

  describe('events', () => {
    beforeEach(() => {
      createComponent({ visible: true });
    });

    it('emits hide when modal hide event fires', async () => {
      await findModal().vm.$emit('hide');

      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('emits confirm when action-primary event fires', async () => {
      await findModal().vm.$emit('primary');

      expect(wrapper.emitted('confirm')).toHaveLength(1);
    });
  });
});
