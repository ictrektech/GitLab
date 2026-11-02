<script>
import { GlModal } from '@gitlab/ui';
import { s__, __, sprintf } from '~/locale';

export default {
  name: 'DisableScannerConfirmationModal',
  components: {
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    profileName: {
      type: String,
      required: true,
    },
  },
  emits: ['confirm', 'cancel'],
  computed: {
    modalTitle() {
      return sprintf(s__('SecurityProfiles|Disable %{profileName}'), {
        profileName: this.profileName,
      });
    },
    confirmationMessage() {
      return sprintf(
        s__(
          'SecurityProfiles|You are about to disable the %{profileName} profile for this project. Are you sure you want to proceed?',
        ),
        { profileName: this.profileName },
      );
    },
    actionPrimaryProps() {
      return {
        text: this.modalTitle,
        attributes: {
          variant: 'danger',
        },
      };
    },
    actionCancelProps() {
      return {
        text: __('Cancel'),
      };
    },
  },
  methods: {
    handleConfirm() {
      this.$emit('confirm');
    },
    handleCancel() {
      this.$emit('cancel');
    },
  },
};
</script>

<template>
  <gl-modal
    :visible="visible"
    :title="modalTitle"
    :action-primary="actionPrimaryProps"
    :action-cancel="actionCancelProps"
    modal-id="disable-scanner-confirmation-modal"
    size="sm"
    @primary="handleConfirm"
    @hidden="handleCancel"
  >
    <p>{{ confirmationMessage }}</p>
  </gl-modal>
</template>
