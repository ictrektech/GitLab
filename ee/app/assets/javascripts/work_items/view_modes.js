import { s__ } from '~/locale';
import { VIEW_MODE_BOARD } from '~/work_items/constants';
import { viewModeOptions as ceViewModeOptions } from '~/work_items/view_modes';

export const hasBoardViewMode = true;

export const viewModeOptions = [
  ...ceViewModeOptions,
  {
    value: VIEW_MODE_BOARD,
    text: s__('WorkItemPlanningView|Board'),
    props: { icon: 'columns' },
  },
];
