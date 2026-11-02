<script>
import { GlButton, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import emptyStateSvg from '@gitlab/svgs/dist/illustrations/status/status-new-sm.svg';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { destroyImageLightbox } from '~/behaviors/markdown/render_image_lightbox';
import SafeHtml from '~/vue_shared/directives/safe_html';
import WorkplanAvailabilityPopover from './workplan_availability_popover.vue';

export default {
  name: 'WorkplanView',
  directives: {
    SafeHtml,
  },
  components: {
    GlButton,
    GlEmptyState,
    GlLoadingIcon,
    WorkplanAvailabilityPopover,
  },
  emptyStateSvg,
  props: {
    generationDisabledReason: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: true,
    },
    savedContent: {
      type: String,
      required: true,
    },
    savedContentHtml: {
      type: String,
      required: true,
    },
    isFlowActive: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['start-edit', 'generate'],
  computed: {
    isRegenerating() {
      return this.isFlowActive && this.hasSavedContent;
    },
    hasSavedContent() {
      return Boolean(this.savedContent);
    },
  },
  watch: {
    savedContentHtml: {
      handler() {
        this.renderMarkdown();
      },
      immediate: true,
    },
  },
  beforeDestroy() {
    if (this.$refs['gfm-content']) {
      destroyImageLightbox(this.$refs['gfm-content']);
    }
  },
  methods: {
    async renderMarkdown() {
      await this.$nextTick();
      renderGFM(this.$refs['gfm-content']);
    },
  },
};
</script>

<template>
  <div class="work-item-detail-panel-content">
    <gl-loading-icon v-if="isLoading || isRegenerating" size="md" class="gl-my-5" />
    <template v-else-if="!hasSavedContent">
      <gl-empty-state
        v-if="canUpdate"
        data-testid="workplan-empty-state"
        :svg-path="$options.emptyStateSvg"
        :svg-height="72"
        content-class="!gl-px-0"
        :title="s__('AgentPlan|Create a workplan')"
        :description="
          s__(
            'AgentPlan|A workplan breaks down your work item into a step-by-step implementation guide for GitLab Duo to execute. Create one manually or let Duo generate it for you.',
          )
        "
      >
        <template #actions>
          <div class="gl-flex gl-flex-wrap gl-justify-center gl-gap-3">
            <template v-if="!isFlowActive">
              <gl-button
                ref="generateButton"
                :disabled="Boolean(generationDisabledReason)"
                accessible-disabled
                icon="tanuki-ai"
                variant="confirm"
                data-testid="panel-generate-button"
                @click="$emit('generate')"
              >
                {{ s__('AgentPlan|Generate') }}
              </gl-button>
              <workplan-availability-popover
                v-if="generationDisabledReason"
                :target="() => $refs.generateButton?.$el"
                :reason="generationDisabledReason"
              />
            </template>
            <gl-button
              category="secondary"
              data-testid="panel-create-manually-button"
              @click="$emit('start-edit')"
            >
              {{ s__('AgentPlan|Create manually') }}
            </gl-button>
          </div>
        </template>
      </gl-empty-state>
      <p v-else data-testid="workplan-empty-state" class="gl-mb-0 gl-text-subtle">
        {{
          s__(
            "AgentPlan|No workplan has been added yet. You don't have permission to create or edit the workplan.",
          )
        }}
      </p>
    </template>
    <template v-else>
      <div
        ref="gfm-content"
        v-safe-html="savedContentHtml"
        class="md"
        data-testid="workplan-rendered"
      ></div>
    </template>
  </div>
</template>
