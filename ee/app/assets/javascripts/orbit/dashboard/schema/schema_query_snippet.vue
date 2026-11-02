<script>
import { defineComponent } from 'vue';
import { GlButton } from '@gitlab/ui';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';

export default defineComponent({
  name: 'SchemaQuerySnippet',
  components: { ClipboardButton, GlButton },
  props: {
    query: {
      type: String,
      required: true,
    },
  },
  emits: ['open-query'],
});
</script>

<template>
  <section class="gl-flex gl-flex-col gl-gap-3" data-testid="schema-query-snippet">
    <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h4 class="gl-m-0 gl-text-sm gl-font-bold gl-text-subtle">
        {{ s__('Orbit|Start a query') }}
      </h4>
      <clipboard-button
        :text="query"
        :title="s__('Orbit|Copy query')"
        category="tertiary"
        size="small"
      />
    </div>
    <pre
      class="gl-m-0 gl-overflow-x-auto gl-rounded-md gl-bg-strong gl-px-3 gl-py-2 gl-text-sm"
      data-testid="schema-query-text"
      >{{ query }}</pre>
    <div>
      <gl-button size="small" @click="$emit('open-query', query)">
        {{ s__('Orbit|Open in Query editor') }}
      </gl-button>
    </div>
  </section>
</template>
