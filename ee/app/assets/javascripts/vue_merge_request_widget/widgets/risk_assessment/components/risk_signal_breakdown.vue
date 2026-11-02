<script>
import { GlIcon } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  CONTRIBUTION_MAJOR_THRESHOLD,
  CONTRIBUTION_MINOR_THRESHOLD,
  MITIGATION_CAP_SIGNAL,
} from '../constants';

export default {
  name: 'RiskSignalBreakdown',
  components: { GlIcon },
  props: {
    contributions: {
      type: Array,
      required: true,
    },
  },
  computed: {
    // The cap row only corrects the arithmetic; without numbers on screen it
    // would read as something that raised risk.
    riskRows() {
      return this.contributions
        .filter((entry) => entry.signal !== MITIGATION_CAP_SIGNAL)
        .map((entry) => ({ ...entry, impact: this.impactFor(entry.contribution) }));
    },
  },
  methods: {
    impactFor(contribution) {
      // Defensive: every scored row has a `contribution`, but if one is missing
      // we don't know the direction, so we show no tag rather than claiming
      // "No change", which would misreport a signal that did move the score.
      if (contribution == null) {
        return null;
      }

      if (contribution === 0) {
        return {
          icon: 'dash',
          iconClass: 'gl-text-subtle',
          textClass: 'gl-text-subtle',
          label: s__('RiskAssessment|No change'),
        };
      }

      const size = Math.abs(contribution);
      const isMajor = size >= CONTRIBUTION_MAJOR_THRESHOLD;
      const isMinor = size < CONTRIBUTION_MINOR_THRESHOLD;
      const isIncrease = contribution > 0;

      let label = isIncrease ? s__('RiskAssessment|Increase') : s__('RiskAssessment|Decrease');
      // Only the icon carries direction color; text weight separates the bands.
      let textClass = '';
      if (isMajor) {
        label = isIncrease
          ? s__('RiskAssessment|Major increase')
          : s__('RiskAssessment|Major decrease');
        textClass = 'gl-font-bold';
      }
      if (isMinor) {
        label = isIncrease
          ? s__('RiskAssessment|Minor increase')
          : s__('RiskAssessment|Minor decrease');
        textClass = 'gl-text-subtle';
      }

      return {
        icon: isIncrease ? 'trend-up' : 'trend-down',
        iconClass: isIncrease ? 'gl-text-danger' : 'gl-text-success',
        textClass,
        label,
      };
    },
  },
};
</script>

<template>
  <div>
    <h5 class="gl-mb-2 gl-mt-4">
      {{ s__('RiskAssessment|What affected the risk score') }}
    </h5>
    <ul class="gl-list-none gl-pl-0" data-testid="risk-signal-breakdown">
      <li
        v-for="entry in riskRows"
        :key="entry.signal"
        class="gl-border-b gl-flex gl-items-center gl-justify-between gl-gap-5 gl-border-b-default gl-py-2 last:gl-border-b-0"
      >
        <div>
          {{ entry.label || entry.signal }}
          <span v-if="entry.detail" class="gl-block gl-text-sm gl-text-subtle">{{
            entry.detail
          }}</span>
        </div>
        <span
          v-if="entry.impact"
          :class="entry.impact.textClass"
          class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm"
          data-testid="risk-signal-impact"
        >
          {{ entry.impact.label }}
          <gl-icon :name="entry.impact.icon" :size="12" :class="entry.impact.iconClass" />
        </span>
      </li>
    </ul>
  </div>
</template>
