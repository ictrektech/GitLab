import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DisableScanProfileConfirmationModal from 'ee/security_configuration/components/scan_profiles/disable_scan_profile_confirmation_modal.vue';

describe('DisableScanProfileConfirmationModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(DisableScanProfileConfirmationModal, {
      propsData: {
        visible: true,
        profileName: 'SAST (default)',
        ...props,
      },
      stubs: {
        GlModal,
      },
    });

    return wrapper;
  };

  const findModal = () => wrapper.findComponent(GlModal);

  describe('modal rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders modal with correct props', () => {
      const modal = findModal();
      expect(modal.exists()).toBe(true);
      expect(modal.props()).toMatchObject({
        visible: true,
        modalId: 'disable-scanner-confirmation-modal',
        size: 'sm',
      });
    });

    it('renders modal title with profile name', () => {
      const modal = findModal();
      expect(modal.props('title')).toBe('Disable SAST (default)');
    });

    it('renders confirmation message with profile name', () => {
      expect(wrapper.text()).toContain(
        'You are about to disable the SAST (default) profile for this project. Are you sure you want to proceed?',
      );
    });

    it('renders primary action with danger variant', () => {
      const modal = findModal();
      expect(modal.props('actionPrimary')).toMatchObject({
        text: 'Disable SAST (default)',
        attributes: {
          variant: 'danger',
        },
      });
    });

    it('renders cancel action', () => {
      const modal = findModal();
      expect(modal.props('actionCancel')).toMatchObject({
        text: 'Cancel',
      });
    });
  });

  describe('visibility prop', () => {
    it('passes visible true to modal when prop is true', () => {
      createComponent({ visible: true });

      expect(findModal().props('visible')).toBe(true);
    });

    it('passes visible false to modal when prop is false', () => {
      createComponent({ visible: false });

      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('profile name prop', () => {
    it('updates the title and message for another name', () => {
      createComponent({ profileName: 'Test Profile' });

      expect(findModal().props('title')).toBe('Disable Test Profile');
      expect(wrapper.text()).toContain('You are about to disable the Test Profile profile');
    });
  });

  describe('event handling', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits confirm event when primary action is clicked', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('confirm')).toHaveLength(1);
    });

    it('emits cancel event when modal is hidden', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('cancel')).toHaveLength(1);
    });
  });
});
