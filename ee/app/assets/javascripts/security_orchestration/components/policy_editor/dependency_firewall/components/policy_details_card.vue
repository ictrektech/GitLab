<script>
import { GlCard, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import EnforcementModeControl from './enforcement_mode_control.vue';

export default {
  name: 'PolicyDetailsCard',
  components: { GlCard, GlFormGroup, GlFormInput, EnforcementModeControl },
  i18n: {
    header: s__('SecurityOrchestration|Policy details'),
    name: __('Name'),
    description: __('Description'),
    descriptionPlaceholder: s__('SecurityOrchestration|What this policy is for'),
    optional: __('Optional.'),
    failedValidationText: __('This field is required'),
  },
  props: {
    policy: {
      type: Object,
      required: true,
    },
    enforcementType: {
      type: String,
      required: true,
    },
    hasParsingError: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['update-property', 'change-enforcement-type'],
  data() {
    return {
      nameTouched: false,
    };
  },
  computed: {
    hasValidName() {
      return this.policy.name !== '';
    },
  },
  methods: {
    updateName(value) {
      this.nameTouched = true;
      this.$emit('update-property', 'name', value);
    },
  },
};
</script>

<template>
  <gl-card>
    <template #header>
      <h4 class="gl-m-0 gl-text-base">{{ $options.i18n.header }}</h4>
    </template>

    <gl-form-group
      :label="$options.i18n.name"
      label-for="policyName"
      :invalid-feedback="$options.i18n.failedValidationText"
    >
      <gl-form-input
        id="policyName"
        data-testid="policy-name-text"
        :disabled="hasParsingError"
        :state="hasValidName || !nameTouched"
        :value="policy.name"
        required
        @input="updateName"
      />
    </gl-form-group>

    <gl-form-group :label="$options.i18n.description" label-for="policyDescription">
      <gl-form-input
        id="policyDescription"
        data-testid="policy-description-text"
        :disabled="hasParsingError"
        :value="policy.description"
        :placeholder="$options.i18n.descriptionPlaceholder"
        @input="$emit('update-property', 'description', $event)"
      />
      <template #description>{{ $options.i18n.optional }}</template>
    </gl-form-group>

    <enforcement-mode-control
      :enforcement-type="enforcementType"
      :disabled="hasParsingError"
      @change="$emit('change-enforcement-type', $event)"
    />
  </gl-card>
</template>
