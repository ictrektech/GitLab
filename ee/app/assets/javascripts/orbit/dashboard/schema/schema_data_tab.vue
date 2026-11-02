<script>
import { defineComponent } from 'vue';
import { InternalEvents } from '~/tracking';
import {
  entityPairs,
  entityQuery,
  entityRelationships,
  itemCount,
  relationshipQuery,
  restingPairKeys,
  schemaDomains,
} from './schema_graph';
import { entityLayout } from './schema_layout';
import SchemaEntityCard from './schema_entity_card.vue';
import SchemaGraphCanvas from './schema_graph_canvas.vue';
import SchemaGraphViewport from './schema_graph_viewport.vue';
import SchemaRelationshipCard from './schema_relationship_card.vue';

export default defineComponent({
  name: 'SchemaDataTab',
  components: {
    SchemaEntityCard,
    SchemaGraphCanvas,
    SchemaGraphViewport,
    SchemaRelationshipCard,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    schema: {
      type: Object,
      required: true,
    },
    graphStats: {
      type: Object,
      required: false,
      default: null,
    },
    initialEntity: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['show-instances', 'open-query'],
  data() {
    return {
      selectedEntity: null,
      selectedRelationship: null,
      relationshipOrigin: null,
      hoveredEntity: null,
      highlightedDomain: null,
    };
  },
  computed: {
    domains() {
      return schemaDomains(this.schema);
    },
    entities() {
      return this.domains.flatMap((domain) => domain.entities);
    },
    layout() {
      return entityLayout(this.domains, this.pairs);
    },
    entitiesByName() {
      return Object.fromEntries(this.entities.map((entity) => [entity.name, entity]));
    },
    nodesByName() {
      return Object.fromEntries(this.schema.nodes.map((node) => [node.name, node]));
    },
    pairs() {
      return entityPairs(this.schema);
    },
    restingPairKeys() {
      const domainByEntity = Object.fromEntries(
        this.schema.nodes.map((node) => [node.name, node.domain]),
      );
      return restingPairKeys(this.pairs, domainByEntity);
    },
    focusedEntity() {
      if (this.selectedEntity || this.selectedRelationship) return this.selectedEntity;

      return this.hoveredEntity;
    },
    legend() {
      return this.domains.map((domain) => {
        const isHighlighted = domain.key === this.highlightedDomain;
        return {
          ...domain,
          isHighlighted,
          labelClass: isHighlighted ? 'gl-font-bold gl-text-strong' : 'gl-text-subtle',
        };
      });
    },
    selectedNode() {
      return this.nodesByName[this.selectedEntity] ?? null;
    },
    selectedDomainLabel() {
      return this.domains.find((domain) => domain.key === this.selectedNode.domain).label;
    },
    relationships() {
      return entityRelationships(this.schema, this.selectedEntity);
    },
    selectedItemCount() {
      return itemCount(this.graphStats, this.selectedEntity);
    },
    relationshipDetails() {
      const edge = this.schema.edges.find(({ name }) => name === this.selectedRelationship);
      if (!edge) return null;

      return {
        name: edge.name,
        description: edge.description,
        variants: (edge.variants || [])
          .map((variant) => ({ source: variant.source_type, target: variant.target_type }))
          .filter(({ source, target }) => this.nodesByName[source] && this.nodesByName[target]),
      };
    },
    hasDetails() {
      return Boolean(this.selectedNode || this.relationshipDetails);
    },
    selectedEntityQuery() {
      return entityQuery(this.selectedNode);
    },
    selectedRelationshipQuery() {
      const [variant] = this.relationshipDetails.variants;
      return relationshipQuery({ name: this.selectedRelationship, ...variant }, this.nodesByName);
    },
  },
  watch: {
    initialEntity: 'selectInitialEntity',
  },
  mounted() {
    this.selectInitialEntity();
  },
  methods: {
    selectEntity(name, label) {
      if (name === this.selectedEntity) return;

      this.trackEvent('click_orbit_schema_item', { label });
      this.selectedRelationship = null;
      this.selectedEntity = name;
    },
    selectRelationship(name) {
      this.relationshipOrigin = this.focusedEntity;
      this.selectedEntity = null;
      this.selectedRelationship = name;
    },
    async openFromCard(open) {
      open();
      await this.$nextTick();
      this.$refs.card.focusName();
    },
    async clearSelection() {
      const returnTo = this.selectedEntity ?? this.relationshipOrigin;
      this.selectedEntity = null;
      this.selectedRelationship = null;
      this.relationshipOrigin = null;

      await this.$nextTick();
      if (returnTo) {
        this.$refs.canvas.focusNode(returnTo);
      } else {
        this.$refs.graph.focus();
      }
    },
    toggleDomain(key) {
      this.highlightedDomain = key === this.highlightedDomain ? null : key;
    },
    selectInitialEntity() {
      const wanted = this.initialEntity?.toLowerCase();
      const node = wanted && this.schema.nodes.find((n) => n.name.toLowerCase() === wanted);
      if (node) this.selectedEntity = node.name;
    },
  },
});
</script>

<template>
  <div class="gl-flex gl-min-h-0 gl-flex-1 gl-flex-col gl-gap-4" data-testid="schema-data-tab">
    <div>
      <h2 class="gl-heading-4 gl-mb-1">{{ s__('Orbit|How your data connects') }}</h2>
      <p class="gl-mb-0 gl-text-subtle">
        {{
          s__(
            'Orbit|Select an entity to see its properties, its relationships, and a query to start from.',
          )
        }}
      </p>
    </div>

    <ul
      class="gl-m-0 gl-flex gl-list-none gl-flex-wrap gl-gap-x-5 gl-gap-y-2 gl-p-0"
      :aria-label="s__('Orbit|Areas')"
    >
      <li v-for="domain in legend" :key="domain.key">
        <button
          type="button"
          class="gl-flex gl-items-center gl-gap-2 gl-rounded-md gl-border-0 gl-bg-transparent gl-p-0 gl-text-sm hover:gl-underline focus-visible:gl-focus"
          :class="domain.labelClass"
          :aria-pressed="String(domain.isHighlighted)"
          data-testid="schema-area"
          @click="toggleDomain(domain.key)"
        >
          <span
            class="gl-inline-block gl-h-3 gl-w-3 gl-shrink-0 gl-rounded-full"
            :style="{ backgroundColor: domain.color }"
            aria-hidden="true"
          ></span>
          {{ domain.label }}
          <span class="gl-tabular-nums">{{ domain.entities.length }}</span>
        </button>
      </li>
    </ul>

    <div
      ref="graph"
      tabindex="-1"
      class="gl-relative gl-flex gl-min-h-48 gl-flex-1 gl-flex-col gl-overflow-hidden gl-rounded-xl gl-bg-subtle focus-visible:gl-focus"
      data-testid="schema-graph-panel"
    >
      <schema-graph-viewport :width="layout.width" :height="layout.height">
        <template #default="{ scale }">
          <schema-graph-canvas
            ref="canvas"
            :entities="entities"
            :positions="layout.positions"
            :scale="scale"
            :pairs="pairs"
            :resting-pair-keys="restingPairKeys"
            :focused-entity="focusedEntity"
            :selected-entity="selectedEntity"
            :selected-relationship="selectedRelationship"
            :highlighted-domain="highlightedDomain"
            @select-entity="selectEntity($event, 'graph')"
            @select-relationship="selectRelationship"
            @hover-entity="hoveredEntity = $event"
          />
        </template>
      </schema-graph-viewport>

      <p
        v-if="!hasDetails"
        class="gl-pointer-events-none gl-absolute gl-bottom-4 gl-right-4 gl-m-0 gl-text-sm gl-text-subtle"
      >
        {{ s__('Orbit|Hover over or select an entity to see its relationships.') }}
      </p>

      <div v-else class="gl-absolute gl-bottom-4 gl-right-4 gl-top-4 gl-flex gl-items-start">
        <schema-entity-card
          v-if="selectedNode"
          ref="card"
          :entity="entitiesByName[selectedEntity]"
          :node="selectedNode"
          :domain-label="selectedDomainLabel"
          :relationships="relationships"
          :entities-by-name="entitiesByName"
          :item-count="selectedItemCount"
          :query="selectedEntityQuery"
          @close="clearSelection"
          @select-entity="openFromCard(() => selectEntity($event, 'details'))"
          @select-relationship="openFromCard(() => selectRelationship($event))"
          @show-instances="$emit('show-instances', $event)"
          @open-query="$emit('open-query', $event)"
        />
        <schema-relationship-card
          v-else
          ref="card"
          :relationship="relationshipDetails"
          :entities-by-name="entitiesByName"
          :query="selectedRelationshipQuery"
          @close="clearSelection"
          @select-entity="openFromCard(() => selectEntity($event, 'relationship_card'))"
          @open-query="$emit('open-query', $event)"
        />
      </div>
    </div>
  </div>
</template>
