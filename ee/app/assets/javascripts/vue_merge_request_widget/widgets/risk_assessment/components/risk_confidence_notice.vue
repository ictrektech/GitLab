<script>
export default {
  name: 'RiskConfidenceNotice',
  props: {
    missingLabels: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
};
</script>

<template>
  <div v-if="missingLabels.length" data-testid="risk-low-confidence">
    <h5 class="gl-mb-2 gl-mt-4">{{ s__('RiskAssessment|What lowered confidence') }}</h5>
    <p class="gl-mb-1">{{ s__('RiskAssessment|Could not be measured:') }}</p>
    <ul class="gl-mb-0 gl-pl-5 gl-text-sm gl-text-subtle">
      <li v-for="(label, index) in missingLabels" :key="index">{{ label }}</li>
    </ul>
  </div>
</template>
