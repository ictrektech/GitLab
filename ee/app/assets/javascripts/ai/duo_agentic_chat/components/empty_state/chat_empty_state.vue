<script>
import { DuoChatPredefinedPrompts } from '@gitlab/duo-ui';
import getFirstChatThread from 'ee/ai/graphql/get_first_chat_thread.query.graphql';
import { fetchPolicies } from '~/lib/graphql';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { InternalEvents } from '~/tracking';
import { s__ } from '~/locale';
import {
  TRACKING_EVENT_VIEW_EMPTY_STATE,
  TRACKING_EVENT_CLICK_PROMPT,
  PROMPT_CATEGORY_GET_STARTED,
  PROMPT_CATEGORY_AGENT,
} from '../../constants';
import { captureExceptionForDuoChat } from '../../observability/sentry_utils';
import DuoChatEmptyStateHeader from '../duo_chat_empty_state_header.vue';
import PromptCategories from './prompt_categories.vue';

export default {
  name: 'ChatEmptyState',
  components: {
    DuoChatEmptyStateHeader,
    DuoChatPredefinedPrompts,
    PromptCategories,
  },
  mixins: [glSlotsMixin, InternalEvents.mixin()],
  props: {
    /**
     * Slash-command override for the heading (welcomeMessage).
     */
    welcomeMessage: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * Categories of suggested prompts, `{ key, title, questions }`.
     */
    promptCategories: {
      type: Array,
      required: false,
      default: () => [],
    },
    /**
     * Slash-command override: when set, renders this flat prompt list
     * instead of the categories.
     */
    overridePrompts: {
      type: Array,
      required: false,
      default: null,
    },
    /**
     * Whether the user has typed a draft in the prompt input. Suggestions
     * hide so the growing input has room below.
     */
    hasDraft: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Whether the user has a Duo trial or subscription. The view and prompt
     * events feed the trial or paid funnel, so they only fire for those users.
     */
    hasTrialOrSubscription: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['send-prompt'],
  apollo: {
    // The empty state only needs to know whether any thread exists, so ask for
    // one id rather than pulling in the list owned by the history view.
    firstChatThread: {
      query: getFirstChatThread,
      context: {
        featureCategory: 'duo_agent_platform',
      },
      // Mounted afresh for every new chat. A cached thread renders the
      // returning variant at once; the network read still catches a user
      // whose first thread was created since the cache was filled.
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      // Without this, vue-apollo drops the cached result while the network
      // read is in flight.
      notifyOnNetworkStatusChange: true,
      update(data) {
        return data?.duoWorkflowWorkflows?.nodes?.[0] ?? null;
      },
      error(err) {
        this.firstChatThreadFailed = true;
        captureExceptionForDuoChat(err);
      },
    },
  },
  data() {
    return {
      firstChatThread: null,
      firstChatThreadFailed: false,
    };
  },
  computed: {
    // Until a thread is known to exist or the check settles, first-time-ness
    // is unknown: the heading and the Get started category are held back to
    // avoid flashing the wrong variant.
    isLoadingChatHistory() {
      return this.$apollo.queries.firstChatThread.loading && !this.firstChatThread;
    },
    // First-time users (no chat threads yet) get the introduction heading and
    // the Get started category. On error, fall back to the returning-user
    // variant rather than introducing Duo to someone who may already use it.
    isFirstTimeUser() {
      return !this.isLoadingChatHistory && !this.firstChatThreadFailed && !this.firstChatThread;
    },
    heading() {
      if (this.welcomeMessage) {
        return this.welcomeMessage;
      }
      return this.isFirstTimeUser
        ? s__('DuoAgenticChat|Hello from GitLab Duo')
        : s__("DuoAgenticChat|What's next?");
    },
    secondaryText() {
      if (!this.isFirstTimeUser || this.welcomeMessage) {
        return null;
      }
      return s__('DuoAgenticChat|Collaborate with AI to accomplish tasks or answer questions.');
    },
    visibleCategories() {
      if (this.isFirstTimeUser) {
        return this.promptCategories;
      }
      return this.promptCategories.filter(
        (category) => category.key !== PROMPT_CATEGORY_GET_STARTED,
      );
    },
    // Precedence: agent category first, since picking an agent is explicit
    // intent, then contextual prompts, which dominate usage when the page
    // has any. Get started is a last fallback, and only for users with no
    // threads yet.
    initialExpandedKey() {
      if (this.isLoadingChatHistory) {
        return null;
      }
      const preferred =
        this.visibleCategories.find((category) => category.key === PROMPT_CATEGORY_AGENT) ??
        this.visibleCategories.find((category) => category.contextual);
      if (preferred) {
        return preferred.key;
      }
      return this.isFirstTimeUser ? PROMPT_CATEGORY_GET_STARTED : null;
    },
  },
  mounted() {
    if (this.hasTrialOrSubscription) {
      this.trackEvent(TRACKING_EVENT_VIEW_EMPTY_STATE);
    }
  },
  methods: {
    // A method, not a computed: `glSlots()` is not a reactive dependency, so a cached
    // computed would go stale when the parent starts or stops supplying the notice.
    hasNotice() {
      return Boolean(this.glSlots().notice);
    },
    sendPrompt(prompt) {
      if (this.hasTrialOrSubscription) {
        this.trackEvent(TRACKING_EVENT_CLICK_PROMPT, { label: prompt });
      }
      this.$emit('send-prompt', prompt);
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-w-full gl-grow gl-flex-col gl-gap-5"
    :class="{ 'gl-justify-center': hasNotice() }"
    data-testid="chat-redesigned-empty-state"
  >
    <!-- Fixed-proportion spacer anchoring the prompt slightly above center.
         The heading bottom-aligns inside it so the input holds its position
         while the heading loads in and when suggestions expand below. A notice
         replaces the suggestions, so nothing expands and the whole group
         centers instead. -->
    <div
      class="gl-flex gl-flex-col gl-justify-end gl-gap-5"
      :class="{ 'gl-basis-1/3': !hasNotice() }"
    >
      <duo-chat-empty-state-header
        v-if="!isLoadingChatHistory || welcomeMessage"
        class="gl-text-center"
      >
        <h2 class="gl-heading-1 gl-mb-0" data-testid="chat-empty-state-heading">
          {{ heading }}
        </h2>
        <p
          v-if="secondaryText"
          class="gl-mb-0 gl-mt-3 gl-text-lg gl-text-subtle"
          data-testid="chat-empty-state-secondary-text"
        >
          {{ secondaryText }}
        </p>
      </duo-chat-empty-state-header>
      <slot name="notice"></slot>
    </div>
    <slot name="input"></slot>
    <div v-if="!hasNotice()" v-show="!hasDraft" data-testid="chat-empty-state-suggestions">
      <duo-chat-predefined-prompts
        v-if="overridePrompts"
        :prompts="overridePrompts"
        @click="sendPrompt"
      />
      <prompt-categories
        v-else-if="visibleCategories.length"
        :categories="visibleCategories"
        :initial-expanded-key="initialExpandedKey"
        @select="sendPrompt"
      />
    </div>
  </div>
</template>
