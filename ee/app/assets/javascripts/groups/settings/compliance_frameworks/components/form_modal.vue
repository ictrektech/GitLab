<script>
import { GlModal } from '@gitlab/ui';
import { __, s__ } from '~/locale';

import CreateForm from './create_form.vue';

export default {
  name: 'FormModal',
  components: {
    GlModal,
    CreateForm,
  },
  emits: ['change'],
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- show() is part of the component's public API.
    show() {
      this.$refs.modal.show();
    },
    hide() {
      this.$refs.modal.hide();
    },
    onSuccess({ message: successMessage }) {
      this.$emit('change', successMessage);
    },
  },
  i18n: {
    addTitle: s__('ComplianceFrameworks|New compliance framework'),
    addFramework: s__('ComplianceFrameworks|Add framework'),
    cancel: __('Cancel'),
  },
};
</script>
<template>
  <gl-modal ref="modal" :title="$options.i18n.addTitle" modal-id="framework-form-modal" hide-footer>
    <create-form ref="formComponent" @cancel="hide" @success="onSuccess" />
  </gl-modal>
</template>
