<script>
import { defineComponent } from 'vue';
import { GlLoadingIcon } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import { executeOrbitNamedQuery } from '../api/orbit_api';
import {
  ENTITY_TYPE_COLORS,
  ENTITY_TYPE_NAMES,
  NAMED_QUERY_EXPAND_NEIGHBORS,
  NAMED_QUERY_LIST_NODES,
} from '../constants';
import { mergeNeighborNodes, transformGraphResponse } from '../utils/graph_transform';
import {
  buildNodeStyleMap,
  entityColorsFromSchema,
  entityNamesFromSchema,
} from '../utils/node_style_map';
import { withCache } from '../utils/orbit_cache';
import { ORBIT_ERROR_KIND, orbitErrorKind, orbitErrorMessage } from '../utils/orbit_errors';
import ExplorerNodeSidebar from './explorer_node_sidebar.vue';
import GraphCanvas from './graph_canvas.vue';
import NodeDetailOverlay from './node_detail_overlay.vue';

// Cap on neighbor rows returned for the batched initial-group expansion.
// Capping rows keeps the first render cheap regardless of how many groups
// the user is in.
const INITIAL_NEIGHBOR_LIMIT = 500;
// GKG NodeSelector.node_ids has maxItems 500; clamp the source IDs too so
// users in 500+ groups don't hit a 4xx before the page renders.
const INITIAL_NODE_IDS_CAP = 500;
// Per-node limit when a user double-clicks to expand a single node.
const EXPAND_NEIGHBOR_LIMIT = 50;
const GROUP_ENTITY = 'Group';

export default defineComponent({
  name: 'GraphExplorer',
  components: {
    GlLoadingIcon,
    ExplorerNodeSidebar,
    GraphCanvas,
    NodeDetailOverlay,
  },
  mixins: [InternalEvents.mixin()],
  isDarkMode: darkModeEnabled(),
  props: {
    initialNodes: {
      type: Array,
      required: false,
      default: () => [],
    },
    initialEdges: {
      type: Array,
      required: false,
      default: () => [],
    },
    schema: {
      type: Object,
      required: false,
      default: null,
    },
    instanceMapRequest: {
      type: Object,
      required: false,
      default: null,
    },
    neighborsVersion: {
      type: String,
      required: false,
      default: null,
    },
    expandNeighbors: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  data() {
    return {
      loading: false,
      mapUnavailable: false,
      selectedNode: null,
      hoveredNode: null,
      hoveredPosition: null,
      expandedNodeIds: {},
      nodes: [],
      edges: [],
    };
  },
  computed: {
    canAutoExpand() {
      return this.expandNeighbors && !this.instanceMapRequest && !this.mapUnavailable;
    },
    schemaNodes() {
      return this.schema?.nodes || [];
    },
    nodeStyleMap() {
      return buildNodeStyleMap(this.schemaNodes);
    },
    entityColors() {
      return { ...ENTITY_TYPE_COLORS, ...entityColorsFromSchema(this.schemaNodes) };
    },
    entityNames() {
      return { ...ENTITY_TYPE_NAMES, ...entityNamesFromSchema(this.schemaNodes) };
    },
    selectedNodeId() {
      return this.selectedNode ? this.selectedNode.id : null;
    },
  },
  watch: {
    instanceMapRequest(req) {
      if (req) this.executeInstanceMapQuery(req);
    },
    neighborsVersion() {
      this.autoExpandInitialNodes();
    },
    initialNodes: {
      immediate: true,
      handler(nodes) {
        this.syncInitialGraph(nodes, this.initialEdges);
      },
    },
    initialEdges(edges) {
      this.edges = edges;
    },
  },
  mounted() {
    if (this.instanceMapRequest) {
      this.executeInstanceMapQuery(this.instanceMapRequest);
    }
  },
  methods: {
    syncInitialGraph(nodes, edges) {
      this.nodes = nodes;
      this.edges = edges;
      this.expandedNodeIds = {};
      this.selectedNode = null;

      if (nodes.length === 0) return;

      this.$nextTick(() => {
        if (!this.mapUnavailable) this.$refs.graphCanvas?.setFullData();
        this.autoExpandInitialNodes();
      });
    },
    async autoExpandInitialNodes() {
      if (!this.canAutoExpand) return;

      const groupNodes = this.initialNodes.filter((n) => n.type === 'group' && n.properties?.id);
      if (groupNodes.length === 0) return;

      const ids = groupNodes
        .map((n) => Number(n.properties?.id))
        .filter((id) => Number.isFinite(id))
        .slice(0, INITIAL_NODE_IDS_CAP);
      if (ids.length === 0) return;

      const cacheKey = `initial-neighbors:${GROUP_ENTITY}:${[...ids].sort().join(',')}:${INITIAL_NEIGHBOR_LIMIT}`;

      this.loading = true;
      try {
        const response = await withCache(
          cacheKey,
          async () => {
            const { data } = await executeOrbitNamedQuery(NAMED_QUERY_EXPAND_NEIGHBORS, {
              parameters: { entity: GROUP_ENTITY, node_ids: ids, limit: INITIAL_NEIGHBOR_LIMIT },
            });
            return data?.result || {};
          },
          { version: this.neighborsVersion },
        );

        const { newNodes, newEdges } = mergeNeighborNodes(response, this.nodes, this.nodeStyleMap);

        if (newNodes.length > 0) {
          this.nodes = [...this.nodes, ...newNodes];
          this.edges = [...this.edges, ...newEdges];
          this.$refs.graphCanvas?.addData(newNodes, newEdges);
        }

        const expanded = { ...this.expandedNodeIds };
        for (const node of groupNodes) expanded[node.id] = true;
        this.expandedNodeIds = expanded;
      } catch (error) {
        const kind = orbitErrorKind(error);
        if (kind === ORBIT_ERROR_KIND.FORBIDDEN) return;

        createAlert({
          message: orbitErrorMessage(error, s__('Orbit|Could not load the map. Try again.')),
          error,
          captureError: kind === ORBIT_ERROR_KIND.SERVER,
        });
      } finally {
        this.loading = false;
      }
    },
    async runQuery(request) {
      this.loading = true;
      try {
        const { data } = await request();
        this.expandedNodeIds = {};
        this.selectedNode = null;

        const result = data?.result || {};
        const { nodes, edges } = transformGraphResponse(result, this.nodeStyleMap);
        this.nodes = nodes;
        this.edges = edges;

        if (nodes.length > 0) {
          this.$nextTick(() => {
            if (!this.mapUnavailable) this.$refs.graphCanvas?.setFullData();
          });
        }
      } catch (err) {
        createAlert({
          message:
            err.response?.data?.message ||
            err.message ||
            s__('Orbit|Could not run the query. Try again.'),
        });
      } finally {
        this.loading = false;
      }
    },
    onMapInitError() {
      this.mapUnavailable = true;
    },
    onNodeSelect(node) {
      this.trackEvent('click_orbit_map_node');
      this.selectedNode = node;
    },
    onNodeHover(node, position) {
      this.hoveredNode = node;
      this.hoveredPosition = position;
    },
    onNodeExpand(node) {
      this.trackEvent('click_orbit_expand_map_node');
      this.expandNode(node);
    },
    closeSidebar() {
      this.selectedNode = null;
    },
    resolveEntityType(lowercaseType) {
      return this.entityNames[lowercaseType] || ENTITY_TYPE_NAMES[lowercaseType] || lowercaseType;
    },
    async expandNode(node) {
      if (this.expandedNodeIds[node.id]) return;

      const entityType = this.resolveEntityType(node.type || 'user');
      const numericId = Number(node.properties?.id);
      if (!Number.isFinite(numericId)) return;

      this.loading = true;
      this.$refs.graphCanvas?.setNodeLoading(node.index, true);
      try {
        const { data } = await executeOrbitNamedQuery(NAMED_QUERY_EXPAND_NEIGHBORS, {
          parameters: { entity: entityType, node_ids: [numericId], limit: EXPAND_NEIGHBOR_LIMIT },
        });

        const response = data.result || {};
        const canvas = this.$refs.graphCanvas;
        const graphNodes = this.nodes;
        const { newNodes, newEdges } = mergeNeighborNodes(response, graphNodes, this.nodeStyleMap);

        if (newNodes.length > 0) {
          this.nodes = [...this.nodes, ...newNodes];
          this.edges = [...this.edges, ...newEdges];
          canvas?.addData(newNodes, newEdges);
        }

        this.expandedNodeIds = { ...this.expandedNodeIds, [node.id]: true };
      } catch (err) {
        createAlert({
          message: err.message || s__('Orbit|Could not load the connections. Try again.'),
        });
      } finally {
        this.loading = false;
        this.$refs.graphCanvas?.setNodeLoading(node.index, false);
      }
    },
    async executeInstanceMapQuery({ entityType }) {
      await this.runQuery(() =>
        executeOrbitNamedQuery(NAMED_QUERY_LIST_NODES, { parameters: { entity: entityType } }),
      );
    },
  },
});
</script>

<template>
  <div data-testid="graph-explorer" class="gl-flex gl-flex-col gl-gap-5">
    <div
      class="orbit-graph-container gl-flex gl-min-w-0 gl-flex-1 gl-flex-col gl-overflow-hidden gl-rounded-xl"
    >
      <div class="gl-flex gl-min-h-0 gl-flex-1 gl-flex-col">
        <div class="gl-relative gl-min-h-0 gl-flex-1 gl-overflow-hidden">
          <p
            v-if="mapUnavailable"
            class="gl-m-0 gl-flex gl-h-full gl-items-center gl-justify-center gl-p-5 gl-text-center gl-text-subtle"
            data-testid="graph-explorer-map-unavailable"
          >
            {{
              s__(
                'Orbit|Your browser cannot show the map. Turn on WebGL or hardware acceleration, then reload the page.',
              )
            }}
          </p>

          <gl-loading-icon v-else-if="loading && nodes.length === 0" size="lg" class="gl-mt-20" />

          <graph-canvas
            v-else
            ref="graphCanvas"
            :nodes="nodes"
            :edges="edges"
            :selected-node-id="selectedNodeId"
            :node-style-map="nodeStyleMap"
            :dark-mode="$options.isDarkMode"
            @node-select="onNodeSelect"
            @node-hover="onNodeHover"
            @node-expand="onNodeExpand"
            @init-error="onMapInitError"
          />

          <node-detail-overlay
            :node="hoveredNode"
            :position="hoveredPosition"
            :entity-colors="entityColors"
            :entity-names="entityNames"
            :all-nodes="nodes"
          />

          <div
            class="gl-z-20 gl-absolute gl-right-4 gl-top-4 gl-flex gl-flex-col gl-items-end gl-gap-3"
          >
            <slot name="top-right"></slot>
            <explorer-node-sidebar
              v-if="selectedNode"
              :node="selectedNode"
              :entity-colors="entityColors"
              :entity-names="entityNames"
              @close="closeSidebar"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
