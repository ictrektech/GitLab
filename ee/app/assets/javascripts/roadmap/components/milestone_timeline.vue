<script>
import { cloneDate } from '~/lib/utils/datetime_utility';
import { MILESTONE_ITEM_HEIGHT, PRESET_TYPES } from '../constants';
import localRoadmapSettingsQuery from '../queries/local_roadmap_settings.query.graphql';
import CurrentDayIndicator from './current_day_indicator.vue';
import MilestoneItem from './milestone_item.vue';

export default {
  name: 'MilestoneTimeline',
  components: {
    MilestoneItem,
    CurrentDayIndicator,
  },
  props: {
    timeframe: {
      type: Array,
      required: true,
    },
    milestones: {
      type: Array,
      required: true,
    },
    milestonesExpanded: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      localRoadmapSettings: {},
    };
  },
  apollo: {
    localRoadmapSettings: {
      query: localRoadmapSettingsQuery,
    },
  },
  computed: {
    presetType() {
      return this.localRoadmapSettings.presetType;
    },
    milestonesByTimeframeIndex() {
      const startsInTimeframeItem = this.timeframe.map(this.startsInTimeframeItem);
      const placedMilestones = this.milestones.map((milestone, row) => ({
        milestone,
        index: startsInTimeframeItem.findIndex((startsIn) => startsIn(milestone.startDate)),
        style: { top: `${row * MILESTONE_ITEM_HEIGHT}px` },
      }));

      return this.timeframe.map((_, index) =>
        placedMilestones.filter((placed) => placed.index === index),
      );
    },
    milestoneRowsStyle() {
      return {
        height: `${this.milestones.length * MILESTONE_ITEM_HEIGHT}px`,
      };
    },
  },
  methods: {
    // The same tests as hasStartDateForQuarter, hasStartDateForMonth and hasStartDateForWeek,
    // so a milestone is created in the one column its MilestoneItem draws in.
    startsInTimeframeItem(timeframeItem) {
      if (this.presetType === PRESET_TYPES.QUARTERS) {
        const quarterStart = timeframeItem.range[0].getTime();
        const quarterEnd = timeframeItem.range[2].getTime();
        return (date) => date.getTime() >= quarterStart && date.getTime() <= quarterEnd;
      }
      if (this.presetType === PRESET_TYPES.MONTHS) {
        return (date) =>
          date.getMonth() === timeframeItem.getMonth() &&
          date.getFullYear() === timeframeItem.getFullYear();
      }
      if (this.presetType === PRESET_TYPES.WEEKS) {
        const lastDayOfWeek = cloneDate(timeframeItem);
        lastDayOfWeek.setDate(lastDayOfWeek.getDate() + 6);
        const weekStart = timeframeItem.getTime();
        const weekEnd = lastDayOfWeek.getTime();
        return (date) => date.getTime() >= weekStart && date.getTime() <= weekEnd;
      }
      return () => false;
    },
  },
};
</script>

<template>
  <div>
    <span
      v-for="(timeframeItem, index) in timeframe"
      :key="timeframeItem.id"
      class="milestone-timeline-cell !gl-border-r !gl-border-b gl-relative gl-table-cell !gl-border-b-gray-300 !gl-border-r-gray-300"
    >
      <current-day-indicator :timeframe-item="timeframeItem" />
      <template v-if="milestonesExpanded">
        <milestone-item
          v-for="{ milestone, style } in milestonesByTimeframeIndex[index]"
          :key="milestone.id"
          :milestone="milestone"
          :timeframe-item="timeframeItem"
          :style="style"
          class="gl-absolute gl-left-0 gl-right-0"
        />
        <div :style="milestoneRowsStyle" data-testid="milestone-rows"></div>
      </template>
    </span>
  </div>
</template>
