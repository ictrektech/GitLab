<script>
import { uniqueId } from 'lodash-es';
import { MountingPortal } from 'portal-vue';
import { s__, sprintf } from '~/locale';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import DirectMembersCard from './direct_members_card.vue';
import InheritedMembersCard from './inherited_members_card.vue';

export default {
  name: 'ArtifactRegistryAccessSidePanel',
  components: {
    DirectMembersCard,
    DynamicPanel,
    InheritedMembersCard,
    MountingPortal,
  },
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    repositoryId: {
      type: String,
      required: true,
    },
    repositoryName: {
      type: String,
      required: true,
    },
  },
  emits: ['close'],
  data() {
    return {
      headingId: uniqueId('access-side-panel-heading-'),
    };
  },
  computed: {
    title() {
      return sprintf(
        s__('ArtifactRegistry|Access for %{name}'),
        { name: this.repositoryName },
        false,
      );
    },
  },
  watch: {
    open(open) {
      if (open) {
        this.focus();
      }
    },
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    focus() {
      this.$nextTick(() => this.$refs.panel?.$el.focus());
    },
    hasPriorEscapeHandler() {
      const active = document.activeElement;

      return (
        document.body.classList.contains('modal-open') ||
        document.querySelector('.gl-drawer') != null ||
        active?.closest('.js-editor') != null ||
        active?.closest('[contenteditable]:not([contenteditable="false"])') != null ||
        active?.tagName === 'INPUT' ||
        active?.tagName === 'TEXTAREA'
      );
    },
    handleKeydown({ key }) {
      if (key === 'Escape' && this.open && !this.hasPriorEscapeHandler()) {
        this.$emit('close');
      }
    },
  },
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel
      ref="panel"
      role="region"
      :aria-labelledby="headingId"
      tabindex="-1"
      data-testid="access-side-panel"
      @close="$emit('close')"
    >
      <template #header>
        <h2 :id="headingId" class="panel-header-inner-text gl-m-0" data-testid="access-heading">
          {{ title }}
        </h2>
      </template>

      <div class="gl-my-5 gl-flex gl-flex-col gl-gap-5">
        <direct-members-card :repository-id="repositoryId" />
        <inherited-members-card />
      </div>
    </dynamic-panel>
  </mounting-portal>
</template>
