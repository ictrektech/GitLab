<script>
import { GlBadge, GlCard, GlFormCheckbox } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_PACKAGE_VERSION,
} from '../constants';
import { buildDefaultRuleForType } from '../utils';
import LicenseRuleBuilder from '../rule/license_rule_builder.vue';
import MaliciousRuleBuilder from '../rule/malicious_rule_builder.vue';
import RiskSeverityRuleBuilder from '../rule/risk_severity_rule_builder.vue';
import PackageVersionRuleBuilder from '../rule/package_version_rule_builder.vue';

const RULE_BUILDERS = {
  [RULE_TYPE_LICENSE]: LicenseRuleBuilder,
  [RULE_TYPE_MALICIOUS]: MaliciousRuleBuilder,
  [RULE_TYPE_RISK_SEVERITY]: RiskSeverityRuleBuilder,
  [RULE_TYPE_PACKAGE_VERSION]: PackageVersionRuleBuilder,
};

export default {
  name: 'FixedRuleCard',
  components: {
    GlBadge,
    GlCard,
    GlFormCheckbox,
  },
  i18n: {
    recommended: s__('SecurityOrchestration|Recommended'),
  },
  props: {
    type: {
      type: String,
      required: true,
    },
    label: {
      type: String,
      required: true,
    },
    // The rule object from the policy's `rules:` array, or null when this rule type isn't
    // included in the policy yet.
    rule: {
      type: Object,
      required: false,
      default: null,
    },
    recommended: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['toggle', 'changed'],
  data() {
    return {
      // Kept locally so the fields stay visible and editable while unchecked (matching the
      // design), without writing an edit into `rules:` until the checkbox is actually checked.
      draftRule: this.rule || buildDefaultRuleForType(this.type),
    };
  },
  computed: {
    checked() {
      return this.rule !== null;
    },
    ruleBuilder() {
      return RULE_BUILDERS[this.type];
    },
  },
  watch: {
    rule(newRule) {
      if (newRule) {
        this.draftRule = newRule;
      }
    },
  },
  methods: {
    onToggle(checked) {
      this.$emit('toggle', { checked, draftRule: this.draftRule });
    },
    onChanged(rule) {
      this.draftRule = rule;

      if (this.checked) {
        this.$emit('changed', rule);
      }
    },
  },
};
</script>

<template>
  <gl-card>
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <gl-form-checkbox :checked="checked" class="gl-mb-0" @change="onToggle">
          <span class="gl-font-bold">{{ label }}</span>
        </gl-form-checkbox>
        <gl-badge v-if="recommended" variant="success">{{ $options.i18n.recommended }}</gl-badge>
      </div>
    </template>

    <component
      :is="ruleBuilder"
      v-if="ruleBuilder"
      :init-rule="draftRule"
      :is-active="checked"
      @changed="onChanged"
    />
  </gl-card>
</template>
