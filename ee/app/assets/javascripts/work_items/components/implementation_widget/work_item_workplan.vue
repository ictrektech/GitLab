<script>
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { InternalEvents } from '~/tracking';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { __, s__, sprintf } from '~/locale';
import { clearDraft, getDraft, updateDraft } from '~/lib/utils/autosave';
import { visitUrl } from '~/lib/utils/url_utility';
import { WORKPLAN_PANEL, I18N_WORK_ITEM_ERROR_UPDATING } from '~/work_items/constants';
import {
  findWorkplanWidget,
  isWorkplanFlowAvailable,
  workplanGenerationDisabledReason,
} from 'ee/work_items/utils';
import { writeAgentPlanToCache } from 'ee/work_items/graphql/cache_utils';
import updateWorkItemAgentPlanMutation from 'ee/work_items/graphql/update_work_item_agent_plan.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import workItemResumeWorkplanMutation from 'ee/work_items/graphql/work_item_resume_workplan.mutation.graphql';
import workplanFlowAvailabilityQuery from 'ee/work_items/graphql/workplan_flow_availability.query.graphql';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { eventHub, REFETCH_SESSIONS, SHOW_SESSION } from 'ee/ai/events/panel';
import WorkplanInlineRow from './workplan_inline_row.vue';
import WorkplanPanel from './workplan_panel.vue';
import {
  FLOW_ACTION_TIMEOUT_MS,
  TERMINAL_STATUS_CONFIRM_MS,
  GENERATION_STATUS_NEEDS_INPUT,
  GENERATION_STATUSES_ACTIVE,
  WORKPLAN_ACTION_EVENT,
} from './constants';
import {
  parseWorkplanUrlState,
  buildWorkplanPageUrl,
  writeWorkplanUrl,
  clearWorkplanUrl,
} from './use_workplan_panel_state';

export default {
  name: 'WorkItemWorkplan',
  components: {
    WorkplanInlineRow,
    WorkplanPanel,
  },
  mixins: [glFeatureFlagsMixin(), InternalEvents.mixin()],
  inject: {
    fullPath: { default: '' },
  },
  props: {
    workItem: {
      type: Object,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    isInDrawer: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
    workplan: {
      type: Object,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    isWorkItemClosed: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['request-panel', 'refetch-plan', 'run-active'],
  data() {
    return {
      isEditing: false,
      isSaving: false,
      tmpContent: '',
      draftContent: '',
      planLanded: false,
      runExpected: false,
      terminalConfirmTimeout: null,
      isFlowActionInFlight: false,
      flowActionTimeout: null,
      hasAwaitedInput: false,
      hasTrackedView: false,
      workplanFlowAvailable: null,
    };
  },
  apollo: {
    workplanFlowAvailable: {
      query: workplanFlowAvailabilityQuery,
      variables() {
        return { fullPath: this.workItem.namespace?.fullPath };
      },
      update(data) {
        return isWorkplanFlowAvailable(data.project);
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    workItemId() {
      return this.workItem.id;
    },
    workItemIid() {
      return this.workItem.iid;
    },
    useWorkItemFeatures() {
      return Boolean(this.glFeatures?.workItemFeaturesField);
    },
    includeReadinessScore() {
      return Boolean(this.glFeatures?.workplanScore);
    },
    workItemType() {
      return this.workItem.workItemType.name;
    },
    content() {
      return this.workplan?.content || '';
    },
    contentHtml() {
      return this.workplan?.contentHtml || '';
    },
    readinessScore() {
      return this.workplan?.readinessScore ?? null;
    },
    hasSavedContent() {
      return Boolean(this.content);
    },
    generationStatus() {
      return this.workplan?.generationStatus;
    },
    openQuestionsCount() {
      return this.workplan?.openQuestionsCount;
    },
    generationDisabledReason() {
      return workplanGenerationDisabledReason(this.workplanFlowAvailable);
    },
    isFlowActive() {
      if (this.planLanded) {
        return false;
      }
      return this.runExpected || GENERATION_STATUSES_ACTIVE.includes(this.generationStatus);
    },
    isRunStarting() {
      return this.runExpected && !GENERATION_STATUSES_ACTIVE.includes(this.generationStatus);
    },
    generation() {
      return {
        status: this.generationStatus,
        hasAwaitedInput: this.hasAwaitedInput,
        actionInFlight: this.isFlowActionInFlight,
        isRunning: this.isFlowActive,
        isStarting: this.isRunStarting,
        openQuestionsCount: this.openQuestionsCount,
        hasQuestions: Boolean(this.workplan?.questions?.nodes.length),
        questions: this.workplan?.questions?.nodes ?? [],
      };
    },
    planStorageKey() {
      return `work-plan-draft-${this.workItemId}`;
    },
    workplanViewState() {
      return {
        workItemId: this.workItemId,
        open: this.isPanelOpen,
        visible:
          this.isPanelOpen &&
          !this.isEditing &&
          !this.isLoading &&
          !this.isFlowActive &&
          Boolean(this.content.trim() && this.contentHtml),
      };
    },
  },
  watch: {
    workplanViewState(state, previousState) {
      if (!state.open || state.workItemId !== previousState.workItemId) {
        this.hasTrackedView = false;
      }
      this.trackWorkplanView();
    },
    // Immediate, because the parent owns the query and the status can already be set
    // on first render rather than arriving as a change.
    generationStatus: {
      immediate: true,
      handler(status, previousStatus) {
        // The status moving is what tells us the action landed, so it, not the
        // mutation returning, is what releases the button.
        if (previousStatus !== undefined && status !== previousStatus) {
          this.setFlowActionPending(false);
        }
        if (GENERATION_STATUSES_ACTIVE.includes(status)) {
          this.cancelTerminalConfirm();
        } else if (this.runExpected) {
          this.confirmTerminalStatus();
        }
        // GENERATING covers both the refinement and plan-writing passes, so a prior
        // NEEDS_INPUT is the only signal that the next one is the second pass.
        if (status === GENERATION_STATUS_NEEDS_INPUT) {
          this.hasAwaitedInput = true;
        }
      },
    },
    isFlowActive: {
      immediate: true,
      handler(active) {
        this.$emit('run-active', active);
      },
    },
    // Writing the plan is the flow's last act and reaches us immediately, so new content
    // ends the run ahead of its status. Covers a regenerate too, where the plan is
    // replaced rather than appearing for the first time.
    workplan(newWorkplan, previousWorkplan) {
      const newContent = newWorkplan?.content || '';
      if (newContent === (previousWorkplan?.content || '')) {
        return;
      }
      // With no previous workplan, this is the saved plan arriving on page load, not a
      // run writing a new one.
      if (this.isFlowActive && previousWorkplan) {
        this.planLanded = true;
        this.runExpected = false;
        this.cancelTerminalConfirm();
      }
    },
  },
  created() {
    const { content: storedDraft } = this.loadFromStorage();
    if (storedDraft) {
      this.draftContent = storedDraft;
    }
    if (!this.isInDrawer) {
      window.addEventListener('popstate', this.onPopState);
      this.syncPanelFromUrl({ canClose: false });
    }
  },
  mounted() {
    this.trackWorkplanView();
  },
  beforeDestroy() {
    clearTimeout(this.flowActionTimeout);
    this.cancelTerminalConfirm();
    window.removeEventListener('popstate', this.onPopState);
  },
  methods: {
    async trackWorkplanView() {
      await this.$nextTick();
      if (!this.workplanViewState.visible || this.hasTrackedView) return;

      this.hasTrackedView = true;
      this.trackEvent('view_work_item_workplan', {
        work_item_id: getIdFromGraphQLId(this.workItemId),
      });
    },
    // Tracked here rather than in the handlers, because retry and regenerate also
    // run `handleGenerate` and must still be counted apart.
    onWorkplanAction(handler, label, property) {
      this.trackEvent(WORKPLAN_ACTION_EVENT, { label, property });
      return handler();
    },
    persistField(key, value) {
      if (!key) return;
      if (value) {
        updateDraft(key, value);
      } else {
        clearDraft(key);
      }
    },
    loadFromStorage() {
      return {
        content: this.planStorageKey ? getDraft(this.planStorageKey) : null,
      };
    },
    clearStorage() {
      this.persistField(this.planStorageKey, null);
    },
    openWorkplanAt({ editing = false } = {}) {
      // In the drawer, opening the work plan requires
      // a full navigation to the work item details page.
      // Preserve the url to keep the intent after nav.
      if (this.isInDrawer && this.workItemWebUrl) {
        try {
          visitUrl(buildWorkplanPageUrl(this.workItemWebUrl, { editing }));
          return;
        } catch (e) {
          Sentry.captureException(e);
        }
      }
      this.isEditing = editing;
      writeWorkplanUrl({ editing });
      this.$emit('request-panel', WORKPLAN_PANEL);
    },
    openPanel() {
      if (this.isPanelOpen) {
        this.closePanel();
        return;
      }
      this.openWorkplanAt({ editing: false });
    },
    onCreateManually() {
      this.openWorkplanAt({ editing: true });
    },
    closePanel() {
      this.$emit('request-panel', null);
      clearWorkplanUrl();
      this.isEditing = false;
    },
    syncPanelFromUrl({ canClose = true } = {}) {
      const { requestsPanel, requestsEdit } = parseWorkplanUrlState();
      // The URL carries the edit intent, so mirror it whenever the panel is requested.
      if (requestsPanel) {
        this.isEditing = requestsEdit;
      }
      // URL and panel already are in sync, do nothing
      if (requestsPanel === this.isPanelOpen) {
        return;
      }
      // On initial load a missing param must not close a panel the parent opened.
      if (!requestsPanel && !canClose) {
        return;
      }
      // URL and panel are not in sync and so we open or close to match the URL.
      this.$emit('request-panel', requestsPanel ? WORKPLAN_PANEL : null);
    },
    onPopState() {
      this.syncPanelFromUrl();
    },
    handleDraftChange(value) {
      this.draftContent = value || '';
      this.persistField(this.planStorageKey, value);
    },
    showUpdateError(error) {
      createAlert({
        message: sprintf(I18N_WORK_ITEM_ERROR_UPDATING, {
          workItemType: this.workItemType,
        }),
      });
      Sentry.captureException(error);
    },
    async mutateWorkplanContent() {
      const { data } = await this.$apollo.mutate({
        mutation: updateWorkItemAgentPlanMutation,
        variables: {
          input: {
            id: this.workItemId,
            agentPlanWidget: { content: this.tmpContent },
          },
          useWorkItemFeatures: this.useWorkItemFeatures,
          includeReadinessScore: this.includeReadinessScore,
        },
        update: (cache, { data: result }) => {
          if (result?.workItemUpdate?.errors?.length === 0) {
            const updatedPlan = findWorkplanWidget(result.workItemUpdate.workItem);
            if (!updatedPlan) return;

            writeAgentPlanToCache({
              cache,
              workItemId: this.workItemId,
              workItemIid: this.workItemIid,
              content: this.tmpContent,
              contentHtml: updatedPlan.contentHtml || '',
              aiPlanningEnabled: this.workplan?.aiPlanningEnabled ?? true,
              readinessScore: this.workplan?.readinessScore ?? null,
              generationStatus: this.generationStatus,
              openQuestionsCount: this.openQuestionsCount,
              questions: this.workplan?.questions,
              useWorkItemFeatures: this.useWorkItemFeatures,
              includeReadinessScore: this.includeReadinessScore,
            });
          }
        },
      });
      if (data.workItemUpdate.errors.length) {
        throw new Error(data.workItemUpdate.errors.join('\n'));
      }
    },
    handleStartEdit() {
      this.isEditing = true;
    },
    handleCancelEdit() {
      this.isEditing = false;
      this.draftContent = '';
      this.persistField(this.planStorageKey, null);
      // Cancelling a brand-new create (nothing saved yet) dismisses the panel so
      // no empty workplan is left behind. An existing plan returns to the view.
      if (!this.hasSavedContent) {
        this.closePanel();
      }
    },
    async handleSave(content) {
      // Defence-in-depth: the panel already trims before emitting, but
      // trimming here too means any future caller (e.g. an automated
      // save from a Duo flow) can't accidentally persist whitespace-only
      // content and flip the inline-row status pill to "Ready".
      this.tmpContent = content?.trim() || '';
      this.isSaving = true;
      try {
        await this.mutateWorkplanContent();
        this.isEditing = false;
        this.draftContent = '';
        this.persistField(this.planStorageKey, null);
      } catch (error) {
        this.showUpdateError(error);
      } finally {
        this.isSaving = false;
        this.tmpContent = '';
      }
    },
    // A terminal status is only believed once a later read still agrees, so a run that
    // momentarily reads as finished cannot end the UI's run state or stop polling.
    confirmTerminalStatus() {
      if (this.terminalConfirmTimeout) {
        return;
      }
      this.terminalConfirmTimeout = setTimeout(() => {
        this.terminalConfirmTimeout = null;
        if (!GENERATION_STATUSES_ACTIVE.includes(this.generationStatus)) {
          this.runExpected = false;
        }
      }, TERMINAL_STATUS_CONFIRM_MS);
    },
    cancelTerminalConfirm() {
      clearTimeout(this.terminalConfirmTimeout);
      this.terminalConfirmTimeout = null;
    },
    // Arms the watchdog alongside the flag, so the two can't drift apart and a
    // stale timer can't release an action started after it.
    setFlowActionPending(pending) {
      clearTimeout(this.flowActionTimeout);
      this.isFlowActionInFlight = pending;
      this.flowActionTimeout = pending
        ? setTimeout(() => {
            this.isFlowActionInFlight = false;
          }, FLOW_ACTION_TIMEOUT_MS)
        : null;
    },
    async runFlowMutation({ mutation, payloadKey, failureMessage }) {
      if (this.generationDisabledReason) {
        return null;
      }

      this.planLanded = false;
      this.runExpected = true;
      this.cancelTerminalConfirm();
      this.confirmTerminalStatus();
      this.setFlowActionPending(true);
      try {
        const { data } = await this.$apollo.mutate({
          mutation,
          variables: { input: { id: this.workItemId } },
        });

        // Service messages are written for the user, so surface them verbatim.
        const { errors, workflow } = data[payloadKey];
        if (errors.length) {
          createAlert({ message: errors.join('\n') });
          this.runExpected = false;
          this.setFlowActionPending(false);
          return null;
        }

        // The action deliberately stays pending here. The run keeps its old status
        // for seconds after this returns, so releasing now re-offers the same
        // action; the `generationStatus` watcher releases it instead.
        this.$emit('refetch-plan');
        eventHub.$emit(REFETCH_SESSIONS);
        if (workflow?.id) {
          eventHub.$emit(SHOW_SESSION, { id: getIdFromGraphQLId(workflow.id) });
        }
        return workflow;
      } catch (error) {
        createAlert({ message: failureMessage, captureError: true, error });
        this.runExpected = false;
        this.setFlowActionPending(false);
        return null;
      }
    },
    handleGenerate() {
      return this.runFlowMutation({
        mutation: workItemGenerateWorkplanMutation,
        payloadKey: 'workItemGenerateWorkplan',
        failureMessage: s__('AgentPlan|Something went wrong while starting workplan generation.'),
      });
    },
    handleContinue() {
      return this.runFlowMutation({
        mutation: workItemResumeWorkplanMutation,
        payloadKey: 'workItemResumeWorkplan',
        failureMessage: s__('AgentPlan|Something went wrong while resuming workplan generation.'),
      });
    },
    handleRegenerate() {
      if (this.generationDisabledReason) {
        return;
      }

      if (this.isEditing) {
        this.handleCancelEdit();
      }
      this.closePanel();
      this.handleGenerate();
    },
    async handleDelete() {
      const confirmed = await confirmAction(
        s__(
          'AgentPlan|Are you sure you want to delete this workplan? This action cannot be undone.',
        ),
        {
          primaryBtnText: __('Delete'),
          primaryBtnVariant: 'danger',
        },
      );
      if (!confirmed) return;

      this.tmpContent = '';
      this.isSaving = true;
      this.clearStorage();
      try {
        await this.mutateWorkplanContent();
      } catch (error) {
        this.showUpdateError(error);
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <div>
    <workplan-inline-row
      :can-update="canUpdate"
      :is-panel-open="isPanelOpen"
      :is-loading="isLoading"
      :project-path="fullPath"
      :has-content="hasSavedContent"
      :work-item-iid="workItemIid"
      :work-item-type="workItemType"
      :work-item-web-url="workItemWebUrl"
      :readiness-score="readinessScore"
      :generation="generation"
      :generation-disabled-reason="generationDisabledReason"
      :is-work-item-closed="isWorkItemClosed"
      @open="openPanel"
      @create-manually="onCreateManually"
      @generate="onWorkplanAction(handleGenerate, 'generate', 'inline_row')"
      @retry="onWorkplanAction(handleGenerate, 'retry', 'inline_row')"
      @continue="onWorkplanAction(handleContinue, 'continue', 'inline_row')"
    />
    <workplan-panel
      :open="isPanelOpen"
      :work-item-iid="workItemIid"
      :work-item-type="workItemType"
      :work-item-web-url="workItemWebUrl"
      :readiness-score="readinessScore"
      :saved-content="content"
      :saved-content-html="contentHtml"
      :draft-content="draftContent"
      :can-update="canUpdate"
      :is-editing="isEditing"
      :is-saving="isSaving"
      :is-loading="isLoading"
      :is-flow-active="isFlowActive"
      :is-action-in-flight="isFlowActionInFlight"
      :generation-disabled-reason="generationDisabledReason"
      :is-work-item-closed="isWorkItemClosed"
      @start-edit="handleStartEdit"
      @cancel-edit="handleCancelEdit"
      @save="handleSave"
      @delete="handleDelete"
      @regenerate="onWorkplanAction(handleRegenerate, 'regenerate', 'panel')"
      @generate="onWorkplanAction(handleGenerate, 'generate', 'panel')"
      @draft-change="handleDraftChange"
      @close="closePanel"
    />
  </div>
</template>
