<script>
import { GlResizeObserverDirective } from '@gitlab/ui';
import { debounce } from 'lodash-es';
import { hasHorizontalOverflow } from '~/lib/utils/dom_utils';
import AgentActorLine from './agent_actor_line.vue';

const MAX_STAGE = 1;
const MEASURE_DEBOUNCE_MS = 100;
const ROW_SELECTOR = '.note-headline-meta, .js-note-headline-meta';
const RESIZES_WITH_SELECTOR = '.note-header-info, .js-note-header-info';

export default {
  name: 'NoteAgentActorLine',
  components: {
    AgentActorLine,
  },
  props: {
    presence: {
      type: Object,
      required: true,
    },
  },
  emits: ['overflow'],
  data() {
    return {
      stage: 0,
      overflows: false,
    };
  },
  computed: {
    actorLineProps() {
      const { presence } = this;

      return {
        agentCatalogPath: presence.agentCatalogWebPath,
        sessionId: presence.sessionId,
        user: presence.user,
        triggerSource: presence.triggerSource,
        canViewSession: Boolean(presence.userPermissions?.readDuoWorkflow),
      };
    },
    withInitiator() {
      return this.stage === 0;
    },
  },
  created() {
    this.generation = 0;
    this.observedWidth = null;
    this.debouncedFit = debounce(this.fit, MEASURE_DEBOUNCE_MS);
  },
  mounted() {
    this.row = this.$el.closest(ROW_SELECTOR);
    this.fit();

    this.resizesWith = this.$el.closest(RESIZES_WITH_SELECTOR);
    if (!this.resizesWith || typeof ResizeObserver === 'undefined') return;

    GlResizeObserverDirective.bind(this.resizesWith, { value: this.handleResize });
  },
  beforeDestroy() {
    if (this.resizesWith) GlResizeObserverDirective.unbind(this.resizesWith);
    this.debouncedFit.cancel();
  },
  methods: {
    handleResize({ contentRect: { width } }) {
      const firstObservation = this.observedWidth === null;
      if (width === this.observedWidth) return;

      this.observedWidth = width;
      if (firstObservation) return;

      this.debouncedFit();
    },
    async fit() {
      this.generation += 1;

      this.stage = 0;
      this.setOverflow(false);
      await this.shrinkUntilItFits(this.generation);
    },
    async shrinkUntilItFits(generation) {
      await this.$nextTick();
      if (generation !== this.generation) return;
      if (!hasHorizontalOverflow(this.row)) return;

      if (this.stage < MAX_STAGE) {
        this.stage += 1;
        await this.shrinkUntilItFits(generation);
        return;
      }

      this.setOverflow(true);
    },
    setOverflow(overflows) {
      this.overflows = overflows;
      this.$emit('overflow', overflows);
    },
  },
};
</script>

<template>
  <span class="gl-contents">
    <span
      v-if="!overflows"
      aria-hidden="true"
      class="gl-text-subtle"
      data-testid="actor-line-separator"
      >&middot;</span
    >
    <span class="gl-mx-2">
      <agent-actor-line v-bind="actorLineProps" :with-initiator="withInitiator" />
    </span>
  </span>
</template>
