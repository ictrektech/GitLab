<script>
import { defineComponent } from 'vue';
import { GlLoadingIcon } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { fetchOrbitSchema } from 'ee/orbit/api/orbit_api';
import { toGroupGraphNode } from 'ee/orbit/utils/graph_transform';
import {
  groupsIndexingVersion,
  hasPendingProjects,
  isInitialIndexing,
  sumItemCounts,
} from 'ee/orbit/utils/orbit_group_state';
import GraphExplorer from 'ee/orbit/components/graph_explorer.vue';
import { LOAD_STATUS } from '../constants';
import OverviewPendingProjects from './overview_pending_projects.vue';
import OverviewQueriesLocked from './overview_queries_locked.vue';
import OverviewStatsCard from './overview_stats_card.vue';

const EMPTY_EDGES = Object.freeze([]);

const groupNodesKey = (nodes) =>
  nodes.map((node) => `${node.id}:${node.label}:${node.avatarUrl}`).join('|');

export default defineComponent({
  name: 'OrbitOverviewPage',
  components: {
    GlLoadingIcon,
    GraphExplorer,
    OverviewPendingProjects,
    OverviewQueriesLocked,
    OverviewStatsCard,
  },
  inject: [
    'adminConfigurationPath',
    'defaultGroupMissing',
    'enabledMemberGroups',
    'itemCountGroups',
    'itemCountsLoading',
    'orbitPlatform',
    'queriesAvailable',
  ],
  data() {
    return {
      schema: null,
      globeNodes: [],
    };
  },
  computed: {
    indexingProgress() {
      return groupsIndexingVersion(this.enabledMemberGroups);
    },
    statsStatus() {
      if (this.itemCountGroups.some((group) => group.orbit?.itemCounts)) return LOAD_STATUS.READY;
      return this.itemCountsLoading ? LOAD_STATUS.LOADING : LOAD_STATUS.FAILED;
    },
    graphStats() {
      if (this.statsStatus !== LOAD_STATUS.READY) return null;

      return {
        ...sumItemCounts(this.itemCountGroups),
        indexedProjects: this.enabledMemberGroups.reduce(
          (sum, group) => sum + (group.orbit?.indexing?.projects?.indexed ?? 0),
          0,
        ),
      };
    },
    initialGroupNodes() {
      return this.enabledMemberGroups.map(toGroupGraphNode);
    },
    // A poll hands over new group objects. Only a real change may reset the globe.
    initialGroupNodesKey() {
      return groupNodesKey(this.initialGroupNodes);
    },
    anyInitialIndexing() {
      return this.enabledMemberGroups.some(isInitialIndexing);
    },
    anyPendingProjects() {
      return this.enabledMemberGroups.some(hasPendingProjects);
    },
    showsQueriesLocked() {
      return !this.queriesAvailable && !this.anyInitialIndexing;
    },
    showsPendingProjects() {
      return !this.anyInitialIndexing && this.anyPendingProjects && !this.showsQueriesLocked;
    },
    instanceMapRequest() {
      const [entity] = [].concat(this.$route.query.entity ?? []);
      return entity && this.queriesAvailable ? { entityType: entity } : null;
    },
  },
  watch: {
    initialGroupNodesKey() {
      this.globeNodes = this.initialGroupNodes;
    },
  },
  created() {
    this.globeNodes = this.initialGroupNodes;
  },
  async mounted() {
    try {
      this.schema = await fetchOrbitSchema(this.$apollo);
    } catch (error) {
      Sentry.captureException(error);
    }
  },
  emptyEdges: EMPTY_EDGES,
});
</script>

<template>
  <div
    class="gl-flex gl-min-h-0 gl-flex-1 gl-flex-col gl-gap-3 gl-pt-5"
    data-testid="orbit-overview-page"
  >
    <div class="gl-relative gl-flex gl-min-h-0 gl-flex-1 gl-flex-col">
      <overview-stats-card
        v-if="!anyInitialIndexing"
        class="gl-mb-3 md:gl-absolute md:gl-left-4 md:gl-top-4 md:gl-z-2 md:gl-mb-0 md:gl-w-full md:gl-max-w-28"
        :group-count="enabledMemberGroups.length"
        :graph-stats="graphStats"
        :status="statsStatus"
      />

      <div
        class="gl-relative gl-flex gl-min-h-62 gl-flex-1 gl-flex-col gl-overflow-hidden gl-rounded-xl"
      >
        <graph-explorer
          :key="instanceMapRequest ? instanceMapRequest.entityType : 'groups'"
          class="gl-min-h-0 gl-flex-1"
          :initial-nodes="globeNodes"
          :initial-edges="$options.emptyEdges"
          :schema="schema"
          :instance-map-request="instanceMapRequest"
          :neighbors-version="indexingProgress"
          :expand-neighbors="!defaultGroupMissing && queriesAvailable"
          :inert="showsQueriesLocked"
        >
          <template #top-right>
            <overview-pending-projects v-if="showsPendingProjects" :groups="enabledMemberGroups" />
          </template>
        </graph-explorer>

        <overview-queries-locked
          v-if="showsQueriesLocked"
          :access-state="orbitPlatform.instance?.state ?? null"
          :admin-path="adminConfigurationPath"
        />

        <div
          v-if="anyInitialIndexing"
          class="gl-absolute gl-inset-0 gl-z-2 gl-flex gl-items-center gl-justify-center gl-bg-overlay gl-p-4"
          role="status"
          data-testid="overview-indexing-overlay"
        >
          <div
            class="gl-flex gl-items-center gl-gap-3 gl-rounded-lg gl-bg-default gl-px-4 gl-py-3 gl-shadow-sm"
          >
            <gl-loading-icon size="sm" inline :label="s__('Orbit|Indexing')" />
            <span>
              {{ s__('Orbit|Indexing in progress. The map fills in as data finishes indexing.') }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
