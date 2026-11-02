<script>
import { defineComponent } from 'vue';
import { uniqueId } from 'lodash-es';
import { GlButton, GlDrawer, GlSearchBoxByType, GlTab, GlTabs } from '@gitlab/ui';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import { s__ } from '~/locale';
import {
  entityRelationships,
  filterDomains,
  groupByEntity,
  schemaDomains,
} from '../schema/schema_graph';
import SchemaEntityIcon from '../schema/schema_entity_icon.vue';
import QueryGqlSyntax from './query_gql_syntax.vue';

export default defineComponent({
  name: 'QueryReferenceDrawer',
  components: {
    GlButton,
    GlDrawer,
    GlSearchBoxByType,
    GlTab,
    GlTabs,
    QueryGqlSyntax,
    SchemaEntityIcon,
  },
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    schema: {
      type: Object,
      required: true,
    },
  },
  emits: ['close', 'insert', 'insert-property'],
  data() {
    return {
      search: '',
      selectedEntityName: null,
    };
  },
  computed: {
    headerHeight() {
      return this.open ? getContentWrapperHeight() : '0';
    },
    domains() {
      return schemaDomains(this.schema);
    },
    filteredDomains() {
      return filterDomains(this.domains, this.search);
    },
    selectedNode() {
      return this.schema.nodes.find(({ name }) => name === this.selectedEntityName) ?? null;
    },
    selectedProperties() {
      return this.selectedNode.properties ?? [];
    },
    selectedEntitySummary() {
      return this.domains
        .flatMap((domain) => domain.entities)
        .find(({ name }) => name === this.selectedEntityName);
    },
    relationshipGroups() {
      const { outgoing, incoming } = entityRelationships(this.schema, this.selectedEntityName);

      return [
        { edges: outgoing, prefix: 'outgoing', arrow: '→', directionLabel: s__('Orbit|To') },
        { edges: incoming, prefix: 'incoming', arrow: '←', directionLabel: s__('Orbit|From') },
      ].flatMap(({ edges, prefix, ...direction }) =>
        groupByEntity(edges).map((group) => ({
          ...group,
          ...direction,
          key: `${prefix}-${group.entity}`,
        })),
      );
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.trigger = document.activeElement;
      } else {
        this.trigger?.focus();
        this.trigger = null;
      }
    },
  },
  created() {
    this.titleId = uniqueId('orbit-query-reference-title-');
  },
  methods: {
    focusDrawer() {
      this.$refs.drawer.$el.focus();
    },
    selectEntity(name) {
      this.selectedEntityName = name;
      this.$nextTick(() => this.$refs.backButton.$el.focus());
    },
  },
  DRAWER_Z_INDEX,
});
</script>

<template>
  <gl-drawer
    ref="drawer"
    role="dialog"
    :aria-labelledby="titleId"
    :open="open"
    :header-height="headerHeight"
    :z-index="$options.DRAWER_Z_INDEX"
    header-sticky
    tabindex="-1"
    @opened="focusDrawer"
    @close="$emit('close')"
  >
    <template #title>
      <h2 :id="titleId" class="gl-heading-4 gl-mb-0">{{ s__('Orbit|Query reference') }}</h2>
    </template>

    <gl-tabs>
      <gl-tab :title="s__('Orbit|Schema')">
        <div class="gl-flex gl-flex-col gl-gap-4 gl-pt-3">
          <p v-if="!schema.nodes.length" class="gl-mb-0 gl-text-subtle">
            {{ s__('Orbit|The schema is not available. Try again later.') }}
          </p>

          <template v-else-if="selectedNode">
            <p class="gl-mb-0 gl-text-sm gl-text-subtle">
              {{ s__('Orbit|Select a name to add it at the cursor.') }}
            </p>
            <gl-button
              ref="backButton"
              category="tertiary"
              icon="arrow-left"
              class="gl-self-start"
              data-testid="query-reference-back"
              @click="selectedEntityName = null"
            >
              {{ s__('Orbit|All entities') }}
            </gl-button>

            <div class="gl-flex gl-items-center gl-gap-3">
              <schema-entity-icon
                :icon="selectedEntitySummary.icon"
                :color="selectedEntitySummary.color"
              />
              <gl-button
                category="tertiary"
                class="gl-font-monospace gl-font-bold"
                data-testid="query-reference-insert"
                @click="$emit('insert', selectedNode.name)"
              >
                {{ selectedNode.name }}
              </gl-button>
            </div>
            <p v-if="selectedNode.description" class="gl-mb-0 gl-text-sm gl-text-subtle">
              {{ selectedNode.description }}
            </p>

            <section v-if="selectedProperties.length">
              <h3 class="gl-heading-6 gl-mb-2 gl-text-subtle">{{ s__('Orbit|Properties') }}</h3>
              <div class="gl-flex gl-flex-wrap gl-gap-2">
                <gl-button
                  v-for="property in selectedProperties"
                  :key="property.name"
                  size="small"
                  class="gl-font-monospace"
                  :title="property.data_type"
                  data-testid="query-reference-insert"
                  @click="
                    $emit('insert-property', { entity: selectedNode.name, property: property.name })
                  "
                >
                  {{ property.name }}
                </gl-button>
              </div>
            </section>

            <section v-if="relationshipGroups.length">
              <h3 class="gl-heading-6 gl-mb-2 gl-text-subtle">
                {{ s__('Orbit|Relationships') }}
              </h3>
              <ul class="gl-m-0 gl-list-none gl-p-0">
                <li
                  v-for="group in relationshipGroups"
                  :key="group.key"
                  class="gl-border-t gl-flex gl-flex-wrap gl-items-center gl-gap-2 gl-border-default gl-py-2"
                  data-testid="query-reference-relationship"
                >
                  <span class="gl-text-subtle" aria-hidden="true">{{ group.arrow }}</span>
                  <span class="gl-sr-only">{{ group.directionLabel }}</span>
                  <span class="gl-font-bold">{{ group.entity }}</span>
                  <gl-button
                    v-for="edge in group.edges"
                    :key="edge.name"
                    size="small"
                    category="tertiary"
                    class="gl-font-monospace"
                    :title="edge.description"
                    data-testid="query-reference-insert"
                    @click="$emit('insert', edge.name)"
                  >
                    {{ edge.name }}
                  </gl-button>
                </li>
              </ul>
            </section>
          </template>

          <template v-else>
            <gl-search-box-by-type v-model="search" :placeholder="s__('Orbit|Search entities')" />
            <section v-for="domain in filteredDomains" :key="domain.key">
              <h3 class="gl-heading-6 gl-mb-2 gl-text-subtle">{{ domain.label }}</h3>
              <ul class="gl-m-0 gl-list-none gl-p-0">
                <li v-for="entity in domain.entities" :key="entity.name">
                  <button
                    type="button"
                    class="gl-flex gl-w-full gl-items-center gl-gap-3 gl-rounded-md gl-border-0 gl-bg-transparent gl-px-3 gl-py-2 gl-text-left hover:gl-bg-strong focus:gl-focus"
                    data-testid="query-reference-entity"
                    @click="selectEntity(entity.name)"
                  >
                    <schema-entity-icon :icon="entity.icon" :color="entity.color" />
                    <span class="gl-min-w-0 gl-grow gl-truncate">{{ entity.name }}</span>
                  </button>
                </li>
              </ul>
            </section>
          </template>
        </div>
      </gl-tab>

      <gl-tab :title="s__('Orbit|GQL syntax')">
        <query-gql-syntax />
      </gl-tab>
    </gl-tabs>
  </gl-drawer>
</template>
