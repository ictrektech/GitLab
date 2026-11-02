<script>
import { GlBadge, GlButton } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { getTimeago } from '~/lib/utils/datetime_utility';
import { s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { STATUS_DONE, STATUS_TODO } from '~/ai/settings/readiness/constants';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import orbitLastIndexedQuery from '../graphql/queries/orbit_last_indexed.query.graphql';
import orbitGroupLastIndexedQuery from '../graphql/queries/orbit_group_last_indexed.query.graphql';
import { lockIconProps } from '../group_readiness';

export default {
  name: 'DuoReadinessOrbitRow',
  components: { GlBadge, GlButton, CascadingLockIcon, DuoReadinessRow },
  props: {
    orbit: {
      type: Object,
      required: true,
    },
    fullPath: {
      type: String,
      required: true,
    },
    group: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      enabled: this.orbit.enabled,
      enabling: false,
      lastIndexedAt: null,
    };
  },
  apollo: {
    lastIndexedAt: {
      query() {
        return this.group ? orbitGroupLastIndexedQuery : orbitLastIndexedQuery;
      },
      variables() {
        return { fullPath: this.fullPath };
      },
      skip() {
        return !this.enabled;
      },
      update: (data) => (data.group ?? data.project)?.orbit?.indexing?.lastCompletedAt ?? null,
      error(error) {
        this.lastIndexedAt = null;
        if (!error.graphQLErrors?.length) Sentry.captureException(error);
      },
    },
  },
  computed: {
    status() {
      return this.enabled ? STATUS_DONE : STATUS_TODO;
    },
    showEnable() {
      return this.orbit.canEnable || Boolean(this.orbit.cascadingSettings);
    },
    description() {
      if (this.group) {
        if (this.lastIndexedAt) {
          return sprintf(
            s__(
              'DuoAgentPlatform|A knowledge graph that helps agents reason across whole projects. Indexed %{timeAgo}.',
            ),
            { timeAgo: getTimeago().format(this.lastIndexedAt) },
          );
        }

        return this.enabled || this.orbit.canStartTrial || this.showEnable
          ? s__(
              'DuoAgentPlatform|A knowledge graph that helps agents reason across whole projects.',
            )
          : s__(
              'DuoAgentPlatform|A knowledge graph that helps agents reason across whole projects. Only a Group Owner can turn it on.',
            );
      }

      if (!this.enabled) {
        return this.orbit.canEnable
          ? s__(
              'DuoAgentPlatform|A knowledge graph that helps agents reason across your whole project.',
            )
          : s__(
              'DuoAgentPlatform|A knowledge graph that helps agents reason across your whole project. Only a Group Owner can turn it on.',
            );
      }

      if (this.lastIndexedAt) {
        return sprintf(s__('DuoAgentPlatform|Indexed %{timeAgo}. Agents get repo-wide context.'), {
          timeAgo: getTimeago().format(this.lastIndexedAt),
        });
      }

      return s__('DuoAgentPlatform|Agents get repo-wide context.');
    },
  },
  methods: {
    lockIconProps,
    async enable() {
      this.enabling = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: orbitUpdateMutation,
          variables: { input: { groupPath: this.orbit.rootGroupPath, enabled: true } },
        });

        const [error] = data?.orbitUpdate?.errors ?? [];
        if (error) {
          throw new Error(error);
        }

        this.enabled = true;
      } catch (error) {
        createAlert({
          message: s__('DuoAgentPlatform|Something went wrong while turning on GitLab Orbit.'),
          error,
          captureError: true,
        });
      } finally {
        this.enabling = false;
      }
    },
  },
  i18n: {
    title: s__('DuoAgentPlatform|GitLab Orbit'),
    beta: s__('Orbit|Beta'),
    enable: s__('DuoAgentPlatform|Enable'),
    queryGraph: s__('DuoAgentPlatform|Query graph'),
  },
};
</script>

<template>
  <duo-readiness-row
    :title="$options.i18n.title"
    :description="description"
    :status="status"
    data-testid="orbit-row"
  >
    <template v-if="group" #title-icon>
      <gl-badge variant="info" class="gl-ml-2" data-testid="orbit-beta-badge">{{
        $options.i18n.beta
      }}</gl-badge>
      <cascading-lock-icon
        v-if="orbit.cascadingSettings"
        v-bind="lockIconProps(orbit.cascadingSettings)"
        class="gl-ml-1"
      />
    </template>
    <gl-button
      v-if="enabled"
      category="tertiary"
      size="small"
      :href="orbit.graphPath"
      data-testid="orbit-query-graph-button"
    >
      {{ $options.i18n.queryGraph }}
    </gl-button>
    <gl-button
      v-else-if="orbit.canStartTrial"
      category="secondary"
      size="small"
      :href="orbit.settingsPath"
      data-testid="orbit-start-trial-button"
    >
      {{ s__('DuoAgentPlatform|Start trial') }}
    </gl-button>
    <gl-button
      v-else-if="showEnable"
      category="secondary"
      size="small"
      :disabled="!orbit.canEnable"
      :loading="enabling"
      data-testid="orbit-enable-button"
      @click="enable"
    >
      {{ $options.i18n.enable }}
    </gl-button>
  </duo-readiness-row>
</template>
