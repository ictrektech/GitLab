<script>
import { uniqueId } from 'lodash-es';
import { GlDrawer, GlSkeletonLoader } from '@gitlab/ui';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';

export default {
  name: 'ProfileListDrawer',
  components: {
    GlDrawer,
    GlSkeletonLoader,
  },
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    title: {
      type: String,
      required: true,
    },
    narrow: {
      type: Boolean,
      required: false,
      default: false,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    error: {
      type: Boolean,
      required: false,
      default: false,
    },
    showList: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['close'],
  data() {
    return {
      titleId: uniqueId('profile-list-drawer-title-'),
    };
  },
  computed: {
    headerHeight() {
      return getContentWrapperHeight();
    },
  },
  DRAWER_Z_INDEX,
};
</script>

<template>
  <gl-drawer
    :header-height="headerHeight"
    :header-sticky="true"
    :open="open"
    :z-index="$options.DRAWER_Z_INDEX"
    :aria-labelledby="titleId"
    :class="['!gl-w-full', narrow ? '!gl-max-w-3xl' : '!gl-max-w-5xl']"
    @close="$emit('close')"
  >
    <template #title>
      <h4 :id="titleId" class="gl-my-0 gl-mr-3 gl-text-size-h2">{{ title }}</h4>
    </template>

    <slot></slot>

    <div v-if="loading" data-testid="profile-list-drawer-loader">
      <gl-skeleton-loader :lines="4" />
    </div>

    <div v-else-if="!error" class="gl-flex gl-h-full gl-gap-5 !gl-pb-0">
      <div
        v-if="showList"
        class="gl-border-r gl-w-1/3 gl-shrink-0 gl-overflow-y-auto focus-visible:gl-focus"
        role="region"
        tabindex="0"
        :aria-label="s__('SecurityConfiguration|Profiles')"
        data-testid="profile-list-drawer-list"
      >
        <slot name="list"></slot>
      </div>
      <div
        class="gl-min-w-0 gl-grow gl-overflow-y-auto gl-pb-5 focus-visible:gl-focus"
        role="region"
        tabindex="0"
        :aria-label="__('Details')"
        data-testid="profile-list-drawer-detail"
      >
        <slot name="detail"></slot>
      </div>
    </div>
  </gl-drawer>
</template>
