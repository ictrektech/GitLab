<script>
import { GlAlert, GlFormGroup, GlFormTextarea, GlModal } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import upsertUserOverridesMutation from '../graphql/upsert_user_overrides.mutation.graphql';
import { parseOverridesCsv } from '../utils';

export default {
  // Soft limit enforced by the GraphQL mutation:
  // ee/app/graphql/mutations/gitlab_subscriptions/budget_caps/upsert_user_overrides.rb
  MAX_OVERRIDES: 200,
  name: 'CreditCapsBulkUpdateOverridesModal',
  components: {
    GlAlert,
    GlFormGroup,
    GlFormTextarea,
    GlModal,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['hidden', 'saved'],
  data() {
    return this.defaultData();
  },
  computed: {
    isSubmitDisabled() {
      return !this.csvText.trim();
    },
    overridesDescription() {
      return sprintf(
        s__(
          'UsageBilling|Add each entry on a separate line: username (without "@"), cap (number of credits), enabled ("true" or "false"). Maximum %{max} entries.',
        ),
        { max: this.$options.MAX_OVERRIDES },
      );
    },
    actionPrimaryConfig() {
      return {
        text: s__('UsageBilling|Save overrides'),
        attributes: {
          type: 'submit',
          form: 'bulk-update-overrides-form',
          variant: 'confirm',
          loading: this.isSaving,
          disabled: this.isSubmitDisabled,
          'data-testid': 'bulk-update-overrides-submit-button',
        },
      };
    },
    actionCancelConfig() {
      return {
        text: s__('UsageBilling|Cancel'),
        attributes: {
          form: 'bulk-update-overrides-form',
          disabled: this.isSaving,
          'data-testid': 'bulk-update-overrides-cancel-button',
        },
      };
    },
  },
  methods: {
    defaultData() {
      return {
        csvText: '',
        isSaving: false,
        errors: [],
      };
    },
    onHidden() {
      if (this.isSaving) {
        toast(s__('UsageBilling|Saving in the background.'));
      } else {
        this.reset();
      }
      this.$emit('hidden');
    },
    reset() {
      Object.assign(this, this.defaultData());
    },
    async onSubmit() {
      if (this.isSaving || this.isSubmitDisabled) return;

      this.errors = [];

      const { overrides, errors } = parseOverridesCsv(this.csvText);

      if (errors.length) {
        this.errors = errors;
        return;
      }

      if (overrides.length === 0) {
        this.errors = [s__('UsageBilling|No overrides to save. Please add at least one entry.')];
        return;
      }

      if (overrides.length > this.$options.MAX_OVERRIDES) {
        this.errors = [
          sprintf(s__('UsageBilling|Maximum %{max} overrides allowed per submission.'), {
            max: this.$options.MAX_OVERRIDES,
          }),
        ];
        return;
      }

      try {
        this.isSaving = true;

        const { data } = await this.$apollo.mutate({
          mutation: upsertUserOverridesMutation,
          variables: {
            namespacePath: this.namespacePath,
            overrides,
          },
        });

        if (data?.upsertUserBudgetCapOverrides?.errors?.length) {
          this.errors = data.upsertUserBudgetCapOverrides.errors;
          return;
        }

        toast(s__('UsageBilling|Overrides saved.'));
        this.$emit('saved');
        this.reset();
        this.$emit('hidden');
      } catch (error) {
        this.errors = [error.message];
        logError(error);
        captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <gl-modal
    modal-id="bulk-update-overrides-modal"
    :visible="visible"
    :title="s__('UsageBilling|Bulk update cap overrides')"
    :action-primary="actionPrimaryConfig"
    :action-cancel="actionCancelConfig"
    size="md"
    data-testid="bulk-update-overrides-modal"
    @primary.prevent
    @hidden="onHidden"
  >
    <form id="bulk-update-overrides-form" @submit.prevent="onSubmit">
      <gl-alert
        v-if="errors.length"
        variant="danger"
        :dismissible="false"
        class="gl-mb-4"
        data-testid="bulk-update-overrides-errors-alert"
      >
        <ul class="gl-mb-0 gl-pl-4">
          <li v-for="(error, index) in errors" :key="index">{{ error }}</li>
        </ul>
      </gl-alert>

      <gl-form-group
        :label="s__('UsageBilling|Overrides')"
        label-for="bulk-update-overrides-textarea"
        :description="overridesDescription"
      >
        <gl-form-textarea
          id="bulk-update-overrides-textarea"
          v-model="csvText"
          :disabled="isSaving"
          no-resize
          rows="10"
          required
          data-testid="bulk-update-overrides-textarea"
        />
      </gl-form-group>
    </form>
  </gl-modal>
</template>
