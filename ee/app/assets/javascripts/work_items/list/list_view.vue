<script>
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { DEFAULT_PAGE_SIZE } from '~/vue_shared/issuable/list/constants';
import ListView from '~/work_items/list/list_view.vue';
import { findStatusWidget } from '~/work_items/utils';
import WorkItemStatusBadge from '../components/shared/work_item_status_badge.vue';

export default {
  name: 'ListViewEE',
  components: {
    ListView,
    WorkItemStatusBadge,
  },
  mixins: [glListenersMixin, glSlotsMixin],
  props: {
    rootPageFullPath: {
      type: String,
      required: true,
    },
    queryVariables: {
      type: Object,
      required: true,
    },
    skipQuery: {
      type: Boolean,
      required: false,
      default: false,
    },
    error: {
      type: String,
      required: false,
      default: undefined,
    },
    showBulkEditSidebar: {
      type: Boolean,
      required: true,
    },
    checkedIssuableIds: {
      type: Array,
      required: false,
      default: () => [],
    },
    displaySettings: {
      type: Object,
      required: false,
      default: () => {},
    },
    pageSize: {
      type: Number,
      required: false,
      default: DEFAULT_PAGE_SIZE,
    },
    apiFilterParams: {
      type: Object,
      required: false,
      default: () => {},
    },
    sortKey: {
      type: String,
      required: true,
    },
    isSortKeyInitialized: {
      type: Boolean,
      required: true,
    },
    activeItem: {
      type: Object,
      required: false,
      default: null,
    },
    workItemsCount: {
      type: Number,
      required: false,
      default: 0,
    },
  },
  methods: {
    hasStatus(issuable) {
      return Boolean(findStatusWidget(issuable)?.status);
    },
    issuableStatusItem(issuable) {
      return findStatusWidget(issuable)?.status || {};
    },
  },
};
</script>

<template>
  <list-view v-bind="$props" v-on="glListeners()">
    <template v-if="glSlots()['list-empty-state']" #list-empty-state>
      <slot name="list-empty-state"></slot>
    </template>
    <template #custom-status="{ issuable = {} }">
      <work-item-status-badge v-if="hasStatus(issuable)" :item="issuableStatusItem(issuable)" />
    </template>
  </list-view>
</template>
