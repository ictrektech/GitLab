<script>
import { GlButton } from '@gitlab/ui';
import { InternalEvents } from '~/tracking';
import {
  REQUEST_STATE,
  PAINTED_DOOR_FEATURES,
  getInitialRequestState,
  recordRequest,
} from 'ee/painted_door_request/utils';
import TanukiAiIcon from '../../shared/widgets/tanuki_ai_icon.vue';
import {
  DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE,
  DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
  DUO_PANEL_EVENT_CLICK_REQUEST_DUO,
} from '../../constants';
import DuoWorkflowExamplesCard from './duo_workflow_examples_card.vue';

export default {
  name: 'AccessDeniedEmptyState',
  components: {
    TanukiAiIcon,
    GlButton,
    DuoWorkflowExamplesCard,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    requestGroupId: {
      type: Number,
      required: false,
      default: null,
    },
    requested: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      requestState: this.requestGroupId
        ? getInitialRequestState({
            feature: PAINTED_DOOR_FEATURES.DUO_PANEL,
            groupId: this.requestGroupId,
            requested: this.requested,
          })
        : null,
    };
  },
  computed: {
    showRequestButton() {
      return (
        Boolean(this.requestGroupId) && this.requestState !== REQUEST_STATE.PREVIOUSLY_REQUESTED
      );
    },
    isRequested() {
      return this.requestState === REQUEST_STATE.REQUESTED;
    },
  },
  mounted() {
    this.trackEvent(DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE);

    if (this.requestGroupId) {
      this.trackEvent(DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE, {
        label: this.requestState,
        property: String(this.requestGroupId),
      });
    }
  },
  methods: {
    // aria-disabled (kept for the confirm styling) doesn't block clicks.
    handleRequestClick() {
      if (this.isRequested) return;

      this.requestState = REQUEST_STATE.REQUESTED;
      this.trackEvent(DUO_PANEL_EVENT_CLICK_REQUEST_DUO, {
        property: String(this.requestGroupId),
      });
      recordRequest({ feature: PAINTED_DOOR_FEATURES.DUO_PANEL, groupId: this.requestGroupId });
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-w-full gl-flex-col gl-items-start gl-gap-4">
    <tanuki-ai-icon />

    <h2 class="gl-my-0 gl-text-size-h2">
      {{ s__("DuoAgentsPlatform|Your group doesn't have GitLab Duo yet") }}
    </h2>
    <p class="gl-m-0 gl-text-subtle" data-testid="empty-state-text">
      {{
        s__(
          'DuoAgentsPlatform|Ask a group Owner to start a trial or purchase GitLab Credits to enable GitLab Duo for everyone.',
        )
      }}
    </p>
    <gl-button
      v-if="showRequestButton"
      variant="confirm"
      :icon="isRequested ? 'check' : undefined"
      :aria-disabled="isRequested ? 'true' : undefined"
      data-testid="request-duo-button"
      @click="handleRequestClick"
    >
      {{
        isRequested
          ? s__('DuoAgentsPlatform|Interest recorded')
          : s__('DuoAgentsPlatform|Request GitLab Duo')
      }}
    </gl-button>
    <div v-if="requestGroupId" aria-live="polite" data-testid="request-duo-live-region">
      <p v-if="isRequested" class="gl-m-0 gl-text-subtle">
        {{
          s__(
            "DuoAgentsPlatform|Thank you for your interest. Your group Owner isn't notified, so ask them directly if you need GitLab Credits.",
          )
        }}
      </p>
    </div>
    <duo-workflow-examples-card :request-state="requestState" :request-group-id="requestGroupId" />
  </div>
</template>
