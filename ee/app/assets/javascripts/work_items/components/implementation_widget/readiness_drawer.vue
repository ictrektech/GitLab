<script>
import { GlAlert, GlDrawer, GlLink, GlSkeletonLoader, GlSprintf } from '@gitlab/ui';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { destroyImageLightbox } from '~/behaviors/markdown/render_image_lightbox';
import { helpPagePath } from '~/helpers/help_page_helper';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import SafeHtml from '~/vue_shared/directives/safe_html';

export default {
  name: 'ReadinessDrawer',
  directives: {
    SafeHtml,
  },
  components: {
    GlAlert,
    GlDrawer,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
  },
  props: {
    isOpen: {
      type: Boolean,
      required: true,
    },
    feedbackHtml: {
      type: String,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    hasError: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['close', 'opened', 'retry'],
  computed: {
    headerHeight() {
      return getContentWrapperHeight();
    },
    hasFeedback() {
      return Boolean(this.feedbackHtml?.trim());
    },
    showSkeleton() {
      return this.isLoading && !this.hasFeedback;
    },
  },
  watch: {
    isOpen: {
      handler(newVal) {
        if (newVal) {
          this.renderMarkdown();
        } else {
          // The drawer body unmounts on close, so release its lightbox before it goes.
          this.destroyMarkdown();
        }
      },
      immediate: true,
    },
    feedbackHtml() {
      // Feedback is only requested once the drawer opens, so it usually arrives after `isOpen`.
      this.renderMarkdown();
    },
  },
  beforeDestroy() {
    this.destroyMarkdown();
  },
  methods: {
    async renderMarkdown() {
      await this.$nextTick();
      renderGFM(this.$refs['gfm-content']);
    },
    destroyMarkdown() {
      if (this.$refs['gfm-content']) {
        destroyImageLightbox(this.$refs['gfm-content']);
      }
    },
    focusHeading() {
      this.$refs.heading?.focus();
      this.$emit('opened');
    },
    retry() {
      this.$refs.heading?.focus();
      this.$emit('retry');
    },
  },
  DRAWER_Z_INDEX,
  readinessHelpPath: helpPagePath('user/work_items/workplan.md', { anchor: 'readiness' }),
};
</script>

<template>
  <div @keydown.esc.stop="$emit('close')">
    <gl-drawer
      :open="isOpen"
      :header-height="headerHeight"
      header-sticky
      :z-index="$options.DRAWER_Z_INDEX"
      data-testid="readiness-drawer"
      @opened="focusHeading"
      @close="$emit('close')"
    >
      <template #title>
        <h2 ref="heading" tabindex="-1" class="gl-heading-4 gl-my-0">
          {{ s__('AgentPlan|Readiness') }}
        </h2>
      </template>
      <div>
        <span role="status" class="gl-sr-only" data-testid="readiness-feedback-status">
          <template v-if="showSkeleton">{{ s__('AgentPlan|Loading readiness details') }}</template>
        </span>
        <div v-if="showSkeleton" aria-hidden="true" data-testid="readiness-feedback-loading">
          <gl-skeleton-loader :lines="6" />
        </div>
        <gl-alert
          v-if="hasError"
          variant="danger"
          :dismissible="false"
          :primary-button-text="s__('AgentPlan|Try again')"
          class="gl-mb-5"
          @primary-action="retry"
        >
          {{ s__('AgentPlan|Readiness details could not be loaded.') }}
        </gl-alert>
        <template v-if="hasFeedback">
          <h3 class="gl-heading-5 gl-mb-3">{{ s__('AgentPlan|How to improve readiness') }}</h3>
          <p>
            {{ s__('AgentPlan|GitLab Duo reviewed this work item and suggests these changes:') }}
          </p>
          <div
            ref="gfm-content"
            v-safe-html="feedbackHtml"
            class="md"
            data-testid="readiness-feedback-rendered"
          ></div>
        </template>
      </div>
      <template #footer>
        <gl-alert
          variant="info"
          :dismissible="false"
          :title="s__('AgentPlan|What is readiness?')"
          :header-level="3"
          politeness="off"
          class="gl-text-sm"
        >
          <gl-sprintf
            :message="
              s__(
                'AgentPlan|Shows how ready this work item is for GitLab Duo to implement. %{linkStart}Learn more%{linkEnd}.',
              )
            "
          >
            <template #link="{ content }">
              <gl-link :href="$options.readinessHelpPath" target="_blank">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </gl-alert>
      </template>
    </gl-drawer>
  </div>
</template>
