<script>
import { GlFormInput } from '@gitlab/ui';
import { debounce } from 'lodash-es';
// eslint-disable-next-line no-restricted-imports
import { mapState, mapActions } from 'vuex';
import { createAlert } from '~/alert';
import { n__, s__ } from '~/locale';
import showToast from '~/vue_shared/plugins/global_toast';
import { RULE_TYPE_ANY_APPROVER } from '../../constants';

const ANY_RULE_NAME = 'All Members';

export default {
  name: 'RuleInput',
  components: {
    GlFormInput,
  },
  i18n: {
    inputLabel(approvalsCount) {
      return n__('Approval required', 'Approvals required', approvalsCount);
    },
    saveSuccess: s__('ApprovalRule|Required approvals updated.'),
    saveError: s__('ApprovalRule|An error occurred while updating the required approvals.'),
  },
  props: {
    rule: {
      type: Object,
      required: true,
    },
    isMrEdit: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  computed: {
    ...mapState(['settings']),
    uniqueInputId() {
      return `approvals-number-field-${this.rule.id}`;
    },
    minInputValue() {
      return this.rule.minApprovalsRequired || 0;
    },
    isEnabled() {
      return this.settings.canEdit;
    },
  },
  created() {
    this.onInputChangeDebounced = debounce((event) => {
      this.onInputChange(event);
    }, 1000);
  },
  methods: {
    ...mapActions(['putRule', 'postRule']),
    onInputChange(value) {
      const approvalsRequired = parseInt(value, 10);

      const request = this.rule.id
        ? this.putRule({ id: this.rule.id, approvalsRequired })
        : this.postRule({
            name: ANY_RULE_NAME,
            ruleType: RULE_TYPE_ANY_APPROVER,
            approvalsRequired,
          });

      // On the MR edit form the value is only saved with the merge request,
      // so feedback is only shown where the change is saved immediately.
      if (this.isMrEdit) return;

      request
        .then(() => showToast(this.$options.i18n.saveSuccess))
        .catch((error) => {
          createAlert({ message: this.$options.i18n.saveError, captureError: true, error });
        });
    },
  },
};
</script>

<template>
  <div>
    <label :for="uniqueInputId" class="gl-sr-only">
      {{ $options.i18n.inputLabel(rule.approvalsRequired) }}
    </label>
    <gl-form-input
      :id="uniqueInputId"
      :value="rule.approvalsRequired"
      :disabled="!isEnabled"
      class="-gl-my-3 gl-ml-auto gl-w-10 @md/panel:gl-mr-auto"
      type="number"
      name="approvals-number-field"
      :min="minInputValue"
      data-testid="approvals-number-field"
      @input="onInputChangeDebounced"
    />
  </div>
</template>
