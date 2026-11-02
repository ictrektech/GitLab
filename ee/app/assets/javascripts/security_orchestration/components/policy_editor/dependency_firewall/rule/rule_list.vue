<script>
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_PACKAGE_VERSION,
} from '../constants';
import { buildDefaultRuleForType } from '../utils';
import FixedRuleCard from '../components/fixed_rule_card.vue';

export default {
  name: 'RuleList',
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_PACKAGE_VERSION,
  components: { FixedRuleCard },
  mixins: [glFeatureFlagsMixin()],
  i18n: {
    maliciousLabel: s__('SecurityOrchestration|Malicious packages'),
    // "Known vulnerabilities" is the design's name for the risk_severity card.
    knownVulnerabilitiesLabel: s__('SecurityOrchestration|Known vulnerabilities'),
    licenseLabel: s__('SecurityOrchestration|Licenses'),
    packageVersionLabel: s__('SecurityOrchestration|Package versions'),
  },
  props: {
    rules: {
      type: Array,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    packageVersionEnabled() {
      return Boolean(
        this.glFeatures.dependencyFirewallAccess &&
        this.glFeatures.dependencyFirewallPackageVersion,
      );
    },
    maliciousRule() {
      return this.findRule(RULE_TYPE_MALICIOUS);
    },
    licenseRule() {
      return this.findRule(RULE_TYPE_LICENSE);
    },
    riskSeverityRule() {
      return this.findRule(RULE_TYPE_RISK_SEVERITY);
    },
    packageVersionRule() {
      return this.findRule(RULE_TYPE_PACKAGE_VERSION);
    },
  },
  methods: {
    findRule(type) {
      return this.rules.find((rule) => rule.type === type) || null;
    },
    toggleRule(type, { checked, draftRule }) {
      if (checked) {
        this.$emit('changed', [...this.rules, draftRule || buildDefaultRuleForType(type)]);
      } else {
        this.$emit(
          'changed',
          this.rules.filter((rule) => rule.type !== type),
        );
      }
    },
    updateRule(type, rule) {
      this.$emit(
        'changed',
        this.rules.map((existing) => (existing.type === type ? rule : existing)),
      );
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4">
    <fixed-rule-card
      :type="$options.RULE_TYPE_MALICIOUS"
      :label="$options.i18n.maliciousLabel"
      :rule="maliciousRule"
      recommended
      @toggle="toggleRule($options.RULE_TYPE_MALICIOUS, $event)"
      @changed="updateRule($options.RULE_TYPE_MALICIOUS, $event)"
    />

    <fixed-rule-card
      :type="$options.RULE_TYPE_RISK_SEVERITY"
      :label="$options.i18n.knownVulnerabilitiesLabel"
      :rule="riskSeverityRule"
      @toggle="toggleRule($options.RULE_TYPE_RISK_SEVERITY, $event)"
      @changed="updateRule($options.RULE_TYPE_RISK_SEVERITY, $event)"
    />

    <fixed-rule-card
      :type="$options.RULE_TYPE_LICENSE"
      :label="$options.i18n.licenseLabel"
      :rule="licenseRule"
      @toggle="toggleRule($options.RULE_TYPE_LICENSE, $event)"
      @changed="updateRule($options.RULE_TYPE_LICENSE, $event)"
    />

    <fixed-rule-card
      v-if="packageVersionEnabled"
      :type="$options.RULE_TYPE_PACKAGE_VERSION"
      :label="$options.i18n.packageVersionLabel"
      :rule="packageVersionRule"
      @toggle="toggleRule($options.RULE_TYPE_PACKAGE_VERSION, $event)"
      @changed="updateRule($options.RULE_TYPE_PACKAGE_VERSION, $event)"
    />
  </div>
</template>
