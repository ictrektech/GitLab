<script>
import { defineComponent } from 'vue';
import { GlButton, GlButtonGroup, GlResizeObserverDirective } from '@gitlab/ui';
import { MAX_GRAPH_SCALE, MIN_GRAPH_SCALE, ZOOM_STEP } from './constants';

const GRAPH_PADDING_PX = 24;

export default defineComponent({
  name: 'SchemaGraphViewport',
  components: { GlButton, GlButtonGroup },
  directives: { GlResizeObserver: GlResizeObserverDirective },
  props: {
    width: {
      type: Number,
      required: true,
    },
    height: {
      type: Number,
      required: true,
    },
  },
  data() {
    return {
      viewport: { width: 0, height: 0 },
      zoom: 1,
      pan: { x: 0, y: 0 },
      panStart: null,
    };
  },
  computed: {
    fitScale() {
      const width = this.viewport.width - GRAPH_PADDING_PX * 2;
      const height = this.viewport.height - GRAPH_PADDING_PX * 2;
      return Math.max(Math.min(width / this.width, height / this.height), 0);
    },
    maxZoom() {
      return MAX_GRAPH_SCALE / this.fitScale;
    },
    currentZoom() {
      return Math.min(this.zoom, this.maxZoom);
    },
    canZoomIn() {
      return this.zoom < this.maxZoom;
    },
    canZoomOut() {
      return this.currentZoom > ZOOM_STEP;
    },
    requestedScale() {
      return this.fitScale * this.currentZoom;
    },
    scale() {
      return Math.max(this.requestedScale, MIN_GRAPH_SCALE);
    },
    shrink() {
      return this.requestedScale / this.scale;
    },
    sizerStyle() {
      return {
        width: `${this.width * this.requestedScale}px`,
        height: `${this.height * this.requestedScale}px`,
        transform: `translate(${this.pan.x}px, ${this.pan.y}px)`,
      };
    },
    canvasStyle() {
      return {
        width: `${this.width * this.scale}px`,
        height: `${this.height * this.scale}px`,
        transform: `scale(${this.shrink})`,
        transformOrigin: '0 0',
      };
    },
    viewportStyle() {
      return { touchAction: 'none' };
    },
    isPanning() {
      return Boolean(this.panStart);
    },
    viewportCursorClass() {
      return this.isPanning ? 'gl-cursor-grabbing gl-select-none' : 'gl-cursor-grab';
    },
  },
  methods: {
    onResize({ contentRect: { width, height } }) {
      this.viewport = { width, height };
    },
    zoomIn() {
      this.zoom += ZOOM_STEP;
    },
    zoomOut() {
      this.zoom = Math.max(this.currentZoom - ZOOM_STEP, ZOOM_STEP);
    },
    resetView() {
      this.zoom = 1;
      this.pan = { x: 0, y: 0 };
    },
    startPan(event) {
      if (event.button !== 0 || event.target.closest('button')) return;

      this.panStart = { x: event.clientX - this.pan.x, y: event.clientY - this.pan.y };
      event.currentTarget.setPointerCapture(event.pointerId);
    },
    movePan({ clientX, clientY }) {
      if (!this.isPanning) return;

      this.pan = { x: clientX - this.panStart.x, y: clientY - this.panStart.y };
    },
    endPan() {
      this.panStart = null;
    },
  },
});
</script>

<template>
  <section
    :aria-label="s__('Orbit|Schema graph')"
    class="gl-relative gl-flex gl-min-h-0 gl-flex-1 gl-flex-col"
  >
    <div
      v-gl-resize-observer="onResize"
      class="gl-flex gl-min-h-0 gl-flex-1 gl-items-center gl-justify-center gl-overflow-hidden gl-p-5"
      :class="viewportCursorClass"
      :style="viewportStyle"
      data-testid="schema-graph-viewport"
      @pointerdown="startPan"
      @pointermove="movePan"
      @pointerup="endPan"
      @pointercancel="endPan"
    >
      <div class="gl-relative gl-shrink-0" :style="sizerStyle" data-testid="schema-graph-sizer">
        <div class="gl-absolute gl-left-0 gl-top-0" :style="canvasStyle">
          <slot :scale="scale"></slot>
        </div>
      </div>
    </div>

    <div class="gl-absolute gl-bottom-4 gl-left-4">
      <gl-button-group>
        <gl-button
          icon="dash"
          size="small"
          :aria-label="s__('Orbit|Zoom out')"
          :disabled="!canZoomOut"
          data-testid="schema-zoom-out"
          @click="zoomOut"
        />
        <gl-button
          icon="retry"
          size="small"
          :aria-label="s__('Orbit|Reset view')"
          data-testid="schema-zoom-reset"
          @click="resetView"
        />
        <gl-button
          icon="plus"
          size="small"
          :aria-label="s__('Orbit|Zoom in')"
          :disabled="!canZoomIn"
          data-testid="schema-zoom-in"
          @click="zoomIn"
        />
      </gl-button-group>
    </div>
  </section>
</template>
