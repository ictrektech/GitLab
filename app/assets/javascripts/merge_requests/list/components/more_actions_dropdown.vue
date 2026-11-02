<script>
import {
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlDisclosureDropdownGroup,
  GlTooltipDirective,
} from '@gitlab/ui';
import { __ } from '~/locale';
import CsvImportExportButtons from './csv_import_export_buttons.vue';

export default {
  name: 'MoreActionsDropdown',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlDisclosureDropdownGroup,
    CsvImportExportButtons,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  provide: {
    showExportButton: true,
  },
  inject: {
    isSignedIn: {},
    isProject: { default: true },
    rssUrl: {},
  },
  props: {
    count: {
      type: Number,
      required: true,
    },
    exportVariables: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  data() {
    return {
      isDropdownVisible: false,
    };
  },
  computed: {
    moreActionsTooltip() {
      return this.isDropdownVisible ? '' : this.$options.i18n.toggleText;
    },
    subscribeToRSSItem() {
      return {
        text: this.$options.i18n.subscribeToRSS,
        href: this.rssUrl,
      };
    },
  },
  methods: {
    showDropdown() {
      this.isDropdownVisible = true;
    },
    hideDropdown() {
      this.isDropdownVisible = false;
    },
  },
  i18n: {
    toggleText: __('Actions'),
    subscribeToRSS: __('Subscribe to RSS feed'),
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    v-gl-tooltip.top.viewport="moreActionsTooltip"
    block
    placement="bottom-end"
    no-caret
    icon="ellipsis_v"
    text-sr-only
    category="tertiary"
    :toggle-text="$options.i18n.toggleText"
    @shown="showDropdown"
    @hidden="hideDropdown"
  >
    <template v-if="isProject">
      <csv-import-export-buttons
        v-if="isSignedIn"
        :issuable-count="count"
        :export-variables="exportVariables"
      />
      <gl-disclosure-dropdown-group :bordered="isSignedIn">
        <gl-disclosure-dropdown-item :item="subscribeToRSSItem" />
      </gl-disclosure-dropdown-group>
    </template>
    <gl-disclosure-dropdown-item v-else :item="subscribeToRSSItem" />
  </gl-disclosure-dropdown>
</template>
