<script>
import { defineAsyncComponent } from 'vue';
import { GlTruncate } from '@gitlab/ui';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import IssuableMilestone from '~/vue_shared/issuable/list/components/issuable_milestone.vue';
import {
  findHealthStatusWidget,
  findIterationWidget,
  findMilestoneWidget,
  findStartAndDueDateWidget,
  findStatusWidget,
  findWeightWidget,
  getDisplayReference,
} from '~/work_items/utils';
import {
  COLUMN_CREATED_AT,
  COLUMN_DUE_DATE,
  COLUMN_HEALTH_STATUS,
  COLUMN_ITERATION,
  COLUMN_MILESTONE,
  COLUMN_REFERENCE,
  COLUMN_START_DATE,
  COLUMN_STATUS,
  COLUMN_WEIGHT,
} from '../constants';
import WorkItemWeightCell from './work_item_weight_cell.vue';

export default {
  name: 'WorkItemTableCell',
  components: {
    GlTruncate,
    IssuableMilestone,
    WorkItemWeightCell,
    IssueHealthStatus: defineAsyncComponent(
      () => import('ee_component/issues/components/issue_health_status.vue'),
    ),
    IssueIteration: defineAsyncComponent(
      () => import('ee_component/boards/components/issue_iteration.vue'),
    ),
    WorkItemStatusBadge: defineAsyncComponent(
      () => import('ee_component/work_items/components/shared/work_item_status_badge.vue'),
    ),
  },
  inject: ['rootPageFullPath'],
  props: {
    item: {
      type: Object,
      required: true,
    },
    columnKey: {
      type: String,
      required: true,
    },
  },
  computed: {
    // An item from the table's own namespace shows as `#iid`. An item from somewhere else
    // (e.g. another project on a group's table) keeps its full reference.
    reference() {
      return getDisplayReference(this.rootPageFullPath, this.item.reference);
    },
    status() {
      return findStatusWidget(this.item)?.status;
    },
    milestone() {
      return findMilestoneWidget(this.item)?.milestone;
    },
    iteration() {
      return findIterationWidget(this.item)?.iteration;
    },
    startDate() {
      return findStartAndDueDateWidget(this.item)?.startDate;
    },
    dueDate() {
      return findStartAndDueDateWidget(this.item)?.dueDate;
    },
    healthStatus() {
      return findHealthStatusWidget(this.item)?.healthStatus;
    },
    weightWidget() {
      return findWeightWidget(this.item);
    },
  },
  methods: {
    formatDate(date) {
      return localeDateFormat.asDate.format(newDate(date));
    },
  },
  COLUMN_CREATED_AT,
  COLUMN_DUE_DATE,
  COLUMN_HEALTH_STATUS,
  COLUMN_ITERATION,
  COLUMN_MILESTONE,
  COLUMN_REFERENCE,
  COLUMN_START_DATE,
  COLUMN_STATUS,
  COLUMN_WEIGHT,
};
</script>

<template>
  <span v-if="columnKey === $options.COLUMN_REFERENCE" data-testid="cell-reference">
    <gl-truncate :text="reference" position="middle" />
  </span>

  <work-item-status-badge
    v-else-if="columnKey === $options.COLUMN_STATUS && status"
    data-testid="cell-status"
    :item="status"
  />

  <work-item-weight-cell
    v-else-if="columnKey === $options.COLUMN_WEIGHT && weightWidget"
    :item="item"
  />

  <issuable-milestone
    v-else-if="columnKey === $options.COLUMN_MILESTONE && milestone"
    data-testid="cell-milestone"
    :milestone="milestone"
  />

  <issue-iteration
    v-else-if="columnKey === $options.COLUMN_ITERATION && iteration"
    data-testid="cell-iteration"
    :iteration="iteration"
  />

  <time
    v-else-if="columnKey === $options.COLUMN_START_DATE && startDate"
    :datetime="startDate"
    data-testid="cell-start-date"
  >
    {{ formatDate(startDate) }}
  </time>

  <time
    v-else-if="columnKey === $options.COLUMN_DUE_DATE && dueDate"
    :datetime="dueDate"
    data-testid="cell-due-date"
  >
    {{ formatDate(dueDate) }}
  </time>

  <issue-health-status
    v-else-if="columnKey === $options.COLUMN_HEALTH_STATUS && healthStatus"
    data-testid="cell-health-status"
    display-as-text
    text-size="sm"
    :health-status="healthStatus"
  />

  <time
    v-else-if="columnKey === $options.COLUMN_CREATED_AT && item.createdAt"
    :datetime="item.createdAt"
    data-testid="cell-created-at"
  >
    {{ formatDate(item.createdAt) }}
  </time>
</template>
