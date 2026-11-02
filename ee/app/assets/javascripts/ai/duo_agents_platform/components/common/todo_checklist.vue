<script>
import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { TODO_STATUS_ICON } from 'ee/ai/duo_agents_platform/constants';

export default {
  name: 'TodoChecklist',
  components: {
    GlIcon,
    GlLoadingIcon,
  },
  props: {
    toolInfo: {
      type: Object,
      required: true,
    },
    bordered: {
      type: Boolean,
      required: false,
      default: true,
    },
    flowFinished: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    todos() {
      return this.toolInfo?.args?.todos || [];
    },
    containerClasses() {
      return this.bordered ? 'gl-border gl-rounded-base gl-px-4 gl-py-3' : '';
    },
  },
  methods: {
    statusIcon(status) {
      return TODO_STATUS_ICON[status] ?? TODO_STATUS_ICON.pending;
    },
    isInProgress(status) {
      return status === 'in_progress';
    },
    isCancelled(status) {
      return status === 'cancelled';
    },
  },
};
</script>
<template>
  <div v-if="todos.length" data-testid="todo-checklist-container" :class="containerClasses">
    <ul class="gl-m-0 gl-list-none gl-pl-0">
      <li
        v-for="(todo, index) in todos"
        :key="index"
        class="gl-flex gl-items-start gl-gap-3 gl-py-1"
      >
        <div
          class="gl-mt-1 gl-flex gl-h-5 gl-w-5 gl-shrink-0 gl-translate-y-px gl-items-center gl-justify-center"
        >
          <gl-loading-icon
            v-if="!flowFinished && isInProgress(todo.status)"
            size="sm"
            :label="__('In progress')"
            class="todo-checklist-spinner"
          />
          <gl-icon
            v-else
            :name="statusIcon(todo.status).icon"
            :variant="statusIcon(todo.status).variant"
            :aria-label="statusIcon(todo.status).ariaLabel"
            :size="12"
          />
        </div>
        <span
          data-testid="todo-description"
          :class="{ 'gl-text-subtle gl-line-through': isCancelled(todo.status) }"
        >
          {{ todo.description }}
        </span>
      </li>
    </ul>
  </div>
</template>
