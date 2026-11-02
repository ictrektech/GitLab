<script>
import { defineComponent } from 'vue';
import { GlButton, GlIcon } from '@gitlab/ui';
import { n__, sprintf } from '~/locale';
import SchemaEntityIcon from './schema_entity_icon.vue';
import SchemaQuerySnippet from './schema_query_snippet.vue';

export default defineComponent({
  name: 'SchemaRelationshipCard',
  components: { GlButton, GlIcon, SchemaEntityIcon, SchemaQuerySnippet },
  props: {
    relationship: {
      type: Object,
      required: true,
    },
    entitiesByName: {
      type: Object,
      required: true,
    },
    query: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['close', 'select-entity', 'open-query'],
  computed: {
    pairs() {
      return this.relationship.variants.map(({ source, target }) => ({
        key: `${source}-${target}`,
        source: this.entitiesByName[source],
        target: this.entitiesByName[target],
      }));
    },
    pairsTitle() {
      return sprintf(
        n__('Orbit|Connects %{count} pair', 'Orbit|Connects %{count} pairs', this.pairs.length),
        {
          count: this.pairs.length,
        },
      );
    },
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- called via $refs by schema_data_tab.vue
    focusName() {
      this.$refs.name.focus();
    },
  },
});
</script>

<template>
  <aside
    :aria-label="s__('Orbit|Relationship details')"
    class="gl-border gl-flex gl-max-h-full gl-w-37 gl-max-w-full gl-flex-col gl-overflow-y-auto gl-rounded-lg gl-border-default gl-bg-default gl-shadow-sm"
    data-testid="schema-relationship-card"
  >
    <div class="gl-flex gl-items-start gl-gap-3 gl-px-4 gl-pt-4">
      <div class="gl-min-w-0 gl-grow">
        <h3
          ref="name"
          tabindex="-1"
          class="gl-heading-5 gl-m-0 gl-break-words gl-font-monospace"
          data-testid="schema-relationship-name"
        >
          {{ relationship.name }}
        </h3>
        <p class="gl-m-0 gl-text-sm gl-text-subtle">{{ s__('Orbit|Relationship') }}</p>
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
      <p v-if="relationship.description" class="gl-m-0 gl-text-subtle">
        {{ relationship.description }}
      </p>
      <section>
        <h4 class="gl-m-0 gl-mb-2 gl-text-sm gl-font-bold gl-text-subtle">{{ pairsTitle }}</h4>
        <ul class="gl-m-0 gl-list-none gl-p-0">
          <li
            v-for="pair in pairs"
            :key="pair.key"
            class="gl-border-b gl-flex gl-flex-wrap gl-items-center gl-gap-2 gl-border-subtle gl-py-2"
            data-testid="schema-relationship-pair"
          >
            <gl-button variant="link" @click="$emit('select-entity', pair.source.name)">
              <span class="gl-flex gl-items-center gl-gap-2">
                <schema-entity-icon :icon="pair.source.icon" :color="pair.source.color" />
                <span>{{ pair.source.name }}</span>
              </span>
            </gl-button>
            <gl-icon name="arrow-right" :size="12" variant="subtle" />
            <gl-button variant="link" @click="$emit('select-entity', pair.target.name)">
              <span class="gl-flex gl-items-center gl-gap-2">
                <schema-entity-icon :icon="pair.target.icon" :color="pair.target.color" />
                <span>{{ pair.target.name }}</span>
              </span>
            </gl-button>
          </li>
        </ul>
      </section>
    </div>

    <schema-query-snippet
      v-if="query"
      class="gl-border-t gl-border-default gl-p-4"
      :query="query"
      @open-query="$emit('open-query', $event)"
    />
  </aside>
</template>
