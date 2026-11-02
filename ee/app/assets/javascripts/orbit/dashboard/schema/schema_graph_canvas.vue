<script>
import { defineComponent } from 'vue';
import { n__, sprintf } from '~/locale';
import {
  EDGE_GAP_PX,
  EDGE_STAGGER_MS,
  MAX_EDGE_DELAY_MS,
  NODE_RADIUS_PX,
  SCOPE_ENTITY,
  SCOPE_NODE_RADIUS_PX,
  SCOPE_RELATIONSHIP,
} from './constants';
import { edgeArrowheads, edgeSegment, placeEdgeLabels } from './schema_graph';
import SchemaEntityIcon from './schema_entity_icon.vue';

const ARROW_SIZE_PX = 7;
const LABEL_CHAR_WIDTH_PX = 6.6;
const LABEL_PADDING_PX = 8;
const LABEL_HEIGHT_PX = 16;
const NAME_CHAR_WIDTH_PX = 6.8;
const NAME_HEIGHT_PX = 20;
const SCOPE_PILL_OFFSET_PX = 56;

const nodeRadius = (name) => (name === SCOPE_ENTITY ? SCOPE_NODE_RADIUS_PX : NODE_RADIUS_PX);

export default defineComponent({
  name: 'SchemaGraphCanvas',
  components: { SchemaEntityIcon },
  props: {
    entities: {
      type: Array,
      required: true,
    },
    positions: {
      type: Object,
      required: true,
    },
    scale: {
      type: Number,
      required: true,
    },
    pairs: {
      type: Array,
      required: true,
    },
    restingPairKeys: {
      type: Set,
      required: true,
    },
    focusedEntity: {
      type: String,
      required: false,
      default: null,
    },
    selectedEntity: {
      type: String,
      required: false,
      default: null,
    },
    selectedRelationship: {
      type: String,
      required: false,
      default: null,
    },
    highlightedDomain: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['select-entity', 'select-relationship', 'hover-entity'],
  SCOPE_RELATIONSHIP,
  data() {
    return {
      nodeWithFocus: null,
    };
  },
  computed: {
    highlightedPairs() {
      if (this.selectedRelationship) {
        return this.pairs.filter((pair) =>
          pair.relationships.some(({ name }) => name === this.selectedRelationship),
        );
      }
      if (this.focusedEntity) {
        return this.pairs.filter(({ first, second }) =>
          [first, second].includes(this.focusedEntity),
        );
      }
      return [];
    },
    edgeDelays() {
      const ordered = this.focusedEntity
        ? [...this.highlightedPairs].sort(
            (a, b) => this.distanceFromFocus(a) - this.distanceFromFocus(b),
          )
        : this.highlightedPairs;

      return new Map(
        ordered.map((pair, index) => [
          pair.key,
          Math.min(index * EDGE_STAGGER_MS, MAX_EDGE_DELAY_MS),
        ]),
      );
    },
    linePairs() {
      return this.pairs.filter(({ first, second }) => first !== second);
    },
    connectedEntities() {
      return new Set(this.highlightedPairs.flatMap(({ first, second }) => [first, second]));
    },
    isFocused() {
      return Boolean(this.focusedEntity || this.selectedRelationship);
    },
    edges() {
      return this.linePairs.map((pair) => {
        const isHighlighted = this.edgeDelays.has(pair.key);
        const startsAtSecond = pair.second === this.focusedEntity;
        const [start, end] = startsAtSecond ? [pair.second, pair.first] : [pair.first, pair.second];
        const segment = edgeSegment(this.pixelPosition(start), this.pixelPosition(end), {
          fromGap: nodeRadius(start) + EDGE_GAP_PX,
          toGap: nodeRadius(end) + EDGE_GAP_PX,
        });
        const shown = this.shownRelationships(pair, isHighlighted);

        return {
          key: pair.key,
          segment,
          isHighlighted,
          isVisible: isHighlighted || (!this.isFocused && this.restingPairKeys.has(pair.key)),
          names: [...new Set(shown.map(({ name }) => name))],
          arrows: edgeArrowheads(segment, shown, { start, end, size: ARROW_SIZE_PX }),
          style: {
            '--edge-length': segment.length,
            '--edge-delay': `${this.edgeDelays.get(pair.key) ?? 0}ms`,
          },
        };
      });
    },
    edgeLabels() {
      if (this.selectedRelationship) return [];

      const candidates = this.edges
        .filter((edge) => edge.isHighlighted)
        .map((edge) => ({ ...edge, names: this.labelNames(edge.names) }))
        .filter(({ names }) => names.length)
        .sort((a, b) => this.edgeDelays.get(a.key) - this.edgeDelays.get(b.key))
        .map(({ key, segment, names, style }) => {
          const text = this.edgeLabelText(names);
          return {
            key,
            names,
            text,
            style,
            segment,
            width: text.length * LABEL_CHAR_WIDTH_PX + LABEL_PADDING_PX,
            height: LABEL_HEIGHT_PX,
          };
        });

      return placeEdgeLabels(candidates, this.nodeBoxes).map(
        ({ key, names, text, style, box }) => ({
          key,
          names,
          text,
          style: { ...style, left: `${box.x}px`, top: `${box.y}px` },
        }),
      );
    },
    nodeBoxes() {
      return this.entities
        .filter((entity) => !this.isEntityDimmed(entity))
        .map(({ name }) => {
          const { x, y } = this.pixelPosition(name);
          const radius = nodeRadius(name);
          const halfWidth = Math.max(radius, (name.length * NAME_CHAR_WIDTH_PX) / 2);
          return {
            left: x - halfWidth,
            right: x + halfWidth,
            top: y - radius,
            bottom: y + radius + NAME_HEIGHT_PX,
          };
        });
    },
    scopedEntityCount() {
      return this.pairs.filter(
        (pair) =>
          [pair.first, pair.second].includes(SCOPE_ENTITY) &&
          pair.relationships.some(({ name }) => name === SCOPE_RELATIONSHIP),
      ).length;
    },
    scopePill() {
      if (this.focusedEntity !== SCOPE_ENTITY || this.selectedRelationship) return null;

      const center = this.pixelPosition(SCOPE_ENTITY);
      return {
        text: sprintf(
          n__(
            'Orbit|%{relationship} · %{count} entity type',
            'Orbit|%{relationship} · %{count} entity types',
            this.scopedEntityCount,
          ),
          { relationship: SCOPE_RELATIONSHIP, count: this.scopedEntityCount },
        ),
        style: { left: `${center.x}px`, top: `${center.y + SCOPE_PILL_OFFSET_PX}px` },
      };
    },
    nodes() {
      return this.entities.map((entity) => {
        const center = this.pixelPosition(entity.name);
        const radius = nodeRadius(entity.name);
        const isSelected = entity.name === this.selectedEntity;

        return {
          ...entity,
          isSelected,
          nameClass: isSelected ? 'gl-font-bold gl-text-strong' : 'gl-text-default',
          isFocused: entity.name === this.focusedEntity,
          isDimmed: this.isEntityDimmed(entity),
          iconSize: entity.name === SCOPE_ENTITY ? 'lg' : 'md',
          style: { left: `${center.x}px`, top: `${center.y - radius}px` },
        };
      });
    },
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- called via $refs by schema_data_tab.vue
    focusNode(name) {
      this.$refs.nodeButtons.find((button) => button.dataset.entity === name).focus();
    },
    setNodeWithFocus(name) {
      this.nodeWithFocus = name;
      this.$emit('hover-entity', name);
    },
    pixelPosition(name) {
      const { x, y } = this.positions[name];
      return { x: x * this.scale, y: y * this.scale };
    },
    distanceFromFocus({ first, second }) {
      const focus = this.pixelPosition(this.focusedEntity);
      const other = this.pixelPosition(first === this.focusedEntity ? second : first);
      return Math.hypot(other.x - focus.x, other.y - focus.y);
    },
    shownRelationships(pair, isHighlighted) {
      if (!isHighlighted || !this.selectedRelationship) return pair.relationships;

      return pair.relationships.filter(({ name }) => name === this.selectedRelationship);
    },
    isEntityDimmed(entity) {
      if (this.isFocused) {
        return entity.name !== this.focusedEntity && !this.connectedEntities.has(entity.name);
      }
      return Boolean(this.highlightedDomain) && entity.domain !== this.highlightedDomain;
    },
    labelNames(names) {
      if (this.focusedEntity !== SCOPE_ENTITY) return names;

      return names.filter((name) => name !== SCOPE_RELATIONSHIP);
    },
    edgeLabelText([first, ...rest]) {
      if (!rest.length) return first;

      return sprintf(
        n__('Orbit|%{name} +%{count} more', 'Orbit|%{name} +%{count} more', rest.length),
        { name: first, count: rest.length },
      );
    },
  },
});
</script>

<template>
  <div class="gl-absolute gl-inset-0" data-testid="schema-graph-canvas">
    <svg
      class="gl-absolute gl-left-0 gl-top-0 gl-h-full gl-w-full gl-overflow-visible"
      aria-hidden="true"
    >
      <g
        v-for="edge in edges"
        :key="edge.key"
        class="orbit-schema-edge"
        :class="{
          'orbit-schema-edge-highlighted': edge.isHighlighted,
          'orbit-schema-edge-hidden': !edge.isVisible,
        }"
        :style="edge.style"
        :data-pair="edge.key"
        data-testid="schema-edge"
      >
        <line
          :x1="edge.segment.x1"
          :y1="edge.segment.y1"
          :x2="edge.segment.x2"
          :y2="edge.segment.y2"
        />
        <template v-if="edge.isHighlighted">
          <polygon
            v-for="points in edge.arrows"
            :key="points"
            class="orbit-schema-edge-arrow"
            :points="points"
          />
        </template>
      </g>
    </svg>

    <button
      v-for="node in nodes"
      ref="nodeButtons"
      :key="node.name"
      :data-entity="node.name"
      type="button"
      class="orbit-schema-node gl-absolute gl-flex -gl-translate-x-1/2 gl-flex-col gl-items-center gl-gap-1 gl-rounded-md gl-border-0 gl-bg-transparent gl-p-0 gl-transition-opacity gl-duration-slow focus-visible:gl-focus"
      :class="{
        'gl-opacity-3': node.isDimmed,
        'orbit-schema-node-selected': node.isSelected,
        'orbit-schema-node-focused': node.isFocused,
      }"
      :style="node.style"
      :aria-pressed="String(node.isSelected)"
      data-testid="schema-node"
      @click="$emit('select-entity', node.name)"
      @mouseenter="$emit('hover-entity', node.name)"
      @mouseleave="$emit('hover-entity', nodeWithFocus)"
      @focus="setNodeWithFocus(node.name)"
      @blur="setNodeWithFocus(null)"
    >
      <schema-entity-icon
        class="orbit-schema-node-icon"
        :icon="node.icon"
        :color="node.color"
        :size="node.iconSize"
      />
      <span
        class="gl-whitespace-nowrap gl-rounded-md gl-bg-subtle gl-px-1 gl-text-xs"
        :class="node.nameClass"
      >
        {{ node.name }}
      </span>
    </button>

    <button
      v-for="label in edgeLabels"
      :key="`label-${label.key}`"
      type="button"
      class="orbit-schema-edge-label gl-absolute -gl-translate-x-1/2 -gl-translate-y-1/2 gl-whitespace-nowrap gl-rounded-md gl-border-0 gl-bg-subtle gl-px-1 gl-font-monospace gl-text-xs gl-text-subtle hover:gl-text-link focus-visible:gl-focus"
      :style="label.style"
      :title="label.names.join(', ')"
      data-testid="schema-edge-label"
      @click="$emit('select-relationship', label.names[0])"
    >
      {{ label.text }}
    </button>

    <button
      v-if="scopePill"
      type="button"
      class="orbit-schema-edge-label gl-border gl-absolute -gl-translate-x-1/2 gl-whitespace-nowrap gl-rounded-full gl-border-default gl-bg-default gl-px-2 gl-font-monospace gl-text-xs gl-text-subtle hover:gl-text-link focus-visible:gl-focus"
      :style="scopePill.style"
      data-testid="schema-scope-pill"
      @click="$emit('select-relationship', $options.SCOPE_RELATIONSHIP)"
    >
      {{ scopePill.text }}
    </button>
  </div>
</template>
