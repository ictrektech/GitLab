<script>
import { GlPopover, GlIcon, GlLink, GlAvatar, GlSkeletonLoader } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { parseAgentSessionUrl } from '~/blob/components/source_viewer/utils';
import TimeagoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { formatAgentFlowTitle, formatAgentStatus } from 'ee/ai/duo_agents_platform/utils';
import agentSessionQuery from '../queries/agent_session.query.graphql';
import agentSessionLinksQuery from '../queries/agent_session_links.query.graphql';
import {
  buildLinkedItems,
  isCreatedLinkedItem,
  pickShownLinkedItems,
} from '../utils/agent_session_linked_items';
import AgentSessionLink from './agent_session_link.vue';

const LINKED_ITEM_ACCESSIBLE_LABELS = {
  workItem: {
    source: s__('Blame|from work item %{reference}'),
    created: s__('Blame|created work item %{reference}'),
  },
  mergeRequest: {
    source: s__('Blame|from merge request %{reference}'),
    created: s__('Blame|created merge request %{reference}'),
  },
  pipeline: {
    source: s__('Blame|from pipeline %{reference}'),
    created: s__('Blame|created pipeline %{reference}'),
  },
  note: {
    source: s__('Blame|from a note on %{reference}'),
    created: s__('Blame|created a note on %{reference}'),
  },
};

export default {
  name: 'AgentSessionPopover',
  // A short show delay keeps the pointer passing over the icon from fetching details.
  POPOVER_DELAY: { show: 200, hide: 150 },
  components: {
    GlPopover,
    GlIcon,
    GlLink,
    GlAvatar,
    GlSkeletonLoader,
    TimeagoTooltip,
    AgentSessionLink,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    sessionUrls: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      hasLoaded: false,
      isLoading: false,
      sessionDetails: {},
    };
  },
  computed: {
    sessions() {
      return this.sessionUrls
        .map((url) => ({ id: parseAgentSessionUrl(url)?.id, url }))
        .filter(({ id }) => id);
    },
    sessionViewModels() {
      return this.sessions.map((session) => {
        const details = this.sessionDetails[session.id];
        if (!details) {
          return {
            ...session,
            title: sprintf(s__('Blame|Agent session %{id}'), { id: session.id }),
            details: null,
          };
        }

        const linkedItems = buildLinkedItems(details);
        const shownLinkedItems = pickShownLinkedItems(linkedItems);
        const moreLinkedItemsCount = linkedItems.length - shownLinkedItems.length;

        return {
          ...session,
          title: formatAgentFlowTitle(details.title, details.workflowDefinition),
          details,
          // Finished is the expected state for committed code, so only other states are called out.
          status: details.status === 'FINISHED' ? null : formatAgentStatus(details.humanStatus),
          linkedItems: shownLinkedItems.map((item) => ({
            ...item,
            label: this.linkedItemLabel(item),
            accessibleLabel: this.linkedItemAccessibleLabel(item),
          })),
          moreLinkedItemsCount,
          moreLinkedItemsLabel: sprintf(
            n__('Blame|+%{count} more', 'Blame|+%{count} more', moreLinkedItemsCount),
            { count: moreLinkedItemsCount },
          ),
          moreLinkedItemsAccessibleLabel: sprintf(
            n__(
              'Blame|+%{count} more linked item',
              'Blame|+%{count} more linked items',
              moreLinkedItemsCount,
            ),
            { count: moreLinkedItemsCount },
          ),
        };
      });
    },
  },
  methods: {
    onShow() {
      this.trackEvent('view_agent_session_popover');

      if (this.hasLoaded || this.isLoading) return;
      this.fetchSessionDetails();
    },
    // Each session is looked up by ID, the way the Duo panel opens it. A session
    // the user cannot read is an error for its own lookup, so the others still load.
    async fetchSessionDetails() {
      this.isLoading = true;
      const nodes = await Promise.all(this.sessions.map(({ id }) => this.fetchSession(id)));
      this.hasLoaded = nodes.some(Boolean);
      this.sessionDetails = Object.fromEntries(
        nodes.filter(Boolean).map((node) => [String(getIdFromGraphQLId(node.id)), node]),
      );
      this.isLoading = false;
    },
    async fetchSession(id) {
      const variables = { workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, id) };
      const firstNode = (result) =>
        result.status === 'fulfilled' ? result.value.data?.duoWorkflowWorkflows?.nodes?.[0] : null;
      const [details, links] = await Promise.allSettled([
        this.$apollo.query({ query: agentSessionQuery, variables }),
        this.$apollo.query({ query: agentSessionLinksQuery, variables }),
      ]);
      const node = firstNode(details);

      return node ? { ...node, ...firstNode(links) } : null;
    },
    linkedItemLabel(item) {
      const { kind, reference } = item;
      const created = isCreatedLinkedItem(item);

      if (kind === 'note' && !reference) {
        return created ? s__('Blame|created a note') : s__('Blame|from a note');
      }
      return created
        ? sprintf(s__('Blame|created %{reference}'), { reference })
        : sprintf(s__('Blame|from %{reference}'), { reference });
    },
    linkedItemAccessibleLabel(item) {
      const { kind, reference } = item;
      if (!reference) return null;

      const labels = LINKED_ITEM_ACCESSIBLE_LABELS[kind];
      return sprintf(isCreatedLinkedItem(item) ? labels.created : labels.source, { reference });
    },
  },
};
</script>

<template>
  <span v-if="sessions.length" class="gl-flex gl-shrink-0">
    <agent-session-link
      ref="trigger"
      :href="sessions[0].url"
      tracking-property="gutter_icon"
      :aria-label="s__('DuoAgentPlatform|View session for this change')"
      class="gl-inline-flex gl-items-center !gl-text-subtle hover:!gl-text-default focus-visible:gl-focus-inset"
      data-testid="agent-session-trigger"
    >
      <gl-icon name="session-ai" />
    </agent-session-link>
    <gl-popover
      :target="() => $refs.trigger"
      :css-classes="['gl-max-w-88']"
      triggers="hover focus"
      :delay="$options.POPOVER_DELAY"
      placement="top"
      boundary="viewport"
      data-testid="agent-session-popover"
      @show="onShow"
    >
      <gl-skeleton-loader v-if="isLoading" :lines="2" />

      <ul v-else class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-p-0">
        <li
          v-for="(session, index) in sessionViewModels"
          :key="session.id"
          class="gl-flex gl-flex-col gl-gap-1"
          :class="{ 'gl-border-t gl-mt-3 gl-pt-3': index > 0 }"
          data-testid="agent-session"
        >
          <agent-session-link
            :href="session.url"
            tracking-property="popover_title"
            class="gl-min-w-0 gl-font-bold gl-text-default"
            data-testid="agent-session-link"
          >
            {{ session.title }}
          </agent-session-link>

          <template v-if="session.details">
            <!-- `summary` is only written when a session fails, so it isn't shown. -->
            <p
              v-if="session.details.goal"
              class="gl-m-0 gl-line-clamp-2 gl-text-subtle"
              data-testid="agent-session-goal"
            >
              {{ session.details.goal }}
            </p>
            <div
              class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-2 gl-text-sm gl-text-subtle"
              data-testid="agent-session-meta"
            >
              <template v-if="session.details.user">
                <gl-avatar :src="session.details.user.avatarUrl" :size="16" />
                <span>{{ session.details.user.name }}</span>
                <span aria-hidden="true">·</span>
              </template>
              <timeago-tooltip :time="session.details.updatedAt" />
              <template v-if="session.status">
                <span aria-hidden="true">·</span>
                <span data-testid="agent-session-status">{{ session.status }}</span>
              </template>
              <template v-for="item in session.linkedItems">
                <span :key="`${item.href}-separator`" aria-hidden="true">·</span>
                <gl-link
                  :key="item.href"
                  :href="item.href"
                  :aria-label="item.accessibleLabel"
                  class="gl-inline-flex gl-min-w-0 gl-items-center gl-gap-1"
                  data-testid="agent-session-linked-item"
                >
                  <gl-icon :name="item.icon" :size="12" class="gl-shrink-0" />
                  <span class="gl-truncate">{{ item.label }}</span>
                </gl-link>
              </template>
              <template v-if="session.moreLinkedItemsCount > 0">
                <span aria-hidden="true">·</span>
                <agent-session-link
                  :href="session.url"
                  :aria-label="session.moreLinkedItemsAccessibleLabel"
                  tracking-property="popover_more"
                  data-testid="agent-session-more-linked-items"
                >
                  {{ session.moreLinkedItemsLabel }}
                </agent-session-link>
              </template>
            </div>
          </template>
        </li>
      </ul>
    </gl-popover>
  </span>
</template>
