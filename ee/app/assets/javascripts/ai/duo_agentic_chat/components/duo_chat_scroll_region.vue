<script>
import { throttle } from 'lodash-es';
import { GlButton } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID } from 'ee/ai/constants';
import { isToolApprovalRequest, isUserMessage } from '../utils/messages_utils';

// Breathing room above a request pinned to the top of the window. Matches
// the 2rem top scrim (duo_chat.scss) so the request sits below its fade.
const TURN_START_TOP_GAP_PX = 32;

// How much of the previous response stays visible above a pinned request,
// for continuity with the turn before. The first request in a conversation
// has nothing to peek at and pins flush to the top gap.
const PREVIOUS_RESPONSE_PEEK_PX = 64;

// How many frames the pin keeps re-applying its scroll position over. The
// composer collapsing a sent prompt away takes several, and every frame of that
// re-flows the window the browser clamps the scroll against.
const PIN_SETTLE_ATTEMPTS = 5;

// Minimum content (spacer excluded) below the viewport before the
// scroll-to-bottom button appears.
const SCROLL_TO_BOTTOM_REVEAL_PX = 24;

// Turn boundaries are found through @gitlab/duo-ui's *internal* markup: it renders
// `.duo-chat-message-container` on every message and `[data-testid="tool-group"]`
// around each run of tool messages, and exports neither. A DOM change upstream
// degrades the pin to a plain scroll-to-bottom rather than breaking it; the
// "turn boundary markup contract" specs mount a real conversation to catch that.
const TURN_BOUNDARY_SELECTOR =
  '[data-testid="chat-messages"] .duo-chat-message-container, [data-testid="chat-messages"] [data-testid="tool-group"]';

export default {
  name: 'DuoChatScrollRegion',
  components: {
    GlButton,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    /**
     * The last message in the conversation. Changing it starts a turn: a request
     * pins to the top, a streamed response resizes the spacer below it.
     */
    lastMessage: {
      type: Object,
      required: false,
      default: null,
    },
    /**
     * Layout classes for the message list, which depend on the consumer's own
     * empty state and loading state.
     */
    contentClass: {
      type: [String, Array],
      required: false,
      default: '',
    },
    /**
     * Name of the message list's transition. An empty name doesn't disable the
     * transition; Vue 2 falls back to the default "v" prefix.
     */
    transitionName: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      scrolledToBottom: true,
      turnStartTop: null,
      turnFloorOffset: null,
      canScrollDown: false,
    };
  },
  computed: {
    turnBased() {
      return Boolean(this.glFeatures.duoChatRedesign);
    },
    /**
     * Floors the message list at one window measured from the pinned request, which
     * is what lets scrollTop reach the pin while the response is still short. A
     * percentage rather than a pixel height so the browser re-resolves it against the
     * live window: the composer collapsing on send, or growing again as the user
     * types, then moves the floor without any measuring here.
     */
    turnFloorStyle() {
      if (this.turnFloorOffset === null) {
        return {};
      }
      const offset = this.turnFloorOffset;
      if (offset === 0) {
        return { minHeight: '100%' };
      }
      // Signed explicitly: the offset is negative whenever the list starts below
      // the pin, and `calc(100% + -40px)` is a parse error in some engines.
      return { minHeight: `calc(100% ${offset < 0 ? '-' : '+'} ${Math.abs(offset)}px)` };
    },
  },
  watch: {
    lastMessage(newMessage, oldMessage) {
      if (this.turnBased) {
        this.handleTurnBasedScroll(newMessage, oldMessage);
        return;
      }
      if (this.scrolledToBottom || isUserMessage(newMessage)) {
        // only scroll to bottom on new message if the user hasn't explicitly scrolled up to view an earlier message
        // or if the user has just submitted a new message
        this.scrollToBottom();
      }
    },
  },
  created() {
    this.handleScrollingThrottled = throttle(this.handleScrolling, 200); // Assume a 200ms throttle for example
    this.followingBottom = false;
    this.lastScrollTop = 0;
  },
  mounted() {
    if (this.turnBased) {
      this.containerWidth = this.$refs.container.clientWidth;
      // Messages keep growing after they render (GFM hydration, code highlighting)
      // and the footer settles after mount, so a loaded thread's single
      // scroll-to-bottom lands short of the end.
      this.resizeObserver = new ResizeObserver(() => {
        // The empty state can overflow the window too, and must open at its top.
        if (this.followingBottom && this.lastMessage) this.$refs.anchor?.scrollIntoView?.();
        this.handleContainerResize();
      });
      this.resizeObserver.observe(this.$refs.container);
      this.resizeObserver.observe(this.$refs.messages.$el);

      // Content can resize without a scroll event or a new message, such as a tool
      // card collapsing, so re-check the button whenever the conversation's end
      // crosses the reveal threshold.
      this.contentEndObserver = new IntersectionObserver(() => this.refreshScrollToBottom(), {
        root: this.$refs.container,
        rootMargin: `0px 0px ${SCROLL_TO_BOTTOM_REVEAL_PX}px 0px`,
      });
      this.contentEndObserver.observe(this.$refs.contentEnd);
    }
    this.followBottom();
  },
  beforeDestroy() {
    this.resizeObserver?.disconnect();
    this.contentEndObserver?.disconnect();
  },
  methods: {
    handleScrolling(event) {
      const { scrollTop, offsetHeight, scrollHeight } = event.target;
      this.scrolledToBottom = scrollTop + offsetHeight >= scrollHeight;
      // Following only ever scrolls down, so scrolling up is the user's doing.
      if (scrollTop < this.lastScrollTop) this.followingBottom = false;
      this.lastScrollTop = scrollTop;
      this.refreshScrollToBottom();
    },
    // Where a node sits in the scroll container's own coordinates.
    offsetWithin(container, node) {
      return (
        node.getBoundingClientRect().top -
        container.getBoundingClientRect().top +
        container.scrollTop
      );
    },
    // The end of the conversation, which is above the blank room the turn floor
    // leaves below it. `scrollHeight` would include that room.
    contentBottom(container) {
      const { contentEnd } = this.$refs;
      return contentEnd ? this.offsetWithin(container, contentEnd) : container.scrollHeight;
    },
    // The scroll-to-bottom button shows while conversation content (the blank
    // room under the turn floor excluded) extends below the viewport.
    refreshScrollToBottom() {
      if (!this.turnBased) {
        return;
      }
      const { container } = this.$refs;
      // No conversation, no button: the empty state can overflow the window
      // on its own, and there is nothing to scroll down *to*.
      if (!container || !this.lastMessage) {
        this.canScrollDown = false;
        return;
      }
      const visibleBottom = container.scrollTop + container.clientHeight;
      this.canScrollDown =
        this.contentBottom(container) - visibleBottom > SCROLL_TO_BOTTOM_REVEAL_PX;
    },
    scrollToLatest() {
      const { container } = this.$refs;
      if (!container) {
        return;
      }
      container.scrollTo?.({
        top: this.contentBottom(container) - container.clientHeight,
        behavior: 'smooth',
      });
    },
    // A tick is not enough to see the footer settle: GlFormTextarea's auto-height
    // collapses the composer on send over a `requestAnimationFrame` and then one
    // more render, so a pin that only awaits microtasks measures the pre-collapse
    // height and the browser clamps the scroll back down.
    async nextFrame() {
      await new Promise((resolve) => {
        window.requestAnimationFrame(resolve);
      });
      await this.$nextTick();
    },
    async scrollToBottom() {
      await this.$nextTick();

      this.$refs.anchor?.scrollIntoView?.();
    },
    // Scrolls a loaded thread to the bottom and keeps it there while its messages
    // finish rendering, until the user scrolls up or sends a request.
    followBottom() {
      this.followingBottom = true;
      this.scrollToBottom();
    },
    // `rePinIfAtBottom` is called by the consumer via $refs when its footer resizes.
    // Ideally we would mark it as a public method via Vue's `expose` option, but that
    // makes `vm` private and several specs assert against it.
    // eslint-disable-next-line vue/no-unused-properties
    rePinIfAtBottom() {
      // The footer resized under the scroll container, but `lastMessage` did not
      // change, so the existing watcher will not re-pin.
      if (!this.scrolledToBottom) return;

      this.scrollToBottom();
    },
    // Turn-based auto-scroll (duo_chat_redesign): each sent request pins
    // near the top of the window, keeping the tail of the previous response
    // in view above it, and its response streams in below, so nothing moves
    // during a turn. A min-height floor on the message list gives a short turn
    // the scroll room the pin needs, and the response fills that room as it
    // streams. Manual scrolling is never overridden mid-stream; a pending
    // tool approval scrolls into view so it can be acted on.
    async handleTurnBasedScroll(newMessage, oldMessage) {
      if (!newMessage) {
        this.followingBottom = false;
        this.resetTurnScroll();
        return;
      }
      // The composer appends a sent request with the pending id, while a restored
      // thread's last request already carries its assigned one.
      if (
        isUserMessage(newMessage) &&
        newMessage.requestId === DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID
      ) {
        this.followingBottom = false;
        await this.pinTurnStartToTop();
        return;
      }
      if (!oldMessage) {
        // A bulk-loaded thread rather than a streamed turn.
        this.resetTurnScroll();
        this.followBottom();
        return;
      }
      // The floor holds the scroll geometry on its own, so a streamed chunk only
      // has to re-check whether the button is warranted.
      await this.$nextTick();
      this.refreshScrollToBottom();
      if (isToolApprovalRequest(newMessage) && !isToolApprovalRequest(oldMessage)) {
        // The floor keeps the pinned turn, approval included, within one
        // window of the very bottom, so this always reveals the approval.
        this.scrollToBottom();
      }
    },
    resetTurnScroll() {
      this.turnStartIndex = null;
      this.turnStartTop = null;
      this.turnFloorOffset = null;
      this.canScrollDown = false;
    },
    async pinTurnStartToTop() {
      await this.$nextTick();

      const { container, messages } = this.$refs;
      // The request that just landed is the last rendered message node:
      // the response only arrives later.
      const rendered = this.$el.querySelectorAll(TURN_BOUNDARY_SELECTOR);

      if (!container || !messages || !rendered.length) {
        this.scrollToBottom();
        return;
      }

      // Kept as an index so a re-measure never holds a node Vue has since replaced;
      // the turn's later boundaries only ever append after it.
      this.turnStartIndex = rendered.length - 1;
      this.measurePin();

      // The floor lands a tick later, and the composer keeps collapsing for a few
      // frames after that, so the first scroll assignment is clamped short.
      for (let attempt = 0; attempt < PIN_SETTLE_ATTEMPTS; attempt += 1) {
        // eslint-disable-next-line no-await-in-loop
        await this.nextFrame();
        container.scrollTop = this.turnStartTop;
      }
      this.refreshScrollToBottom();
    },
    measurePin() {
      const { container, messages } = this.$refs;
      const rendered = this.$el.querySelectorAll(TURN_BOUNDARY_SELECTOR);
      const turnStart = rendered[this.turnStartIndex];
      if (!turnStart) return;

      const previousTurnEnd = rendered[this.turnStartIndex - 1];
      const offsetOf = (node) => this.offsetWithin(container, node);

      let target = offsetOf(turnStart) - TURN_START_TOP_GAP_PX;
      if (previousTurnEnd) {
        // Stop the pin short of the top so the tail of the previous response
        // stays in view above the request, without ever revealing more than
        // that whole response.
        target = Math.max(
          target - PREVIOUS_RESPONSE_PEEK_PX,
          offsetOf(previousTurnEnd) - TURN_START_TOP_GAP_PX,
        );
      }
      this.turnStartTop = Math.max(0, target);
      // `calc(100% + offset)` on the list puts its bottom edge one window below the
      // pin, wherever the list starts, so the pinned position is exactly the scroll
      // limit and nothing below the conversation can shrink it away.
      this.turnFloorOffset = Math.round(this.turnStartTop - offsetOf(messages.$el));
    },
    // A width change, such as maximizing the panel, re-wraps the conversation and
    // moves the pinned request, so the floor's pixel offset goes stale. Height
    // changes need nothing: the floor's percentage already tracks them.
    async handleContainerResize() {
      const { container } = this.$refs;
      if (container.clientWidth === this.containerWidth) return;
      this.containerWidth = container.clientWidth;
      if (this.turnStartTop === null) return;

      const wasPinned = Math.abs(container.scrollTop - this.turnStartTop) <= 1;
      this.measurePin();
      if (wasPinned) {
        await this.$nextTick();
        container.scrollTop = this.turnStartTop;
      }
      this.refreshScrollToBottom();
    },
  },
};
</script>
<template>
  <div class="gl-relative gl-flex gl-min-h-0 gl-flex-grow gl-flex-col gl-bg-inherit">
    <div
      ref="container"
      class="panel-content-inner gl-flex gl-flex-grow gl-flex-col gl-overscroll-contain gl-bg-inherit"
      :class="{
        /* Replaces the panel's border-on-scroll strip with background-color
           fades at both scroll edges (see duo_chat.scss). */
        'duo-chat-scroll-scrims': turnBased,
        /* .panel-content-inner reserves a scrollbar gutter on the right edge
           only, which reads as the centered empty state sitting off-center;
           reserve both edges so the content box stays symmetric. */
        '[scrollbar-gutter:stable_both-edges]': turnBased,
        /* Native scroll anchoring fights the pinned request: with the spacer
           in view it re-anchors to nodes below the streaming message and
           bumps scrollTop line by line. Scroll position is fully managed
           here, so suppress it. */
        '[overflow-anchor:none]': turnBased,
      }"
      data-testid="chat-history"
      @scroll="handleScrollingThrottled"
    >
      <slot name="header"></slot>

      <transition-group
        ref="messages"
        mode="out-in"
        tag="section"
        :name="transitionName"
        :css="!turnBased"
        :style="turnFloorStyle"
        data-testid="chat-messages"
        :class="[
          'duo-chat-history gl-mx-auto gl-w-full gl-max-w-4xl gl-px-4',
          contentClass,
          /* An explicit min-height replaces the automatic minimum size that keeps a
             flex item from shrinking under its own content, so without this the list
             shrinks to the floor and its bottom padding strands mid-conversation. */
          { 'gl-shrink-0': turnBased },
        ]"
      >
        <!-- Every root node placed in this slot becomes a direct child of the
        transition-group, so each one must be keyed: the move check reads the direct
        children and an unkeyed comment node there makes it throw on `cloneNode`. -->
        <slot></slot>
        <!-- Marks where the conversation ends. The turn floor leaves blank room
        below it, which `scrollHeight` counts and the scroll-to-bottom button must
        not. -->
        <div key="content-end" ref="contentEnd" data-testid="content-end"></div>
      </transition-group>
      <!-- Outside the list, so it stays at the true bottom of the scroll container
      rather than above the turn floor's blank room. -->
      <div ref="anchor" class="scroll-anchor"></div>
    </div>
    <!-- The wrapper provides an opaque backdrop: the button's own translucent
         background would let the conversation show through. It stacks above the
         bottom scroll scrim, which fades in under the same condition. -->
    <div
      v-if="canScrollDown"
      class="gl-absolute gl-bottom-3 gl-left-1/2 gl-z-3 -gl-translate-x-1/2 gl-rounded-full gl-bg-default gl-shadow-md"
    >
      <gl-button
        class="!gl-rounded-full"
        icon="arrow-down"
        category="secondary"
        :aria-label="s__('DuoAgenticChat|Scroll to bottom')"
        data-testid="scroll-to-bottom-button"
        @click="scrollToLatest"
      />
    </div>
  </div>
</template>
