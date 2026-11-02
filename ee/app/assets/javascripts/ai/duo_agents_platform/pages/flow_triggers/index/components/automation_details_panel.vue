<script>
import { GlAvatar, GlBadge, GlIcon, GlLink, GlSprintf, GlToken } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import getProjectServiceAccountRoles from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_account_roles.query.graphql';
import { flowTriggerEventLabels, scheduleSummaryLabels } from 'ee/ai/duo_agents_platform/utils';
import AutomationRecentRuns from './automation_recent_runs.vue';
import AutomationRunStats from './automation_run_stats.vue';

export default {
  name: 'AutomationDetailsPanel',
  components: {
    AutomationRecentRuns,
    AutomationRunStats,
    DetailLayout,
    DynamicPanel,
    GlAvatar,
    GlBadge,
    GlIcon,
    GlLink,
    GlSprintf,
    GlToken,
    MountingPortal,
  },
  inject: {
    projectPath: { from: 'projectPath' },
    timezoneData: { default: () => [] },
  },
  props: {
    automation: {
      type: Object,
      required: true,
    },
  },
  emits: ['close'],
  data() {
    return {
      serviceAccountRole: null,
    };
  },
  apollo: {
    serviceAccountRole: {
      query: getProjectServiceAccountRoles,
      skip() {
        return !this.automation.user;
      },
      variables() {
        return { fullPath: this.projectPath, ids: [this.automation.user.id] };
      },
      update: (data) => data.project?.projectMembers?.nodes[0]?.accessLevel.humanAccess ?? null,
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    conditions() {
      return flowTriggerEventLabels(this.automation, { withSchedule: false });
    },
    schedule() {
      return scheduleSummaryLabels(this.automation.filter, this.timezoneData)[0];
    },
    configFileName() {
      return this.automation.configPath?.split('/').at(-1) ?? '';
    },
    catalogItemName() {
      return this.automation.aiCatalogItemConsumer?.item?.name ?? null;
    },
    serviceAccountMessage() {
      return this.serviceAccountRole
        ? s__('DuoAgentsPlatform|%{serviceAccount} runs as %{role}')
        : '%{serviceAccount}';
    },
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    handleKeydown({ key }) {
      if (
        key !== 'Escape' ||
        document.body.classList.contains('modal-open') ||
        document.activeElement?.closest('.gl-form-input, .gl-new-dropdown')
      ) {
        return;
      }

      this.$emit('close');
    },
  },
};
</script>

<template>
  <mounting-portal mount-to="#contextual-panel-portal" append>
    <dynamic-panel :header="s__('DuoAgentsPlatform|Automation details')" @close="$emit('close')">
      <detail-layout :heading="automation.description" :show-sidebar="false">
        <section class="gl-border gl-rounded-lg gl-bg-subtle gl-p-4">
          <h3 class="gl-heading-4 gl-mb-3">{{ __('Overview') }}</h3>
          <automation-run-stats :key="automation.id" :automation-id="automation.id" />
          <!-- eslint-disable-next-line tailwindcss/no-arbitrary-value -->
          <dl class="gl-m-0 gl-grid gl-grid-cols-[max-content_1fr] gl-gap-x-6 gl-gap-y-3">
            <template v-if="conditions.length">
              <dt class="gl-text-subtle">{{ s__('DuoAgentsPlatform|Conditions') }}</dt>
              <dd
                class="-gl-my-2 gl-mx-0 gl-flex gl-flex-wrap gl-gap-2"
                data-testid="automation-conditions"
              >
                <gl-token v-for="condition in conditions" :key="condition" view-only>
                  {{ condition }}
                </gl-token>
              </dd>
            </template>

            <template v-if="schedule">
              <dt class="gl-flex gl-items-center gl-gap-2 gl-text-subtle">
                {{ __('Schedule') }}
                <gl-badge data-testid="automation-schedule-beta-badge">
                  {{ s__('DuoAgentsPlatform|Beta') }}
                </gl-badge>
              </dt>
              <dd class="gl-m-0" data-testid="automation-schedule">{{ schedule }}</dd>
            </template>

            <template v-if="automation.configUrl || catalogItemName">
              <dt class="gl-text-subtle">{{ __('Source') }}</dt>
              <dd class="gl-m-0 gl-flex gl-items-center gl-gap-2" data-testid="automation-source">
                <gl-icon
                  :name="automation.configUrl ? 'doc-text' : 'flow-ai'"
                  class="gl-shrink-0 gl-text-subtle"
                />
                <gl-link v-if="automation.configUrl" :href="automation.configUrl">
                  {{ configFileName }}
                </gl-link>
                <template v-else>{{ catalogItemName }}</template>
              </dd>
            </template>

            <template v-if="automation.user">
              <dt class="gl-text-subtle">{{ __('Service account') }}</dt>
              <dd
                class="gl-m-0 gl-flex gl-flex-wrap gl-items-center gl-gap-2"
                data-testid="automation-service-account"
              >
                <gl-sprintf :message="serviceAccountMessage">
                  <template #serviceAccount>
                    <gl-link
                      :href="automation.user.webPath"
                      class="gl-inline-flex gl-items-center gl-gap-2"
                    >
                      <gl-avatar :size="16" :src="automation.user.avatarUrl" :alt="''" />
                      {{ automation.user.name }}
                    </gl-link>
                  </template>
                  <template #role>{{ serviceAccountRole }}</template>
                </gl-sprintf>
              </dd>
            </template>
          </dl>
        </section>

        <automation-recent-runs
          :key="automation.id"
          :automation-id="automation.id"
          class="gl-mt-6"
        />
      </detail-layout>
    </dynamic-panel>
  </mounting-portal>
</template>
