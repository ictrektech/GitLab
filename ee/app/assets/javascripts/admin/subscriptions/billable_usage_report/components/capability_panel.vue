<script>
import { GlTableLite } from '@gitlab/ui';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { createListFormat, formatNumber, n__, s__, sprintf } from '~/locale';

const CELL_CLASS = '!gl-px-5 !gl-py-3';

export default {
  name: 'CapabilityPanel',
  components: { CrudComponent, GlTableLite },
  props: {
    panel: {
      type: Object,
      required: true,
    },
  },
  computed: {
    totalText() {
      const { totalBillableEvents } = this.panel;

      return sprintf(
        n__(
          'SuperSonics|%{count} total billable event',
          'SuperSonics|%{count} total billable events',
          totalBillableEvents,
        ),
        { count: formatNumber(totalBillableEvents) },
      );
    },
    snapshotNote() {
      const names = this.panel.capabilities
        .filter(({ isSnapshot }) => isSnapshot)
        .map(({ name }) => name);

      if (!names.length) {
        return null;
      }

      return sprintf(
        s__(
          'SuperSonics|Excluded from the total (month-end counts, not billable events): %{capabilities}',
        ),
        { capabilities: this.$options.listFormatter.format(names) },
      );
    },
  },
  methods: {
    formatNumber,
  },
  fields: [
    {
      key: 'name',
      label: s__('SuperSonics|Capability'),
      thClass: `gl-w-5/12 ${CELL_CLASS}`,
      tdClass: CELL_CLASS,
    },
    {
      key: 'meteringUnit',
      label: s__('SuperSonics|Metering unit'),
      thClass: `gl-w-4/12 ${CELL_CLASS}`,
      tdClass: CELL_CLASS,
    },
    {
      key: 'quantity',
      label: s__('SuperSonics|Quantity'),
      thClass: `gl-w-3/12 gl-text-right ${CELL_CLASS}`,
      tdClass: `gl-text-right ${CELL_CLASS}`,
    },
  ],
  listFormatter: createListFormat({ style: 'long', type: 'conjunction' }),
  footerClass: 'gl-border-t gl-border-default !gl-px-5 !gl-py-4',
};
</script>

<template>
  <crud-component
    :title="panel.product"
    body-class="gl-p-0"
    :footer-class="$options.footerClass"
    data-testid="capability-panel"
  >
    <template #actions>
      <span class="gl-whitespace-nowrap gl-text-sm gl-text-subtle" data-testid="capability-total">
        {{ totalText }}
      </span>
    </template>

    <gl-table-lite :items="panel.capabilities" :fields="$options.fields" fixed class="gl-mb-0">
      <template #cell(quantity)="{ item }">{{ formatNumber(item.quantity) }}</template>
    </gl-table-lite>

    <template v-if="snapshotNote" #footer>
      <p class="gl-m-0 gl-text-sm gl-text-subtle" data-testid="snapshot-note">{{ snapshotNote }}</p>
    </template>
  </crud-component>
</template>
