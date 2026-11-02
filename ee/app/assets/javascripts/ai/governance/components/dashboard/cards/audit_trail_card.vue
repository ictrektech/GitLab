<script>
import { GlIcon, GlLink } from '@gitlab/ui';
import { s__, n__, sprintf } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { formatAgentDefinition } from 'ee/ai/duo_agents_platform/utils';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import getAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_agent_artifacts.query.graphql';
import getProjectAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_project_agent_artifacts.query.graphql';
import getAiGovernanceSessionsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_sessions.query.graphql';
import getProjectAiGovernanceSessionsQuery from 'ee/ai/governance/graphql/queries/get_project_ai_governance_sessions.query.graphql';
import { AGENT_CLASS_ALL } from 'ee/ai/governance/constants';
import { formatSessionSource } from 'ee/ai/governance/utils';
import DashboardListCard from './dashboard_list_card.vue';

const LIMIT = 5;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A full UUID leaves no room for the agent name, so external rows show its first block.
const shortSessionId = (sessionId) =>
  UUID_PATTERN.test(sessionId) ? String(sessionId).slice(0, 8) : sessionId;

export default {
  name: 'AuditTrailCard',
  components: {
    DashboardListCard,
    TimeAgoTooltip,
    GlIcon,
    GlLink,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  props: {
    agentClass: {
      type: String,
      required: false,
      default: AGENT_CLASS_ALL,
    },
  },
  apollo: {
    sessionArtifacts: {
      query() {
        if (this.sessionsApiEnabled) {
          return this.isProjectMode
            ? getProjectAiGovernanceSessionsQuery
            : getAiGovernanceSessionsQuery;
        }

        return this.isProjectMode ? getProjectAgentArtifactsQuery : getAgentArtifactsQuery;
      },
      variables() {
        // 19.4 shipped this card unfiltered, and `INTERNAL_DAP` is narrower
        // than no filter at all. Only send the class once the filter flag is
        // on, so the flag-off query stays identical to what 19.4 ships.
        const base = this.connectedAgentsFilterEnabled
          ? { first: LIMIT, agentClass: this.agentClass }
          : { first: LIMIT };

        return this.isProjectMode
          ? { ...base, projectFullPath: this.projectFullPath }
          : { ...base, groupFullPath: this.groupFullPath };
      },
      update(data) {
        const container = data.project ?? data.group;
        const connection = this.sessionsApiEnabled
          ? container?.aiGovernanceSessions
          : container?.duoWorkflowSessionArtifacts;

        return connection?.nodes || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      sessionArtifacts: [],
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    connectedAgentsFilterEnabled() {
      return Boolean(this.glFeatures.aiGovernanceConnectedAgentsFilter);
    },
    sessionsApiEnabled() {
      return Boolean(this.glFeatures.aiGovernanceSessionsApi);
    },
    loading() {
      return this.$apollo.queries.sessionArtifacts.loading;
    },
    sessions() {
      return (this.sessionArtifacts || []).map((node) => {
        const id = getIdFromGraphQLId(node.id);
        const sourceLabel = formatSessionSource(node);
        const flowType = node.flowType ?? node.workflowDefinition;
        // External sessions carry no flow type, so their source names them.
        const name = !flowType && sourceLabel ? sourceLabel : formatAgentDefinition(flowType);
        const isExternal = node.source !== 'GITLAB_DUO' && name === sourceLabel;
        // The audit events tab opens its drawer by `sessionId` on the sessions API,
        // for every source, and by workflow id on the legacy one.
        const drawerId = this.sessionsApiEnabled ? node.sessionId : id;

        return {
          id,
          // The session's own DAP page is scoped to whoever ran it, so it 404s
          // for anyone else. Link to the audit events tab instead and let it
          // open the session in the drawer.
          href: drawerId ? `?tab=agent-artifacts&session=${drawerId}` : '?tab=agent-artifacts',
          createdAt: node.sessionStartedAt ?? node.workflowCreatedAt,
          title: isExternal
            ? sprintf(s__('AiGovernance|Session #%{id} done by %{agent}'), {
                id: shortSessionId(node.sessionId ?? id),
                agent: name,
              })
            : sprintf(s__('AiGovernance|Session #%{id} · %{name}'), {
                id: node.sessionId ?? id,
                name,
              }),
          // When the source already names the row, do not repeat it underneath.
          subtitle: this.subtitleFor(node, name === sourceLabel ? null : sourceLabel),
        };
      });
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.sessions.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load audit logs.') : '';
    },
  },
  methods: {
    subtitleFor(node, sourceLabel) {
      const events = n__(
        'AiGovernance|%d audit event',
        'AiGovernance|%d audit events',
        node.auditEventsCount ?? 0,
      );

      return sourceLabel ? `${events} · ${sourceLabel}` : events;
    },
  },
  i18n: {
    title: s__('AiGovernance|Recent agent sessions'),
    viewAll: s__('AiGovernance|View all audit logs'),
    empty: s__('AiGovernance|No recent agent sessions.'),
    footnote: s__('AiGovernance|Shows the last 180 days, not filtered by date range.'),
  },
  // Links to the "Audit events" tab on the same governance page.
  viewAllHref: '?tab=agent-artifacts',
};
</script>

<template>
  <dashboard-list-card
    :title="$options.i18n.title"
    :view-all-text="$options.i18n.viewAll"
    :view-all-href="$options.viewAllHref"
    :loading="loading"
    :error-text="errorText"
    :is-empty="isEmpty"
    :empty-text="$options.i18n.empty"
    :footnote="$options.i18n.footnote"
    tracking-label="audit_trail"
  >
    <li
      v-for="session in sessions"
      :key="session.id"
      class="gl-border-b gl-border-section last:gl-border-b-0"
    >
      <gl-link
        :href="session.href"
        class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-p-4 gl-text-default hover:gl-bg-strong hover:gl-no-underline"
        data-testid="audit-trail-row"
        data-event-tracking="click_card_link_on_ai_governance_dashboard"
        data-event-label="audit_trail"
        data-event-property="row"
      >
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <gl-icon name="documents" class="gl-shrink-0 gl-text-subtle" />
          <span class="gl-min-w-0">
            <span class="gl-block gl-truncate gl-font-bold">{{ session.title }}</span>
            <span class="gl-block gl-truncate gl-text-sm gl-text-subtle">
              {{ session.subtitle }}
            </span>
          </span>
        </span>
        <span class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
          <time-ago-tooltip :time="session.createdAt" />
          <gl-icon name="chevron-right" data-testid="audit-trail-chevron" />
        </span>
      </gl-link>
    </li>
  </dashboard-list-card>
</template>
