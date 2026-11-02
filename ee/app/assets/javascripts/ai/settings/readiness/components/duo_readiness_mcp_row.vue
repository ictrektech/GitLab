<script>
import { GlButton } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { n__, s__, sprintf } from '~/locale';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import {
  STATUS_DONE,
  STATUS_TODO,
  STATUS_ERROR,
  STATUS_LOADING,
} from '~/ai/settings/readiness/constants';
import duoMcpServerNamesQuery from '../graphql/queries/duo_mcp_server_names.query.graphql';

export default {
  name: 'DuoReadinessMcpRow',
  components: { GlButton, DuoReadinessRow },
  props: {
    mcp: {
      type: Object,
      required: true,
    },
    projectFullPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      serverNames: null,
      loadFailed: false,
    };
  },
  apollo: {
    serverNames: {
      query: duoMcpServerNamesQuery,
      variables() {
        return { fullPath: this.projectFullPath };
      },
      update(data) {
        return data.project?.duoMcpServerNames ?? null;
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
    // A null list inside a successful response means the field was redacted by
    // authorization, so it reads as a failed check rather than as no servers.
    errored() {
      return !this.loading && (this.loadFailed || this.serverNames === null);
    },
    connected() {
      return Boolean(this.serverNames?.length);
    },
    status() {
      if (this.loading) return STATUS_LOADING;
      if (this.errored) return STATUS_ERROR;

      return this.connected ? STATUS_DONE : STATUS_TODO;
    },
    description() {
      if (this.loading || this.errored || !this.connected) {
        return this.$options.descriptions[this.status];
      }

      const [first, second, ...rest] = this.serverNames;

      // Names render as text, so they are not escaped here.
      if (!second) {
        return sprintf(
          s__('DuoAgentPlatform|%{name} connected. Agents can use it.'),
          { name: first },
          false,
        );
      }
      if (rest.length === 0) {
        return sprintf(
          s__('DuoAgentPlatform|%{first} and %{second} connected. Agents can use both.'),
          { first, second },
          false,
        );
      }

      // n__ with one English form for both: "more" does not inflect here, but
      // other languages pluralize on the count.
      return sprintf(
        n__(
          'DuoAgentPlatform|%{first}, %{second}, and %{count} more connected. Agents can use them all.',
          'DuoAgentPlatform|%{first}, %{second}, and %{count} more connected. Agents can use them all.',
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
  descriptions: {
    [STATUS_LOADING]: s__('DuoAgentPlatform|Checking connected MCP servers.'),
    [STATUS_ERROR]: s__('DuoAgentPlatform|Could not check for connected MCP servers.'),
    [STATUS_TODO]: s__(
      'DuoAgentPlatform|Experiment. Agents can connect to tools your team already uses, such as Jira or Linear.',
    ),
  },
  i18n: {
    title: s__('DuoAgentPlatform|MCP servers'),
    viewServers: s__('DuoAgentPlatform|View servers'),
    howToConnect: s__('DuoAgentPlatform|How to connect'),
    checkAgain: s__('DuoAgentPlatform|Check again'),
  },
};
</script>

<template>
  <duo-readiness-row
    :title="$options.i18n.title"
    :description="description"
    :status="status"
    data-testid="mcp-row"
  >
    <gl-button
      v-if="connected"
      category="tertiary"
      size="small"
      :href="mcp.serversPath"
      data-testid="mcp-view-servers-button"
    >
      {{ $options.i18n.viewServers }}
    </gl-button>
    <gl-button
      v-else-if="errored"
      category="secondary"
      size="small"
      icon="retry"
      data-testid="mcp-retry-button"
      @click="retry"
    >
      {{ $options.i18n.checkAgain }}
    </gl-button>
    <gl-button
      v-else
      category="secondary"
      size="small"
      icon="external-link"
      :href="$options.docsPath"
      target="_blank"
      :disabled="loading"
      data-testid="mcp-how-to-connect-button"
    >
      {{ $options.i18n.howToConnect }}
    </gl-button>
  </duo-readiness-row>
</template>
