<script>
export default {
  name: 'FieldRow',
  props: {
    label: {
      type: String,
      required: true,
    },
    // When set, the label is a real `<label for>`; otherwise it is a `<span>` that the
    // control references with aria-labelledby (via `labelId`).
    labelFor: {
      type: String,
      required: false,
      default: '',
    },
    labelId: {
      type: String,
      required: false,
      default: '',
    },
    hint: {
      type: String,
      required: false,
      default: '',
    },
    last: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-flex-col gl-gap-2 @md/panel:gl-flex-row @md/panel:gl-items-start @md/panel:gl-gap-1"
    :class="{ 'gl-mb-5': !last }"
  >
    <label
      v-if="labelFor"
      :for="labelFor"
      class="gl-mb-0 gl-shrink-0 gl-font-bold @md/panel:gl-w-26 @md/panel:gl-pt-2"
    >
      {{ label }}
    </label>
    <span v-else :id="labelId" class="gl-shrink-0 gl-font-bold @md/panel:gl-w-26 @md/panel:gl-pt-2">
      {{ label }}
    </span>

    <div class="gl-min-w-0 gl-grow">
      <slot></slot>
      <p v-if="hint" class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle">{{ hint }}</p>
    </div>
  </div>
</template>
