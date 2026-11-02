<script>
import { GlButton } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { n__, s__, sprintf } from '~/locale';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { STATUS_DONE, STATUS_TODO, STATUS_LOADING } from '~/ai/settings/readiness/constants';
import duoGroupMcpServerNamesQuery from '../graphql/queries/duo_group_mcp_server_names.query.graphql';

const CHECKING = s__('DuoAgentPlatform|Checking connected MCP tools.');
const READ_FAILED = s__('DuoAgentPlatform|Could not check for connected MCP tools.');
const NONE_CONNECTED = s__(
  'DuoAgentPlatform|Experiment. Connect to tools your team already uses, such as Jira or Linear. None connected yet.',
);
const ONE_CONNECTED = s__('DuoAgentPlatform|Experiment. %{name} connected. Agents can use it.');
const TWO_CONNECTED = s__(
  'DuoAgentPlatform|Experiment. %{first} and %{second} connected. Agents can use both.',
);
const IDE_ACCESS_OFF = s__(
  'DuoAgentPlatform|Experiment. Turn on IDE access to connect external MCP tools.',
);
const SET_UP_ON_TOP_LEVEL_GROUP = s__(
  'DuoAgentPlatform|Experiment. External MCP tools are set up on the top-level group.',
);
const UNAVAILABLE_TO_USER = s__(
  'DuoAgentPlatform|Experiment. External MCP tools are not available to you in this group.',
);

export default {
  name: 'DuoGroupReadinessMcpRow',
  components: { GlButton, DuoReadinessRow },
  inject: {
    groupFullPath: { default: null },
    groupMcpServersPath: { default: null },
    groupIsRoot: { default: true },
    duoWorkflowMcpRootEnabled: { default: false },
  },
  data() {
    return {
      serverNames: null,
      loadFailed: false,
    };
  },
  apollo: {
    serverNames: {
      query: duoGroupMcpServerNamesQuery,
      variables() {
        return { fullPath: this.groupFullPath };
      },
      skip() {
        return !this.canReadServers;
      },
      update(data) {
        return data.group?.duoMcpServerNames ?? null;
      },
      error() {
        this.loadFailed = true;
      },
    },
  },
  computed: {
    loading() {
      return this.$apollo.queries.serverNames.loading;
    },
    canReadServers() {
      return Boolean(this.groupMcpServersPath);
    },
    // A null list inside a successful response means the field was redacted by
    // authorization, so it reads as a failed check rather than as no servers.
    readFailed() {
      return this.canReadServers && !this.loading && (this.loadFailed || this.serverNames === null);
    },
    connected() {
      return Boolean(this.serverNames?.length);
    },
    // A failed read keeps the row checkable rather than showing an error.
    status() {
      if (this.loading) return STATUS_LOADING;

      return this.connected ? STATUS_DONE : STATUS_TODO;
    },
    neutralDescription() {
      if (this.canReadServers) return null;
      if (!this.groupIsRoot) return SET_UP_ON_TOP_LEVEL_GROUP;

      // The saved value, so flipping the unsaved toggle does not change this copy.
      return this.duoWorkflowMcpRootEnabled ? UNAVAILABLE_TO_USER : IDE_ACCESS_OFF;
    },
    description() {
      if (this.neutralDescription) return this.neutralDescription;
      if (this.loading) return CHECKING;
      if (this.readFailed) return READ_FAILED;
      if (!this.connected) return NONE_CONNECTED;

      const [first, second, ...rest] = this.serverNames;

      // Names render as text, so they are not escaped here.
      if (!second) return sprintf(ONE_CONNECTED, { name: first }, false);
      if (rest.length === 0) return sprintf(TWO_CONNECTED, { first, second }, false);

      // n__ with one English form for both: "more" does not inflect here, but
      // other languages pluralize on the count.
      return sprintf(
        n__(
          'DuoAgentPlatform|Experiment. %{first}, %{second}, and %{count} more connected. Agents can use them all.',
          'DuoAgentPlatform|Experiment. %{first}, %{second}, and %{count} more connected. Agents can use them all.',
          rest.length,
        ),
        { first, second, count: rest.length },
        false,
      );
    },
  },
  methods: {
    retry() {
      this.loadFailed = false;
      this.$apollo.queries.serverNames.refetch();
    },
  },
  docsPath: helpPagePath('user/gitlab_duo/model_context_protocol/ai_catalog_mcp_servers.md'),
};
</script>

<template>
  <duo-readiness-row
    :title="s__('DuoAgentPlatform|External MCP tools')"
    :description="description"
    :status="status"
    data-testid="group-mcp-row"
  >
    <gl-button
      v-if="connected"
      category="tertiary"
      size="small"
      :href="groupMcpServersPath"
      data-testid="group-mcp-row-action"
    >
      {{ s__('DuoAgentPlatform|View tools') }}
    </gl-button>
    <gl-button
      v-else-if="readFailed"
      category="secondary"
      size="small"
      icon="retry"
      data-testid="group-mcp-row-action"
      @click="retry"
    >
      {{ s__('DuoAgentPlatform|Check again') }}
    </gl-button>
    <gl-button
      v-else-if="canReadServers"
      category="secondary"
      size="small"
      icon="external-link"
      :href="$options.docsPath"
      target="_blank"
      :disabled="loading"
      data-testid="group-mcp-row-action"
    >
      {{ s__('DuoAgentPlatform|How to connect') }}
    </gl-button>
  </duo-readiness-row>
</template>
