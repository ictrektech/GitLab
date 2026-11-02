import { uniq, uniqBy } from 'lodash-es';
import { __, n__, s__, sprintf } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import {
  formatTimezone,
  getWeekdayNames,
  padWithZeros,
} from '~/lib/utils/datetime/date_format_utility';
import { localeDateFormat } from '~/lib/utils/datetime/locale_dateformat';
import { isGid, getIdFromGraphQLId } from '~/graphql_shared/utils';
import {
  AGENT_PLATFORM_STATUS_ICON,
  FILTER_FIELD_ACTION,
  FILTER_FIELD_PIPELINE_STATUS,
  FILTER_FIELD_WORK_ITEM_STATUS_NAME,
  FILTER_FIELD_WORK_ITEM_TYPE_ID,
  FILTER_FIELD_WORK_ITEM_SOFTWARE_FACTORY_ENABLED,
  FILTER_OPERATOR_IN,
  FLOW_TRIGGER_MODE_EVENT,
  FLOW_TRIGGER_MODE_SCHEDULE,
  FLOW_TRIGGER_TYPES,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST_READY,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST_CODE_CONFLICT,
  FLOW_TRIGGER_TYPE_PIPELINE_HOOKS,
  FLOW_TRIGGER_TYPE_SCHEDULE,
  FLOW_TRIGGER_TYPE_WORK_ITEM,
  MERGE_REQUEST_ACTIONS,
  PIPELINE_HOOK_STATUSES,
  SCHEDULE_DAY_OF_MONTH_MAX,
  SCHEDULE_DAY_OF_MONTH_MIN,
  SCHEDULE_DAY_OF_WEEK_MAX,
  SCHEDULE_DAY_OF_WEEK_MIN,
  SCHEDULE_DEFAULT_TIMEZONE,
  SCHEDULE_FIELD_DAY_OF_MONTH,
  SCHEDULE_FIELD_DAY_OF_WEEK,
  SCHEDULE_FIELD_HOUR,
  SCHEDULE_FIELD_MINUTE,
  SCHEDULE_FIELD_TIMEZONE,
  SCHEDULE_FREQUENCY_DAILY,
  SCHEDULE_FREQUENCY_EVERY_15_MINUTES,
  SCHEDULE_FREQUENCY_EVERY_30_MINUTES,
  SCHEDULE_FREQUENCY_FIELDS,
  SCHEDULE_FREQUENCY_HOURLY,
  SCHEDULE_FREQUENCY_MONTHLY,
  SCHEDULE_FREQUENCY_WEEKDAYS,
  SCHEDULE_FREQUENCY_WEEKLY,
  SCHEDULE_HOUR_MAX,
  SCHEDULE_HOUR_MIN,
  SCHEDULE_MINUTE_VALUES,
  WORK_ITEM_ACTION_STATUS_CHANGED,
  WORK_ITEM_ACTIONS,
  AGENT_PLATFORM_SESSION_RETENTION_LENGTH,
} from '../constants';

export const getNumericId = (id) => {
  if (!id) return null;
  return isGid(id) ? getIdFromGraphQLId(id) : id;
};

export const getSessionRetentionCutoff = () => {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - AGENT_PLATFORM_SESSION_RETENTION_LENGTH);
  return cutoff.toISOString();
};

export { getToolData, getMessageData } from '../icon_utils';

export const formatAgentDefinition = (agentDefinition) => {
  return humanize(agentDefinition || s__('DuoAgentsPlatform|Agent session'));
};

export const formatSessionTitleWithId = (title, id) => {
  return `${title} #${id}`;
};

export const formatAgentFlowNameWithId = (agentDefinition, id) => {
  return formatSessionTitleWithId(formatAgentDefinition(agentDefinition), id);
};

export const formatFlowLabel = (name, version) => (version ? `${name} · ${version}` : name);

export const formatAgentFlowTitle = (title, agentDefinition) =>
  title?.trim() ? title : formatAgentDefinition(agentDefinition);

export const formatAgentFlowTitleTooltip = (title, id) =>
  sprintf(s__('DuoAgentsPlatform|%{title} %{id}'), { title, id }, false);

// `title` defaults to `workflow_definition` when no custom title exists (e.g. null/legacy sessions).
// Equal values mean no custom title was generated.
export const validateTitleIsNotDefinition = ({ title, agentDefinition } = {}) =>
  Boolean(title?.trim()) && title !== agentDefinition;

export const formatSessionLabel = ({ title, agentDefinition, flowName, id } = {}) =>
  validateTitleIsNotDefinition({ title, agentDefinition })
    ? formatSessionTitleWithId(title, id)
    : formatAgentFlowNameWithId(flowName, id);

export const formatSessionTooltip = ({ title, agentDefinition, flowName, id } = {}) =>
  formatAgentFlowTitleTooltip(
    validateTitleIsNotDefinition({ title, agentDefinition })
      ? title
      : formatAgentDefinition(flowName),
    id,
  );

export const formatAgentStatus = (status) => {
  return status ? humanize(status.toLowerCase()) : s__('DuoAgentsPlatform|Unknown');
};

export const getAgentStatusIconVariant = (status) => {
  return AGENT_PLATFORM_STATUS_ICON[status] || AGENT_PLATFORM_STATUS_ICON.UNKNOWN;
};

const STATUS_VARIANT_CLASSES = {
  success: { fill: 'gl-fill-status-success', text: 'gl-text-status-success' },
  danger: { fill: 'gl-fill-status-danger', text: 'gl-text-status-danger' },
  info: { fill: 'gl-fill-status-info', text: 'gl-text-status-info' },
  warning: { fill: 'gl-fill-status-warning', text: 'gl-text-status-warning' },
  subtle: { fill: 'gl-fill-status-neutral', text: 'gl-text-status-neutral' },
};

const getStatusVariantClasses = (status) =>
  STATUS_VARIANT_CLASSES[getAgentStatusIconVariant(status).variant] ??
  STATUS_VARIANT_CLASSES.subtle;

export const getAgentStatusFillClass = (status) => getStatusVariantClasses(status).fill;
export const getAgentStatusTextClass = (status) => getStatusVariantClasses(status).text;

export const getNamespaceDatasetProperties = (dataset, properties) =>
  properties.reduce((acc, prop) => {
    acc[prop] = dataset[prop];
    return acc;
  }, {});

export const parseExecutorLogUrls = (urls = []) =>
  urls
    .map((url) => ({ webPath: url, iid: url.split('/').pop() }))
    .filter(({ iid }) => iid && !Number.isNaN(Number(iid)));

export const ciJobsLabel = (count) =>
  n__('DuoAgentPlatform|CI job', 'DuoAgentPlatform|CI jobs', count);

export const formatDate = (isoString) => {
  if (!isoString) return '';

  try {
    return localeDateFormat.asDate.format(new Date(isoString));
  } catch {
    return '';
  }
};

/**
 * Extracts the values of the single `{ field, operator: 'in', value: [...] }` rule for `field`
 * in a trigger filter scope. With `options`, only values in that option set are kept; without,
 * only values that pass `isValue` are kept (for fields whose value set is not known statically).
 *
 * The filter is shaped like `{ <scope>: { rules: [{ field, operator, value }, ...] } }`
 * (validated by app/validators/json_schemas/filter.json); rules for other fields are ignored.
 * Returns `[]` when the filter is missing, malformed, or `field` has no single matching rule.
 * Two rules for the same field are ambiguous and treated as no rule, not merged.
 */
export const parseFilterRuleValues = ({
  filter,
  scope,
  field,
  options,
  isValue = (value) => typeof value === 'string',
}) => {
  const rules = filter?.[scope]?.rules;
  if (!Array.isArray(rules)) return [];

  const matchingRules = rules.filter(
    (rule) => rule.field === field && rule.operator === FILTER_OPERATOR_IN,
  );
  if (matchingRules.length !== 1 || !Array.isArray(matchingRules[0].value)) return [];

  const [rule] = matchingRules;
  if (!options) return rule.value.filter(isValue);

  const allowedValues = options.map((option) => option.value);
  return rule.value.filter((value) => allowedValues.includes(value));
};

/**
 * Maps selected option values to their human-readable labels, preserving option order.
 * Used to render the trigger token summary on the catalog item page.
 */
const selectedOptions = (options, values) =>
  options.filter((option) => values.includes(option.value));

const selectedOptionLabels = (options, values) =>
  selectedOptions(options, values).map((option) => option.text);

export const parsePipelineStatusFilter = (filter) =>
  parseFilterRuleValues({
    filter,
    scope: FLOW_TRIGGER_TYPE_PIPELINE_HOOKS.value,
    field: FILTER_FIELD_PIPELINE_STATUS,
    options: PIPELINE_HOOK_STATUSES,
  });

export const pipelineStatusLabels = (filter) =>
  selectedOptionLabels(PIPELINE_HOOK_STATUSES, parsePipelineStatusFilter(filter));

const FOLDABLE_MERGE_REQUEST_ACTIONS = MERGE_REQUEST_ACTIONS.filter(
  (action) => action.eventTypeValueInt != null,
);

const buildMergeRequestActionFilter = (filter, actions) => ({
  ...(filter || {}),
  [FLOW_TRIGGER_TYPE_MERGE_REQUEST.value]: {
    rules: [{ field: FILTER_FIELD_ACTION, operator: FILTER_OPERATOR_IN, value: actions }],
  },
});

const filterWithoutMergeRequest = (filter) =>
  Object.fromEntries(
    Object.entries(filter || {}).filter(([key]) => key !== FLOW_TRIGGER_TYPE_MERGE_REQUEST.value),
  );

/**
 * Extracts the selected merge_request action values from a trigger's filter JSONB.
 *
 * The filter is shaped like
 *   `{ merge_request: { rules: [{ field: 'action', operator: 'in', value: [...] }] } }`.
 * Returns the validated action values (e.g. `['ready', 'approved']`), or `[]` if the
 * filter is missing, malformed, or contains values outside the known action set.
 */
export const parseMergeRequestActionFilter = (filter) => {
  const rules = filter?.[FLOW_TRIGGER_TYPE_MERGE_REQUEST.value]?.rules;
  if (!Array.isArray(rules) || rules.length !== 1) return [];

  const [rule] = rules;
  if (
    rule.field !== FILTER_FIELD_ACTION ||
    rule.operator !== FILTER_OPERATOR_IN ||
    !Array.isArray(rule.value)
  ) {
    return [];
  }

  const allowedValues = MERGE_REQUEST_ACTIONS.map((action) => action.value);
  return rule.value.filter((value) => allowedValues.includes(value));
};

export const parseWorkItemActionFilter = (filter) =>
  parseFilterRuleValues({
    filter,
    scope: FLOW_TRIGGER_TYPE_WORK_ITEM.value,
    field: FILTER_FIELD_ACTION,
    options: WORK_ITEM_ACTIONS,
  });

/**
 * Returns the human-readable labels for the merge_request actions selected in a filter,
 * e.g. `['Ready', 'Approved']`. Used to render the trigger token summary on the catalog item page.
 */
export const mergeRequestActionLabels = (filter) =>
  selectedOptionLabels(MERGE_REQUEST_ACTIONS, parseMergeRequestActionFilter(filter));

/**
 * Returns the status names a work_item filter is scoped to via a
 * `{ field: 'status.name', operator: 'in', value: [...] }` rule, or `[]` when there is none.
 */
export const parseWorkItemStatusNamesFilter = (filter) =>
  parseFilterRuleValues({
    filter,
    scope: FLOW_TRIGGER_TYPE_WORK_ITEM.value,
    field: FILTER_FIELD_WORK_ITEM_STATUS_NAME,
  });

/**
 * Statuses are defined per work item type, and triggers match and set a status by name,
 * so each name appears once. Takes the result of getStatuses from ee/work_items/utils.
 */
export const workItemStatusNameOptions = (statuses) =>
  uniqBy(statuses, 'name').map(({ name }) => ({ value: name, text: name }));

/**
 * Type rules hold integer IDs, the numeric part of the type's GraphQL ID. A string such as "5"
 * never matches the integer in the event, so it is dropped here, and the model rejects it.
 */
export const parseWorkItemTypeIdsFilter = (filter) =>
  parseFilterRuleValues({
    filter,
    scope: FLOW_TRIGGER_TYPE_WORK_ITEM.value,
    field: FILTER_FIELD_WORK_ITEM_TYPE_ID,
    isValue: Number.isInteger,
  });

/**
 * Returns `true` or `false` for a `software_factory_enabled` rule, or `null` when there is none.
 * A rule with both values matches every work item, so it counts as no rule.
 */
export const parseWorkItemSoftwareFactoryFilter = (filter) => {
  const values = uniq(
    parseFilterRuleValues({
      filter,
      scope: FLOW_TRIGGER_TYPE_WORK_ITEM.value,
      field: FILTER_FIELD_WORK_ITEM_SOFTWARE_FACTORY_ENABLED,
      isValue: (value) => typeof value === 'boolean',
    }),
  );

  return values.length === 1 ? values[0] : null;
};

/**
 * Takes `namespace.workItemTypes.nodes` from the namespaceWorkItemTypes query.
 */
export const workItemTypeOptions = (workItemTypes) =>
  workItemTypes.map(({ id, name }) => ({ value: getIdFromGraphQLId(id), text: name }));

/**
 * Returns the work item types with the given IDs, or every type when no ID is given,
 * because a trigger without a type rule runs for every type.
 */
export const filterWorkItemTypesByIds = (workItemTypes, typeIds) =>
  typeIds.length
    ? workItemTypes.filter(({ id }) => typeIds.includes(getIdFromGraphQLId(id)))
    : workItemTypes;

/**
 * Matches Ai::FlowTrigger#status_changed_with_statuses?, which the on-finish settings require:
 * Status changed as the only action, at least one status, and a scope that matches all rules.
 * Skips the known-actions filter of parseWorkItemActionFilter, because the model rejects any extra value.
 * Non-string values are dropped here, and the model rejects a filter that has them.
 */
export const isWorkItemStatusChangedWithStatuses = (filter) => {
  const scope = FLOW_TRIGGER_TYPE_WORK_ITEM.value;
  if ((filter?.[scope]?.match || 'all') !== 'all') return false;

  const actions = parseFilterRuleValues({ filter, scope, field: FILTER_FIELD_ACTION });

  return (
    actions.length === 1 &&
    actions[0] === WORK_ITEM_ACTION_STATUS_CHANGED.value &&
    parseWorkItemStatusNamesFilter(filter).length > 0
  );
};

export const workItemActionLabels = (filter) => {
  const statusNames = parseWorkItemStatusNamesFilter(filter);
  const typeCount = parseWorkItemTypeIdsFilter(filter).length;
  const softwareFactoryEnabled = parseWorkItemSoftwareFactoryFilter(filter);

  const labels = selectedOptions(WORK_ITEM_ACTIONS, parseWorkItemActionFilter(filter)).map(
    (action) =>
      statusNames.length && action.value === WORK_ITEM_ACTION_STATUS_CHANGED.value
        ? sprintf(s__('DuoAgentsPlatform|Status changed to %{statusNames}'), {
            statusNames: statusNames.join(', '),
          })
        : action.text,
  );

  // The type names need a query, so the summary shows only how many types the rule selects.
  if (labels.length && typeCount) {
    labels.push(
      sprintf(
        n__(
          'DuoAgentsPlatform|%{count} work item type',
          'DuoAgentsPlatform|%{count} work item types',
          typeCount,
        ),
        { count: typeCount },
      ),
    );
  }

  if (labels.length && softwareFactoryEnabled !== null) {
    labels.push(
      softwareFactoryEnabled
        ? s__('DuoAgentsPlatform|Software Factory work items')
        : s__('DuoAgentsPlatform|Other work items'),
    );
  }

  return labels;
};

// Every event type that can appear in a trigger's event_types, including the foldable
// merge_request actions (4/5) that are not offered as standalone listbox options.
const ALL_FLOW_TRIGGER_TYPES = [
  ...FLOW_TRIGGER_TYPES,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST_READY,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST_CODE_CONFLICT,
];

/**
 * Maps string event-type values (e.g. `'merge_request'`) to their numeric ids, dropping
 * any unknown values. Lets string-keyed callers reuse the int-keyed fold helpers below.
 */
export const eventTypeValuesToInts = (values = []) =>
  values
    .map((value) => ALL_FLOW_TRIGGER_TYPES.find((type) => type.value === value)?.valueInt)
    .filter((valueInt) => valueInt != null);

/**
 * Inverse of `eventTypeValuesToInts`: maps numeric event-type ids back to their string
 * values, dropping any unknown ids.
 */
export const eventTypeIntsToValues = (ints = []) =>
  ints
    .map((valueInt) => ALL_FLOW_TRIGGER_TYPES.find((type) => type.valueInt === valueInt)?.value)
    .filter(Boolean);

/**
 * Inverse of `normalizeMergeRequestEventTypes`: restores each foldable action to its own
 * event type (`ready` -> 4, `code_conflict` -> 5) on save, so only the non-foldable actions
 * (`approved`, `merged`) are ever stored under `merge_request` (6). Idempotent and pure.
 *
 * The card's single goal is copied onto every event type it splits into, because
 * Ai::FlowTrigger#goal_keys_match_event_types rejects a goal for an unused event type.
 */
export const denormalizeMergeRequestEventTypes = ({ eventTypes, filter, goals }) => {
  const mrId = FLOW_TRIGGER_TYPE_MERGE_REQUEST.valueInt;
  const mrValue = FLOW_TRIGGER_TYPE_MERGE_REQUEST.value;
  const currentGoals = goals || {};
  const actions = parseMergeRequestActionFilter(filter);

  const toRestore = FOLDABLE_MERGE_REQUEST_ACTIONS.filter((action) =>
    actions.includes(action.value),
  );

  if (!toRestore.length) {
    return { eventTypes, filter: filter || {}, goals: currentGoals };
  }

  const restoredValues = toRestore.map((action) => action.value);
  const remainingActions = actions.filter((action) => !restoredValues.includes(action));
  const nextFilter = remainingActions.length
    ? buildMergeRequestActionFilter(filterWithoutMergeRequest(filter), remainingActions)
    : filterWithoutMergeRequest(filter);

  let nextEventTypes = [...(eventTypes || [])];
  toRestore.forEach(({ eventTypeValueInt }) => {
    if (!nextEventTypes.includes(eventTypeValueInt)) nextEventTypes.push(eventTypeValueInt);
  });
  if (!remainingActions.length) {
    nextEventTypes = nextEventTypes.filter((id) => id !== mrId);
  }

  const nextGoals = { ...currentGoals };
  if (currentGoals[mrValue]) {
    eventTypeIntsToValues(toRestore.map((action) => action.eventTypeValueInt)).forEach((name) => {
      nextGoals[name] = currentGoals[mrValue];
    });
    if (!remainingActions.length) {
      delete nextGoals[mrValue];
    }
  }

  return { eventTypes: nextEventTypes, filter: nextFilter, goals: nextGoals };
};

/**
 * Folds `merge_request_ready` (4) and `merge_request_code_conflict` (5) into `merge_request`
 * (6) with the matching action filter, so the field only deals with the consolidated shape.
 * Idempotent and pure.
 *
 * Their goals collapse too. A goal already on `merge_request` wins, because that is the
 * card's own goal; otherwise the first folded goal is kept.
 */
export const normalizeMergeRequestEventTypes = ({ eventTypes, filter, goals }) => {
  const types = Array.isArray(eventTypes) ? [...eventTypes] : eventTypes;
  const currentGoals = goals || {};
  if (!Array.isArray(types)) return { eventTypes, filter: filter || {}, goals: currentGoals };

  const mrId = FLOW_TRIGGER_TYPE_MERGE_REQUEST.valueInt;
  const mrValue = FLOW_TRIGGER_TYPE_MERGE_REQUEST.value;
  const toFold = FOLDABLE_MERGE_REQUEST_ACTIONS.filter((action) =>
    types.includes(action.eventTypeValueInt),
  );

  if (!toFold.length) {
    return { eventTypes: types, filter: filter || {}, goals: currentGoals };
  }

  const eventTypeValueInts = toFold.map((action) => action.eventTypeValueInt);
  const filteredTypes = types.filter((id) => !eventTypeValueInts.includes(id));
  if (!filteredTypes.includes(mrId)) {
    filteredTypes.push(mrId);
  }

  const existingActions = parseMergeRequestActionFilter(filter);
  const foldedActions = toFold
    .map((action) => action.value)
    .filter((value) => !existingActions.includes(value));

  const foldedNames = eventTypeIntsToValues(eventTypeValueInts);
  const nextGoals = { ...currentGoals };
  const foldedGoal =
    currentGoals[mrValue] ?? foldedNames.map((name) => currentGoals[name]).find(Boolean);
  foldedNames.forEach((name) => delete nextGoals[name]);
  if (foldedGoal) {
    nextGoals[mrValue] = foldedGoal;
  }

  return {
    eventTypes: filteredTypes,
    filter: buildMergeRequestActionFilter(filter, [...existingActions, ...foldedActions]),
    goals: nextGoals,
  };
};

const randomInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));

const randomFrom = (values) => values[Math.floor(Math.random() * values.length)];

// Returns the plain schedule object described in `constants.js`, or null when absent.
export const parseScheduleConfig = (filter) => filter?.[FLOW_TRIGGER_TYPE_SCHEDULE.value] ?? null;

const isIntegerInRange = (value, min, max) =>
  Number.isInteger(value) && value >= min && value <= max;

const isScheduleFieldValid = (field, value) => {
  switch (field) {
    case SCHEDULE_FIELD_MINUTE:
      return SCHEDULE_MINUTE_VALUES.includes(value);
    case SCHEDULE_FIELD_HOUR:
      return isIntegerInRange(value, SCHEDULE_HOUR_MIN, SCHEDULE_HOUR_MAX);
    case SCHEDULE_FIELD_DAY_OF_WEEK:
      return isIntegerInRange(value, SCHEDULE_DAY_OF_WEEK_MIN, SCHEDULE_DAY_OF_WEEK_MAX);
    case SCHEDULE_FIELD_DAY_OF_MONTH:
      return isIntegerInRange(value, SCHEDULE_DAY_OF_MONTH_MIN, SCHEDULE_DAY_OF_MONTH_MAX);
    case SCHEDULE_FIELD_TIMEZONE:
      return typeof value === 'string' && value.length > 0;
    default:
      return false;
  }
};

export const isScheduleConfigValid = (filter) => {
  const schedule = parseScheduleConfig(filter);
  const fields = schedule && SCHEDULE_FREQUENCY_FIELDS[schedule.frequency];
  if (!fields) return false;

  return fields.every((field) => isScheduleFieldValid(field, schedule[field]));
};

const scheduleTime = ({ hour, minute }) => padWithZeros(hour, minute).join(':');

export const scheduleTimezoneLabel = (filter, timezoneData = []) => {
  if (!isScheduleConfigValid(filter)) return '';

  const { frequency, timezone } = parseScheduleConfig(filter);
  if (!SCHEDULE_FREQUENCY_FIELDS[frequency].includes(SCHEDULE_FIELD_TIMEZONE)) return '';

  const match = timezoneData.find(({ identifier }) => identifier === timezone);

  return match ? formatTimezone(match) : timezone;
};

const SCHEDULE_LABEL_MESSAGES = {
  [SCHEDULE_FREQUENCY_EVERY_15_MINUTES]: () => s__('DuoAgentsPlatform|Every 15 minutes'),
  [SCHEDULE_FREQUENCY_EVERY_30_MINUTES]: () => s__('DuoAgentsPlatform|Every 30 minutes'),
  [SCHEDULE_FREQUENCY_HOURLY]: (withTimezone) =>
    withTimezone
      ? s__('DuoAgentsPlatform|Hourly at %{minute} minutes past the hour %{timezone}')
      : s__('DuoAgentsPlatform|Hourly at %{minute} minutes past the hour'),
  [SCHEDULE_FREQUENCY_DAILY]: (withTimezone) =>
    withTimezone
      ? s__('DuoAgentsPlatform|Daily at %{time} %{timezone}')
      : s__('DuoAgentsPlatform|Daily at %{time}'),
  [SCHEDULE_FREQUENCY_WEEKDAYS]: (withTimezone) =>
    withTimezone
      ? s__('DuoAgentsPlatform|Weekdays at %{time} %{timezone}')
      : s__('DuoAgentsPlatform|Weekdays at %{time}'),
  [SCHEDULE_FREQUENCY_WEEKLY]: (withTimezone) =>
    withTimezone
      ? s__('DuoAgentsPlatform|Weekly on %{dayOfWeek} at %{time} %{timezone}')
      : s__('DuoAgentsPlatform|Weekly on %{dayOfWeek} at %{time}'),
  [SCHEDULE_FREQUENCY_MONTHLY]: (withTimezone) =>
    withTimezone
      ? s__('DuoAgentsPlatform|Monthly on day %{dayOfMonth} at %{time} %{timezone}')
      : s__('DuoAgentsPlatform|Monthly on day %{dayOfMonth} at %{time}'),
};

const scheduleLabels = (filter, timezone = '') => {
  if (!isScheduleConfigValid(filter)) return [];

  const schedule = parseScheduleConfig(filter);
  const message = SCHEDULE_LABEL_MESSAGES[schedule.frequency]?.(Boolean(timezone));
  if (!message) return [];

  const params = {
    minute: padWithZeros(schedule.minute).join(''),
    time: scheduleTime(schedule),
    dayOfWeek: getWeekdayNames()[schedule.dayOfWeek],
    dayOfMonth: schedule.dayOfMonth,
    timezone,
  };

  // Unescaped: labels only render as text (never v-html), and "US & Canada" would show "&amp;".
  return [sprintf(message, params, false)];
};

/**
 * Describes a schedule as a single phrase, e.g. `['Weekly on Monday at 09:30 Etc/UTC']`, so two
 * schedules on the same flow are told apart without opening the edit form.
 */
export const scheduleSummaryLabels = (filter, timezoneData = []) =>
  scheduleLabels(filter, scheduleTimezoneLabel(filter, timezoneData));

export const scheduleTokenLabels = (filter) => scheduleLabels(filter);

const EVENT_LABEL_BUILDERS = {
  [FLOW_TRIGGER_TYPE_PIPELINE_HOOKS.valueInt]: pipelineStatusLabels,
  [FLOW_TRIGGER_TYPE_MERGE_REQUEST.valueInt]: mergeRequestActionLabels,
  [FLOW_TRIGGER_TYPE_WORK_ITEM.valueInt]: workItemActionLabels,
  [FLOW_TRIGGER_TYPE_SCHEDULE.valueInt]: scheduleTokenLabels,
};

const EVENT_TOOLTIP_BUILDERS = {
  [FLOW_TRIGGER_TYPE_SCHEDULE.valueInt]: scheduleTimezoneLabel,
};

// One token per event type, e.g. [{ eventType: 2, text: 'Merge request (Merged)', tooltip: '' }].
export const flowTriggerEventTokens = (
  flowTrigger,
  { withSchedule = true, timezoneData = [] } = {},
) => {
  const { eventTypes, filter } = normalizeMergeRequestEventTypes({
    eventTypes: flowTrigger.eventTypes,
    filter: flowTrigger.filter,
  });

  if (!Array.isArray(eventTypes)) return [];

  return eventTypes.map((eventType) => {
    const name =
      FLOW_TRIGGER_TYPES.find((type) => type.valueInt === eventType)?.text || __('Unknown');
    const labels =
      !withSchedule && eventType === FLOW_TRIGGER_TYPE_SCHEDULE.valueInt
        ? []
        : (EVENT_LABEL_BUILDERS[eventType]?.(filter) ?? []);

    return {
      eventType,
      text: labels.length ? `${name} (${labels.join(', ')})` : name,
      tooltip: EVENT_TOOLTIP_BUILDERS[eventType]?.(filter, timezoneData) || '',
    };
  });
};

// One label per event type, e.g. ['Mention', 'Merge request (Approved, Merged)'].
export const flowTriggerEventLabels = (flowTrigger, options) =>
  flowTriggerEventTokens(flowTrigger, options).map(({ text }) => text);

const EVENT_SUMMARY_LABEL_BUILDERS = {
  [FLOW_TRIGGER_TYPE_PIPELINE_HOOKS.value]: ({ filter }) => pipelineStatusLabels(filter),
  [FLOW_TRIGGER_TYPE_MERGE_REQUEST.value]: ({ filter }) => mergeRequestActionLabels(filter),
  [FLOW_TRIGGER_TYPE_WORK_ITEM.value]: ({ filter }) => workItemActionLabels(filter),
  [FLOW_TRIGGER_TYPE_SCHEDULE.value]: ({ filter, timezoneData }) =>
    scheduleSummaryLabels(filter, timezoneData),
};

/**
 * The trigger types a namespace can actually offer, given its feature flags. Types opt out
 * either with an `isAvailable` predicate or a plain `featureFlag` name; anything declaring
 * neither is always available.
 */
export const getEnabledFlowTriggerTypes = (glFeatures = {}) =>
  FLOW_TRIGGER_TYPES.filter((type) => {
    if (type.isAvailable) return type.isAvailable(glFeatures);
    if (type.featureFlag) return Boolean(glFeatures[type.featureFlag]);
    return true;
  });

/**
 * Shapes a trigger type for a listbox. Descriptions are templated per item type, so a flow
 * and an agent read correctly from the same definition. A description may also be a function
 * of `glFeatures`, so a flag-gated type can describe itself differently once its flag is on.
 */
export const toFlowTriggerTypeOption = (
  { value, text, description },
  itemTypeLabel,
  glFeatures = {},
) => {
  const resolved = typeof description === 'function' ? description(glFeatures) : description;

  return {
    value,
    text,
    description: resolved ? sprintf(resolved, { itemType: itemTypeLabel }) : undefined,
  };
};

/**
 * Which mode a condition's event type belongs to. Only the `scheduled` type is time based; every
 * other type is driven by something happening in the project.
 */
export const flowTriggerModeFor = (typeValue) =>
  typeValue === FLOW_TRIGGER_MODE_SCHEDULE ? FLOW_TRIGGER_MODE_SCHEDULE : FLOW_TRIGGER_MODE_EVENT;

/**
 * Summarizes a single configured event type as one line, e.g. "Merge request: Marked ready" or
 * "Schedule: Weekly on Monday at 09:30 Etc/UTC". Event types with no rules are named but not
 * described.
 */
export const flowTriggerEventSummary = (typeValue, options = {}) => {
  const type = FLOW_TRIGGER_TYPES.find(({ value }) => value === typeValue);

  if (!type) {
    return s__('DuoAgentsPlatform|Unknown event');
  }

  const labels = EVENT_SUMMARY_LABEL_BUILDERS[typeValue]?.(options) ?? [];

  if (!labels.length) {
    return type.text;
  }

  return sprintf(
    s__('DuoAgentsPlatform|%{event}: %{conditions}'),
    { event: type.text, conditions: labels.join(', ') },
    false,
  );
};

// Randomize each field's default so new schedules spread across the domain instead of clustering
// on the first selectable value. The timezone defaults to the user's zone, never a random one.
export const randomizeScheduleDefaults = (frequency, { timezone = '' } = {}) => {
  const fields = SCHEDULE_FREQUENCY_FIELDS[frequency] ?? [];
  const schedule = { frequency };

  if (fields.includes(SCHEDULE_FIELD_MINUTE)) schedule.minute = randomFrom(SCHEDULE_MINUTE_VALUES);
  if (fields.includes(SCHEDULE_FIELD_HOUR)) {
    schedule.hour = randomInt(SCHEDULE_HOUR_MIN, SCHEDULE_HOUR_MAX);
  }
  if (fields.includes(SCHEDULE_FIELD_DAY_OF_WEEK)) {
    schedule.dayOfWeek = randomInt(SCHEDULE_DAY_OF_WEEK_MIN, SCHEDULE_DAY_OF_WEEK_MAX);
  }
  if (fields.includes(SCHEDULE_FIELD_DAY_OF_MONTH)) {
    schedule.dayOfMonth = randomInt(SCHEDULE_DAY_OF_MONTH_MIN, SCHEDULE_DAY_OF_MONTH_MAX);
  }
  if (fields.includes(SCHEDULE_FIELD_TIMEZONE)) schedule.timezone = timezone;

  return schedule;
};

// Only default to a zone the dropdown can actually display. Storing an identifier absent
// from `timezoneData` (e.g. a deprecated profile zone) would pass validation yet show blank.
export const defaultScheduleTimezone = (timezoneData, userTimezone) => {
  const isSelectable = (identifier) => timezoneData.some((tz) => tz.identifier === identifier);

  if (userTimezone && isSelectable(userTimezone)) return userTimezone;

  const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (isSelectable(browserTimezone)) return browserTimezone;

  return isSelectable(SCHEDULE_DEFAULT_TIMEZONE) ? SCHEDULE_DEFAULT_TIMEZONE : '';
};

// Returns the goal every event type shares, or null when their goals differ.
export const automationSharedGoal = ({ eventTypes, filter, goals }) => {
  const normalized = normalizeMergeRequestEventTypes({ eventTypes, filter, goals });
  const values = uniq(
    eventTypeIntsToValues(normalized.eventTypes).map((name) => normalized.goals[name] ?? ''),
  );

  return values.length > 1 ? null : (values[0] ?? '');
};
