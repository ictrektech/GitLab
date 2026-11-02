<script>
import { isEqual } from 'lodash-es';
import { createAlert, VARIANT_WARNING } from '~/alert';
import { formatNumber, s__, sprintf } from '~/locale';

import groupMilestones from '../queries/group_milestones.query.graphql';
import localRoadmapSettingsQuery from '../queries/local_roadmap_settings.query.graphql';
import { getEpicsTimeframeRange, mapLocalSettings } from '../utils/roadmap_utils';
import {
  formatRoadmapItemDetails,
  timeframeStartDate,
  timeframeEndDate,
} from '../utils/roadmap_item_utils';

import eventHub from '../event_hub';
import {
  MILESTONES_GROUP,
  MILESTONES_SUBGROUP,
  MILESTONES_PROJECT,
  MILESTONES_PAGE_SIZE,
  MILESTONES_MAX_REQUEST_COUNT,
} from '../constants';

import EpicsListSection from './epics_list_section.vue';
import MilestonesListSection from './milestones_list_section.vue';
import RoadmapTimelineSection from './roadmap_timeline_section.vue';

export default {
  name: 'RoadmapShell',
  components: {
    EpicsListSection,
    MilestonesListSection,
    RoadmapTimelineSection,
  },
  inject: ['fullPath', 'epicIid'],
  props: {
    epics: {
      type: Array,
      required: true,
    },
    epicsFetchNextPageInProgress: {
      type: Boolean,
      required: true,
    },
    hasNextPage: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['scrolled-to-end'],
  data() {
    return {
      containerStyles: {},
      canCalculateEpicsListHeight: false,
      milestones: [],
      milestonesRequestCount: 0,
      milestonesRequestVariables: null,
      milestonesRequestedPages: new Set(),
      milestonesFailedPages: new Set(),
      milestonesCapAlert: null,
      // eslint-disable-next-line vue/no-unused-properties -- This is used in Apollo query
      localRoadmapSettings: {},
    };
  },
  apollo: {
    milestones: {
      query: groupMilestones,
      variables() {
        return this.milestonesQueryVariables;
      },
      skip() {
        return !this.isShowingMilestones;
      },
      update(data) {
        const rawMilestones = data.group.milestones.nodes;
        const startDate = timeframeStartDate(this.presetType, this.timeframe);
        const endDate = timeframeEndDate(this.presetType, this.timeframe);

        return rawMilestones.reduce((filteredMilestones, milestone) => {
          const formattedMilestone = formatRoadmapItemDetails(milestone, startDate, endDate);
          // Exclude any Milestone that has invalid dates
          // or is already present in Roadmap timeline
          if (formattedMilestone.startDate.getTime() <= formattedMilestone.endDate.getTime()) {
            filteredMilestones.push(formattedMilestone);
          }
          return filteredMilestones;
        }, []);
      },
      result({ data }) {
        const { nodes, pageInfo } = data?.group?.milestones ?? {};

        if (!isEqual(this.milestonesRequestVariables, this.milestonesQueryVariables)) {
          this.milestonesRequestVariables = this.milestonesQueryVariables;
          this.milestonesRequestCount = 1;
        }

        if (!pageInfo?.hasNextPage) {
          return;
        }

        if (
          this.milestonesRequestCount < MILESTONES_MAX_REQUEST_COUNT &&
          nodes.length < MILESTONES_PAGE_SIZE * MILESTONES_MAX_REQUEST_COUNT
        ) {
          this.fetchNextMilestonesPage(pageInfo.endCursor);
        } else {
          this.milestonesCapAlert = createAlert({
            message: sprintf(s__('GroupRoadmap|Maximum number of milestones loaded (%{count})'), {
              count: formatNumber(MILESTONES_PAGE_SIZE * MILESTONES_MAX_REQUEST_COUNT),
            }),
            variant: VARIANT_WARNING,
          });
        }
      },
      error() {
        this.showMilestonesFetchError();
      },
    },
    localRoadmapSettings: {
      query: localRoadmapSettingsQuery,
    },
  },
  computed: {
    ...mapLocalSettings([
      'isShowingMilestones',
      'milestonesType',
      'bufferSize',
      'timeframe',
      'filterParams',
      'presetType',
    ]),
    milestonesQueryVariables() {
      return {
        fullPath: this.fullPath,
        state: 'active',
        ...getEpicsTimeframeRange({
          presetType: this.presetType,
          timeframe: this.timeframe,
        }),
        includeDescendants: true,
        includeAncestors: true,
        searchTitle: this.filterParams.milestoneTitle,
        first: MILESTONES_PAGE_SIZE,
      };
    },
    shownMilestonesQueryVariables() {
      return this.isShowingMilestones ? this.milestonesQueryVariables : null;
    },
    isScopedRoadmap() {
      return Boolean(this.epicIid);
    },
    displayMilestones() {
      return Boolean(this.milestones.length) && this.isShowingMilestones;
    },
    milestonesToShow() {
      switch (this.milestonesType) {
        case MILESTONES_GROUP:
          return this.milestones.filter((m) => m.groupMilestone && !m.subgroupMilestone);
        case MILESTONES_SUBGROUP:
          return this.milestones.filter((m) => m.subgroupMilestone);
        case MILESTONES_PROJECT:
          return this.milestones.filter((m) => m.projectMilestone);
        default:
          return this.milestones;
      }
    },
    footerMessageHeight() {
      return document.querySelector('.footer-message')?.getBoundingClientRect().height || 0;
    },
    epicsHaveChildren() {
      return this.epics.some((epic) => epic.hasChildren);
    },
  },
  watch: {
    shownMilestonesQueryVariables(variables, previousVariables) {
      if (previousVariables && !isEqual(variables, previousVariables)) {
        this.dismissMilestonesCapAlert();
      }
    },
  },
  mounted() {
    this.$nextTick(() => {
      this.containerStyles = this.getContainerStyles();
    });
  },
  beforeDestroy() {
    this.dismissMilestonesCapAlert();
  },
  methods: {
    fetchNextMilestonesPage(endCursor) {
      const page = JSON.stringify({ ...this.milestonesQueryVariables, after: endCursor });
      if (this.milestonesRequestedPages.has(page)) {
        if (this.milestonesFailedPages.has(page)) {
          this.showMilestonesFetchError();
        }
        return;
      }
      this.milestonesRequestedPages.add(page);
      this.milestonesRequestCount += 1;

      this.$apollo.queries.milestones
        .fetchMore({
          variables: {
            after: endCursor,
          },
        })
        .catch(() => {
          this.milestonesFailedPages.add(page);
          this.showMilestonesFetchError();
        });
    },
    dismissMilestonesCapAlert() {
      this.milestonesCapAlert?.dismiss();
      this.milestonesCapAlert = null;
    },
    showMilestonesFetchError() {
      createAlert({
        message: s__('GroupRoadmap|Something went wrong while fetching milestones'),
      });
    },
    handleScroll() {
      const { scrollTop, scrollLeft, clientHeight, scrollHeight } = this.$el;

      eventHub.$emit('epics-list-scrolled', { scrollTop, scrollLeft, clientHeight, scrollHeight });
    },
    getContainerStyles() {
      const { top } = this.$el.getBoundingClientRect();
      return {
        height: this.isScopedRoadmap ? '100%' : `calc(100vh - ${top + this.footerMessageHeight}px)`,
      };
    },
    toggleCanCalculateEpicsListHeight() {
      this.canCalculateEpicsListHeight = true;
    },
  },
};
</script>

<template>
  <div
    class="js-roadmap-shell gl-relative gl-w-full gl-overflow-x-auto"
    data-testid="roadmap-shell"
    :style="containerStyles"
    @scroll="handleScroll"
  >
    <roadmap-timeline-section
      ref="roadmapTimeline"
      :preset-type="presetType"
      :timeframe="timeframe"
    />
    <milestones-list-section
      v-if="displayMilestones"
      :milestones="milestonesToShow"
      :timeframe="timeframe"
      @milestones-mounted="toggleCanCalculateEpicsListHeight"
    />
    <epics-list-section
      :key="canCalculateEpicsListHeight"
      :epics="epics"
      :timeframe="timeframe"
      :epics-fetch-next-page-in-progress="epicsFetchNextPageInProgress"
      :epics-have-children="epicsHaveChildren"
      :has-next-page="hasNextPage"
      :buffer-size="bufferSize"
      @scrolled-to-end="$emit('scrolled-to-end')"
    />
  </div>
</template>
