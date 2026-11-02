<script>
import emptyStateIllustrationPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-ai-catalog-md.svg?url';
import { GlButton, GlKeysetPagination, GlToastMixin } from '@gitlab/ui';
import { isEqual } from 'lodash-es';
import { s__ } from '~/locale';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import { fetchPolicies } from '~/lib/graphql';
import { setPageFullWidth, setPageDefaultWidth } from '~/lib/utils/common_utils';
import { parseErrorMessage } from '~/lib/utils/error_message';
import EmptyResult, { TYPES } from '~/vue_shared/components/empty_result.vue';
import PanelActionsPortal from '~/vue_shared/components/panel_actions_portal.vue';
import ResourceListsEmptyState from '~/vue_shared/components/resource_lists/empty_state.vue';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import ResourceListsLoadingStateList from '~/vue_shared/components/resource_lists/loading_state_list.vue';
import { TYPENAME_AI_FLOW_TRIGGER } from 'ee/graphql_shared/constants';
import getAiFlowTriggers from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_triggers.query.graphql';
import getAutomations from 'ee/ai/duo_agents_platform/graphql/queries/get_automations.query.graphql';
import getAutomationsCount from 'ee/ai/duo_agents_platform/graphql/queries/get_automations_count.query.graphql';
import getAiFlowTriggerRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_trigger_run_stats.query.graphql';
import deleteAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/delete_ai_flow_trigger.mutation.graphql';
import updateAiFlowTrigger from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import { FLOW_TRIGGERS_INDEX_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { initialPaginationParams, reactivePaginationMethods } from 'ee/ai/catalog/pagination_utils';
import { DUO_AGENT_PLATFORM_POLLING_INTERVAL } from 'ee/ai/duo_agents_platform/constants';
import AutomationModal from '../components/automation_modal.vue';
import AutomationDetailsPanel from './components/automation_details_panel.vue';
import AutomationRow from './components/automation_row.vue';
import AutomationsFilteredSearch from './components/automations_filtered_search.vue';
import AutomationsStats from './components/automations_stats.vue';
import {
  DEFAULT_KIND,
  DEFAULT_SORT,
  EVENT_TYPE_OPTIONS,
  KIND_EVENT,
  KIND_SCHEDULED,
  LAST_RUN_OPTIONS,
  SEARCH_MAX_LENGTH,
  SORT_OPTIONS,
  STATUS_OFF,
  STATUS_ON,
} from './constants';

const SORT_VALUES = SORT_OPTIONS.flatMap(({ sortDirection }) => Object.values(sortDirection));

export default {
  name: 'AutomationsIndex',
  components: {
    AutomationDetailsPanel,
    AutomationModal,
    AutomationRow,
    AutomationsFilteredSearch,
    AutomationsStats,
    ConfirmActionModal,
    EmptyResult,
    GlButton,
    GlKeysetPagination,
    PanelActionsPortal,
    ResourceListsEmptyState,
    ResourceListsLoadingStateList,
  },
  mixins: [glAbilitiesMixin(), GlToastMixin],
  inject: ['projectPath'],
  data() {
    return {
      automations: [],
      selectedAutomation: null,
      automationsCount: 0,
      pageInfo: {},
      paginationVariables: initialPaginationParams(),
      idToBeDeleted: null,
      togglingIds: [],
      isModalOpen: false,
      automationToEdit: null,
    };
  },
  apollo: {
    automationsCount: {
      query: getAutomationsCount,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return { projectPath: this.projectPath };
      },
      update: (data) => data.project?.aiFlowTriggers?.count ?? 0,
      error(error) {
        Sentry.captureException(error);
      },
    },
    selectedAutomation: {
      query: getAiFlowTriggers,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      skip() {
        return !this.selectedId;
      },
      variables() {
        return {
          projectPath: this.projectPath,
          ids: [convertToGraphQLId(TYPENAME_AI_FLOW_TRIGGER, this.selectedId)],
        };
      },
      update: (data) => data.project?.aiFlowTriggers?.nodes[0] ?? null,
      result({ data, loading, error }) {
        if (!loading && !error && !data?.project?.aiFlowTriggers?.nodes.length) {
          this.closeSelected();
        }
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
    automations: {
      query: getAutomations,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          projectPath: this.projectPath,
          ...this.filterVariables,
          ...this.paginationVariables,
        };
      },
      update: (data) => data.project?.aiFlowTriggers?.nodes ?? [],
      result({ data, loading, error }) {
        const connection = data?.project?.aiFlowTriggers;
        this.pageInfo = connection?.pageInfo ?? {};
        if (loading || error) return;

        const { after, before } = this.paginationVariables;
        if (connection && !connection.nodes.length && (after || before)) {
          this.resetPagination();
          return;
        }

        if (this.automations.some(({ runningCount }) => runningCount > 0)) {
          this.$apollo.queries.automations.startPolling(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
        } else {
          this.$apollo.queries.automations.stopPolling();
        }
      },
      error(error) {
        this.$apollo.queries.automations.stopPolling();
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to fetch automations'),
          captureError: true,
          error,
        });
      },
    },
  },
  computed: {
    isCountLoading() {
      return this.$apollo.queries.automationsCount.loading && !this.automationsCount;
    },
    hasFilters() {
      return Object.keys(this.filters).length > 0;
    },
    emptyKindTitle() {
      return this.kind === KIND_EVENT
        ? s__('DuoAgentsPlatform|No event based automations')
        : s__('DuoAgentsPlatform|No scheduled automations');
    },
    isLoading() {
      return this.$apollo.queries.automations.loading;
    },
    kind() {
      const { kind } = this.$route.query;
      return [KIND_SCHEDULED, KIND_EVENT].includes(kind) ? kind : DEFAULT_KIND;
    },
    filters() {
      const { status, event, last_run: lastRun, search } = this.$route.query;
      const isValidEvent =
        this.kind === KIND_EVENT && EVENT_TYPE_OPTIONS.some(({ value }) => value === event);
      const isValidLastRun = LAST_RUN_OPTIONS.some(({ value }) => value === lastRun);

      return {
        ...([STATUS_ON, STATUS_OFF].includes(status) && { status }),
        ...(isValidEvent && { event }),
        ...(isValidLastRun && { last_run: lastRun }),
        ...(search && { search: search.slice(0, SEARCH_MAX_LENGTH) }),
      };
    },
    sort() {
      const { sort } = this.$route.query;
      return SORT_VALUES.includes(sort) ? sort : DEFAULT_SORT;
    },
    filterVariables() {
      const { status, event, last_run: lastRun, search } = this.filters;

      return {
        kind: this.kind.toUpperCase(),
        active: status ? status === STATUS_ON : null,
        eventType: EVENT_TYPE_OPTIONS.find(({ value }) => value === event)?.graphQL ?? null,
        lastRunStatus: LAST_RUN_OPTIONS.find(({ value }) => value === lastRun)?.graphQL ?? null,
        search: search ?? null,
        sort: this.sort,
      };
    },
    showNewAutomationButton() {
      return (
        this.glAbilities.manageAiFlowTriggers &&
        (this.glAbilities.readAiCatalogThirdPartyFlow ||
          this.glAbilities.readAiCatalogFlow ||
          this.glAbilities.createAiCatalogThirdPartyFlow)
      );
    },
    emptyStateDescription() {
      return this.glAbilities.manageAiFlowTriggers
        ? s__(
            'DuoAgentsPlatform|Automations connect flows or external agents to events or schedules in this project. Create an automation to determine when your flows or external agents run.',
          )
        : s__(
            'DuoAgentsPlatform|Automations connect flows or external agents to events or schedules in this project.',
          );
    },
    selectedId() {
      return this.$route.params.id;
    },
    currentAutomation() {
      const isSelected = (automation) =>
        getIdFromGraphQLId(automation?.id) === Number(this.selectedId);

      return (
        this.automations.find(isSelected) ??
        (isSelected(this.selectedAutomation) ? this.selectedAutomation : undefined)
      );
    },
  },
  watch: {
    '$route.query': {
      handler(query, oldQuery) {
        if (!isEqual(query, oldQuery)) this.resetPagination();
      },
    },
  },
  mounted() {
    setPageFullWidth();
  },
  beforeDestroy() {
    setPageDefaultWidth();
  },
  methods: {
    ...reactivePaginationMethods,
    openModal(automation = null) {
      this.automationToEdit = automation;
      this.isModalOpen = true;
    },
    closeModal() {
      this.isModalOpen = false;
      this.automationToEdit = null;
    },
    onSaved() {
      this.$apollo.queries.automations.refetch();
      this.$apollo.queries.automationsCount.refetch();
    },
    isToggling(id) {
      return this.togglingIds.includes(id);
    },
    async deleteAutomation() {
      try {
        await this.$apollo.mutate({
          mutation: deleteAiFlowTrigger,
          variables: {
            id: this.idToBeDeleted,
          },
          refetchQueries: [getAutomations, getAutomationsCount, getAiFlowTriggerRunStats],
        });

        if (getIdFromGraphQLId(this.idToBeDeleted) === Number(this.selectedId)) {
          this.closeSelected();
        }
        this.$toast.show(s__('DuoAgentsPlatform|Automation deleted successfully.'));
      } catch (error) {
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to delete automation.'),
          captureError: true,
          error,
        });
      } finally {
        this.resetIdToBeDeleted();
      }
    },
    closeSelected() {
      return this.$router.replace({ name: FLOW_TRIGGERS_INDEX_ROUTE, query: this.$route.query });
    },
    async closePanel() {
      const { id } = this.currentAutomation;

      await this.closeSelected();
      await this.$nextTick();
      this.$el.querySelector(`[data-automation-id="${id}"]`)?.focus();
    },
    resetIdToBeDeleted() {
      this.idToBeDeleted = null;
    },
    async toggleAutomation({ id, active }) {
      this.togglingIds = [...this.togglingIds, id];

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiFlowTrigger,
          variables: { input: { id, active } },
        });

        const { errors } = data.aiFlowTriggerUpdate;

        if (errors.length > 0) {
          createAlert({ message: errors.join(' ') });
          return;
        }

        if (this.filters.status) {
          this.$apollo.queries.automations.refetch();
        }

        this.$toast.show(
          active
            ? s__('DuoAgentsPlatform|Automation turned on')
            : s__('DuoAgentsPlatform|Automation turned off'),
        );
      } catch (error) {
        createAlert({
          message: parseErrorMessage(error, s__('DuoAgentsPlatform|Failed to update automation.')),
          error,
          captureError: true,
        });
      } finally {
        this.togglingIds = this.togglingIds.filter((togglingId) => togglingId !== id);
      }
    },
  },
  emptyStateIllustrationPath,
  emptyResultType: TYPES.filter,
};
</script>

<template>
  <div>
    <h1 class="gl-sr-only">{{ s__('DuoAgentsPlatform|Automations') }}</h1>
    <panel-actions-portal v-if="showNewAutomationButton">
      <gl-button variant="confirm" size="small" @click="openModal()">
        {{ s__('DuoAgentsPlatform|New automation') }}
      </gl-button>
    </panel-actions-portal>
    <resource-lists-loading-state-list v-if="isCountLoading" />
    <resource-lists-empty-state
      v-else-if="!automationsCount"
      :title="s__('DuoAgentsPlatform|No automations yet')"
      :description="emptyStateDescription"
      :svg-path="$options.emptyStateIllustrationPath"
    >
      <template v-if="showNewAutomationButton" #actions>
        <gl-button variant="confirm" @click="openModal()">
          {{ s__('DuoAgentsPlatform|New automation') }}
        </gl-button>
      </template>
    </resource-lists-empty-state>
    <template v-else>
      <automations-stats />
      <automations-filtered-search :kind="kind" :filters="filters" :sort="sort" />
      <resource-lists-loading-state-list v-if="isLoading" />
      <empty-result
        v-else-if="!automations.length && hasFilters"
        :type="$options.emptyResultType"
      />
      <resource-lists-empty-state
        v-else-if="!automations.length"
        :title="emptyKindTitle"
        :svg-path="$options.emptyStateIllustrationPath"
      />
      <ul v-else class="gl-m-0 gl-list-none gl-p-0">
        <automation-row
          v-for="automation in automations"
          :key="automation.id"
          :automation="automation"
          :is-toggling="isToggling(automation.id)"
          :is-selected="automation === currentAutomation"
          @delete="(id) => (idToBeDeleted = id)"
          @toggle="toggleAutomation"
          @edit="openModal"
        />
      </ul>
      <gl-keyset-pagination
        v-bind="pageInfo"
        class="gl-mt-5 gl-flex gl-justify-center"
        @prev="handlePrevPage"
        @next="handleNextPage"
      />
      <confirm-action-modal
        v-if="idToBeDeleted"
        modal-id="delete-automation-modal"
        variant="danger"
        :title="s__('DuoAgentsPlatform|Delete automation')"
        :action-fn="deleteAutomation"
        :action-text="__('Delete')"
        @close="resetIdToBeDeleted"
      >
        {{
          s__(
            'DuoAgentsPlatform|Are you sure you want to delete this automation? This action cannot be undone.',
          )
        }}
      </confirm-action-modal>
    </template>
    <automation-modal
      v-if="isModalOpen"
      :automation="automationToEdit"
      @saved="onSaved"
      @hidden="closeModal"
    />
    <automation-details-panel
      v-if="currentAutomation"
      :key="currentAutomation.id"
      :automation="currentAutomation"
      @close="closePanel"
    />
  </div>
</template>
