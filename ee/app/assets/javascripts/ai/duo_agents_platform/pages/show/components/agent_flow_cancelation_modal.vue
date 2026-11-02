<script>
import { GlModal } from '@gitlab/ui';
import { __, s__ } from '~/locale';

const actionCancel = {
  text: __('Dismiss'),
  attributes: {
    'data-testid': 'cancel-session-modal-dismiss',
  },
};

export default {
  name: 'AgentFlowCancelationModal',
  components: {
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['hide', 'confirm'],
  actionCancel,
  computed: {
    modalTitle() {
      return s__('DuoAgentsPlatform|Cancel session?');
    },
    actionPrimary() {
      return {
        text: s__('DuoAgentsPlatform|Cancel session'),
        attributes: {
          variant: 'danger',
          loading: this.loading,
          'data-testid': 'cancel-session-modal-confirm',
        },
      };
    },
  },
  methods: {
    handleHide() {
      this.$emit('hide');
    },
    handleConfirm() {
      this.$emit('confirm');
    },
  },
};
</script>
<template>
  <gl-modal
    modal-id="cancel-session-confirmation-modal"
    :title="modalTitle"
    :visible="visible"
    size="sm"
    data-testid="cancel-session-confirmation-modal"
    :action-primary="actionPrimary"
    :action-cancel="$options.actionCancel"
    @hide="handleHide"
    @primary="handleConfirm"
  >
    <p class="gl-mb-0">
      {{
        s__(
          'DuoAgentsPlatform|Are you sure you want to cancel this session? This action cannot be undone.',
        )
      }}
    </p>
  </gl-modal>
</template>
