<script>
import { GlAvatar, GlFormCheckbox, GlTableLite } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  TURN_ON_ACTION,
  canTurnOn,
  deniedOnInstance,
  needsSales,
  trialEnded,
} from 'ee/orbit/access/turn_on_action';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import { turnOnOfferText } from 'ee/orbit/utils/trial_offer_text';

export default {
  name: 'OrbitOffGroupsTable',
  components: { ContactSalesButton, GlAvatar, GlFormCheckbox, GlTableLite },
  inject: ['orbitPlatform'],
  props: {
    rows: { type: Array, required: true },
    selected: { type: Array, required: true },
  },
  emits: ['update:selected'],
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    selectableKeys() {
      return this.rows.filter((row) => canTurnOn(row.action)).map((row) => row.key);
    },
    allSelected() {
      return (
        this.selectableKeys.length > 0 &&
        this.selectableKeys.every((key) => this.selected.includes(key))
      );
    },
    someSelected() {
      return !this.allSelected && this.selectableKeys.some((key) => this.selected.includes(key));
    },
    showAvailability() {
      return this.rows.some((row) => this.showsSales(row) || this.availabilityText(row));
    },
    fields() {
      const fields = [{ key: 'name', label: s__('Orbit|Name'), tdClass: '!gl-align-middle' }];
      if (this.showAvailability) {
        fields.push({
          key: 'availability',
          label: s__('Orbit|Availability'),
          tdClass: '!gl-align-middle',
        });
      }
      if (!this.selectableKeys.length) return fields;

      return [
        { key: 'select', label: '', thClass: 'gl-w-7', tdClass: '!gl-align-middle' },
        ...fields,
      ];
    },
  },
  methods: {
    canTurnOn,
    showsSales(row) {
      return this.saas && needsSales(row.action);
    },
    isSelected(row) {
      return this.selected.includes(row.key);
    },
    rowClass(row) {
      return row && this.isSelected(row) ? 'gl-bg-feedback-info' : '';
    },
    rowAttributes(row) {
      return row ? { 'data-testid': `orbit-off-row-${row.key}` } : {};
    },
    toggleRow(row, checked) {
      const selected = checked
        ? [...this.selected, row.key]
        : this.selected.filter((key) => key !== row.key);

      this.$emit('update:selected', selected);
    },
    toggleAll(checked) {
      this.$emit('update:selected', checked ? this.selectableKeys : []);
    },
    statusText(row) {
      if (!this.saas) return '';

      switch (row.action) {
        case TURN_ON_ACTION.NOT_LICENSED:
          return s__('Orbit|GitLab Orbit is available on Premium and Ultimate');
        case TURN_ON_ACTION.NOT_AVAILABLE:
        case TURN_ON_ACTION.NOT_ELIGIBLE:
          return s__('Orbit|Contact sales to get GitLab Orbit for this group');
        case TURN_ON_ACTION.TRIAL_ENDED:
          return s__('Orbit|Trial ended');
        case TURN_ON_ACTION.CREDITS_USED_UP:
          return s__('Orbit|Credits used up');
        default:
          return '';
      }
    },
    availabilityText(row) {
      if (row.action === TURN_ON_ACTION.UNAVAILABLE) return s__('Orbit|Could not load');
      if (row.action === TURN_ON_ACTION.START_TRIAL) return turnOnOfferText(row.offer);
      if (!this.saas) return this.instanceAvailabilityText(row);

      return row.trialActive ? s__('Orbit|Trial active') : '';
    },
    instanceAvailabilityText(row) {
      if (deniedOnInstance(row.action)) return s__('Orbit|Ask your administrator');
      if (trialEnded(row.action)) return s__('Orbit|Trial ended');

      return row.trialActive ? s__('Orbit|Trial active') : '';
    },
  },
};
</script>

<template>
  <gl-table-lite
    :items="rows"
    :fields="fields"
    :tbody-tr-class="rowClass"
    :tbody-tr-attr="rowAttributes"
    primary-key="key"
    stacked="md"
    class="gl-mb-0"
    data-testid="orbit-off-groups-table"
  >
    <template #head(select)>
      <gl-form-checkbox
        class="gl-mb-0"
        :checked="allSelected"
        :indeterminate="someSelected"
        :aria-label="s__('Orbit|Select all groups')"
        data-testid="orbit-off-select-all"
        @change="toggleAll"
      />
    </template>

    <template #cell(select)="{ item: row }">
      <gl-form-checkbox
        v-if="canTurnOn(row.action)"
        class="gl-mb-0 gl-pt-2"
        :checked="isSelected(row)"
        :aria-label="row.name"
        data-testid="orbit-off-select-group"
        @change="toggleRow(row, $event)"
      />
    </template>

    <template #cell(name)="{ item: row }">
      <span class="gl-flex gl-items-center gl-gap-3">
        <gl-avatar :src="row.avatarUrl" :entity-name="row.name" :size="24" shape="rect" />
        <span class="gl-flex gl-min-w-0 gl-flex-col">
          <span class="gl-break-words gl-font-bold">{{ row.name }}</span>
          <span v-if="statusText(row)" class="gl-text-sm gl-text-subtle">
            {{ statusText(row) }}
          </span>
        </span>
      </span>
    </template>

    <template #cell(availability)="{ item: row }">
      <contact-sales-button
        v-if="showsSales(row)"
        glm-content="orbit-off-page"
        :namespace-id="row.namespaceId"
        size="small"
        data-testid="orbit-off-contact-sales"
      />
      <span v-else class="gl-text-subtle" data-testid="orbit-off-availability">
        {{ availabilityText(row) }}
      </span>
    </template>
  </gl-table-lite>
</template>
