<script>
import { s__, sprintf } from '~/locale';
import ConfirmDangerModal from '~/vue_shared/components/confirm_danger/confirm_danger_modal.vue';
import { formattedCount, humanSizeClamped } from '../utils';

const MODAL_ID = 'artifact-registry-disable-modal';

export default {
  name: 'ArtifactRegistryDisableConfirmation',
  i18n: {
    // Two sentences, translated separately: each has to stay whole, and neither is
    // locked into the other's position.
    intent: s__('ArtifactRegistry|You are about to disable Artifact Registry.'),
    effect: s__('ArtifactRegistry|This will affect all projects currently using this registry.'),
    repositories: s__('ArtifactRegistry|Repositories: %{count}'),
    storage: s__('ArtifactRegistry|Storage used: %{size}'),
  },
  components: {
    ConfirmDangerModal,
  },
  provide: {
    confirmButtonText: s__('ArtifactRegistry|Disable Artifact Registry'),
  },
  model: {
    prop: 'visible',
    event: 'change',
  },
  props: {
    handle: {
      type: String,
      required: true,
    },
    statistics: {
      type: Object,
      required: false,
      default: null,
    },
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change', 'confirm'],
  computed: {
    // Each figure is nullable on its own. An unknown one is left out rather than rendered as
    // zero, which in this dialog would read as nothing to lose.
    statisticsItems() {
      const { repositoriesCount, deduplicatedSizeBytes } = this.statistics ?? {};
      const items = [];

      if (repositoriesCount != null) {
        items.push(
          sprintf(this.$options.i18n.repositories, { count: formattedCount(repositoriesCount) }),
        );
      }

      if (deduplicatedSizeBytes != null) {
        items.push(
          sprintf(this.$options.i18n.storage, { size: humanSizeClamped(deduplicatedSizeBytes) }),
        );
      }

      return items;
    },
  },
  modalId: MODAL_ID,
};
</script>

<template>
  <confirm-danger-modal
    :visible="visible"
    :modal-id="$options.modalId"
    :phrase="handle"
    :confirm-loading="loading"
    @confirm="$emit('confirm')"
    @change="$emit('change', $event)"
  >
    <template #modal-body>
      <div data-testid="disable-consequences">
        <p>{{ $options.i18n.intent }}</p>
        <p>{{ $options.i18n.effect }}</p>
        <ul v-if="statisticsItems.length" data-testid="disable-statistics">
          <li v-for="item in statisticsItems" :key="item">{{ item }}</li>
        </ul>
      </div>
    </template>
  </confirm-danger-modal>
</template>
