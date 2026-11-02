<script>
import { GlIcon, GlFormRadio, GlFormRadioGroup } from '@gitlab/ui';
import { isNumber } from 'lodash-es';
import {
  VISIBILITY_LEVEL_LABELS,
  VISIBILITY_TYPE_ICON,
  VISIBILITY_LEVELS_INTEGER_TO_STRING,
  VISIBILITY_LEVEL_PRIVATE_INTEGER,
} from '~/visibility_level/constants';

export default {
  name: 'VisibilityLevelRadioButtons',
  components: {
    GlIcon,
    GlFormRadio,
    GlFormRadioGroup,
  },
  model: {
    prop: 'checked',
  },
  props: {
    checked: {
      type: Number,
      required: true,
    },
    visibilityLevels: {
      type: Array,
      required: true,
    },
    visibilityLevelDescriptions: {
      type: Object,
      required: true,
    },
    minVisibilityLevel: {
      type: Number,
      required: false,
      default: VISIBILITY_LEVEL_PRIVATE_INTEGER,
    },
    // Visibility levels to disable individually, mapped to the reason they are
    // disabled, for example `{ 20: 'Restricted by your administrator.' }`.
    // An empty reason disables the level without rendering a reason.
    disabledVisibilityLevels: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    // Form field name, so the radio buttons can be submitted by a native form.
    name: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  computed: {
    visibilityLevelsOptions() {
      return this.visibilityLevels.map((visibilityLevel) => {
        const stringValue = VISIBILITY_LEVELS_INTEGER_TO_STRING[visibilityLevel];
        const isBelowMinimum = isNumber(this.minVisibilityLevel)
          ? visibilityLevel < this.minVisibilityLevel
          : false;
        const isDisabledIndividually = Object.prototype.hasOwnProperty.call(
          this.disabledVisibilityLevels,
          visibilityLevel,
        );

        return {
          label: VISIBILITY_LEVEL_LABELS[stringValue],
          description: this.visibilityLevelDescriptions[stringValue],
          icon: VISIBILITY_TYPE_ICON[stringValue],
          value: visibilityLevel,
          disabled: isBelowMinimum || isDisabledIndividually,
          disabledReason: isDisabledIndividually
            ? this.disabledVisibilityLevels[visibilityLevel]
            : '',
        };
      });
    },
    hasDisabledVisibilityLevels() {
      return this.visibilityLevelsOptions.some((visibilityLevel) => visibilityLevel.disabled);
    },
  },
};
</script>

<template>
  <gl-form-radio-group :checked="checked" :name="name" @input="$emit('input', $event)">
    <gl-form-radio
      v-for="{
        label,
        description,
        icon,
        value,
        disabled,
        disabledReason,
      } in visibilityLevelsOptions"
      :key="value"
      :value="value"
      :disabled="disabled"
    >
      <div>
        <gl-icon :name="icon" />
        <span>{{ label }}</span>
      </div>
      <template #help>
        {{ description }}
        <span
          v-if="disabledReason"
          class="gl-mt-2 gl-flex gl-gap-2"
          data-testid="visibility-level-disabled-reason"
        >
          <gl-icon name="lock" class="gl-mt-1 gl-shrink-0" />
          <span>
            <slot name="disabled-reason" :reason="disabledReason" :level="value">{{
              disabledReason
            }}</slot>
          </span>
        </span>
      </template>
    </gl-form-radio>
    <slot v-if="hasDisabledVisibilityLevels" name="disabled-message"></slot>
  </gl-form-radio-group>
</template>
