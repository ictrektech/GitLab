<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { REPOSITORY_FORMAT_LABELS, UPSTREAM_REPOSITORIES_CAP } from '../../constants';
import UpstreamRepositoriesOrderTable from './upstream_repositories_order_table.vue';
import UpstreamRepositoryPicker from './upstream_repository_picker.vue';

export default {
  name: 'ArtifactRegistryUpstreamRepositoriesSection',
  components: {
    CrudComponent,
    GlAlert,
    GlButton,
    UpstreamRepositoriesOrderTable,
    UpstreamRepositoryPicker,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    sources: {
      type: Array,
      required: true,
    },
    submitError: {
      type: String,
      required: false,
      default: '',
    },
    loadFailed: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['add', 'move', 'remove'],
  data() {
    return {
      announcement: '',
      movedId: null,
      removedIndex: null,
      isPickerOpen: false,
    };
  },
  computed: {
    title() {
      return sprintf(s__('ArtifactRegistry|%{format} repositories'), {
        format: REPOSITORY_FORMAT_LABELS[this.format] ?? this.format,
      });
    },
    counter() {
      return sprintf(s__('ArtifactRegistry|%{count} of %{cap}'), {
        count: this.sources.length,
        cap: UPSTREAM_REPOSITORIES_CAP,
      });
    },
    isEmpty() {
      return this.sources.length === 0;
    },
    alertMessage() {
      if (this.loadFailed) return s__('ArtifactRegistry|Failed to load upstream repositories.');

      return this.submitError;
    },
    showsEmptyLine() {
      return this.isEmpty && !this.isPickerOpen && !this.alertMessage;
    },
    isCapReached() {
      return this.sources.length >= UPSTREAM_REPOSITORIES_CAP;
    },
  },
  watch: {
    // The picker is only open at the cap right after the last pick, so close it there.
    isCapReached(reached) {
      if (reached && this.isPickerOpen) this.closePicker();
    },
    format() {
      this.$refs.crud.hideForm();
    },
    submitError(value) {
      if (value) this.announcement = value;
    },
    async sources(next, previous) {
      this.announcement = this.announcementFor(next, previous);

      const { movedId, removedIndex } = this;
      this.movedId = null;
      this.removedIndex = null;

      if (removedIndex !== null && next.length < previous.length) {
        await this.$nextTick();

        this.focusAfterRemove(removedIndex);
        return;
      }

      if (movedId === null || next.length !== previous.length) return;

      const from = previous.findIndex(({ id }) => id === movedId);
      const to = next.findIndex(({ id }) => id === movedId);

      if (from === -1 || to === -1 || from === to) return;

      await this.$nextTick();

      this.focusAfterMove(to, to < from);
    },
  },
  methods: {
    announcementFor(next, previous) {
      if (!next.length) {
        return s__('ArtifactRegistry|All upstream repositories removed. The list is empty.');
      }

      const position = next.findIndex(({ id }) => id === this.movedId);

      if (this.movedId && next.length === previous.length && position !== -1) {
        return sprintf(s__('ArtifactRegistry|%{name} moved to position %{position} of %{total}.'), {
          name: next[position].name,
          position: position + 1,
          total: next.length,
        });
      }

      const known = new Set(previous.map(({ id }) => id));
      const added = next.filter(({ id }) => !known.has(id));

      if (added.length === 1 && next.length === previous.length + 1) {
        return sprintf(s__('ArtifactRegistry|%{name} added. %{count} of %{cap}.'), {
          name: added[0].name,
          count: next.length,
          cap: UPSTREAM_REPOSITORIES_CAP,
        });
      }

      return sprintf(s__('ArtifactRegistry|Resolution order updated: %{names}.'), {
        names: next.map(({ name }, index) => `${index + 1}. ${name}`).join(', '),
      });
    },
    async closePicker() {
      this.$refs.crud.hideForm();

      await this.$nextTick();

      this.focusTrigger();
    },
    focusTrigger() {
      (this.$refs.toggle?.$el ?? this.$refs.capMessage)?.focus();
    },
    onMove({ from, to }) {
      this.movedId = this.sources[from]?.id ?? null;
      this.$emit('move', { from, to });
    },
    onRemove(index) {
      this.movedId = null;
      this.removedIndex = index;
      this.$emit('remove', index);
    },
    focusAfterRemove(index) {
      const { table } = this.$refs;

      if (!table) {
        this.focusTrigger();
        return;
      }

      table.focusRemove(index);
    },
    focusAfterMove(index, movedUp) {
      this.$refs.table?.focusArrow(index, movedUp ? 'up' : 'down');
    },
  },
};
</script>

<template>
  <div class="gl-mb-5" data-testid="upstream-repositories-section">
    <crud-component
      ref="crud"
      :title="title"
      :count="counter"
      :description="
        s__(
          'ArtifactRegistry|Use the arrow buttons to reorder repositories. Artifacts are resolved from top to bottom.',
        )
      "
      :body-class="isPickerOpen ? '!gl-p-0' : null"
      @show-form="isPickerOpen = true"
      @hide-form="isPickerOpen = false"
    >
      <template #actions="{ showForm }">
        <span
          v-if="isCapReached"
          ref="capMessage"
          tabindex="-1"
          data-testid="upstream-repositories-cap-reached"
          >{{ s__('ArtifactRegistry|Maximum number of upstream repositories reached.') }}</span
        >
        <gl-button
          v-else-if="!isPickerOpen && !loadFailed"
          ref="toggle"
          size="small"
          data-testid="add-upstream-repository"
          @click="showForm"
        >
          {{ s__('ArtifactRegistry|Add repository') }}
        </gl-button>
      </template>

      <template #form>
        <upstream-repository-picker
          :format="format"
          :excluded-ids="sources.map(({ id }) => id)"
          :list-size="sources.length"
          @add="$emit('add', $event)"
          @close="closePicker"
        />
      </template>

      <template v-if="showsEmptyLine" #empty>{{
        s__('ArtifactRegistry|No repositories added yet. Select Add repository to add a source.')
      }}</template>

      <template v-if="!showsEmptyLine" #default>
        <div v-if="alertMessage" :class="{ 'gl-p-3': !isEmpty }">
          <gl-alert variant="danger" :dismissible="false" data-testid="upstream-repositories-alert">
            {{ alertMessage }}
          </gl-alert>
        </div>

        <upstream-repositories-order-table
          v-if="!isEmpty"
          ref="table"
          :sources="sources"
          @move="onMove"
          @remove="onRemove"
        />
      </template>
    </crud-component>

    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="upstream-repositories-announcement"
      >{{ announcement }}</span
    >
  </div>
</template>
