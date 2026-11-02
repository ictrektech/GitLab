<script>
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, sprintf } from '~/locale';
import { joinPaths, visitUrl, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import { createAlert } from '~/alert';
import { NAMESPACE_TYPE_GROUP } from '../../constants';
import { policyMutationVariables } from '../../policies';
import {
  apiErrorMessage,
  isDuplicateNameError,
  isRuleRegoParseError,
  readMutationPayload,
} from '../../utils';
import singlePolicyQuery from '../../single_policy_query';
import governPolicyCreateMutation from '../../graphql/govern_policy_create.mutation.graphql';
import governPolicyUpdateMutation from '../../graphql/govern_policy_update.mutation.graphql';
import { serializePolicyParams } from './serializer';
import StepWizard from './step_wizard.vue';

export default {
  name: 'PolicyStoreEditorRoot',
  components: {
    GlAlert,
    GlLoadingIcon,
    StepWizard,
  },
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    policyId: { default: '' },
    listPath: { default: '' },
  },
  data() {
    return {
      editingPolicy: null,
      policyError: false,
      saving: false,
      nameError: '',
    };
  },
  apollo: {
    // Skips itself on the blank "new" page, which has no policy to resolve.
    editingPolicy: singlePolicyQuery,
  },
  computed: {
    // The wizard reads its policy prop once, on mount, so the editor renders
    // only after the read settles rather than mounting empty and never refilling.
    policyLoading() {
      return this.$apollo.queries.editingPolicy.loading;
    },
    // An edit page never mounts the wizard without its policy; a null read
    // falls through to the error alert instead of a blank page.
    policyReady() {
      return !this.policyId || Boolean(this.editingPolicy);
    },
    detailPath() {
      return this.listPath && this.policyId ? joinPaths(this.listPath, this.policyId) : '';
    },
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    namespaceIdentifier() {
      return this.isGroupContext ? this.namespacePath : this.organizationId;
    },
  },
  methods: {
    // Both save paths leave with a full navigation, which drops the cache, so
    // nothing here reads the payload. The update document still selects the
    // GovernPolicy fragment because the detail page's status toggle shares it.
    async savePolicy(params) {
      const isUpdate = Boolean(this.policyId);
      const mutation = isUpdate ? governPolicyUpdateMutation : governPolicyCreateMutation;
      const field = isUpdate ? 'governPolicyUpdate' : 'governPolicyCreate';

      const { data } = await this.$apollo.mutate({
        mutation,
        variables: policyMutationVariables({
          document: mutation,
          namespaceType: this.namespaceType,
          namespaceIdentifier: this.namespaceIdentifier,
          policyId: isUpdate ? this.policyId : undefined,
          params,
        }),
      });

      readMutationPayload(data, field);
    },
    async onSave(wizardState) {
      this.saving = true;
      this.nameError = '';

      const params = serializePolicyParams(wizardState);

      // An untouched Scope step is not sent on update, so a scope authored
      // through the API (hand-written Rego, groups, frameworks) is not
      // overwritten by the wizard's project-only view of it.
      if (this.policyId && !wizardState.scopeChanged) delete params.policy_scope;

      try {
        await this.savePolicy(params);

        if (this.policyId) {
          // An edit returns to the detail view it came from, so the updated
          // configuration is what the user lands on.
          this.leaveWithConfirmation(this.detailPath, {
            id: 'policy-store-policy-updated',
            message: sprintf(s__('PolicyStore|Policy %{name} was updated.'), {
              name: params.name,
            }),
          });
        } else {
          this.leaveWithConfirmation(this.listPath, {
            id: 'policy-store-policy-created',
            message: sprintf(s__('PolicyStore|Policy %{name} was created.'), {
              name: params.name,
            }),
          });
        }
      } catch (error) {
        const message = apiErrorMessage(error);

        // A duplicate name is ordinary user input: it belongs on the name
        // field, not in a page alert, and is not worth tracking as a failure.
        if (isDuplicateNameError(message)) {
          this.nameError = s__(
            'PolicyStore|A policy with this name already exists. Choose a different name.',
          );
        } else {
          // A parse failure is author input, not a bug. Where it belongs in the
          // editor is still open: https://gitlab.com/gitlab-org/gitlab/-/work_items/629577
          if (!isRuleRegoParseError(message)) Sentry.captureException(error);

          createAlert({
            message: message || s__('PolicyStore|The policy could not be saved. Try again.'),
          });
        }

        this.saving = false;
      }
    },
    // Cancel mirrors save: an edit returns to the detail view it came from,
    // a new policy returns to the list.
    onCancel() {
      const path = this.policyId ? this.detailPath : this.listPath;

      if (path) visitUrl(path);
    },
    leaveWithConfirmation(path, alert) {
      if (path) visitUrlWithAlerts(path, [{ ...alert, variant: 'success' }]);
    },
  },
};
</script>

<template>
  <gl-loading-icon v-if="policyLoading" size="lg" class="gl-mt-6" data-testid="policy-loading" />
  <gl-alert
    v-else-if="policyError || !policyReady"
    variant="danger"
    :dismissible="false"
    class="gl-mt-4"
    data-testid="policy-error"
  >
    {{
      s__(
        'PolicyStore|The policy could not be loaded from the Policy Store API. Refresh the page to try again.',
      )
    }}
  </gl-alert>
  <step-wizard
    v-else
    :policy="editingPolicy"
    :saving="saving"
    :name-error="nameError"
    @cancel="onCancel"
    @save="onSave"
    @name-update="nameError = ''"
  />
</template>
