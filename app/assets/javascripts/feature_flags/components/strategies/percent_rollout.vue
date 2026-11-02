<script>
import { GlFormInput } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import {
  GROUP_ID_DESCRIPTION,
  GROUP_ID_INVALID_FEEDBACK,
  GROUP_ID_LABEL,
  GROUP_ID_REGEX,
  PERCENT_ROLLOUT_GROUP_ID,
} from '../../constants';
import ParameterFormGroup from './parameter_form_group.vue';

export default {
  name: 'PercentRollout',
  components: {
    GlFormInput,
    ParameterFormGroup,
  },
  props: {
    strategy: {
      required: true,
      type: Object,
    },
  },
  emits: ['change'],
  i18n: {
    groupIdDescription: GROUP_ID_DESCRIPTION,
    groupIdInvalid: GROUP_ID_INVALID_FEEDBACK,
    groupIdLabel: GROUP_ID_LABEL,
    rolloutPercentageDescription: __('Enter an integer number between 0 and 100'),
    rolloutPercentageInvalid: s__(
      'FeatureFlags|Percent rollout must be an integer number between 0 and 100',
    ),
    rolloutPercentageLabel: s__('FeatureFlag|Percentage'),
  },
  computed: {
    groupId() {
      return this.strategy?.parameters?.groupId ?? PERCENT_ROLLOUT_GROUP_ID;
    },
    isGroupIdValid() {
      return GROUP_ID_REGEX.test(this.groupId);
    },
    isValid() {
      const percentageNum = Number(this.percentage);
      return Number.isInteger(percentageNum) && percentageNum >= 0 && percentageNum <= 100;
    },
    percentage() {
      return this.strategy?.parameters?.percentage ?? '100';
    },
  },
  methods: {
    onPercentageChange(value) {
      this.$emit('change', {
        parameters: {
          percentage: value,
          groupId: this.groupId,
        },
      });
    },
    onGroupIdChange(value) {
      this.$emit('change', {
        parameters: {
          percentage: this.percentage,
          groupId: value,
        },
      });
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-flex-wrap gl-gap-x-7">
    <div class="gl-min-w-0 gl-max-w-full" data-testid="strategy-percent-rollout-percentage">
      <parameter-form-group
        :label="$options.i18n.rolloutPercentageLabel"
        :description="isValid ? $options.i18n.rolloutPercentageDescription : ''"
        :invalid-feedback="$options.i18n.rolloutPercentageInvalid"
        :state="isValid"
      >
        <template #default="{ inputId }">
          <div class="gl-flex gl-items-center">
            <gl-form-input
              :id="inputId"
              :value="percentage"
              :state="isValid"
              type="number"
              min="0"
              max="100"
              width="xs"
              @input="onPercentageChange"
            />
            <span class="gl-ml-2">%</span>
          </div>
        </template>
      </parameter-form-group>
    </div>
    <div class="gl-w-26 gl-min-w-0 gl-max-w-full" data-testid="strategy-percent-rollout-group-id">
      <parameter-form-group
        :label="$options.i18n.groupIdLabel"
        :description="isGroupIdValid ? $options.i18n.groupIdDescription : ''"
        :invalid-feedback="$options.i18n.groupIdInvalid"
        :state="isGroupIdValid"
      >
        <template #default="{ inputId }">
          <gl-form-input
            :id="inputId"
            :value="groupId"
            :state="isGroupIdValid"
            width="md"
            @input="onGroupIdChange"
          />
        </template>
      </parameter-form-group>
    </div>
  </div>
</template>
