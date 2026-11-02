<script>
import { GlTableLite } from '@gitlab/ui';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { formatNumber, n__, s__, sprintf } from '~/locale';

const CELL_CLASS = '!gl-px-5 !gl-py-3';

export default {
  name: 'SeatLinkPanel',
  components: { CrudComponent, GlTableLite },
  props: {
    summary: {
      type: Object,
      required: true,
    },
    licensedSeats: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    recordCountText() {
      const { recordCount } = this.summary;

      return sprintf(
        n__('SuperSonics|%{count} daily record', 'SuperSonics|%{count} daily records', recordCount),
        { count: formatNumber(recordCount) },
      );
    },
    items() {
      return [
        {
          highestBillableUsers: formatNumber(this.summary.highestBillableUsers),
          billableUsersOnLastDay: formatNumber(this.summary.billableUsersOnLastDay),
          licensedSeats: this.licensedSeats === null ? '-' : formatNumber(this.licensedSeats),
        },
      ];
    },
  },
  fields: [
    {
      key: 'highestBillableUsers',
      label: s__('SuperSonics|Highest billable users'),
      thClass: CELL_CLASS,
      tdClass: CELL_CLASS,
    },
    {
      key: 'billableUsersOnLastDay',
      label: s__('SuperSonics|Billable users on the last day'),
      thClass: CELL_CLASS,
      tdClass: CELL_CLASS,
    },
    {
      key: 'licensedSeats',
      label: s__('SuperSonics|Licensed seats'),
      thClass: `gl-text-right ${CELL_CLASS}`,
      tdClass: `gl-text-right ${CELL_CLASS}`,
    },
  ],
};
</script>

<template>
  <crud-component
    :title="s__('SuperSonics|Seat link')"
    body-class="gl-p-0"
    data-testid="seat-link-panel"
  >
    <template #actions>
      <span class="gl-whitespace-nowrap gl-text-sm gl-text-subtle" data-testid="seat-link-records">
        {{ recordCountText }}
      </span>
    </template>

    <gl-table-lite :items="items" :fields="$options.fields" fixed class="gl-mb-0" />
  </crud-component>
</template>
