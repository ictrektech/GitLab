<script>
import { defineComponent } from 'vue';
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import { fetchPolicies } from '~/lib/graphql';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { fetchOrbitSchema } from 'ee/orbit/api/orbit_api';
import { sumItemCounts } from 'ee/orbit/utils/orbit_group_state';
import { ROUTE_OVERVIEW, ROUTE_QUERY } from '../constants';
import { normalizeSchema } from './schema_graph';
import SchemaDataTab from './schema_data_tab.vue';

export default defineComponent({
  name: 'OrbitSchemaPage',
  components: { GlAlert, GlLoadingIcon, SchemaDataTab },
  inject: ['itemCountGroups'],
  data() {
    return {
      schema: null,
      isLoadingSchema: true,
      hasSchemaError: false,
    };
  },
  computed: {
    initialEntity() {
      return [].concat(this.$route.query.entity)[0] ?? null;
    },
    graphStats() {
      const groups = this.itemCountGroups;
      if (!groups.length || groups.some((group) => !group.orbit?.itemCounts)) return null;

      return sumItemCounts(groups).entities;
    },
  },
  mounted() {
    this.loadSchema();
  },
  methods: {
    async loadSchema(fetchPolicy) {
      this.isLoadingSchema = true;
      this.hasSchemaError = false;
      try {
        const schema = await fetchOrbitSchema(this.$apollo, { fetchPolicy });
        this.hasSchemaError = !schema;
        this.schema = normalizeSchema(schema);
      } catch (error) {
        Sentry.captureException(error);
        this.hasSchemaError = true;
      } finally {
        this.isLoadingSchema = false;
      }
    },
    retryLoadSchema() {
      this.loadSchema(fetchPolicies.NETWORK_ONLY);
    },
    onShowInstances({ entityType } = {}) {
      this.$router.push({
        name: ROUTE_OVERVIEW,
        query: entityType ? { entity: entityType } : {},
      });
    },
    onOpenQuery(query) {
      this.$router.push({ name: ROUTE_QUERY, query: { query } });
    },
  },
});
</script>

<template>
  <div class="gl-flex gl-min-h-0 gl-flex-1 gl-flex-col gl-pt-5" data-testid="orbit-schema-page">
    <gl-loading-icon v-if="isLoadingSchema" size="lg" class="gl-my-6" />
    <gl-alert
      v-else-if="hasSchemaError"
      variant="danger"
      :dismissible="false"
      :primary-button-text="__('Try again')"
      data-testid="schema-load-error"
      @primary-action="retryLoadSchema"
    >
      {{ s__('Orbit|Could not load the schema. Try again.') }}
    </gl-alert>
    <schema-data-tab
      v-else
      :schema="schema"
      :graph-stats="graphStats"
      :initial-entity="initialEntity"
      @show-instances="onShowInstances"
      @open-query="onOpenQuery"
    />
  </div>
</template>
