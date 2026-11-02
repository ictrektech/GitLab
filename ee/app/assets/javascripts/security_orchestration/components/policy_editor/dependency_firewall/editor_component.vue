<script>
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { extractPolicyContent, fromYaml } from 'ee/security_orchestration/components/utils';
import {
  policyBodyToYaml,
  policyToYaml,
} from 'ee/security_orchestration/components/policy_editor/utils';
import {
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
  EDITOR_MODES,
  SECURITY_POLICY_ACTIONS,
  RULE_SECTION_DISABLE_ERROR,
} from '../constants';
import EditorLayout from '../editor_layout.vue';
import DisabledSection from '../disabled_section.vue';
import { DEPENDENCY_FIREWALL_POLICY_TYPE } from '../../constants';
import { ENFORCEMENT_WARN } from './constants';
import RuleList from './rule/rule_list.vue';
import BypassSettings from './advanced_settings/bypass_settings.vue';
import SectionHeading from './components/section_heading.vue';
import PolicyDetailsCard from './components/policy_details_card.vue';
import PolicyScopeCard from './components/policy_scope_card.vue';

export const DEFAULT_DEPENDENCY_FIREWALL_POLICY = `dependency_firewall_policy:
  - name: ''
    description: ''
    enabled: true
    # \`enforced\` blocks the download when a rule matches.
    # \`warn\` allows the download and records a warning.
    enforcement_type: warn
    policy_scope:
      projects:
        excluding: []
    # Add at least one rule by checking one of the rule cards below.
    rules: []
`;

// Pre-phase-2 default: rendered only when `dependency_firewall_phase2` is disabled, so the
// rule-builder UI can roll out incrementally without changing the YAML-only experience.
const LEGACY_DEFAULT_DEPENDENCY_FIREWALL_POLICY = `dependency_firewall_policy:
  - name: Your policy name
    description: Your policy description
    enabled: true
    # \`enforced\` blocks the download when a rule matches.
    # \`warn\` allows the download and records a warning.
    enforcement_type: warn
    policy_scope:
      projects:
        excluding: []
    rules:
      # Deny by SPDX license name. Swap \`denied\` for \`allowed\` to use an allowlist.
      - type: license
        denied:
          - name: SPDX License Name
        # Optional: exempt specific packages from this rule.
        # exceptions:
        #   - purl: pkg:npm/lodash@4.17.21
      # Denies a package that has more than \`threshold\` vulnerabilities at a severity.
      # One of: critical, high, medium, low. List each severity at most once.
      - type: risk_severity
        denied:
          - severity: high
            threshold: 0
        # Optional: exempt specific vulnerabilities from this rule.
        # exceptions:
        #   - id: CVE-2021-23337
      # Blocks packages flagged by the malicious packages feed.
      # \`denied\` only - \`allowed\` is not permitted for this type.
      - type: malicious
        denied:
          - is_malicious: true
`;

const YAML_ONLY_MODES = [
  { value: EDITOR_MODE_YAML, text: s__('SecurityOrchestration|.yaml mode') },
];

export default {
  name: 'DependencyFirewallEditorComponent',
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
  EDITOR_MODES,
  YAML_ONLY_MODES,
  SECURITY_POLICY_ACTIONS,
  i18n: {
    RULE_SECTION_DISABLE_ERROR,
    rulesHeading: s__('SecurityOrchestration|What should it look for?'),
    rulesSubtitle: s__('SecurityOrchestration|Three kinds of rule, all in one policy.'),
    rulesSubtitleWithPackageVersion: s__(
      'SecurityOrchestration|Four kinds of rule, all in one policy.',
    ),
    bypassHeading: s__('SecurityOrchestration|Who can bypass it?'),
    bypassSubtitle: s__(
      'SecurityOrchestration|A listed user or access token is allowed through, and the audit event records the bypass.',
    ),
    scopeHeading: s__('SecurityOrchestration|Which groups and projects should it apply to?'),
    scopeSubtitle: s__(
      'SecurityOrchestration|A policy normally applies only where it is defined. The dependency firewall lets one policy cover a tree.',
    ),
  },
  components: {
    EditorLayout,
    DisabledSection,
    RuleList,
    BypassSettings,
    SectionHeading,
    PolicyDetailsCard,
    PolicyScopeCard,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    existingPolicy: {
      type: Object,
      required: false,
      default: null,
    },
    isCreating: {
      type: Boolean,
      required: true,
    },
    isDeleting: {
      type: Boolean,
      required: true,
    },
    isEditing: {
      type: Boolean,
      required: true,
    },
    selectedPolicyType: {
      type: String,
      required: true,
    },
  },
  emits: ['save'],
  data() {
    let yamlEditorValue;

    if (this.existingPolicy) {
      yamlEditorValue = policyToYaml(this.existingPolicy, this.selectedPolicyType);
    } else if (this.glFeatures.dependencyFirewallPhase2) {
      yamlEditorValue = DEFAULT_DEPENDENCY_FIREWALL_POLICY;
    } else {
      yamlEditorValue = LEGACY_DEFAULT_DEPENDENCY_FIREWALL_POLICY;
    }

    const policy = fromYaml({ manifest: yamlEditorValue, type: DEPENDENCY_FIREWALL_POLICY_TYPE });

    return {
      policy,
      yamlEditorValue,
    };
  },
  computed: {
    packageVersionEnabled() {
      return Boolean(
        this.glFeatures.dependencyFirewallAccess &&
        this.glFeatures.dependencyFirewallPackageVersion,
      );
    },
    rulesSubtitle() {
      return this.packageVersionEnabled
        ? this.$options.i18n.rulesSubtitleWithPackageVersion
        : this.$options.i18n.rulesSubtitle;
    },
    phase2Enabled() {
      return Boolean(this.glFeatures.dependencyFirewallPhase2);
    },
    defaultEditorMode() {
      return this.phase2Enabled ? this.$options.EDITOR_MODE_RULE : this.$options.EDITOR_MODE_YAML;
    },
    editorModes() {
      return this.phase2Enabled ? this.$options.EDITOR_MODES : this.$options.YAML_ONLY_MODES;
    },
    parsingError() {
      return Boolean(this.yamlEditorValue) && Object.keys(this.policy).length === 0;
    },
    rules() {
      return this.policy.rules || [];
    },
    enforcementType() {
      return this.policy.enforcement_type || ENFORCEMENT_WARN;
    },
    bypassSettings() {
      return this.policy.bypass_settings || {};
    },
  },
  methods: {
    updateYamlEditorValue(policy) {
      this.yamlEditorValue = policyToYaml(policy, this.selectedPolicyType);
    },
    updateRules(rules) {
      this.policy = { ...this.policy, rules };
      this.updateYamlEditorValue(this.policy);
    },
    updateEnforcementType(enforcementType) {
      this.policy = { ...this.policy, enforcement_type: enforcementType };
      this.updateYamlEditorValue(this.policy);
    },
    async handleModifyPolicy(action) {
      const policy = extractPolicyContent({
        manifest: this.yamlEditorValue,
        type: this.selectedPolicyType,
        withType: true,
      });

      this.$emit('save', {
        action,
        policy: policyBodyToYaml(policy),
      });
    },
    areManifestsEqual(manifest) {
      return policyToYaml(this.policy, this.selectedPolicyType) === manifest;
    },
    handleUpdateYaml(manifest) {
      // The underlying Monaco editor fires this on any content change, including
      // when we set its :value ourselves via updateYamlEditorValue() below (e.g.
      // after a rule edit). Re-parsing that echo would round-trip `policy` through
      // YAML text, which has no `id` field, so every rule/action would get a fresh
      // id from fromYaml's addIdsToPolicy - breaking `:key="rule.id"` in rule_list.vue
      // and force-remounting the whole rule subtree (dropping focus mid-edit).
      // Matches the same guard already used in pipeline_execution and
      // vulnerability_management's editor_component.vue for this exact bug class.
      if (this.areManifestsEqual(manifest)) {
        return;
      }

      this.yamlEditorValue = manifest;
      this.policy = fromYaml({ manifest, type: DEPENDENCY_FIREWALL_POLICY_TYPE });
    },
    handleRemoveProperty(property) {
      const { [property]: removedProperty, ...updatedPolicy } = this.policy;
      this.policy = updatedPolicy;
      this.updateYamlEditorValue(this.policy);
    },
    handleUpdateProperty(property, value) {
      // Assign via a new object (not `this.policy[property] = value`): bypass_settings
      // isn't in the default policy, and Vue 2 doesn't react to adding a brand-new
      // property by plain mutation, only to reassigning the object.
      this.policy = { ...this.policy, [property]: value };
      this.updateYamlEditorValue(this.policy);
    },
  },
};
</script>
<template>
  <editor-layout
    :default-editor-mode="defaultEditorMode"
    :editor-modes="editorModes"
    :is-editing="isEditing"
    :is-removing-policy="isDeleting"
    :is-updating-policy="isCreating"
    :policy="policy"
    :yaml-editor-value="yamlEditorValue"
    @remove-policy="handleModifyPolicy($options.SECURITY_POLICY_ACTIONS.REMOVE)"
    @save-policy="handleModifyPolicy"
    @remove-property="handleRemoveProperty"
    @update-property="handleUpdateProperty"
    @update-yaml="handleUpdateYaml"
  >
    <template v-if="phase2Enabled" #policy-details>
      <policy-details-card
        :policy="policy"
        :enforcement-type="enforcementType"
        :has-parsing-error="parsingError"
        @update-property="handleUpdateProperty"
        @change-enforcement-type="updateEnforcementType"
      />
    </template>

    <!-- The scope lives at the bottom of the form in this policy's design, so the layout's
         own scope slot is deliberately emptied rather than filled. -->
    <template v-if="phase2Enabled" #policy-scope>
      <span class="gl-hidden" data-testid="policy-scope-moved"></span>
    </template>

    <template v-if="phase2Enabled" #rules>
      <disabled-section :disabled="parsingError" :error="$options.i18n.RULE_SECTION_DISABLE_ERROR">
        <template #title>
          <section-heading :title="$options.i18n.rulesHeading" :subtitle="rulesSubtitle" />
        </template>
        <rule-list :rules="rules" @changed="updateRules" />
      </disabled-section>
    </template>

    <template v-if="phase2Enabled" #settings>
      <disabled-section :disabled="parsingError" :error="$options.i18n.RULE_SECTION_DISABLE_ERROR">
        <template #title>
          <section-heading
            :title="$options.i18n.bypassHeading"
            :subtitle="$options.i18n.bypassSubtitle"
          />
        </template>
        <bypass-settings :bypass-settings="bypassSettings" @changed="handleUpdateProperty" />
      </disabled-section>

      <section-heading
        :title="$options.i18n.scopeHeading"
        :subtitle="$options.i18n.scopeSubtitle"
      />

      <policy-scope-card
        :policy-scope="policy.policy_scope"
        :has-parsing-error="parsingError"
        @update-property="handleUpdateProperty"
        @remove-property="handleRemoveProperty"
      />
    </template>
  </editor-layout>
</template>
