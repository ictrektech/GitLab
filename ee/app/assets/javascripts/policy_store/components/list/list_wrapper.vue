<script>
import {
  GlBadge,
  GlButton,
  GlEmptyState,
  GlExperimentBadge,
  GlLink,
  GlLoadingIcon,
  GlSprintf,
  GlTable,
} from '@gitlab/ui';
import { __, s__ } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { groupSecurityPolicyStoreIndexPath } from 'ee/lib/utils/path_helpers/group';
import { POLICY_STATUS_ACTIVE } from '../../constants';
import ConfigInfo from './config_info.vue';
import StatsBar from './stats_bar.vue';
import { modeLabel, modeVariant, statusLabel, statusVariant, scopeLabel } from './utils';

export default {
  name: 'ListWrapper',
  components: {
    GlBadge,
    GlButton,
    GlEmptyState,
    GlExperimentBadge,
    GlLink,
    GlLoadingIcon,
    GlSprintf,
    GlTable,
    TimeAgoTooltip,
    ConfigInfo,
    StatsBar,
  },
  fields: [
    { key: 'name', label: __('Name'), sortable: true, tdClass: 'gl-font-bold gl-content-center' },
    { key: 'type', label: __('Type'), sortable: true, tdClass: 'gl-content-center' },
    {
      key: 'source',
      label: s__('PolicyStore|Source'),
      sortable: true,
      tdClass: 'gl-content-center',
    },
    { key: 'mode', label: s__('PolicyStore|Mode'), sortable: true, tdClass: 'gl-content-center' },
    { key: 'status', label: __('Status'), sortable: true, tdClass: 'gl-content-center' },
    {
      key: 'scopedProjectsCount',
      label: s__('PolicyStore|Scope'),
      sortable: true,
      tdClass: 'gl-content-center',
    },
    {
      key: 'updated_at',
      label: s__('PolicyStore|Last updated'),
      sortable: true,
      tdClass: 'gl-content-center',
    },
    { key: 'configInfo', label: '', tdClass: 'gl-content-center gl-text-right' },
  ],
  inject: ['emptyListSvgPath'],
  props: {
    policies: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    error: {
      type: Boolean,
      required: false,
      default: false,
    },
    recentEvaluations: {
      type: Number,
      required: false,
      default: null,
    },
    recentEvaluationsLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    canCreatePolicy: {
      type: Boolean,
      required: false,
      default: false,
    },
    showRecentEvaluations: {
      type: Boolean,
      required: false,
      default: true,
    },
    newPolicyPath: {
      type: String,
      required: false,
      default: '',
    },
    hasNextPage: {
      type: Boolean,
      required: false,
      default: false,
    },
    loadingMore: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['load-more'],
  computed: {
    activePoliciesCount() {
      return this.policies.filter(({ status }) => status === POLICY_STATUS_ACTIVE).length;
    },
    // A container without a create path is read-only, so the empty state points
    // at where its policies come from. Where authoring is possible but this
    // reader cannot, there is nothing to instruct them to press.
    // The permission alone is not enough to offer a Create button: without a
    // path it would link to the current page.
    canCreate() {
      return this.canCreatePolicy && Boolean(this.newPolicyPath);
    },
    emptyStateDescription() {
      if (this.canCreatePolicy) {
        return s__(
          'PolicyStore|Create a policy to enforce rules for deployments across your organization.',
        );
      }

      return this.newPolicyPath
        ? ''
        : s__(
            'PolicyStore|Policies that apply here are created in the parent group or organization.',
          );
    },
  },
  methods: {
    modeLabel,
    modeVariant,
    statusLabel,
    statusVariant,
    scopeLabel,
    groupSecurityPolicyStoreIndexPath,
  },
};
</script>

<template>
  <div class="gl-pt-6">
    <stats-bar
      :active-policies="activePoliciesCount"
      :recent-evaluations="recentEvaluations"
      :recent-evaluations-loading="recentEvaluationsLoading"
      :show-recent-evaluations="showRecentEvaluations"
      class="gl-mb-6"
    />

    <div class="gl-mb-4 gl-flex gl-items-center gl-justify-between">
      <div class="gl-flex gl-items-center">
        <h2 data-testid="policies-heading" class="gl-heading-2 gl-mb-0">
          {{ s__('PolicyStore|Policies') }}
        </h2>
        <gl-experiment-badge type="experiment" />
      </div>
      <gl-button
        v-if="canCreate"
        variant="confirm"
        :href="newPolicyPath"
        data-testid="create-policy"
      >
        {{ s__('PolicyStore|Create new policy') }}
      </gl-button>
    </div>

    <gl-table
      v-if="!error"
      :items="policies"
      :fields="$options.fields"
      :busy="loading"
      hover
      stacked="md"
      show-empty
    >
      <template #table-busy>
        <gl-loading-icon size="lg" class="gl-my-5" data-testid="policies-loading" />
      </template>

      <template #empty>
        <gl-empty-state
          :svg-path="emptyListSvgPath"
          :svg-height="150"
          :title="s__('PolicyStore|No policies found')"
          :description="emptyStateDescription"
          data-testid="policies-empty-state"
        >
          <template #actions>
            <gl-button
              v-if="canCreate"
              variant="confirm"
              :href="newPolicyPath"
              data-testid="empty-state-create-button"
            >
              {{ s__('PolicyStore|Create new policy') }}
            </gl-button>
          </template>
        </gl-empty-state>
      </template>

      <!-- A read-only container has no detail page, so its names are plain text. -->
      <template #cell(name)="{ item }">
        <gl-link v-if="item.detailPath" :href="item.detailPath">{{ item.name }}</gl-link>
        <span v-else>{{ item.name }}</span>
      </template>

      <template #cell(type)="{ item }">
        <gl-badge variant="neutral">{{ item.type }}</gl-badge>
      </template>

      <!-- A policy can only be changed from the container that owns it, so the
           source doubles as the answer to why this list cannot edit a row. -->
      <template #cell(source)="{ item }">
        <span class="gl-whitespace-nowrap">
          <gl-sprintf
            v-if="item.inherited && item.group"
            :message="s__('PolicyStore|Inherited from %{namespace}')"
          >
            <template #namespace>
              <gl-link :href="groupSecurityPolicyStoreIndexPath(item.group.fullPath)">
                {{ item.group.name }}
              </gl-link>
            </template>
          </gl-sprintf>
          <span v-else-if="item.inherited" data-testid="inherited-from-organization">
            {{ s__('PolicyStore|Inherited from the organization') }}
          </span>
          <gl-link
            v-else-if="item.group"
            :href="groupSecurityPolicyStoreIndexPath(item.group.fullPath)"
          >
            {{ item.group.name }}
          </gl-link>
          <span v-else>{{ s__('PolicyStore|Organization') }}</span>
        </span>
      </template>

      <template #cell(mode)="{ item }">
        <gl-badge :variant="modeVariant(item.mode)">{{ modeLabel(item.mode) }}</gl-badge>
      </template>

      <template #cell(status)="{ item }">
        <gl-badge :variant="statusVariant(item.status)">{{ statusLabel(item.status) }}</gl-badge>
      </template>

      <template #cell(scopedProjectsCount)="{ item }">
        {{ scopeLabel(item.scopedProjectsCount) }}
      </template>

      <template #cell(updated_at)="{ item }">
        <time-ago-tooltip v-if="item.updated_at" :time="item.updated_at" />
        <span v-else>—</span>
      </template>

      <template #cell(configInfo)="{ detailsShowing, toggleDetails }">
        <gl-button
          category="tertiary"
          size="small"
          :icon="detailsShowing ? 'chevron-up' : 'chevron-down'"
          :aria-label="
            detailsShowing
              ? s__('PolicyStore|Hide configuration details')
              : s__('PolicyStore|Show configuration details')
          "
          data-testid="config-info-toggle"
          @click="toggleDetails"
        />
      </template>

      <!-- Rendered only for expanded rows, so config detail stays on demand. -->
      <template #row-details="{ item }">
        <config-info :policy="item" />
      </template>
    </gl-table>

    <div v-if="!error && !loading && hasNextPage" class="gl-mt-4 gl-flex gl-justify-center">
      <gl-button
        :loading="loadingMore"
        data-testid="load-more-policies"
        @click="$emit('load-more')"
      >
        {{ __('Load more') }}
      </gl-button>
    </div>
  </div>
</template>
