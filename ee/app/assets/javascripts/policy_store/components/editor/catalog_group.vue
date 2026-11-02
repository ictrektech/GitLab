<script>
import { GlButton, GlIcon, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'CatalogGroup',
  components: { GlButton, GlIcon },
  directives: { GlTooltip: GlTooltipDirective },
  props: {
    group: {
      type: Object,
      required: true,
    },
    selectedIds: {
      type: Array,
      required: false,
      default: () => [],
    },
    optionTestid: {
      type: String,
      required: true,
    },
    // Item id to the sentence saying why it cannot be picked. A disabled item stays
    // visible: dropping it out of the group makes the picker look broken.
    disabledItems: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['select'],
  data() {
    return { highlightedItem: null };
  },
  methods: {
    isSelected({ id }) {
      return this.selectedIds.includes(id);
    },
    ariaPressed(item) {
      return String(this.isSelected(item));
    },
    showsInfo(item) {
      return this.highlightedItem === item.id && Boolean(item.description);
    },
    isDisabled({ id }) {
      return Boolean(this.disabledItems[id]);
    },
    // A selected disallowed item is still clickable, so marking it disabled would tell a
    // screen-reader or pointer user the only way out of the pairing is unavailable.
    showsDisabled(item) {
      return this.isDisabled(item) && !this.isSelected(item);
    },
    // Only while the item reads as disabled: a selected disallowed item is still clickable,
    // so the reason it cannot be picked would contradict the one control that works.
    tooltipFor(item) {
      return this.showsDisabled(item) ? this.disabledItems[item.id] : item.description;
    },
    // A selected item stays clickable even while disallowed: a policy can be loaded
    // already holding a pairing this rule refuses, and deselecting is the way out of it.
    select(item) {
      if (!this.isDisabled(item) || this.isSelected(item)) this.$emit('select', item.id);
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-2">
    <p class="gl-mb-0 gl-px-2 gl-py-1 gl-text-sm gl-font-semibold gl-text-subtle">
      {{ group.label }}
    </p>
    <!-- aria-disabled, not `disabled`: a disabled button takes neither hover nor focus, so
    the tooltip carrying the reason it cannot be picked would never open. -->
    <gl-button
      v-for="item in group.items"
      :key="item.id"
      v-gl-tooltip
      :title="tooltipFor(item)"
      block
      :aria-disabled="showsDisabled(item) || null"
      :aria-pressed="ariaPressed(item)"
      :data-testid="optionTestid"
      class="!gl-rounded-lg"
      :class="{ 'gl-cursor-not-allowed gl-opacity-5': showsDisabled(item) }"
      button-text-classes="gl-flex gl-w-full gl-min-w-0 gl-items-center gl-gap-3 gl-text-left"
      @click="select(item)"
      @mouseenter="highlightedItem = item.id"
      @mouseleave="highlightedItem = null"
      @focusin="highlightedItem = item.id"
      @focusout="highlightedItem = null"
    >
      <span
        class="gl-flex gl-h-6 gl-w-6 gl-flex-shrink-0 gl-items-center gl-justify-center gl-rounded-base gl-text-subtle"
      >
        <gl-icon :name="item.icon" :size="14" />
      </span>
      <span class="gl-min-w-0 gl-flex-1 gl-truncate gl-text-sm">{{ item.label }}</span>
      <gl-icon
        v-if="showsInfo(item)"
        name="information-o"
        :size="14"
        class="gl-flex-shrink-0 gl-text-subtle"
      />
      <gl-icon
        v-else-if="isSelected(item)"
        name="check-circle-filled"
        :size="14"
        class="gl-flex-shrink-0 gl-text-success"
      />
    </gl-button>
  </div>
</template>
