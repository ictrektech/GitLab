<script>
import { GlFilteredSearch, GlFilteredSearchToken } from '@gitlab/ui';
import {
  OPERATORS_IS,
  OPERATORS_IS_NOT,
} from '~/vue_shared/components/filtered_search_bar/constants';
import { queryToObject } from '~/lib/utils/url_utility';
import { convertToSnakeCase } from '~/lib/utils/text_utility';
import { s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import { AGENT_CLASS_EXTERNAL, AGENT_CLASS_INTERNAL_DAP } from 'ee/ai/governance/constants';
import DateToken from '~/vue_shared/components/filtered_search_bar/tokens/date_token.vue';
import ProjectToken from './tokens/project_token.vue';
import TriggeredByToken from './tokens/triggered_by_token.vue';

// Filter types that can be pre-set from the URL, deep-linked from the dashboard
// Developer activity (triggeredByUserId) and Project exposure (projectPath)
// cards, with the card's date window (startTimeAfter) and agent class (agentClass).
const URL_FILTER_TYPES = ['triggeredByUserId', 'projectPath', 'startTimeAfter', 'agentClass'];

// Labels sent with the apply filter event; the per-filter metrics filter on
// them. Both spellings of the agent token count under `agent`. A token type
// that is not listed is tracked under its snake_case name.
const FILTER_TRACKING_LABELS = {
  startTimeAfter: 'created_after',
  startTimeBefore: 'created_before',
  projectPath: 'project',
  triggeredByUserId: 'triggered_by',
  agentType: 'agent',
  agent: 'agent',
};

const filterTrackingLabel = (type) => FILTER_TRACKING_LABELS[type] || convertToSnakeCase(type);

const filterKey = ({ type, value }) => JSON.stringify([type, value.operator, value.data]);

export default {
  name: 'AgentArtifactsFilteredSearch',
  components: {
    GlFilteredSearch,
  },
  mixins: [InternalEvents.mixin()],
  inject: {
    groupId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  emits: ['filter'],
  data() {
    return {
      filterValue: [],
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    tokens() {
      return [
        {
          type: 'startTimeAfter',
          icon: 'calendar',
          title: s__('AgentArtifacts|Created after'),
          token: DateToken,
          unique: true,
          operators: OPERATORS_IS,
        },
        {
          type: 'startTimeBefore',
          icon: 'calendar',
          title: s__('AgentArtifacts|Created before'),
          token: DateToken,
          unique: true,
          operators: OPERATORS_IS,
        },
        !this.isProjectMode &&
          this.groupId && {
            type: 'projectPath',
            icon: 'project',
            title: s__('AgentArtifacts|Project'),
            token: ProjectToken,
            unique: true,
            operators: OPERATORS_IS_NOT,
          },
        {
          type: 'triggeredByUserId',
          icon: 'user',
          title: s__('AgentArtifacts|Triggered by'),
          token: TriggeredByToken,
          unique: true,
          operators: OPERATORS_IS_NOT,
          fullPath: this.projectFullPath || this.groupFullPath,
          isProject: this.isProjectMode,
          valueField: 'id',
          defaultUsers: [],
        },
        {
          type: 'agentClass',
          icon: 'tanuki-ai',
          title: s__('AgentArtifacts|Agent class'),
          token: GlFilteredSearchToken,
          unique: true,
          operators: OPERATORS_IS,
          options: [
            { value: AGENT_CLASS_INTERNAL_DAP, title: s__('AiGovernance|DAP') },
            { value: AGENT_CLASS_EXTERNAL, title: s__('AiGovernance|Connected') },
          ],
        },
      ].filter(Boolean);
    },
  },
  created() {
    // Seed the filter from URL params so deep links (e.g. from the dashboard
    // cards) open the report with the filter already applied. Only seed types
    // that exist as a token in the current mode (projectPath has no token in
    // project mode), so we never create an orphan filter chip.
    const params = queryToObject(window.location.search);
    const availableTypes = new Set(this.tokens.map((token) => token.type));
    const seeded = URL_FILTER_TYPES.filter((type) => params[type] && availableTypes.has(type)).map(
      (type) => ({
        type,
        value: { data: params[type], operator: '=' },
      }),
    );

    // Filters already counted: a search tracks only the ones added or changed since the
    // last one, and filters from the URL never count because the user did not apply them.
    this.trackedFilterKeys = new Set(seeded.map(filterKey));

    if (!seeded.length) return;

    this.filterValue = seeded;
    // Emit after the initial render so the sibling table is mounted and applies
    // the filter; emitting during created() runs before the table can react, so
    // the results would not update. Not tracked: the user applied nothing.
    this.$nextTick(() => this.emitFilter());
  },
  methods: {
    handleSubmit() {
      const applied = this.appliedFilters();

      applied
        .filter((filter) => !this.trackedFilterKeys.has(filterKey(filter)))
        .forEach(({ type }) => {
          this.trackEvent('apply_filter_on_ai_audit_events_report', {
            label: filterTrackingLabel(type),
          });
        });
      this.trackedFilterKeys = new Set(applied.map(filterKey));

      this.emitFilter();
    },
    handleClear() {
      this.trackedFilterKeys = new Set();
      this.$emit('filter', {});
    },
    appliedFilters() {
      return this.filterValue.filter(
        ({ value }) => value?.data && (value.operator === '=' || value.operator === '!='),
      );
    },
    emitFilter() {
      const variables = {};
      const notFilters = {};

      this.appliedFilters().forEach(({ type, value: { data, operator } }) => {
        if (operator === '=') {
          variables[type] = data;
        } else {
          notFilters[type] = data;
        }
      });

      if (Object.keys(notFilters).length > 0) {
        variables.not = notFilters;
      }

      this.$emit('filter', variables);
    },
  },
};
</script>

<template>
  <gl-filtered-search
    v-model="filterValue"
    :placeholder="s__('AgentArtifacts|Filter agent artifacts')"
    :available-tokens="tokens"
    terms-as-tokens
    @submit="handleSubmit"
    @clear="handleClear"
  />
</template>
