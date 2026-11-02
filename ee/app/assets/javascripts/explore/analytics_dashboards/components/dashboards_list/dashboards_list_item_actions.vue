<script>
import { GlDisclosureDropdownGroup, GlDisclosureDropdownItem, GlToastMixin } from '@gitlab/ui';
import CeDashboardsListItemActions from '~/explore/analytics_dashboards/components/dashboards_list/dashboards_list_item_actions.vue';
import { s__, sprintf } from '~/locale';
import DashboardDeleteModal from './dashboard_delete_modal.vue';

export default {
  name: 'DashboardsListItemActionsEE',
  components: {
    CeDashboardsListItemActions,
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    DashboardDeleteModal,
  },
  mixins: [GlToastMixin],
  props: {
    actionLabel: {
      type: String,
      required: true,
    },
    id: {
      type: String,
      required: false,
      default: '',
    },
    name: {
      type: String,
      required: false,
      default: '',
    },
    system: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  methods: {
    handleDeleteAction() {
      this.$refs.deleteModal.show();
    },
    handleDeleteSuccess() {
      this.$refs.deleteModal.hide();
      // Deleting is permanent and the card disappears, so confirm it happened,
      // matching the Copy link toast in the same menu.
      this.$toast.show(sprintf(s__('AnalyticsDashboards|%{name} deleted'), { name: this.name }));
    },
  },
  deleteDashboardItem: { text: s__('AnalyticsDashboards|Delete dashboard') },
};
</script>

<template>
  <ce-dashboards-list-item-actions v-bind="$attrs" :action-label="actionLabel">
    <template #ee-delete-modal>
      <dashboard-delete-modal
        v-if="!system"
        ref="deleteModal"
        :dashboard-id="id"
        :dashboard-name="name"
        @delete="handleDeleteSuccess"
      />
    </template>

    <template #ee-delete-actions>
      <gl-disclosure-dropdown-group v-if="!system" bordered>
        <gl-disclosure-dropdown-item
          :item="$options.deleteDashboardItem"
          icon="remove"
          variant="danger"
          data-testid="dashboard-delete-action"
          @action="handleDeleteAction"
        />
      </gl-disclosure-dropdown-group>
    </template>
  </ce-dashboards-list-item-actions>
</template>
