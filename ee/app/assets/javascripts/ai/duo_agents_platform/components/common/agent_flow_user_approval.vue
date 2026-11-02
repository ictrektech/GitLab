<script>
import { GlAlert, GlButton, GlFormGroup, GlFormTextarea } from '@gitlab/ui';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { resumeWorkflow, cancelWorkflow } from 'ee/rest_api';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { getAgentFlow } from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow.query.graphql';

export default {
  name: 'AgentFlowUserApproval',
  components: {
    GlAlert,
    GlButton,
    GlFormGroup,
    GlFormTextarea,
  },
  data() {
    return {
      isEditMode: false,
      modificationText: '',
      pendingAction: null,
      isSubmitted: false,
      errorMessage: '',
    };
  },
  computed: {
    isSubmitting() {
      return this.pendingAction !== null;
    },
  },
  methods: {
    toggleEditMode(enable = !this.isEditMode) {
      this.isEditMode = enable;
      this.modificationText = '';
      this.errorMessage = '';
    },
    startSubmit(action) {
      this.pendingAction = action;
      this.errorMessage = '';
    },
    // Rendered inline rather than with createAlert, which shows at the top of
    // the page and is out of view when the session is open in the side panel.
    handleError(error, fallbackMessage) {
      this.errorMessage = error.response?.data?.message || fallbackMessage;
      Sentry.captureException(error);
    },
    async refetchWorkflow() {
      await this.$apollo.query({
        query: getAgentFlow,
        variables: {
          workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.$route.params.id),
        },
        fetchPolicy: 'network-only',
      });
    },
    async submitApproval() {
      this.startSubmit('approve');
      try {
        await resumeWorkflow(this.$route.params.id, {
          humanApproval: true,
        });
        this.isSubmitted = true;
        this.refetchWorkflow();
      } catch (error) {
        this.handleError(
          error,
          s__('DuoAgentsPlatform|Failed to submit approval. Please try again.'),
        );
      } finally {
        this.pendingAction = null;
      }
    },
    async submitModification() {
      this.startSubmit('modify');
      try {
        await resumeWorkflow(this.$route.params.id, {
          humanApproval: false,
          humanMessage: this.modificationText,
        });
        this.toggleEditMode(false);
        this.refetchWorkflow();
      } catch (error) {
        this.handleError(
          error,
          s__('DuoAgentsPlatform|Failed to submit modification. Please try again.'),
        );
      } finally {
        this.pendingAction = null;
      }
    },
    async rejectPlan() {
      this.startSubmit('reject');
      try {
        await cancelWorkflow(this.$route.params.id);
        this.isSubmitted = true;
        createAlert({
          message: s__('DuoAgentsPlatform|Session has been canceled successfully.'),
          variant: 'success',
        });
        this.refetchWorkflow();
      } catch (error) {
        this.handleError(
          error,
          s__('DuoAgentsPlatform|Failed to cancel session. Please try again.'),
        );
      } finally {
        this.pendingAction = null;
      }
    },
  },
};
</script>
<template>
  <div v-if="!isSubmitted">
    <div v-if="isEditMode" class="gl-mb-3">
      <gl-form-group
        id="modify-flow-plan_group"
        :label-description="
          s__(
            'DuoAgentsPlatform|Tell the agent what to change and it will generate an updated plan for your review.',
          )
        "
        label-for="modify-flow-plan"
        :label="s__('DuoAgentsPlatform|Modify plan')"
      >
        <gl-form-textarea
          id="modify-flow-plan"
          v-model="modificationText"
          autofocus
          :no-resize="false"
          :character-count-limit="null"
          :textarea-classes="null"
          :rows="8"
        />
      </gl-form-group>
    </div>
    <gl-alert v-if="errorMessage" variant="danger" class="gl-mb-3" @dismiss="errorMessage = ''">{{
      errorMessage
    }}</gl-alert>
    <div class="gl-flex gl-w-full gl-justify-end gl-gap-3">
      <template v-if="!isEditMode">
        <gl-button
          data-testid="flow-user-approval-modify-button"
          :disabled="isSubmitting"
          @click="toggleEditMode(true)"
          >{{ __('Modify') }}</gl-button
        >
        <gl-button
          data-testid="flow-user-approval-reject-button"
          :disabled="isSubmitting"
          :loading="pendingAction === 'reject'"
          @click="rejectPlan"
          >{{ __('Reject') }}</gl-button
        >
        <gl-button
          variant="confirm"
          data-testid="flow-user-approval-approve-button"
          :disabled="isSubmitting"
          :loading="pendingAction === 'approve'"
          @click="submitApproval"
          >{{ __('Approve') }}</gl-button
        >
      </template>
      <template v-else>
        <gl-button
          data-testid="flow-user-approval-cancel-button"
          :disabled="isSubmitting"
          @click="toggleEditMode(false)"
          >{{ __('Cancel') }}</gl-button
        >
        <gl-button
          variant="confirm"
          data-testid="flow-user-approval-submit-button"
          :disabled="isSubmitting || !modificationText.trim()"
          :loading="pendingAction === 'modify'"
          @click="submitModification"
          >{{ __('Submit') }}</gl-button
        >
      </template>
    </div>
  </div>
</template>
