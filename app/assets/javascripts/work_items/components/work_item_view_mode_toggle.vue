<script>
import { GlButton, GlButtonGroup, GlTooltipDirective } from '@gitlab/ui';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';
import { isInPast, newDate } from '~/lib/utils/datetime/date_calculation_utility';
import { viewModeOptions } from 'ee_else_ce/work_items/view_modes';
import { BOARD_VIEW_POPOVER_END_DATE, VIEW_MODE_BOARD, VIEW_MODE_TABLE } from '../constants';
import WorkItemBoardViewPopover from './work_item_board_view_popover.vue';

export default {
  name: 'WorkItemViewModeToggle',
  components: {
    GlButton,
    GlButtonGroup,
    UserCalloutDismisser,
    WorkItemBoardViewPopover,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagMixin()],
  props: {
    viewMode: {
      type: String,
      required: true,
    },
    isBoardEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    showBoardPopover: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['toggle-view-mode'],
  computed: {
    shouldShowBoardPopover() {
      return (
        this.showBoardPopover &&
        this.isBoardEnabled &&
        !isInPast(newDate(BOARD_VIEW_POPOVER_END_DATE))
      );
    },
    isBoardViewActive() {
      return this.viewMode === VIEW_MODE_BOARD;
    },
    availableViewModeOptions() {
      return viewModeOptions.filter((option) => {
        if (option.value === VIEW_MODE_TABLE) {
          return Boolean(this.glFeatures.planningViewTable);
        }
        if (option.value === VIEW_MODE_BOARD) {
          return this.isBoardEnabled;
        }
        return true;
      });
    },
  },
  methods: {
    boardButtonTarget(type) {
      return () =>
        this.$refs.toggle?.querySelector(`[data-testid="view-mode-${type}-${VIEW_MODE_BOARD}"]`);
    },
    onToggleViewMode(newViewMode, { dismiss, shouldShowCallout } = {}) {
      if (newViewMode === VIEW_MODE_BOARD && this.shouldShowBoardPopover && shouldShowCallout) {
        dismiss();
      }
      this.$emit('toggle-view-mode', newViewMode);
    },
    isPressed(value) {
      return value === this.viewMode ? 'true' : 'false';
    },
  },
};
</script>

<template>
  <user-callout-dismisser
    feature-name="work_item_board_view_popover"
    :skip-query="!shouldShowBoardPopover"
  >
    <template #default="callout">
      <div v-if="availableViewModeOptions.length > 1" ref="toggle" class="gl-relative">
        <gl-button-group class="@md/panel:gl-hidden" data-testid="view-mode-icon-toggle">
          <gl-button
            v-for="option in availableViewModeOptions"
            :key="option.value"
            v-gl-tooltip
            :icon="option.props.icon"
            :title="option.text"
            :aria-label="option.text"
            :aria-pressed="isPressed(option.value)"
            :selected="option.value === viewMode"
            :data-testid="`view-mode-icon-${option.value}`"
            @click="onToggleViewMode(option.value, callout)"
          />
        </gl-button-group>
        <gl-button-group
          class="gl-hidden @md/panel:gl-inline-flex"
          data-testid="view-mode-label-toggle"
        >
          <gl-button
            v-for="option in availableViewModeOptions"
            :key="option.value"
            :aria-pressed="isPressed(option.value)"
            :selected="option.value === viewMode"
            :data-testid="`view-mode-label-${option.value}`"
            @click="onToggleViewMode(option.value, callout)"
          >
            {{ option.text }}
          </gl-button>
        </gl-button-group>
        <template v-if="shouldShowBoardPopover && callout.shouldShowCallout && !isBoardViewActive">
          <!-- Board is the last option, so the toggle's top-right corner is the board button's. -->
          <span
            class="gl-pointer-events-none gl-absolute gl-right-2 gl-top-3"
            aria-hidden="true"
            data-testid="board-view-hotspot"
          >
            <span class="hotspot-pulse gl-block"></span>
          </span>
          <work-item-board-view-popover :target="boardButtonTarget('icon')" />
          <work-item-board-view-popover :target="boardButtonTarget('label')" />
        </template>
      </div>
    </template>
  </user-callout-dismisser>
</template>
