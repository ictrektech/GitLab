<script>
import { defineComponent } from 'vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';

export default defineComponent({
  name: 'QuerySyntaxList',
  components: { ClipboardButton },
  props: {
    items: {
      type: Array,
      required: true,
    },
  },
});
</script>

<template>
  <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-4 gl-p-0">
    <li v-for="item in items" :key="item.code" data-testid="gql-syntax-item">
      <div class="gl-relative">
        <code
          class="gl-block gl-whitespace-pre-wrap gl-rounded-md gl-bg-strong gl-py-2 gl-pl-3 gl-pr-8 gl-text-sm"
          >{{ item.code }}</code
        >
        <clipboard-button
          :text="item.code"
          :title="s__('Orbit|Copy example')"
          category="tertiary"
          size="small"
          class="gl-absolute gl-right-1 gl-top-1"
        />
      </div>
      <p class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle">{{ item.description }}</p>
    </li>
  </ul>
</template>
