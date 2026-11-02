<script>
import { sprintf, s__ } from '~/locale';
import { SEVERITY_ORDER, SEVERITY_LABELS, SEVERITY_METER_FILL } from './constants';

// A domain-agnostic segmented meter over the 4-rung SEVERITY_ORDER scale. Callers
// supply their own `label` to frame it for a domain (e.g. risk, impact). Distinct
// from the security SeverityBadge, which renders a 5-6 level icon/badge, not a meter.
export default {
  name: 'SeverityMeter',
  props: {
    // One of SEVERITY_ORDER. An unknown or null level fills no segments, leaving
    // an empty grey meter.
    severity: {
      type: String,
      required: false,
      default: null,
    },
    // Optional override for the accessible label. Defaults to a "Severity: X"
    // sentence built from the level, so callers only set it when their domain
    // needs different wording (e.g. "Risk level: High").
    label: {
      type: String,
      required: false,
      default: null,
    },
    // While a value is still being determined there is no reading yet, so the
    // segments pulse instead of showing a level.
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    filledCount() {
      const index = SEVERITY_ORDER.indexOf(this.severity);
      return index === -1 ? 0 : index + 1;
    },
    ariaLabel() {
      if (this.label) {
        return this.label;
      }

      if (this.loading) {
        return s__('SeverityMeter|Assessing severity');
      }

      const severityLabel = SEVERITY_LABELS[this.severity];
      return severityLabel
        ? sprintf(s__('SeverityMeter|Severity: %{level}'), { level: severityLabel })
        : s__('SeverityMeter|Severity not available');
    },
  },
  segments: SEVERITY_ORDER,
  methods: {
    // Uniform fill: every filled bar takes the current level's colour (the
    // password-strength / signal-meter convention), empty bars sit on the track.
    segmentClass(index) {
      if (this.loading) {
        return 'gl-animate-skeleton-loader';
      }

      return index < this.filledCount ? SEVERITY_METER_FILL[this.severity] : 'severity-meter-track';
    },
  },
};
</script>

<template>
  <span
    class="gl-inline-flex gl-gap-1"
    role="img"
    :aria-label="ariaLabel"
    data-testid="severity-meter"
  >
    <span
      v-for="(segmentSeverity, index) in $options.segments"
      :key="segmentSeverity"
      class="gl-h-5 gl-w-2 gl-rounded-sm"
      :class="segmentClass(index)"
      aria-hidden="true"
    ></span>
  </span>
</template>
