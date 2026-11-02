<script>
import { defineComponent } from 'vue';
import { GlAccordion, GlAccordionItem, GlButton, GlIcon } from '@gitlab/ui';
import { formatNumber, n__, s__, sprintf } from '~/locale';
import { SCOPE_RELATIONSHIP } from './constants';
import { RELATIONSHIP_DIRECTION, connectedEntities } from './schema_graph';
import SchemaEntityIcon from './schema_entity_icon.vue';
import SchemaQuerySnippet from './schema_query_snippet.vue';

function propertyValues({ enum_values: enumValues, nullable }) {
  if (enumValues?.length) return enumValues.join(', ');
  if (nullable) return s__('Orbit|Can be empty');
  return '';
}

export default defineComponent({
  name: 'SchemaEntityCard',
  components: {
    GlAccordion,
    GlAccordionItem,
    GlButton,
    GlIcon,
    SchemaEntityIcon,
    SchemaQuerySnippet,
  },
  props: {
    entity: {
      type: Object,
      required: true,
    },
    node: {
      type: Object,
      required: true,
    },
    domainLabel: {
      type: String,
      required: true,
    },
    relationships: {
      type: Object,
      required: true,
    },
    entitiesByName: {
      type: Object,
      required: true,
    },
    itemCount: {
      type: Number,
      required: false,
      default: null,
    },
    query: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['close', 'select-entity', 'select-relationship', 'show-instances', 'open-query'],
  SCOPE_RELATIONSHIP,
  data() {
    return {
      showsScopedEntities: false,
    };
  },
  computed: {
    relationshipCount() {
      return this.relationships.outgoing.length + this.relationships.incoming.length;
    },
    subtitle() {
      return sprintf(
        n__(
          'Orbit|%{area} · %{count} relationship',
          'Orbit|%{area} · %{count} relationships',
          this.relationshipCount,
        ),
        { area: this.domainLabel, count: this.relationshipCount },
      );
    },
    connections() {
      return connectedEntities(this.relationships, this.entity.name);
    },
    connectionRows() {
      return this.connections.rows.map((row) => ({
        ...row,
        key: `${row.direction}-${row.entity}`,
        summary: this.entitiesByName[row.entity],
        icon: row.direction === RELATIONSHIP_DIRECTION.OUTGOING ? 'arrow-right' : 'arrow-left',
        directionLabel: this.directionLabel(row),
      }));
    },
    scopedEntities() {
      return this.connections.scopedEntities.map((name) => this.entitiesByName[name]);
    },
    hasScopedEntities() {
      return this.scopedEntities.length > 0;
    },
    scopedToggleIcon() {
      return this.showsScopedEntities ? 'chevron-down' : 'chevron-right';
    },
    connectedTitle() {
      const count = this.connectionRows.length + (this.hasScopedEntities ? 1 : 0);
      return sprintf(s__('Orbit|Connected entities (%{count})'), { count });
    },
    scopedText() {
      return sprintf(
        n__(
          'Orbit|%{count} entity type belongs to it',
          'Orbit|%{count} entity types belong to it',
          this.scopedEntities.length,
        ),
        { count: this.scopedEntities.length },
      );
    },
    properties() {
      return (this.node.properties || []).map((property) => ({
        name: property.name,
        type: property.data_type,
        values: propertyValues(property),
      }));
    },
    propertiesTitle() {
      return sprintf(s__('Orbit|Properties (%{count})'), { count: this.properties.length });
    },
    hasItemCount() {
      return this.itemCount !== null;
    },
    itemCountText() {
      return sprintf(s__('Orbit|%{count} in your graph'), {
        count: formatNumber(this.itemCount),
      });
    },
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- called via $refs by schema_data_tab.vue
    focusName() {
      this.$refs.name.focus();
    },
    directionLabel({ direction, entity }) {
      const [source, target] =
        direction === RELATIONSHIP_DIRECTION.OUTGOING
          ? [this.entity.name, entity]
          : [entity, this.entity.name];

      return sprintf(s__('Orbit|%{source} points to %{target}'), { source, target });
    },
  },
});
</script>

<template>
  <aside
    :aria-label="s__('Orbit|Entity details')"
    class="gl-border gl-flex gl-max-h-full gl-w-37 gl-max-w-full gl-flex-col gl-overflow-y-auto gl-rounded-lg gl-border-default gl-bg-default gl-shadow-sm"
    data-testid="schema-entity-card"
  >
    <div class="gl-flex gl-items-start gl-gap-3 gl-px-4 gl-pt-4">
      <schema-entity-icon :icon="entity.icon" :color="entity.color" size="md" />
      <div class="gl-min-w-0 gl-grow">
        <h3
          ref="name"
          tabindex="-1"
          class="gl-heading-5 gl-m-0 gl-break-words"
          data-testid="schema-entity-name"
        >
          {{ entity.name }}
        </h3>
        <p class="gl-m-0 gl-text-sm gl-text-subtle">{{ subtitle }}</p>
      </div>
      <gl-button
        category="tertiary"
        icon="close"
        size="small"
        :aria-label="s__('Orbit|Close details')"
        data-testid="schema-details-close"
        @click="$emit('close')"
      />
    </div>

    <div class="gl-flex gl-flex-col gl-gap-3 gl-p-4">
      <p v-if="node.description" class="gl-m-0 gl-text-subtle">{{ node.description }}</p>
      <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
        <span v-if="hasItemCount" class="gl-text-sm gl-text-subtle">{{ itemCountText }}</span>
        <gl-button
          v-if="itemCount !== 0"
          size="small"
          data-testid="schema-explore"
          @click="$emit('show-instances', { entityType: entity.name })"
        >
          {{ s__('Orbit|Show on map') }}
        </gl-button>
      </div>
    </div>

    <gl-accordion :header-level="4" class="gl-border-t gl-border-default gl-px-4 gl-py-3">
      <gl-accordion-item :title="propertiesTitle">
        <ul class="gl-m-0 gl-list-none gl-p-0">
          <li
            v-for="property in properties"
            :key="property.name"
            class="gl-border-b gl-flex gl-flex-col gl-gap-1 gl-border-subtle gl-py-2"
            data-testid="schema-property"
          >
            <div class="gl-flex gl-items-baseline gl-justify-between gl-gap-3">
              <code class="gl-min-w-0 gl-break-words gl-bg-transparent gl-p-0 gl-text-sm">{{
                property.name
              }}</code>
              <span class="gl-shrink-0 gl-text-sm gl-text-subtle">{{ property.type }}</span>
            </div>
            <span v-if="property.values" class="gl-break-words gl-text-sm gl-text-subtle">
              {{ property.values }}
            </span>
          </li>
        </ul>
      </gl-accordion-item>

      <gl-accordion-item :title="connectedTitle" visible>
        <ul class="gl-m-0 gl-list-none gl-p-0">
          <li v-if="hasScopedEntities" class="gl-border-b gl-border-subtle gl-py-2">
            <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-3 gl-gap-y-1">
              <gl-button
                variant="link"
                :icon="scopedToggleIcon"
                :aria-expanded="String(showsScopedEntities)"
                data-testid="schema-scoped-entities-toggle"
                @click="showsScopedEntities = !showsScopedEntities"
              >
                {{ scopedText }}
              </gl-button>
              <gl-button
                variant="link"
                data-testid="schema-scope-relationship"
                @click="$emit('select-relationship', $options.SCOPE_RELATIONSHIP)"
              >
                <code class="gl-bg-transparent gl-p-0 gl-text-xs gl-text-subtle">{{
                  $options.SCOPE_RELATIONSHIP
                }}</code>
              </gl-button>
            </div>
            <ul
              v-if="showsScopedEntities"
              class="gl-m-0 gl-mt-2 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0 gl-pl-5"
              data-testid="schema-scoped-entities"
            >
              <li v-for="scoped in scopedEntities" :key="scoped.name">
                <gl-button variant="link" @click="$emit('select-entity', scoped.name)">
                  <span class="gl-flex gl-items-center gl-gap-2">
                    <schema-entity-icon :icon="scoped.icon" :color="scoped.color" />
                    <span>{{ scoped.name }}</span>
                  </span>
                </gl-button>
              </li>
            </ul>
          </li>
          <li
            v-for="row in connectionRows"
            :key="row.key"
            class="gl-border-b gl-flex gl-items-start gl-gap-2 gl-border-subtle gl-py-2"
            data-testid="schema-connected-entity"
          >
            <gl-icon
              :name="row.icon"
              :size="12"
              variant="subtle"
              :aria-label="row.directionLabel"
              class="gl-mt-2 gl-shrink-0"
            />
            <div class="gl-flex gl-min-w-0 gl-flex-col gl-items-start gl-gap-1">
              <gl-button variant="link" @click="$emit('select-entity', row.entity)">
                <span class="gl-flex gl-items-center gl-gap-2">
                  <schema-entity-icon :icon="row.summary.icon" :color="row.summary.color" />
                  <span>{{ row.entity }}</span>
                </span>
              </gl-button>
              <div class="gl-flex gl-flex-wrap gl-gap-x-3">
                <gl-button
                  v-for="edge in row.edges"
                  :key="edge.name"
                  variant="link"
                  :title="edge.description"
                  @click="$emit('select-relationship', edge.name)"
                >
                  <code class="gl-bg-transparent gl-p-0 gl-text-xs gl-text-subtle">{{
                    edge.name
                  }}</code>
                </gl-button>
              </div>
            </div>
          </li>
        </ul>
      </gl-accordion-item>
    </gl-accordion>

    <schema-query-snippet
      v-if="query"
      class="gl-border-t gl-border-default gl-p-4"
      :query="query"
      @open-query="$emit('open-query', $event)"
    />
  </aside>
</template>
