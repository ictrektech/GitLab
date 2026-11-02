<script>
import { GlButton, GlLink } from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import { groupRunnersPath } from '~/lib/utils/path_helpers/group';
import {
  PARAM_KEY_RUNNER_TYPE,
  INSTANCE_TYPE,
  GROUP_TYPE,
  PROJECT_TYPE,
} from '~/ci/runner/constants';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { STATUS_DONE, STATUS_TODO, STATUS_LOADING } from '~/ai/settings/readiness/constants';
import duoGroupWorkflowRunnerAvailableQuery from '../graphql/queries/duo_group_workflow_runner_available.query.graphql';

// The query returns the Rails enum value; the runners page filters by the GraphQL one.
const RUNNER_TYPE_FILTER = {
  instance_type: INSTANCE_TYPE,
  group_type: GROUP_TYPE,
  project_type: PROJECT_TYPE,
};

export default {
  name: 'DuoGroupReadinessRunnerRow',
  components: { DuoReadinessRow, GlButton, GlLink },
  inject: {
    groupFullPath: { default: null },
    isSaaS: { default: false },
    showDuoAgentPlatformEnablementSetting: { default: false },
  },
  props: {
    nested: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['runner-confirmed'],
  data() {
    return {
      // { available, runnerType }, or null while unloaded and after a failed read.
      runnerCheck: null,
      // Mirrors the query's loading state: a computed reading the query's `loading`
      // runs for the confirmed watcher before vue-apollo registers the query, which
      // poisons its cache.
      loading: true,
      rechecking: false,
    };
  },
  apollo: {
    runnerCheck: {
      query: duoGroupWorkflowRunnerAvailableQuery,
      // Runner availability is external, volatile state: a cached verdict goes stale
      // the moment someone registers or stops a runner, so every mount re-checks.
      fetchPolicy: 'network-only',
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update(data) {
        const available = data.group?.duoWorkflowRunnerAvailable;

        // Field-level authorization redacts to a bare null with no error; the row
        // treats that like a failed read rather than "no runner".
        if (available == null) return null;

        return { available, runnerType: data.group.duoWorkflowUsableRunnerType };
      },
      watchLoading(isLoading) {
        this.loading = isLoading;
      },
      error() {
        this.runnerCheck = null;
      },
    },
  },
  computed: {
    connected() {
      return this.runnerCheck?.available === true;
    },
    confirmed() {
      return !this.loading && this.connected;
    },
    readFailed() {
      return !this.loading && this.runnerCheck === null;
    },
    // A failed or redacted read keeps the row checkable rather than showing an error.
    status() {
      if (this.loading) return STATUS_LOADING;

      return this.connected ? STATUS_DONE : STATUS_TODO;
    },
    viewRunnersHref() {
      const runnersPath = groupRunnersPath(this.groupFullPath);
      const filter = RUNNER_TYPE_FILTER[this.runnerCheck?.runnerType];

      return filter
        ? mergeUrlParams({ [PARAM_KEY_RUNNER_TYPE]: filter }, runnersPath)
        : runnersPath;
    },
    // A root group Owner can register the runner themselves; the how-to link
    // carries the steps, so only namespaces that must ask someone get a hint.
    registerHint() {
      if (!this.isSaaS) return s__('DuoAgentPlatform|Ask an administrator to register one.');
      if (this.showDuoAgentPlatformEnablementSetting) return null;

      return s__('DuoAgentPlatform|Ask a top-level group Owner to register one.');
    },
    description() {
      if (this.loading) return s__('DuoAgentPlatform|Checking for a runner this group can use.');
      if (this.connected) {
        return s__('DuoAgentPlatform|Connected. A runner is available and picking up jobs.');
      }
      if (this.readFailed) return s__('DuoAgentPlatform|Could not check for a runner.');

      return [
        s__('DuoAgentPlatform|Not connected. Flows run as CI/CD jobs and require a runner.'),
        this.registerHint,
      ]
        .filter(Boolean)
        .join(' ');
    },
    showHowToConfigure() {
      return !this.loading && !this.connected && !this.readFailed;
    },
  },
  watch: {
    confirmed(value) {
      this.$emit('runner-confirmed', value);
    },
  },
  methods: {
    async recheck() {
      if (this.rechecking) return;

      this.rechecking = true;

      try {
        await this.$apollo.queries.runnerCheck.refetch();
      } catch {
        this.runnerCheck = null;
      } finally {
        this.rechecking = false;
      }
    },
  },
  howToConfigureRunnersPath: helpPagePath('user/duo_agent_platform/flows/execution/_index.md', {
    anchor: 'configure-runners-to-execute-flows',
  }),
};
</script>

<template>
  <duo-readiness-row
    :nested="nested"
    :title="s__('DuoAgentPlatform|Group runner')"
    :status="status"
    data-testid="runner-row"
  >
    <template #description>
      {{ description }}
      <template v-if="showHowToConfigure">
        <gl-link :href="$options.howToConfigureRunnersPath" target="_blank">{{
          s__('DuoAgentPlatform|How to configure')
        }}</gl-link
        >.
      </template>
    </template>
    <gl-button
      v-if="connected"
      category="tertiary"
      size="small"
      :href="viewRunnersHref"
      target="_blank"
      data-testid="runner-row-action"
    >
      {{ s__('DuoAgentPlatform|View runners') }}
    </gl-button>
    <gl-button
      v-else
      category="secondary"
      size="small"
      icon="retry"
      :disabled="loading"
      :loading="rechecking"
      data-testid="runner-row-action"
      @click="recheck"
    >
      {{ s__('DuoAgentPlatform|Check again') }}
    </gl-button>
  </duo-readiness-row>
</template>
