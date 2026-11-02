<script>
import CeBlobButtonGroup from '~/repository/components/header_area/blob_button_group.vue';

// Kept as a passthrough: `ee_else_ce` resolves blob_button_group.vue to this
// file in EE, and CE blob_overflow_menu.vue binds the lock props unconditionally,
// so they must stay declared here. Folding this into CE is a follow-up.

export default {
  name: 'BlobButtonGroupEE',
  components: {
    CeBlobButtonGroup,
  },
  props: {
    ...CeBlobButtonGroup.props,
    projectPath: {
      type: String,
      required: true,
    },
    canCreateLock: {
      type: Boolean,
      required: true,
    },
    canDestroyLock: {
      type: Boolean,
      required: true,
    },
    isLocked: {
      type: Boolean,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['show-fork-suggestion'],
  methods: {
    onShowForkSuggestion() {
      this.$emit('show-fork-suggestion');
    },
  },
};
</script>

<template>
  <ce-blob-button-group v-bind="$props" @show-fork-suggestion="onShowForkSuggestion" />
</template>
