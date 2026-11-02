<script>
import { GlIcon, GlPopover, GlSkeletonLoader, GlButton } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { SESSIONS_PAGE_SIZE } from '../constants';
import BoardCardSessionBadgeRow from './board_card_session_badge_row.vue';

export default {
  name: 'BoardCardSessionBadgePopover',
  components: {
    BoardCardSessionBadgeRow,
    GlButton,
    GlIcon,
    GlPopover,
    GlSkeletonLoader,
  },
  props: {
    target: {
      type: String,
      required: true,
    },
    sessions: {
      type: Array,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    queryError: {
      type: Boolean,
      required: true,
    },
    hasNextPage: {
      type: Boolean,
      required: true,
    },
    displayCount: {
      type: String,
      required: true,
    },
  },
  emits: ['close', 'retry', 'show-session', 'view-all'],
  computed: {
    popoverTitle() {
      return sprintf(
        n__(
          'DuoAgentPlatform|%{count} session',
          'DuoAgentPlatform|%{count} sessions',
          this.sessions.length,
        ),
        { count: this.displayCount },
      );
    },
    showingFirstText() {
      return sprintf(s__('DuoAgentPlatform|Showing most recent %{count}'), {
        count: SESSIONS_PAGE_SIZE,
      });
    },
  },
  methods: {
    focusFirstActionInPopover(event) {
      const tip = event?.relatedTarget;
      if (!tip?.classList.contains('show')) return;

      const focusable = tip.querySelector('a[href], button:not([disabled])') || this.$refs.body;
      focusable?.focus();
    },
  },
};
</script>

<template>
  <gl-popover
    :target="target"
    triggers="click blur"
    placement="bottom"
    data-testid="session-badge-popover"
    @shown="focusFirstActionInPopover"
  >
    <template #title>
      <div class="gl-flex gl-items-center gl-gap-2">
        <gl-icon name="session-ai" :size="16" />
        <span data-testid="popover-title">{{ popoverTitle }}</span>
      </div>
    </template>

    <div ref="body" tabindex="-1" data-testid="popover-body" @keydown.esc="$emit('close')">
      <div v-if="queryError" data-testid="popover-error">
        <p class="gl-mb-3 gl-text-subtle">
          {{ s__("DuoAgentPlatform|Couldn't load sessions.") }}
        </p>
        <gl-button size="small" data-testid="popover-retry-button" @click="$emit('retry')">
          {{ s__('DuoAgentPlatform|Retry') }}
        </gl-button>
      </div>

      <div v-else-if="isLoading" data-testid="popover-loading">
        <gl-skeleton-loader :lines="3" />
      </div>

      <template v-else>
        <board-card-session-badge-row
          v-for="session in sessions"
          :key="session.id"
          :session="session"
          @show-session="$emit('show-session', $event)"
        />

        <div
          class="gl-border-t gl-mt-2 gl-pt-2 gl-text-sm gl-text-subtle"
          data-testid="popover-footer"
        >
          <span v-if="hasNextPage" data-testid="popover-showing-first">
            {{ showingFirstText }} &middot;
          </span>
          <gl-button
            variant="link"
            class="gl-text-sm"
            data-testid="popover-view-all-link"
            @click.prevent="$emit('view-all')"
          >
            {{ s__('DuoAgentPlatform|View all sessions') }}
          </gl-button>
        </div>
      </template>
    </div>
  </gl-popover>
</template>
