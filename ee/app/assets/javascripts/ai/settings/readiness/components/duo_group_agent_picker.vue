<script>
import { GlFormCheckbox } from '@gitlab/ui';
import { isAgentSelected } from '../group_readiness';

export default {
  name: 'DuoGroupAgentPicker',
  components: {
    GlFormCheckbox,
  },
  props: {
    statuses: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    // id of the note that says why the checkboxes are disabled.
    describedBy: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['change'],
  computed: {
    selectedCount() {
      return this.statuses.filter(isAgentSelected).length;
    },
    allSelected() {
      return this.statuses.length > 0 && this.selectedCount === this.statuses.length;
    },
    someSelected() {
      return this.selectedCount > 0 && !this.allSelected;
    },
  },
  methods: {
    isAgentSelected,
    toggleAgent(reference, checked) {
      this.$emit(
        'change',
        this.statuses.map((agent) =>
          agent.reference === reference ? { ...agent, enabled: checked } : agent,
        ),
      );
    },
    toggleAll(checked) {
      this.$emit(
        'change',
        this.statuses.map((agent) => ({ ...agent, enabled: checked })),
      );
    },
  },
};
</script>
<template>
  <div>
    <gl-form-checkbox
      :checked="allSelected"
      :indeterminate="someSelected"
      :disabled="disabled"
      :aria-describedby="describedBy"
      class="gl-ml-6 gl-mt-3"
      data-testid="foundational-agent-select-all"
      @change="toggleAll"
    >
      {{ s__('DuoAgentPlatform|Select all agents') }}
    </gl-form-checkbox>
    <div class="gl-ml-6 gl-mt-3 gl-pl-5">
      <gl-form-checkbox
        v-for="agent in statuses"
        :key="agent.reference"
        :checked="isAgentSelected(agent)"
        :disabled="disabled"
        :aria-describedby="describedBy"
        data-testid="foundational-agent-checkbox"
        @change="toggleAgent(agent.reference, $event)"
      >
        <div>
          {{ agent.name }}
          <div class="gl-text-sm gl-text-subtle">{{ agent.description }}</div>
        </div>
      </gl-form-checkbox>
    </div>
  </div>
</template>
