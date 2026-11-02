<script>
import { GlFormInput, GlFormSelect } from '@gitlab/ui';
import { __ } from '~/locale';
import {
  GROUP_ID_DESCRIPTION,
  GROUP_ID_INVALID_FEEDBACK,
  GROUP_ID_LABEL,
  GROUP_ID_REGEX,
  PERCENT_ROLLOUT_GROUP_ID,
} from '../../constants';
import ParameterFormGroup from './parameter_form_group.vue';

export default {
  name: 'FlexibleRollout',
  components: {
    GlFormInput,
    GlFormSelect,
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
    percentageDescription: __('Enter an integer number between 0 and 100'),
    percentageInvalid: __('Percent rollout must be an integer number between 0 and 100'),
    percentageLabel: __('Percentage'),
    stickinessDescription: __('Consistency guarantee method'),
    stickinessLabel: __('Based on'),
  },
  stickinessOptions: [
    {
      value: 'default',
      text: __('Available ID'),
    },
    {
      value: 'userId',
      text: __('User ID'),
    },
    {
      value: 'sessionId',
      text: __('Session ID'),
    },
    {
      value: 'random',
      text: __('Random'),
    },
  ],
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
      return this.strategy?.parameters?.rollout ?? '100';
    },
    stickiness() {
      return this.strategy?.parameters?.stickiness ?? this.$options.stickinessOptions[0].value;
    },
  },
  methods: {
    onPercentageChange(value) {
      this.$emit('change', {
        parameters: {
          groupId: this.groupId,
          rollout: value,
          stickiness: this.stickiness,
        },
      });
    },
    onStickinessChange(value) {
      this.$emit('change', {
        parameters: {
          groupId: this.groupId,
          rollout: this.percentage,
          stickiness: value,
        },
      });
    },
    onGroupIdChange(value) {
      this.$emit('change', {
        parameters: {
          groupId: value,
          rollout: this.percentage,
          stickiness: this.stickiness,
        },
      });
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-flex-wrap gl-gap-x-7">
    <div class="gl-min-w-0 gl-max-w-full" data-testid="strategy-flexible-rollout-percentage">
      <parameter-form-group
        :label="$options.i18n.percentageLabel"
        :description="isValid ? $options.i18n.percentageDescription : ''"
        :invalid-feedback="$options.i18n.percentageInvalid"
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
            <span class="!gl-ml-2">%</span>
          </div>
        </template>
      </parameter-form-group>
    </div>

    <div class="gl-min-w-0 gl-max-w-full" data-testid="strategy-flexible-rollout-stickiness">
      <parameter-form-group
        :label="$options.i18n.stickinessLabel"
        :description="$options.i18n.stickinessDescription"
      >
        <template #default="{ inputId }">
          <gl-form-select
            :id="inputId"
            :value="stickiness"
            :options="$options.stickinessOptions"
            @change="onStickinessChange"
          />
        </template>
      </parameter-form-group>
    </div>
    <div class="gl-w-26 gl-min-w-0 gl-max-w-full" data-testid="strategy-flexible-rollout-group-id">
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
