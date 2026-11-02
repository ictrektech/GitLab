<script>
import { GlModal, GlSearchBoxByType, GlIcon } from '@gitlab/ui';
import { __ } from '~/locale';
import { REGO_TEMPLATES } from '../../catalog/rego_templates';

export default {
  name: 'RegoTemplatesModal',
  components: { GlModal, GlSearchBoxByType, GlIcon },
  props: {
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select', 'hide'],
  data() {
    return { search: '' };
  },
  computed: {
    filteredTemplates() {
      const query = this.search.toLowerCase().trim();
      if (!query) return REGO_TEMPLATES;

      return REGO_TEMPLATES.filter(
        (template) =>
          template.name.toLowerCase().includes(query) ||
          template.description.toLowerCase().includes(query),
      );
    },
  },
  methods: {
    select(template) {
      this.$emit('select', template.rego);
      this.$emit('hide');
    },
  },
  cancelAction: { text: __('Cancel') },
};
</script>

<template>
  <gl-modal
    modal-id="rego-templates-modal"
    :visible="visible"
    :title="s__('PolicyStore|Browse templates')"
    :action-cancel="$options.cancelAction"
    @hidden="$emit('hide')"
    @canceled="$emit('hide')"
  >
    <gl-search-box-by-type v-model="search" :placeholder="s__('PolicyStore|Search templates...')" />

    <div class="gl-mt-4 gl-grid gl-grid-cols-2 gl-gap-3">
      <button
        v-for="template in filteredTemplates"
        :key="template.id"
        type="button"
        data-testid="rego-template-card"
        class="gl-flex gl-w-full gl-cursor-pointer gl-items-start gl-gap-3 gl-rounded-lg gl-border-0 gl-bg-strong gl-p-4 gl-text-left hover:gl-bg-subtle"
        @click="select(template)"
      >
        <gl-icon :name="template.icon" :size="16" class="gl-mt-1 gl-flex-shrink-0 gl-text-subtle" />
        <span>
          <span class="gl-block gl-font-bold">{{ template.name }}</span>
          <span class="gl-text-sm gl-text-subtle">{{ template.description }}</span>
        </span>
      </button>
    </div>
  </gl-modal>
</template>
