import { __, s__ } from '~/locale';
import {
  AUTOMATION_RUN_STATUS_META,
  FLOW_TRIGGER_TYPES,
  FLOW_TRIGGER_TYPE_SCHEDULE,
} from 'ee/ai/duo_agents_platform/constants';

export const KIND_SCHEDULED = 'scheduled';
export const KIND_EVENT = 'event';
export const DEFAULT_KIND = KIND_SCHEDULED;

export const STATUS_ON = 'on';
export const STATUS_OFF = 'off';

export const SORT_OPTIONS = [
  {
    id: 1,
    title: s__('DuoAgentsPlatform|Last run'),
    sortDirection: { descending: 'LAST_RUN_DESC', ascending: 'LAST_RUN_ASC' },
  },
  {
    id: 2,
    title: __('Name'),
    sortDirection: { descending: 'NAME_DESC', ascending: 'NAME_ASC' },
  },
  {
    id: 3,
    title: s__('DuoAgentsPlatform|Total runs'),
    sortDirection: { descending: 'TOTAL_RUNS_DESC', ascending: 'TOTAL_RUNS_ASC' },
  },
  {
    id: 4,
    title: __('Created date'),
    sortDirection: { descending: 'CREATED_DESC', ascending: 'CREATED_ASC' },
  },
  {
    id: 5,
    title: __('Updated date'),
    sortDirection: { descending: 'UPDATED_DESC', ascending: 'UPDATED_ASC' },
  },
];

export const DEFAULT_SORT = 'LAST_RUN_DESC';

export const SEARCH_MAX_LENGTH = 255;

export const LAST_RUN_OPTIONS = Object.entries(AUTOMATION_RUN_STATUS_META).map(
  ([status, { text }]) => ({ value: status.toLowerCase(), title: text, graphQL: status }),
);

export const EVENT_TYPE_OPTIONS = FLOW_TRIGGER_TYPES.filter(
  (type) => type !== FLOW_TRIGGER_TYPE_SCHEDULE,
);
