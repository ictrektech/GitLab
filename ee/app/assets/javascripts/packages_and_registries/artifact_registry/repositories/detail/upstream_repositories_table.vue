<script>
import { GlBadge, GlButton, GlIcon, GlTable, GlTooltipDirective } from '@gitlab/ui';
import { isNil } from 'lodash-es';
import {
  REPOSITORY_HEALTH_STATUS_UNKNOWN,
  REPOSITORY_KIND_LABELS,
  UPSTREAM_HEALTH_STATUS_ICONS,
  UPSTREAM_REPOSITORIES_ORDER_HELP,
  UPSTREAM_REPOSITORIES_TABLE_FIELDS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { upstreamHasActions } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import { humanSize } from 'ee/packages_and_registries/artifact_registry/utils';
import { s__, sprintf } from '~/locale';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import UpstreamRepositoryActions from './upstream_repository_actions.vue';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesTable',
  components: {
    GlBadge,
    GlButton,
    GlIcon,
    GlTable,
    HelpPopover,
    UpstreamRepositoryActions,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    upstreamRepositories: {
      type: Array,
      required: true,
    },
    repository: {
      type: Object,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  computed: {
    fields() {
      const hasActions = this.upstreamRepositories.some(({ upstreamRepository }) =>
        upstreamHasActions(upstreamRepository, this.permissions),
      );

      return hasActions
        ? UPSTREAM_REPOSITORIES_TABLE_FIELDS
        : UPSTREAM_REPOSITORIES_TABLE_FIELDS.filter(({ key }) => key !== 'actions');
    },
  },
  methods: {
    // A kind added to the upstream enum passes the server's contract check, so it arrives here
    // with no entry in the label map. Rendering it raw beats rendering an empty badge.
    kindLabel(kind) {
      return REPOSITORY_KIND_LABELS[kind] || kind;
    },
    healthTreatment({ lastHealthStatus }) {
      return (
        UPSTREAM_HEALTH_STATUS_ICONS[lastHealthStatus] ??
        UPSTREAM_HEALTH_STATUS_ICONS[REPOSITORY_HEALTH_STATUS_UNKNOWN]
      );
    },
    healthAccessibleName({ name, settings }) {
      return sprintf(
        s__('ArtifactRegistry|Connection status for %{name}: %{verdict}'),
        { name, verdict: this.healthTreatment(settings).label },
        false,
      );
    },
    hasSize({ sizeBytes }) {
      return !isNil(sizeBytes);
    },
    humanSize,
  },
  orderHelp: { content: UPSTREAM_REPOSITORIES_ORDER_HELP },
};
</script>

<template>
  <gl-table :fields="fields" :items="upstreamRepositories" show-empty>
    <template #empty>
      <p class="gl-mb-0 gl-py-2 gl-text-center gl-text-subtle">
        {{ s__('ArtifactRegistry|There are no upstream repositories yet') }}
      </p>
    </template>

    <template #head(position)="{ label }">
      <span class="gl-flex gl-w-full gl-items-center gl-justify-center gl-gap-2">
        {{ label }}
        <help-popover
          :options="$options.orderHelp"
          icon="information-o"
          data-testid="upstream-order-help"
        />
      </span>
    </template>

    <template #cell(position)="{ item }">
      <gl-badge data-testid="upstream-position">{{ item.position }}</gl-badge>
    </template>

    <template #cell(name)="{ item }">
      <span class="gl-font-semibold gl-text-default gl-wrap-anywhere" data-testid="upstream-name">{{
        item.upstreamRepository.name
      }}</span>
      <div
        v-if="item.upstreamRepository.settings"
        class="gl-mt-1 gl-flex gl-flex-wrap gl-items-center gl-gap-2"
        data-testid="upstream-source"
      >
        <span
          v-if="item.upstreamRepository.settings.url"
          class="gl-text-sm gl-text-subtle gl-wrap-anywhere"
          data-testid="upstream-url"
          >{{ item.upstreamRepository.settings.url }}</span
        >
        <gl-button
          v-gl-tooltip
          :title="healthTreatment(item.upstreamRepository.settings).label"
          :aria-label="healthAccessibleName(item.upstreamRepository)"
          category="tertiary"
          size="small"
          class="!gl-min-h-5 !gl-min-w-5 !gl-p-0"
          data-testid="upstream-health"
        >
          <gl-icon
            :name="healthTreatment(item.upstreamRepository.settings).icon"
            :variant="healthTreatment(item.upstreamRepository.settings).variant"
          />
        </gl-button>
      </div>
    </template>

    <template #cell(kind)="{ item }">
      <gl-badge data-testid="upstream-kind">{{ kindLabel(item.upstreamRepository.kind) }}</gl-badge>
    </template>

    <template #cell(sizeBytes)="{ item }">
      <span v-if="hasSize(item.upstreamRepository)" data-testid="upstream-size">{{
        humanSize(item.upstreamRepository.sizeBytes)
      }}</span>
    </template>

    <template #cell(actions)="{ item }">
      <upstream-repository-actions
        :upstream-repository="item.upstreamRepository"
        :association-id="item.id"
        :repository="repository"
        :permissions="permissions"
      />
    </template>
  </gl-table>
</template>
