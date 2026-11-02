import { __, s__ } from '~/locale';

export const NAME_FIELD = { key: 'name', label: __('Title') };

// Stacked rows drop an empty cell rather than print a label with nothing beside it: a
// custom dashboard whose creator was deleted has no author, and a system dashboard has no
// edit time. The query matches `stacked="md"`.
export const AUTHOR_FIELD = {
  key: 'author',
  label: s__('AnalyticsDashboards|Created by'),
  tdClass: (value, key, item) => (item.system || item.createdBy ? '' : '@max-md/panel:!gl-hidden'),
};

export const UPDATED_AT_FIELD = {
  key: 'updatedAt',
  label: s__('AnalyticsDashboards|Last edited'),
  tdClass: (updatedAt) => (updatedAt ? '' : '@max-md/panel:!gl-hidden'),
};

// No label, so the stacked mobile layout doesn't print a visible "Actions"
// beside the menu, which already has its own accessible name.
export const ACTIONS_FIELD = {
  key: 'actions',
  label: '',
  thClass: 'gl-w-0',
  tdClass: 'gl-text-right',
};
