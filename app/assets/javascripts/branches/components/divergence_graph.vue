<script>
import { GlTooltipDirective } from '@gitlab/ui';
import { sprintf, __ } from '~/locale';
import { MAX_COMMIT_COUNT } from '../constants';
import GraphBar from './graph_bar.vue';

export default {
  name: 'DivergenceGraph',
  components: {
    GraphBar,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    defaultBranch: {
      type: String,
      required: true,
    },
    distance: {
      type: Number,
      required: false,
      default: null,
    },
    aheadCount: {
      type: Number,
      required: true,
    },
    behindCount: {
      type: Number,
      required: true,
    },
    maxCommits: {
      type: Number,
      required: true,
    },
  },
  computed: {
    title() {
      if (this.distance) {
        return sprintf(
          __('More than %{number_commits_distance} commits different with %{default_branch}'),
          {
            number_commits_distance:
              this.distance >= MAX_COMMIT_COUNT ? `${MAX_COMMIT_COUNT - 1}+` : this.distance,
            default_branch: this.defaultBranch,
          },
        );
      }

      return sprintf(
        __(
          '%{number_commits_behind} commits behind %{default_branch}, %{number_commits_ahead} commits ahead',
        ),
        {
          number_commits_behind: this.behindCount,
          number_commits_ahead: this.aheadCount,
          default_branch: this.defaultBranch,
        },
      );
    },
  },
};
</script>

<template>
  <button
    v-gl-tooltip.viewport
    type="button"
    :title="title"
    class="divergence-graph gl-hidden gl-rounded-base gl-border-0 gl-bg-transparent !gl-px-3 gl-py-0 gl-text-inherit focus-visible:gl-focus @md/panel:gl-block"
  >
    <span class="gl-sr-only">{{ title }}</span>
    <template v-if="distance">
      <graph-bar :count="distance" :max-commits="maxCommits" position="full" aria-hidden="true" />
    </template>
    <template v-else>
      <graph-bar
        :count="behindCount"
        :max-commits="maxCommits"
        position="left"
        aria-hidden="true"
      />
      <div class="graph-separator !gl-float-left !gl-mt-2" aria-hidden="true"></div>
      <graph-bar
        :count="aheadCount"
        :max-commits="maxCommits"
        position="right"
        aria-hidden="true"
      />
    </template>
  </button>
</template>
