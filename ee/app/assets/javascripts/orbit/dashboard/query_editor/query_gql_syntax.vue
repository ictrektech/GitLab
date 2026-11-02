<script>
import { defineComponent } from 'vue';
import { GlAccordion, GlAccordionItem, GlLink, GlSprintf } from '@gitlab/ui';
import { GQL_MORE_SYNTAX, GQL_REFERENCE_URL, GQL_STARTER, OPEN_CYPHER_URL } from './constants';
import QuerySyntaxList from './query_syntax_list.vue';

export default defineComponent({
  name: 'QueryGqlSyntax',
  components: { GlAccordion, GlAccordionItem, GlLink, GlSprintf, QuerySyntaxList },
  gqlStarter: GQL_STARTER,
  gqlMoreSyntax: GQL_MORE_SYNTAX,
  gqlReferenceUrl: GQL_REFERENCE_URL,
  openCypherUrl: OPEN_CYPHER_URL,
});
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5 gl-pt-3">
    <query-syntax-list :items="$options.gqlStarter" data-testid="gql-starter" />

    <gl-accordion :header-level="3">
      <gl-accordion-item :title="s__('Orbit|More syntax')">
        <div class="gl-flex gl-flex-col gl-gap-5">
          <section v-for="group in $options.gqlMoreSyntax" :key="group.title">
            <h4 class="gl-heading-6 gl-mb-3 gl-text-subtle">{{ group.title }}</h4>
            <query-syntax-list :items="group.items" />
          </section>
        </div>
      </gl-accordion-item>
    </gl-accordion>

    <footer class="gl-border-t gl-flex gl-flex-col gl-gap-2 gl-border-default gl-pt-4 gl-text-sm">
      <p class="gl-mb-0 gl-text-subtle">
        {{ s__('Orbit|Read-only. No OR or OPTIONAL MATCH. Up to 3 hops and 1,000 rows.') }}
      </p>
      <p class="gl-mb-0">
        <gl-sprintf
          :message="
            s__(
              'Orbit|%{referenceStart}Full GQL reference%{referenceEnd} · based on %{cypherStart}openCypher 9%{cypherEnd}',
            )
          "
        >
          <template #reference="{ content }">
            <gl-link :href="$options.gqlReferenceUrl" target="_blank">{{ content }}</gl-link>
          </template>
          <template #cypher="{ content }">
            <gl-link :href="$options.openCypherUrl" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>
    </footer>
  </div>
</template>
