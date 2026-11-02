<script>
import { GlBadge, GlButton, GlPopover, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { truncate } from '~/lib/utils/text_utility';
import { s__, sprintf } from '~/locale';

const MAX_TAGS_SHOWN = 5;

const MAX_TAG_LENGTH = 32;

export default {
  name: 'ArtifactRegistryTagBadges',
  components: {
    GlBadge,
    GlButton,
    GlPopover,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    tags: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  data() {
    return {
      popoverTarget: uniqueId('tag-badges-popover-'),
    };
  },
  computed: {
    visibleTags() {
      return this.tags.slice(0, MAX_TAGS_SHOWN);
    },
    collapsedTags() {
      return this.tags.slice(MAX_TAGS_SHOWN);
    },
    moreTagsText() {
      return sprintf(s__('ArtifactRegistry|+%{count} more'), { count: this.collapsedTags.length });
    },
  },
  methods: {
    tagTitle(tag) {
      return truncate(tag, MAX_TAG_LENGTH);
    },
    tagTooltip(tag) {
      return tag === this.tagTitle(tag) ? null : tag;
    },
  },
};
</script>

<template>
  <ul
    v-if="tags.length"
    class="gl-m-0 gl-flex gl-list-none gl-flex-wrap gl-items-center gl-gap-3 gl-p-0"
    :aria-label="s__('ArtifactRegistry|Tags')"
    data-testid="tag-badges"
  >
    <gl-badge
      v-for="tag in visibleTags"
      :key="tag"
      v-gl-tooltip="tagTooltip(tag)"
      tag="li"
      variant="info"
      data-testid="tag-badge"
      >{{ tagTitle(tag) }}</gl-badge
    >

    <li v-if="collapsedTags.length">
      <gl-button
        :id="popoverTarget"
        category="tertiary"
        size="small"
        data-testid="tag-badges-more"
        >{{ moreTagsText }}</gl-button
      >

      <gl-popover :target="popoverTarget" :title="s__('ArtifactRegistry|All tags')">
        <div class="gl-flex gl-flex-wrap gl-gap-3">
          <gl-badge
            v-for="tag in collapsedTags"
            :key="tag"
            v-gl-tooltip="tagTooltip(tag)"
            variant="info"
            data-testid="tag-badges-collapsed"
            >{{ tagTitle(tag) }}</gl-badge
          >
        </div>
      </gl-popover>
    </li>
  </ul>
</template>
