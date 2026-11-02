<script>
import { defineComponent, markRaw, nextTick } from 'vue';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ThreeGraph3D from '../utils/three_graph_3d';

const NODE_STEP_KEYS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };

export default defineComponent({
  name: 'GraphCanvas',
  props: {
    nodes: {
      type: Array,
      required: true,
    },
    edges: {
      type: Array,
      required: true,
    },
    selectedNodeId: {
      type: String,
      required: false,
      default: null,
    },
    nodeStyleMap: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    darkMode: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['node-select', 'node-hover', 'node-expand', 'init-error'],
  expose: ['setFullData', 'addData', 'setNodeLoading'],
  data() {
    return {
      graph: null,
      resizeObserver: null,
    };
  },
  computed: {
    selectedNodeText() {
      const node = this.nodes.find(({ id }) => id === this.selectedNodeId);

      return node ? sprintf(s__('Orbit|%{name} is selected.'), { name: node.label }) : '';
    },
  },
  watch: {
    selectedNodeId(id) {
      if (!this.graph) return;
      if (id == null) {
        this.graph.deselectNode();
        return;
      }
      const idx = this.nodes.findIndex((n) => n.id === id);
      if (idx >= 0) this.graph.selectNode(idx);
    },
  },
  created() {
    this.helpId = uniqueId('orbit-map-help-');
  },
  mounted() {
    if (!this.initGraph()) return;

    this.resizeObserver = markRaw(
      new ResizeObserver((entries) => {
        const { width, height } = entries[0].contentRect;
        if (width > 0 && height > 0) {
          this.graph?.resize(width, height);
        }
      }),
    );
    this.resizeObserver.observe(this.$el);

    // Resize after the next tick so the flex layout has settled and the
    // renderer captures the final container dimensions rather than any
    // intermediate size that existed at mount time.
    nextTick(() => {
      const { offsetWidth, offsetHeight } = this.$el;
      if (offsetWidth > 0 && offsetHeight > 0) {
        this.graph?.resize(offsetWidth, offsetHeight);
      }
    });

    if (this.nodes.length > 0) {
      this.graph.setData(this.nodes, this.edges);
    }
  },
  beforeDestroy() {
    this.cleanupCanvas();
  },
  methods: {
    cleanupCanvas() {
      if (this.resizeObserver) {
        this.resizeObserver.disconnect();
        this.resizeObserver = null;
      }
      if (this.graph) {
        this.graph.dispose();
        this.graph = null;
      }
    },
    initGraph() {
      try {
        const options = { nodeStyleMap: this.nodeStyleMap, darkMode: this.darkMode };
        this.graph = markRaw(new ThreeGraph3D(this.$refs.canvas, options));
        this.graph.init();
        this.graph.onNodeHover((node, position) => this.$emit('node-hover', node, position));
        this.graph.onNodeSelect((node) => this.$emit('node-select', node));
        this.graph.onNodeExpand((node) => this.$emit('node-expand', node));
        return true;
      } catch (error) {
        // init() throws without WebGL, and a half-built graph cannot dispose.
        this.graph = null;
        Sentry.captureException(error);
        this.$emit('init-error', error);
        return false;
      }
    },

    onKeydown(event) {
      const step = NODE_STEP_KEYS[event.key];
      const { selectedNode } = this.graph;

      if (step) {
        event.preventDefault();
        this.graph.selectNode(this.nodeIndexAfter(selectedNode, step));
      } else if (event.key === 'Enter' && selectedNode) {
        this.$emit('node-expand', selectedNode);
      }
    },

    nodeIndexAfter(node, step) {
      const count = this.nodes.length;
      if (!node) return step > 0 ? 0 : count - 1;

      return (node.index + step + count) % count;
    },

    setFullData() {
      this.graph.setData(this.nodes, this.edges);
    },

    addData(newNodes, newEdges) {
      this.graph.addData(newNodes, newEdges);
      // addData() places new nodes in a ring around their parent; relayout() spreads
      // them over the Fibonacci spiral.
      this.graph.relayout();
    },

    setNodeLoading(nodeIndex, loading) {
      this.graph.setNodeLoading(nodeIndex, loading);
    },
  },
});
</script>

<template>
  <div class="gl-relative gl-h-full gl-w-full" data-testid="graph-canvas">
    <div
      v-show="graph"
      ref="canvas"
      role="application"
      tabindex="0"
      :aria-label="s__('Orbit|GitLab Orbit map')"
      :aria-describedby="helpId"
      class="gl-h-full gl-w-full gl-cursor-grab focus-visible:gl-focus-inset"
      data-testid="graph-canvas-3d"
      @keydown="onKeydown"
    ></div>
    <p :id="helpId" class="gl-sr-only">
      {{
        s__(
          'Orbit|Use the arrow keys to select a node, Enter to load its connections, and Escape to clear the selection.',
        )
      }}
    </p>
    <p class="gl-sr-only" aria-live="polite" data-testid="graph-canvas-selection">
      {{ selectedNodeText }}
    </p>
  </div>
</template>
