<script>
import { GlButton, GlPopover } from '@gitlab/ui';
import { s__, n__, sprintf } from '~/locale';

const SOURCE_SECURITY_SCAN_PROFILES = 'SECURITY_SCAN_PROFILES';

const ANALYZER_SOURCE_LABELS = {
  SCAN_EXECUTION_POLICY: s__('SecurityConfiguration|Scan execution policy'),
  PIPELINE_EXECUTION_POLICY: s__('SecurityConfiguration|Pipeline execution policy'),
  PIPELINE_EXECUTION_POLICY_SCHEDULE: s__(
    'SecurityConfiguration|Scheduled pipeline execution policy',
  ),
  SECURITY_ORCHESTRATION_POLICY: s__('SecurityConfiguration|Security orchestration policy'),
  ON_DEMAND_DAST_SCAN: s__('SecurityConfiguration|On-demand DAST scan'),
  ON_DEMAND_DAST_VALIDATION: s__('SecurityConfiguration|On-demand DAST validation'),
  YML: s__('SecurityConfiguration|YAML configuration'),
};

const SOURCE_CATEGORY_LABELS = {
  SCAN_EXECUTION_POLICY: s__('SecurityConfiguration|Policy'),
  PIPELINE_EXECUTION_POLICY: s__('SecurityConfiguration|Policy'),
  PIPELINE_EXECUTION_POLICY_SCHEDULE: s__('SecurityConfiguration|Policy'),
  SECURITY_ORCHESTRATION_POLICY: s__('SecurityConfiguration|Policy'),
  ON_DEMAND_DAST_SCAN: s__('SecurityConfiguration|On-demand'),
  ON_DEMAND_DAST_VALIDATION: s__('SecurityConfiguration|On-demand'),
  YML: s__('SecurityConfiguration|YAML'),
};

export default {
  name: 'SourceCell',
  components: {
    GlButton,
    GlPopover,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    scannerKey: {
      type: String,
      required: true,
    },
  },
  computed: {
    matchingProfiles() {
      return (this.item.securityScanProfiles ?? []).filter(
        (profile) => profile.scanType === this.scannerKey,
      );
    },
    analyzerSource() {
      return this.item.analyzerStatuses?.find((status) => status.analyzerType === this.scannerKey)
        ?.source;
    },
    sources() {
      const list = this.matchingProfiles.map((profile) => ({
        key: profile.id,
        primaryLabel: profile.name,
        singleSourceCategoryLabel: s__('SecurityConfiguration|Configuration profile'),
        multiSourceCategoryLabel: s__('SecurityConfiguration|Profile'),
      }));

      if (this.analyzerSource && this.analyzerSource !== SOURCE_SECURITY_SCAN_PROFILES) {
        const key = this.analyzerSource;
        list.push({
          key,
          primaryLabel: ANALYZER_SOURCE_LABELS[key] ?? key,
          singleSourceCategoryLabel: null,
          multiSourceCategoryLabel: SOURCE_CATEGORY_LABELS[key] ?? null,
        });
      }

      return list;
    },
    hasMultipleSources() {
      return this.sources.length > 1;
    },
    multiSourceLabel() {
      return sprintf(
        n__(
          'SecurityConfiguration|%{count} source',
          'SecurityConfiguration|%{count} sources',
          this.sources.length,
        ),
        { count: this.sources.length },
      );
    },
    multiSourceCategoryLabel() {
      const labels = this.sources.map((source) => source.multiSourceCategoryLabel).filter(Boolean);
      return [...new Set(labels)].join(', ');
    },
    popoverTargetId() {
      const safeId = String(this.item.id ?? '').replace(/[^a-zA-Z0-9_-]/g, '-');
      return `sources-${safeId}`;
    },
  },
  i18n: {
    noProfileApplied: s__('SecurityConfiguration|No profile applied'),
  },
};
</script>

<template>
  <div>
    <span v-if="sources.length === 0" class="gl-text-subtle">
      {{ $options.i18n.noProfileApplied }}
    </span>

    <template v-else-if="!hasMultipleSources">
      <span>{{ sources[0].primaryLabel }}</span>
      <div
        v-if="sources[0].singleSourceCategoryLabel"
        data-testid="analyzer-source"
        class="gl-text-sm gl-text-subtle"
      >
        {{ sources[0].singleSourceCategoryLabel }}
      </div>
    </template>

    <template v-else>
      <gl-button :id="popoverTargetId" variant="link" data-testid="sources-count">
        {{ multiSourceLabel }}
      </gl-button>
      <div
        v-if="multiSourceCategoryLabel"
        data-testid="analyzer-source"
        class="gl-text-sm gl-text-subtle"
      >
        {{ multiSourceCategoryLabel }}
      </div>
      <gl-popover
        :target="popoverTargetId"
        triggers="hover focus"
        boundary="viewport"
        placement="top"
        data-testid="sources-popover"
      >
        <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0">
          <li v-for="source in sources" :key="source.key">{{ source.primaryLabel }}</li>
        </ul>
      </gl-popover>
    </template>
  </div>
</template>
