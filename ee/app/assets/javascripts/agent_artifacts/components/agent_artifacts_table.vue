<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlTable,
  GlLink,
  GlSprintf,
  GlKeysetPagination,
  GlLoadingIcon,
  GlBadge,
  GlTruncate,
  GlAlert,
} from '@gitlab/ui';
import { formatDate } from '~/lib/utils/datetime_utility';
import { s__, __, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { formatSessionName, getClientType, normalizeLegacySession } from '../utils';
import getAgentArtifactsQuery from '../graphql/queries/get_agent_artifacts.query.graphql';
import getProjectAgentArtifactsQuery from '../graphql/queries/get_project_agent_artifacts.query.graphql';
import getAiGovernanceSessionsQuery from '../graphql/queries/get_agent_artifacts_ai_governance_sessions.query.graphql';
import getProjectAiGovernanceSessionsQuery from '../graphql/queries/get_project_agent_artifacts_ai_governance_sessions.query.graphql';
import ClientTypeIcon from './client_type_icon.vue';

const DEFAULT_PAGE_SIZE = 10;
// Both session fields list at most this many days before `startTimeBefore` (or today) and
// move an earlier `startTimeAfter` up to that bound, so a wider filter needs a note.
const MAX_WINDOW_DAYS = 180;
const DAY_MS = 24 * 60 * 60 * 1000;

// The date tokens are date-only strings, which parse as UTC midnight, and the backend bounds the
// window in UTC, so the day count is taken on UTC calendar days rather than the viewer's local ones.
const utcDay = (value) => {
  const date = value ? new Date(value) : new Date();

  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
};

export default {
  name: 'AgentArtifactsTable',
  components: {
    GlAvatar,
    GlAvatarLink,
    GlTable,
    GlLink,
    GlSprintf,
    GlKeysetPagination,
    GlLoadingIcon,
    GlBadge,
    GlTruncate,
    GlAlert,
    ClientTypeIcon,
  },
  mixins: [glFeatureFlagsMixin(), InternalEvents.mixin()],
  inject: {
    groupFullPath: { default: null },
    projectFullPath: { default: null },
    aiAuditEventsStorageEnabled: { default: true },
    aiAuditEventsSettingsPath: { default: '' },
  },
  props: {
    activeItem: {
      type: Object,
      required: false,
      default: null,
    },
    filter: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    deepLinkedSessionId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['row-click', 'deep-link-missed'],
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
        const paging = {
          last: this.before ? DEFAULT_PAGE_SIZE : null,
          first: this.before ? null : DEFAULT_PAGE_SIZE,
          after: this.after,
          before: this.before,
        };

        if (this.isProjectMode) {
          return {
            projectFullPath: this.projectFullPath,
            ...paging,
            ...this.filter,
          };
        }

        return {
          groupFullPath: this.groupFullPath,
          ...paging,
          ...this.filter,
        };
      },
      skip() {
        return this.isProjectMode ? !this.projectFullPath : !this.groupFullPath;
      },
      update(data) {
        this.hasError = false;
        const container = data.project ?? data.group;

        if (this.sessionsApiEnabled) {
          return container?.aiGovernanceSessions || [];
        }

        const connection = container?.duoWorkflowSessionArtifacts;
        if (!connection) return [];

        return { ...connection, nodes: (connection.nodes || []).map(normalizeLegacySession) };
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      deepLinkConsumed: false,
      sessionArtifacts: null,
      after: null,
      before: null,
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    sessionsApiEnabled() {
      return Boolean(this.glFeatures.aiGovernanceSessionsApi);
    },
    clampedWindowEnd() {
      const { startTimeAfter, startTimeBefore } = this.filter;
      if (!startTimeAfter) {
        return startTimeBefore ? new Date(utcDay(startTimeBefore)) : null;
      }

      const days = (utcDay(startTimeBefore) - utcDay(startTimeAfter)) / DAY_MS;

      return days > MAX_WINDOW_DAYS ? new Date(utcDay(startTimeBefore)) : null;
    },
    clampedWindowMessage() {
      return sprintf(
        s__(
          'AgentArtifacts|Showing the 180 days before %{date}. Sessions are listed for up to 180 days at a time.',
        ),
        { date: formatDate(this.clampedWindowEnd, 'mmm d, yyyy', true) },
      );
    },
    isLoading() {
      return this.$apollo.queries.sessionArtifacts.loading;
    },
    items() {
      return this.sessionArtifacts?.nodes || [];
    },
    hasActiveFilter() {
      return Object.keys(this.filter).length > 0;
    },
    showStorageDisabledMessage() {
      return !this.aiAuditEventsStorageEnabled && !this.hasActiveFilter && !this.hasError;
    },
    pageInfo() {
      return this.sessionArtifacts?.pageInfo || {};
    },
    fields() {
      return [
        {
          key: 'aiItem',
          label: s__('AgentArtifacts|AI Item'),
          tdClass: '@max-sm/panel:gl-w-full @max-lg/panel:gl-wrap-anywhere @sm/panel:gl-max-w-30',
          thClass: '@sm/panel:gl-max-w-30',
        },
        {
          key: 'triggeredBy',
          label: __('User'),
          tdClass: 'gl-whitespace-nowrap',
        },
        {
          key: 'id',
          label: s__('AgentArtifacts|Session ID'),
          tdClass: 'gl-whitespace-nowrap @sm/panel:gl-max-w-20',
        },
        {
          key: 'auditEvents',
          label: s__('AgentArtifacts|Audit events'),
          tdClass: 'gl-whitespace-nowrap',
        },
        // The Project column is redundant in project mode (every row is the current project).
        ...(this.isProjectMode
          ? []
          : [
              {
                key: 'project',
                label: __('Project'),
                tdClass:
                  '@max-lg/panel:gl-w-full @max-lg/panel:gl-wrap-anywhere @lg/panel:gl-max-w-30 gl-hidden @lg/panel:!gl-table-cell',
                thClass: 'gl-max-w-30 gl-hidden @lg/panel:!gl-table-cell',
              },
            ]),
        {
          key: 'startTime',
          label: s__('AgentArtifacts|Start time'),
          tdClass: 'gl-whitespace-nowrap',
        },
      ];
    },
  },
  watch: {
    filter() {
      this.after = null;
      this.before = null;
    },
    // A deep link names a session by id, but the drawer needs the loaded row,
    // so it can only open once the query has resolved. Emitting row-click
    // reuses the same path a real click takes.
    //
    // Consumed on the FIRST resolution whether or not it matched. The linked
    // session may not be on page 1, and leaving the id live would mean a later
    // page or filter that happens to contain it pops the drawer open long
    // after the user has moved on.
    items() {
      if (this.deepLinkConsumed || !this.deepLinkedSessionId) return;

      this.deepLinkConsumed = true;

      const match = this.items.find(
        (item) => String(item.sessionId) === String(this.deepLinkedSessionId),
      );

      if (match) {
        this.$emit('row-click', match);
      } else {
        this.$emit('deep-link-missed');
      }
    },
  },
  methods: {
    rowClass(item) {
      const classes = ['gl-cursor-pointer', 'hover:gl-bg-gray-50'];
      if (item === this.activeItem) {
        classes.push('!gl-bg-blue-50');
      }
      return classes;
    },
    // A deep link emits row-click from the items watcher instead, so only a
    // click by the user is tracked.
    handleRowClick(item) {
      this.trackEvent('open_session_on_ai_audit_events_report');
      this.$emit('row-click', item);
    },
    handleNext(endCursor) {
      this.trackEvent('paginate_ai_audit_events_report', { label: 'next' });
      this.after = endCursor;
      this.before = null;
    },
    handlePrev(startCursor) {
      this.trackEvent('paginate_ai_audit_events_report', { label: 'prev' });
      this.before = startCursor;
      this.after = null;
    },
    formatStartDate(dateString) {
      return formatDate(dateString, 'yyyy-mm-dd');
    },
    formatStartTime(dateString) {
      return formatDate(dateString, 'HH:MM:ss Z');
    },
    formatSessionName(item) {
      return formatSessionName(item);
    },
    getClientType(item) {
      return getClientType(item);
    },
  },
};
</script>

<template>
  <div>
    <gl-alert v-if="hasError" variant="danger" :dismissible="false" class="gl-mb-5">
      {{ s__('AgentArtifacts|Failed to load agent artifacts.') }}
    </gl-alert>
    <gl-alert
      v-else-if="clampedWindowEnd"
      variant="info"
      :dismissible="false"
      class="gl-mb-5"
      data-testid="clamped-window-alert"
    >
      {{ clampedWindowMessage }}
    </gl-alert>
    <gl-table
      :fields="fields"
      :items="items"
      :busy="isLoading"
      show-empty
      stacked="sm"
      :tbody-tr-class="rowClass"
      :tbody-tr-attr="{ 'data-testid': 'agent-artifacts-table-row' }"
      @row-clicked="handleRowClick"
    >
      <template #table-busy>
        <gl-loading-icon size="lg" class="gl-my-5" />
      </template>

      <template #empty>
        <div
          v-if="showStorageDisabledMessage"
          class="gl-py-5 gl-text-center"
          data-testid="storage-disabled-empty-state"
        >
          <gl-sprintf
            :message="
              s__(
                'AgentArtifacts|AI audit event storage is turned off, so no audit events are being recorded. %{linkStart}Turn on storage%{linkEnd} to start capturing audit events.',
              )
            "
          >
            <template #link="{ content }">
              <gl-link
                v-if="aiAuditEventsSettingsPath"
                :href="aiAuditEventsSettingsPath"
                data-testid="enable-storage-link"
                >{{ content }}</gl-link
              >
              <span v-else>{{ content }}</span>
            </template>
          </gl-sprintf>
        </div>
        <div v-else class="gl-py-5 gl-text-center">
          {{ s__('AgentArtifacts|No agent artifacts found.') }}
        </div>
      </template>

      <template #cell(aiItem)="{ item }">
        <div class="gl-flex gl-items-center gl-gap-3">
          <client-type-icon
            :client-type="getClientType(item)"
            data-testid="ai-item-client-type-icon"
          />
          <div class="gl-flex gl-min-w-0 gl-flex-col">
            <span data-testid="ai-item-client-type-name">{{ getClientType(item).name }}</span>
            <gl-truncate
              :text="formatSessionName(item)"
              class="gl-min-w-0 gl-max-w-full gl-text-sm gl-text-subtle"
              with-tooltip
              data-testid="ai-item-name"
            />
          </div>
        </div>
      </template>

      <template #cell(triggeredBy)="{ item }">
        <div
          v-if="item.triggeredBy?.webPath"
          class="gl-flex gl-items-center gl-gap-2"
          data-testid="user-cell"
        >
          <gl-avatar-link
            :href="item.triggeredBy.webPath"
            data-event-tracking="click_linked_item_on_ai_audit_events_report"
            data-event-label="user"
            data-event-property="table"
          >
            <gl-avatar
              :src="item.triggeredBy.avatarUrl"
              :entity-name="item.triggeredBy.name"
              :size="16"
              data-testid="user-avatar"
            />
          </gl-avatar-link>
          <gl-link
            :href="item.triggeredBy.webPath"
            data-testid="user-link"
            data-event-tracking="click_linked_item_on_ai_audit_events_report"
            data-event-label="user"
            data-event-property="table"
            >{{ item.triggeredBy.name }}</gl-link
          >
        </div>
        <span v-else class="gl-text-subtle" data-testid="user-empty">—</span>
      </template>

      <!-- Plain text, not a link. The whole row already opens the drawer, so a
           link here is a second interactive control inside a clickable row,
           and it pointed at the session's own page, which 404s for anyone who
           did not run it. -->
      <template #cell(id)="{ item }">
        <gl-truncate
          v-if="item.sessionId"
          :text="`#${item.sessionId}`"
          class="gl-min-w-0 gl-max-w-full"
          with-tooltip
          data-testid="session-link"
        />
        <span v-else class="gl-text-subtle" data-testid="session-id-empty">—</span>
      </template>

      <template #cell(auditEvents)="{ item }">
        <gl-badge
          v-if="item.auditEventsCount != null"
          variant="neutral"
          class="gl-px-4"
          data-testid="audit-events-count"
        >
          {{ item.auditEventsCount }}
        </gl-badge>
        <span v-else class="gl-text-subtle" data-testid="audit-events-empty">—</span>
      </template>

      <template #cell(project)="{ item }">
        <gl-link
          v-if="item.project?.webPath"
          :href="item.project.webPath"
          data-testid="project-link"
          data-event-tracking="click_linked_item_on_ai_audit_events_report"
          data-event-label="project"
          data-event-property="table"
        >
          <gl-truncate
            :text="item.project.name"
            class="gl-min-w-0 gl-max-w-full hover:gl-underline"
            with-tooltip
          />
        </gl-link>
        <span v-else class="gl-text-subtle" data-testid="project-empty">—</span>
      </template>

      <template #cell(startTime)="{ item }">
        <div class="gl-text-subtle" data-testid="start-time">
          <div>{{ formatStartDate(item.sessionStartedAt) }}</div>
          <div>{{ formatStartTime(item.sessionStartedAt) }}</div>
        </div>
      </template>
    </gl-table>

    <div
      v-if="pageInfo.hasNextPage || pageInfo.hasPreviousPage"
      class="gl-mt-5 gl-flex gl-justify-center"
    >
      <gl-keyset-pagination v-bind="pageInfo" @prev="handlePrev" @next="handleNext" />
    </div>
  </div>
</template>
