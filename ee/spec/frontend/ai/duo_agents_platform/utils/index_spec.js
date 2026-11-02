// eslint-disable-next-line no-restricted-imports
import { __, n__, s__, sprintf } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import {
  denormalizeMergeRequestEventTypes,
  eventTypeIntsToValues,
  eventTypeValuesToInts,
  formatAgentDefinition,
  formatAgentFlowNameWithId,
  formatSessionTitleWithId,
  formatAgentFlowTitle,
  formatAgentFlowTitleTooltip,
  validateTitleIsNotDefinition,
  formatSessionLabel,
  formatSessionTooltip,
  formatAgentStatus,
  formatFlowLabel,
  formatDate,
  getAgentStatusFillClass,
  getAgentStatusTextClass,
  parseExecutorLogUrls,
  ciJobsLabel,
  getMessageData,
  getNamespaceDatasetProperties,
  flowTriggerModeFor,
  getEnabledFlowTriggerTypes,
  getNumericId,
  isScheduleConfigValid,
  isWorkItemStatusChangedWithStatuses,
  filterWorkItemTypesByIds,
  parseWorkItemSoftwareFactoryFilter,
  parseWorkItemTypeIdsFilter,
  workItemStatusNameOptions,
  workItemTypeOptions,
  mergeRequestActionLabels,
  toFlowTriggerTypeOption,
  normalizeMergeRequestEventTypes,
  parseFilterRuleValues,
  parseMergeRequestActionFilter,
  parsePipelineStatusFilter,
  parseScheduleConfig,
  parseWorkItemActionFilter,
  parseWorkItemStatusNamesFilter,
  pipelineStatusLabels,
  randomizeScheduleDefaults,
  scheduleSummaryLabels,
  scheduleTimezoneLabel,
  scheduleTokenLabels,
  workItemActionLabels,
} from 'ee/ai/duo_agents_platform/utils';
import {
  FLOW_TRIGGER_MODE_EVENT,
  FLOW_TRIGGER_MODE_SCHEDULE,
  FLOW_TRIGGER_TYPES,
  MESSAGE_SUB_TYPE_DELEGATION,
  MESSAGE_SUB_TYPE_DELEGATION_RETURNS,
  SCHEDULE_FREQUENCY_EVERY_15_MINUTES,
  SCHEDULE_FREQUENCY_EVERY_30_MINUTES,
  SCHEDULE_FREQUENCY_HOURLY,
  SCHEDULE_FREQUENCY_DAILY,
  SCHEDULE_FREQUENCY_WEEKDAYS,
  SCHEDULE_FREQUENCY_WEEKLY,
  SCHEDULE_FREQUENCY_MONTHLY,
} from 'ee/ai/duo_agents_platform/constants';

// Mock the dependencies
jest.mock('~/locale');
jest.mock('~/lib/utils/text_utility');
jest.mock('~/lib/utils/axios_utils', () => ({
  __esModule: true,
  default: {
    patch: jest.fn(),
  },
}));
jest.mock('~/lib/utils/datetime/locale_dateformat', () => ({
  localeDateFormat: {
    asDate: {
      format: jest.fn((date) => {
        const options = { year: 'numeric', month: 'short', day: 'numeric' };
        return date.toLocaleDateString('en-US', options);
      }),
    },
  },
}));
jest.mock('~/api/api_utils', () => ({
  buildApiUrl: (url) => url.replace(':version', 'v4'),
}));

describe('duo_agents_platform utils', () => {
  describe('formatAgentDefinition', () => {
    beforeEach(() => {
      s__.mockReturnValue('Agent flow');
      humanize.mockImplementation((str) => str.replace(/_/g, ' '));
    });

    describe('when an agent definition is provided', () => {
      beforeEach(() => {
        formatAgentDefinition('software_development');
      });

      it('humanizes the provided definition', () => {
        expect(humanize).toHaveBeenCalledWith('software_development');
      });
    });

    describe('when the agent definition is undefined', () => {
      beforeEach(() => {
        formatAgentDefinition();
      });

      it('humanizes the default fallback text', () => {
        expect(humanize).toHaveBeenCalledWith('Agent flow');
      });
    });
  });

  describe('formatFlowLabel', () => {
    it('appends the version to the name', () => {
      expect(formatFlowLabel('Developer', '3.0.0')).toBe('Developer · 3.0.0');
    });

    it('returns the name alone when there is no version', () => {
      expect(formatFlowLabel('Developer', '')).toBe('Developer');
    });
  });

  describe('formatAgentFlowNameWithId', () => {
    beforeEach(() => {
      s__.mockReturnValue('Agent flow');
    });

    it('formats agent flow name with definition and id', () => {
      const agentDefinition = 'software_development';
      const id = 123;

      const results = formatAgentFlowNameWithId(agentDefinition, id);

      expect(humanize).toHaveBeenCalledWith('software_development');
      expect(results).toBe('software development #123');
    });

    it('formats agent flow name with default definition when null', () => {
      const id = 456;

      const result = formatAgentFlowNameWithId(null, id);

      expect(result).toBe('Agent flow #456');
    });

    it('formats agent flow name with string id', () => {
      const agentDefinition = 'convert_to_ci';
      const id = '789';

      const result = formatAgentFlowNameWithId(agentDefinition, id);

      expect(result).toBe('convert to ci #789');
    });
  });

  describe('formatSessionTitleWithId', () => {
    it('formats session title with id', () => {
      expect(formatSessionTitleWithId('Fix the login bug', 123)).toBe('Fix the login bug #123');
    });
  });

  describe('formatAgentFlowTitle', () => {
    beforeEach(() => {
      s__.mockReturnValue('Agent flow');
      humanize.mockImplementation((str) => str.replace(/_/g, ' '));
    });

    describe('when a title is present', () => {
      it('returns the title unchanged', () => {
        expect(formatAgentFlowTitle('Fix the login bug', 'software_development')).toBe(
          'Fix the login bug',
        );
      });
    });

    describe('when the title is blank', () => {
      it.each([
        ['null', null],
        ['undefined', undefined],
        ['an empty string', ''],
        ['whitespace only', '   '],
      ])('falls back to the agent definition for %s', (_, title) => {
        expect(formatAgentFlowTitle(title, 'software_development')).toBe('software development');
      });
    });

    describe('when both the title and the agent definition are missing', () => {
      it('falls back to the default definition', () => {
        expect(formatAgentFlowTitle(null, null)).toBe('Agent flow');
      });
    });
  });

  describe('formatAgentFlowTitleTooltip', () => {
    beforeEach(() => {
      s__.mockImplementation((key) => key.split('|').pop());
      sprintf.mockImplementation(jest.requireActual('~/locale').sprintf);
    });

    it('appends the session ID to the already formatted title', () => {
      expect(formatAgentFlowTitleTooltip('Fix the login bug', 42)).toBe('Fix the login bug 42');
    });

    it('builds the tooltip from a translatable string', () => {
      formatAgentFlowTitleTooltip('Fix the login bug', 42);

      expect(s__).toHaveBeenCalledWith('DuoAgentsPlatform|%{title} %{id}');
    });

    it('does not HTML-escape the title', () => {
      expect(formatAgentFlowTitleTooltip('Fix A & B', 42)).toBe('Fix A & B 42');
    });

    it('does not format the title again', () => {
      formatAgentFlowTitleTooltip('Software development', 42);

      expect(humanize).not.toHaveBeenCalled();
    });
  });

  describe('validateTitleIsNotDefinition', () => {
    it.each([
      [true, 'a generated title', 'Fix the login bug'],
      [false, 'a title equal to the definition', 'software_development'],
      [false, 'a blank title', '   '],
      [false, 'a missing title', null],
    ])('returns %s for %s', (expected, _, title) => {
      expect(validateTitleIsNotDefinition({ title, agentDefinition: 'software_development' })).toBe(
        expected,
      );
    });
  });

  describe('formatSessionLabel', () => {
    it.each([
      ['the generated title and id', 'Fix the login bug', 'Fix the login bug #123'],
      [
        'the flow name and id while the title is the definition',
        'software_development',
        'software development #123',
      ],
      ['the flow name and id when the title is missing', null, 'software development #123'],
    ])('returns %s', (_, title, expected) => {
      expect(
        formatSessionLabel({
          title,
          agentDefinition: 'software_development',
          flowName: 'software_development',
          id: 123,
        }),
      ).toBe(expected);
    });
  });

  describe('formatSessionTooltip', () => {
    beforeEach(() => {
      humanize.mockImplementation((str) => str.replace(/_/g, ' '));
      s__.mockImplementation((key) => key.split('|').pop());
      sprintf.mockImplementation(jest.requireActual('~/locale').sprintf);
    });

    it.each([
      ['the generated title and id', 'Fix the login bug', 'Fix the login bug 123'],
      [
        'the humanized flow name and id while the title is the definition',
        'software_development',
        'software development 123',
      ],
      ['the humanized flow name and id when the title is empty', '', 'software development 123'],
      [
        'the humanized flow name and id when the title is missing',
        null,
        'software development 123',
      ],
    ])('returns %s', (_, title, expected) => {
      expect(
        formatSessionTooltip({
          title,
          agentDefinition: 'software_development',
          flowName: 'software_development',
          id: 123,
        }),
      ).toBe(expected);
    });
  });

  describe('getAgentStatusFillClass', () => {
    it.each([
      ['CREATED', 'gl-fill-status-neutral'],
      ['RUNNING', 'gl-fill-status-info'],
      ['FINISHED', 'gl-fill-status-success'],
      ['STOPPED', 'gl-fill-status-neutral'],
      ['INPUT_REQUIRED', 'gl-fill-status-warning'],
      ['IDLE', 'gl-fill-status-neutral'],
      ['FAILED', 'gl-fill-status-danger'],
      ['UNKNOWN_FUTURE_STATUS', 'gl-fill-status-neutral'],
    ])('returns the fill class for %s', (status, expected) => {
      expect(getAgentStatusFillClass(status)).toBe(expected);
    });
  });

  describe('getAgentStatusTextClass', () => {
    it.each([
      ['CREATED', 'gl-text-status-neutral'],
      ['RUNNING', 'gl-text-status-info'],
      ['FINISHED', 'gl-text-status-success'],
      ['STOPPED', 'gl-text-status-neutral'],
      ['INPUT_REQUIRED', 'gl-text-status-warning'],
      ['IDLE', 'gl-text-status-neutral'],
      ['FAILED', 'gl-text-status-danger'],
      ['UNKNOWN_FUTURE_STATUS', 'gl-text-status-neutral'],
    ])('returns the text class for %s', (status, expected) => {
      expect(getAgentStatusTextClass(status)).toBe(expected);
    });
  });

  describe('formatAgentStatus', () => {
    beforeEach(() => {
      s__.mockReturnValue('Unknown');
      humanize.mockImplementation((str) => str.charAt(0).toUpperCase() + str.slice(1));
    });

    describe('when status is a non-empty string', () => {
      it.each([
        ['RUNNING', 'running', 'Running'],
        ['COMPLETED', 'completed', 'Completed'],
        ['Failed', 'failed', 'Failed'],
      ])('humanizes %p as %p', (input, humanizeArg, expected) => {
        const result = formatAgentStatus(input);

        expect(humanize).toHaveBeenCalledWith(humanizeArg);
        expect(result).toBe(expected);
      });
    });

    describe('when status is falsy', () => {
      it.each([null, undefined, ''])('returns the default text for %p', (input) => {
        const result = formatAgentStatus(input);

        expect(s__).toHaveBeenCalledWith('DuoAgentsPlatform|Unknown');
        expect(result).toBe('Unknown');
      });
    });
  });

  describe('getNamespaceDatasetProperties', () => {
    it('returns object with specified properties from dataset', () => {
      const dataset = {
        prop1: 'value1',
        prop2: 'value2',
        prop3: 'value3',
        unwanted: 'unwanted',
      };
      const properties = ['prop1', 'prop3'];

      const result = getNamespaceDatasetProperties(dataset, properties);

      expect(result).toEqual({
        prop1: 'value1',
        prop3: 'value3',
      });
    });

    it('returns empty object when no properties specified', () => {
      const dataset = { prop1: 'value1' };
      const properties = [];

      const result = getNamespaceDatasetProperties(dataset, properties);

      expect(result).toEqual({});
    });

    it('handles undefined properties in dataset', () => {
      const dataset = { prop1: 'value1' };
      const properties = ['prop1', 'nonexistent'];

      const result = getNamespaceDatasetProperties(dataset, properties);

      expect(result).toEqual({
        prop1: 'value1',
        nonexistent: undefined,
      });
    });
  });

  describe('getMessageData', () => {
    beforeEach(() => {
      // Strip the namespace prefix the way the real s__ does, so test
      // assertions can use the plain English title.
      s__.mockImplementation((str) => str.split('|').pop());
    });

    it.each([
      ['user', { icon: 'user', title: 'User messaged agent', level: 1 }],
      ['request', { icon: 'question-o', title: 'Agent required human input', level: 1 }],
      ['unknown', { icon: 'work-item-maintenance', title: 'Action', level: 0 }],
    ])('returns correct data for %s message type', (messageType, expected) => {
      const message = { messageType };

      const result = getMessageData(message);

      expect(result).toEqual(expected);
    });

    it('returns default agent reasoning data for agent message type with no sub-type', () => {
      expect(getMessageData({ messageType: 'agent' })).toEqual({
        icon: 'tanuki-ai',
        title: 'Agent reasoning',
        level: 0,
      });
    });

    it('returns delegated-to-subagent data for delegation sub-type', () => {
      expect(
        getMessageData({ messageType: 'tool', messageSubType: MESSAGE_SUB_TYPE_DELEGATION }),
      ).toEqual({
        icon: 'arrow-down',
        title: 'Delegated to subagent',
        level: 1,
      });
    });

    it('returns returned-to-agent data for delegation_returns success', () => {
      expect(
        getMessageData({
          messageType: 'tool',
          messageSubType: MESSAGE_SUB_TYPE_DELEGATION_RETURNS,
          status: 'success',
        }),
      ).toEqual({
        icon: 'arrow-up',
        title: 'Returned to agent',
        level: 1,
      });
    });

    it('returns failure data for delegation_returns failure', () => {
      expect(
        getMessageData({
          messageType: 'tool',
          messageSubType: MESSAGE_SUB_TYPE_DELEGATION_RETURNS,
          status: 'failure',
        }),
      ).toEqual({
        icon: 'error',
        title: 'Subagent did not produce an answer',
        level: 1,
      });
    });

    it('returns returned-to-agent data for delegation_returns without known status', () => {
      expect(
        getMessageData({
          messageType: 'tool',
          messageSubType: MESSAGE_SUB_TYPE_DELEGATION_RETURNS,
          status: 'running',
        }),
      ).toEqual({
        icon: 'arrow-up',
        title: 'Returned to agent',
        level: 1,
      });
    });

    it('returns tool data for tool message type', () => {
      const message = {
        messageType: 'tool',
        toolInfo: { name: 'read_file' },
      };

      const result = getMessageData(message);

      expect(result).toEqual({
        icon: 'eye',
        title: 'Read file',
        level: 0,
      });
    });

    it.each([
      [{}, "Message requires property 'message_type' but got {}"],
      [
        { messageType: null },
        'Message requires property \'message_type\' but got {"messageType":null}',
      ],
    ])('throws error when messageType is invalid: %p', (message, expectedError) => {
      expect(() => getMessageData(message)).toThrow(expectedError);
    });
  });

  describe('getNumericId', () => {
    it.each([null, undefined, ''])('returns null for %p', (input) => {
      expect(getNumericId(input)).toBeNull();
    });

    it('extracts numeric id from a GraphQL global ID', () => {
      expect(getNumericId('gid://gitlab/User/42')).toBe(42);
    });

    it('returns the value as-is when it is not a GID', () => {
      expect(getNumericId('99')).toBe('99');
    });
  });

  describe('ciJobsLabel', () => {
    // `~/locale` is mocked for this suite, so give n__ its real singular/plural choice.
    beforeEach(() => {
      n__.mockImplementation((singular, plural, count) => (count === 1 ? singular : plural));
    });

    it.each`
      count | label
      ${0}  | ${'DuoAgentPlatform|CI jobs'}
      ${1}  | ${'DuoAgentPlatform|CI job'}
      ${2}  | ${'DuoAgentPlatform|CI jobs'}
    `('returns the $label string for $count jobs', ({ count, label }) => {
      expect(ciJobsLabel(count)).toBe(label);
    });
  });

  describe('parseExecutorLogUrls', () => {
    it('derives a job id and link from each executor log url', () => {
      expect(
        parseExecutorLogUrls([
          'https://gitlab.com/gitlab-org/gitlab/-/jobs/123',
          'https://gitlab.com/gitlab-org/gitlab/-/jobs/456',
        ]),
      ).toEqual([
        { webPath: 'https://gitlab.com/gitlab-org/gitlab/-/jobs/123', iid: '123' },
        { webPath: 'https://gitlab.com/gitlab-org/gitlab/-/jobs/456', iid: '456' },
      ]);
    });

    it('drops urls that do not end in a numeric job id', () => {
      expect(parseExecutorLogUrls(['https://gitlab.com/gitlab-org/gitlab/-/jobs/latest'])).toEqual(
        [],
      );
    });

    describe('when there are no urls', () => {
      it('returns an empty array for an omitted list', () => {
        expect(parseExecutorLogUrls()).toEqual([]);
      });

      it('returns an empty array for an empty list', () => {
        expect(parseExecutorLogUrls([])).toEqual([]);
      });
    });
  });

  describe('formatDate', () => {
    it('formats a valid ISO date string', () => {
      const result = formatDate('2024-01-01T00:00:00Z');

      expect(result).toBe('Jan 1, 2024');
    });

    it.each([null, undefined, ''])('returns empty string for %p', (input) => {
      expect(formatDate(input)).toBe('');
    });
  });

  describe('parseFilterRuleValues', () => {
    const SCOPE = 'test_scope';
    const FIELD = 'test_field';
    const OPTIONS = [
      { text: 'Foo', value: 'foo' },
      { text: 'Bar', value: 'bar' },
    ];
    const buildFilter = (rules) => ({ test_scope: { rules } });

    it.each`
      name                             | input
      ${'undefined filter'}            | ${undefined}
      ${'empty filter'}                | ${{}}
      ${'scope present, no rules key'} | ${{ test_scope: {} }}
      ${'empty rules array'}           | ${buildFilter([])}
      ${'multiple rules'}              | ${buildFilter([{ field: FIELD, operator: 'in', value: ['foo'] }, { field: FIELD, operator: 'in', value: ['bar'] }])}
      ${'non-array rules'}             | ${{ test_scope: { rules: 'not an array' } }}
      ${'unsupported operator'}        | ${buildFilter([{ field: FIELD, operator: 'eq', value: ['foo'] }])}
      ${'unsupported field'}           | ${buildFilter([{ field: 'other_field', operator: 'in', value: ['foo'] }])}
      ${'non-array value'}             | ${buildFilter([{ field: FIELD, operator: 'in', value: 'foo' }])}
    `('returns [] for $name', ({ input }) => {
      expect(
        parseFilterRuleValues({ filter: input, scope: SCOPE, field: FIELD, options: OPTIONS }),
      ).toEqual([]);
    });

    it('returns known values from a single valid rule', () => {
      const filter = buildFilter([{ field: FIELD, operator: 'in', value: ['foo', 'bar'] }]);

      expect(
        parseFilterRuleValues({ filter, scope: SCOPE, field: FIELD, options: OPTIONS }),
      ).toEqual(['foo', 'bar']);
    });

    it('drops values outside the known option set', () => {
      const filter = buildFilter([{ field: FIELD, operator: 'in', value: ['foo', 'unknown'] }]);

      expect(
        parseFilterRuleValues({ filter, scope: SCOPE, field: FIELD, options: OPTIONS }),
      ).toEqual(['foo']);
    });

    it('keeps only string values when no options are given', () => {
      const filter = buildFilter([{ field: FIELD, operator: 'in', value: ['foo', 7, 'qux'] }]);

      expect(parseFilterRuleValues({ filter, scope: SCOPE, field: FIELD })).toEqual(['foo', 'qux']);
    });

    it('ignores rules for other fields in the same scope', () => {
      const filter = buildFilter([
        { field: FIELD, operator: 'in', value: ['foo'] },
        { field: 'other_field', operator: 'eq', value: 'baz' },
      ]);

      expect(
        parseFilterRuleValues({ filter, scope: SCOPE, field: FIELD, options: OPTIONS }),
      ).toEqual(['foo']);
    });
  });

  describe('parsePipelineStatusFilter', () => {
    const buildFilter = (rules) => ({ pipeline_hooks: { rules } });

    it('returns the known status values for a single representable rule', () => {
      const filter = buildFilter([
        { field: 'object_attributes.status', operator: 'in', value: ['failed', 'success'] },
      ]);

      expect(parsePipelineStatusFilter(filter)).toEqual(['failed', 'success']);
    });

    it('drops unknown status values from the rule', () => {
      const filter = buildFilter([
        {
          field: 'object_attributes.status',
          operator: 'in',
          value: ['failed', 'something_unknown'],
        },
      ]);

      expect(parsePipelineStatusFilter(filter)).toEqual(['failed']);
    });
  });

  describe('pipelineStatusLabels', () => {
    it('returns one label per configured status', () => {
      const filter = {
        pipeline_hooks: {
          rules: [
            { field: 'object_attributes.status', operator: 'in', value: ['failed', 'canceled'] },
          ],
        },
      };

      expect(pipelineStatusLabels(filter)).toHaveLength(2);
    });

    it('returns [] when filter is empty', () => {
      expect(pipelineStatusLabels({})).toEqual([]);
    });

    it('returns [] when the filter shape is not supported by the field', () => {
      const filter = {
        pipeline_hooks: {
          rules: [{ field: 'object_attributes.status', operator: 'eq', value: 'failed' }],
        },
      };

      expect(pipelineStatusLabels(filter)).toEqual([]);
    });
  });

  describe('parseMergeRequestActionFilter', () => {
    const buildFilter = (rules) => ({ merge_request: { rules } });

    it.each`
      name                             | input
      ${'undefined filter'}            | ${undefined}
      ${'empty filter'}                | ${{}}
      ${'scope present, no rules key'} | ${{ merge_request: {} }}
      ${'empty rules array'}           | ${buildFilter([])}
      ${'non-array rules'}             | ${{ merge_request: { rules: 'not an array' } }}
      ${'unsupported field'}           | ${buildFilter([{ field: 'something.else', operator: 'in', value: ['ready'] }])}
      ${'unsupported operator'}        | ${buildFilter([{ field: 'action', operator: 'eq', value: 'ready' }])}
      ${'in with non-array value'}     | ${buildFilter([{ field: 'action', operator: 'in', value: 'ready' }])}
      ${'multiple rules'}              | ${buildFilter([{ field: 'action', operator: 'in', value: ['ready'] }, { field: 'action', operator: 'in', value: ['approved'] }])}
    `('returns [] for $name', ({ input }) => {
      expect(parseMergeRequestActionFilter(input)).toEqual([]);
    });

    it('returns all actions for an in array rule', () => {
      expect(
        parseMergeRequestActionFilter(
          buildFilter([{ field: 'action', operator: 'in', value: ['ready', 'approved'] }]),
        ),
      ).toEqual(['ready', 'approved']);
    });

    it('returns a single action for an in rule with a one-element array', () => {
      expect(
        parseMergeRequestActionFilter(
          buildFilter([{ field: 'action', operator: 'in', value: ['approved'] }]),
        ),
      ).toEqual(['approved']);
    });

    it('returns the merged action', () => {
      expect(
        parseMergeRequestActionFilter(
          buildFilter([{ field: 'action', operator: 'in', value: ['merged'] }]),
        ),
      ).toEqual(['merged']);
    });

    it('returns the requested_changes action', () => {
      expect(
        parseMergeRequestActionFilter(
          buildFilter([{ field: 'action', operator: 'in', value: ['requested_changes'] }]),
        ),
      ).toEqual(['requested_changes']);
    });

    it('drops unknown action values from the rule', () => {
      expect(
        parseMergeRequestActionFilter(
          buildFilter([{ field: 'action', operator: 'in', value: ['ready', 'something_unknown'] }]),
        ),
      ).toEqual(['ready']);
    });
  });

  describe('mergeRequestActionLabels', () => {
    it('returns one label per configured action', () => {
      const filter = {
        merge_request: {
          rules: [{ field: 'action', operator: 'in', value: ['ready', 'approved'] }],
        },
      };

      expect(mergeRequestActionLabels(filter)).toHaveLength(2);
    });

    it('returns [] when filter is empty', () => {
      expect(mergeRequestActionLabels({})).toEqual([]);
    });

    it('returns [] when the filter shape is not supported by the field', () => {
      const filter = {
        merge_request: { rules: [{ field: 'unknown', operator: 'in', value: ['ready'] }] },
      };

      expect(mergeRequestActionLabels(filter)).toEqual([]);
    });
  });

  describe('parseWorkItemActionFilter', () => {
    const buildFilter = (rules) => ({ work_item: { rules } });

    it('returns the created action when present', () => {
      const filter = buildFilter([{ field: 'action', operator: 'in', value: ['created'] }]);

      expect(parseWorkItemActionFilter(filter)).toEqual(['created']);
    });

    it('returns the status_changed action when present', () => {
      const filter = buildFilter([{ field: 'action', operator: 'in', value: ['status_changed'] }]);

      expect(parseWorkItemActionFilter(filter)).toEqual(['status_changed']);
    });

    it('drops values outside the known action set', () => {
      const filter = buildFilter([
        { field: 'action', operator: 'in', value: ['created', 'bogus'] },
      ]);

      expect(parseWorkItemActionFilter(filter)).toEqual(['created']);
    });
  });

  describe('parseWorkItemStatusNamesFilter', () => {
    const buildFilter = (rules) => ({ work_item: { rules } });

    it.each`
      name                     | input
      ${'undefined filter'}    | ${undefined}
      ${'no work_item scope'}  | ${{}}
      ${'non-array rules'}     | ${{ work_item: { rules: 'nope' } }}
      ${'no status.name rule'} | ${buildFilter([{ field: 'action', operator: 'in', value: ['created'] }])}
      ${'non-in operator'}     | ${buildFilter([{ field: 'status.name', operator: 'eq', value: 'Done' }])}
      ${'non-array value'}     | ${buildFilter([{ field: 'status.name', operator: 'in', value: 'Done' }])}
    `('returns [] for $name', ({ input }) => {
      expect(parseWorkItemStatusNamesFilter(input)).toEqual([]);
    });

    it('returns the string values of the status.name in rule', () => {
      const filter = buildFilter([
        { field: 'action', operator: 'in', value: ['status_changed'] },
        { field: 'status.name', operator: 'in', value: ['In progress', 7, 'Done'] },
      ]);

      expect(parseWorkItemStatusNamesFilter(filter)).toEqual(['In progress', 'Done']);
    });
  });

  describe('workItemStatusNameOptions', () => {
    // Two lifecycles can each define a status with the same name, so the ids differ.
    it('lists each status name once, in the given order', () => {
      const statuses = [
        { id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/1', name: 'In review' },
        { id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/2', name: 'Done' },
        { id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/3', name: 'In review' },
      ];

      expect(workItemStatusNameOptions(statuses)).toEqual([
        { value: 'In review', text: 'In review' },
        { value: 'Done', text: 'Done' },
      ]);
    });
  });

  describe('parseWorkItemTypeIdsFilter', () => {
    const buildFilter = (rules) => ({ work_item: { rules } });

    it.each`
      name                           | input
      ${'undefined filter'}          | ${undefined}
      ${'no work_item_type_id rule'} | ${buildFilter([{ field: 'action', operator: 'in', value: ['created'] }])}
      ${'non-in operator'}           | ${buildFilter([{ field: 'work_item_type_id', operator: 'eq', value: 5 }])}
      ${'non-array value'}           | ${buildFilter([{ field: 'work_item_type_id', operator: 'in', value: 5 }])}
    `('returns [] for $name', ({ input }) => {
      expect(parseWorkItemTypeIdsFilter(input)).toEqual([]);
    });

    // The event carries an integer, so a string ID never matches.
    it('returns the integer values of the work_item_type_id in rule', () => {
      const filter = buildFilter([
        { field: 'action', operator: 'in', value: ['created'] },
        { field: 'work_item_type_id', operator: 'in', value: [5, '1', 1001, 2.5] },
      ]);

      expect(parseWorkItemTypeIdsFilter(filter)).toEqual([5, 1001]);
    });
  });

  describe('parseWorkItemSoftwareFactoryFilter', () => {
    const buildFilter = (rules) => ({ work_item: { rules } });
    const rule = (value) => ({ field: 'software_factory_enabled', operator: 'in', value });

    it.each`
      name                                  | input                                                                                | expected
      ${'undefined filter'}                 | ${undefined}                                                                         | ${null}
      ${'no software_factory_enabled rule'} | ${buildFilter([{ field: 'action', operator: 'in', value: ['created'] }])}            | ${null}
      ${'in [true]'}                        | ${buildFilter([rule([true])])}                                                       | ${true}
      ${'in [false]'}                       | ${buildFilter([rule([false])])}                                                      | ${false}
      ${'in [true, true]'}                  | ${buildFilter([rule([true, true])])}                                                 | ${true}
      ${'in [true, false]'}                 | ${buildFilter([rule([true, false])])}                                                | ${null}
      ${'string values'}                    | ${buildFilter([rule(['true'])])}                                                     | ${null}
      ${'non-in operator'}                  | ${buildFilter([{ field: 'software_factory_enabled', operator: 'eq', value: true }])} | ${null}
    `('returns $expected for $name', ({ input, expected }) => {
      expect(parseWorkItemSoftwareFactoryFilter(input)).toBe(expected);
    });
  });

  describe('workItemTypeOptions', () => {
    it('uses the numeric part of the GraphQL ID as the value', () => {
      const workItemTypes = [
        { id: 'gid://gitlab/WorkItems::Type/5', name: 'Task' },
        { id: 'gid://gitlab/WorkItems::Type/1001', name: 'Bug' },
      ];

      expect(workItemTypeOptions(workItemTypes)).toEqual([
        { value: 5, text: 'Task' },
        { value: 1001, text: 'Bug' },
      ]);
    });
  });

  describe('filterWorkItemTypesByIds', () => {
    const issue = { id: 'gid://gitlab/WorkItems::Type/1', name: 'Issue' };
    const task = { id: 'gid://gitlab/WorkItems::Type/5', name: 'Task' };

    it('returns every type when no ID is given', () => {
      expect(filterWorkItemTypesByIds([issue, task], [])).toEqual([issue, task]);
    });

    it('returns only the types with the given IDs', () => {
      expect(filterWorkItemTypesByIds([issue, task], [5, 1001])).toEqual([task]);
    });
  });

  describe('isWorkItemStatusChangedWithStatuses', () => {
    const statusChanged = { field: 'action', operator: 'in', value: ['status_changed'] };
    const statuses = { field: 'status.name', operator: 'in', value: ['In review'] };
    const buildFilter = (rules, extra = {}) => ({ work_item: { rules, ...extra } });

    it.each`
      name                                  | input
      ${'undefined filter'}                 | ${undefined}
      ${'no work_item scope'}               | ${{}}
      ${'Status changed without a status'}  | ${buildFilter([statusChanged])}
      ${'Created and Status changed'}       | ${buildFilter([{ ...statusChanged, value: ['created', 'status_changed'] }, statuses])}
      ${'an action the form does not know'} | ${buildFilter([{ ...statusChanged, value: ['status_changed', 'closed'] }, statuses])}
      ${'two action rules'}                 | ${buildFilter([statusChanged, statusChanged, statuses])}
      ${'an empty status list'}             | ${buildFilter([statusChanged, { ...statuses, value: [] }])}
      ${'a scope that matches any rule'}    | ${buildFilter([statusChanged, statuses], { match: 'any' })}
    `('returns false for $name', ({ input }) => {
      expect(isWorkItemStatusChangedWithStatuses(input)).toBe(false);
    });

    it.each`
      name                   | input
      ${'no match key'}      | ${buildFilter([statusChanged, statuses])}
      ${'a match all scope'} | ${buildFilter([statusChanged, statuses], { match: 'all' })}
      ${'a type rule'}       | ${buildFilter([statusChanged, statuses, { field: 'work_item_type_id', operator: 'in', value: [5] }])}
    `('returns true for Status changed with a status and $name', ({ input }) => {
      expect(isWorkItemStatusChangedWithStatuses(input)).toBe(true);
    });
  });

  describe('workItemActionLabels', () => {
    describe('with a status.name rule', () => {
      beforeEach(() => {
        s__.mockImplementation((key) => key.split('|')[1]);
        sprintf.mockImplementation((str, params) =>
          str.replace('%{statusNames}', params.statusNames),
        );
      });

      it('appends the status names to the status changed label', () => {
        const filter = {
          work_item: {
            rules: [
              { field: 'action', operator: 'in', value: ['status_changed'] },
              { field: 'status.name', operator: 'in', value: ['In progress', 'Done'] },
            ],
          },
        };

        expect(workItemActionLabels(filter)).toEqual(['Status changed to In progress, Done']);
      });
    });

    it('returns one label per configured action', () => {
      const filter = {
        work_item: { rules: [{ field: 'action', operator: 'in', value: ['created'] }] },
      };

      expect(workItemActionLabels(filter)).toHaveLength(1);
    });

    describe('with a work_item_type_id rule', () => {
      beforeEach(() => {
        n__.mockImplementation(
          (singular, plural, count) => (count === 1 ? singular : plural).split('|')[1],
        );
        sprintf.mockImplementation((str, params) => str.replace('%{count}', params.count));
      });

      it('appends the number of selected types', () => {
        const filter = {
          work_item: {
            rules: [
              { field: 'action', operator: 'in', value: ['created'] },
              { field: 'work_item_type_id', operator: 'in', value: [1, 5] },
            ],
          },
        };

        // The ~/locale mock leaves the action names undefined, so only the count is checked.
        const labels = workItemActionLabels(filter);

        expect(labels).toHaveLength(2);
        expect(labels[1]).toBe('2 work item types');
      });

      it('returns [] when the filter has no action', () => {
        const filter = {
          work_item: { rules: [{ field: 'work_item_type_id', operator: 'in', value: [5] }] },
        };

        expect(workItemActionLabels(filter)).toEqual([]);
      });
    });

    describe('with a software_factory_enabled rule', () => {
      const buildFilter = (rules) => ({ work_item: { rules } });

      beforeEach(() => {
        s__.mockImplementation((key) => key.split('|')[1]);
      });

      it.each`
        values     | label
        ${[true]}  | ${'Software Factory work items'}
        ${[false]} | ${'Other work items'}
      `('appends "$label" for the rule with the value $values', ({ values, label }) => {
        const filter = buildFilter([
          { field: 'action', operator: 'in', value: ['created'] },
          { field: 'software_factory_enabled', operator: 'in', value: values },
        ]);

        // The ~/locale mock leaves the action names undefined, so only the last label is checked.
        const labels = workItemActionLabels(filter);

        expect(labels).toHaveLength(2);
        expect(labels[1]).toBe(label);
      });

      it('appends no label for a rule that matches every work item', () => {
        const filter = buildFilter([
          { field: 'action', operator: 'in', value: ['created'] },
          { field: 'software_factory_enabled', operator: 'in', value: [true, false] },
        ]);

        expect(workItemActionLabels(filter)).toHaveLength(1);
      });

      it('returns [] when the filter has no action', () => {
        const filter = buildFilter([
          { field: 'software_factory_enabled', operator: 'in', value: [true] },
        ]);

        expect(workItemActionLabels(filter)).toEqual([]);
      });
    });

    it('returns [] when filter is empty', () => {
      expect(workItemActionLabels({})).toEqual([]);
    });

    it('returns [] when the filter shape is not supported by the field', () => {
      const filter = {
        work_item: { rules: [{ field: 'unknown', operator: 'in', value: ['created'] }] },
      };

      expect(workItemActionLabels(filter)).toEqual([]);
    });
  });

  describe('normalizeMergeRequestEventTypes', () => {
    it('returns input untouched when event_types is missing', () => {
      const result = normalizeMergeRequestEventTypes({ eventTypes: undefined, filter: undefined });

      expect(result).toEqual({ eventTypes: undefined, filter: {}, goals: {} });
    });

    it('returns input untouched when no merge_request_ready event type is present', () => {
      const input = { eventTypes: [0, 1], filter: { pipeline_hooks: {} } };

      expect(normalizeMergeRequestEventTypes(input)).toEqual({
        eventTypes: [0, 1],
        filter: { pipeline_hooks: {} },
        goals: {},
      });
    });

    it('converts a merge_request_ready event type into merge_request with a ready action filter', () => {
      const result = normalizeMergeRequestEventTypes({ eventTypes: [0, 4], filter: {} });

      expect(result).toEqual({
        eventTypes: [0, 6],
        filter: {
          merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready'] }] },
        },
        goals: {},
      });
    });

    it('combines a merge_request_ready event type with an existing approved merge_request filter', () => {
      const result = normalizeMergeRequestEventTypes({
        eventTypes: [4, 6],
        filter: {
          merge_request: { rules: [{ field: 'action', operator: 'in', value: ['approved'] }] },
        },
      });

      expect(result.eventTypes).toEqual([6]);
      expect(result.filter.merge_request).toEqual({
        rules: [{ field: 'action', operator: 'in', value: ['approved', 'ready'] }],
      });
    });

    it('is a no-op when ready is already in the existing action filter', () => {
      const result = normalizeMergeRequestEventTypes({
        eventTypes: [4, 6],
        filter: {
          merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready'] }] },
        },
      });

      expect(result.eventTypes).toEqual([6]);
      expect(result.filter.merge_request).toEqual({
        rules: [{ field: 'action', operator: 'in', value: ['ready'] }],
      });
    });

    it('converts a merge_request_code_conflict event type into merge_request with a code_conflict action filter', () => {
      const result = normalizeMergeRequestEventTypes({ eventTypes: [0, 5], filter: {} });

      expect(result).toEqual({
        eventTypes: [0, 6],
        filter: {
          merge_request: { rules: [{ field: 'action', operator: 'in', value: ['code_conflict'] }] },
        },
        goals: {},
      });
    });

    it('folds both ready and code_conflict event types into a single merge_request filter', () => {
      const result = normalizeMergeRequestEventTypes({ eventTypes: [4, 5], filter: {} });

      expect(result.eventTypes).toEqual([6]);
      expect(result.filter.merge_request).toEqual({
        rules: [{ field: 'action', operator: 'in', value: ['code_conflict', 'ready'] }],
      });
    });

    it('does not mutate the input event_types array', () => {
      const eventTypes = [4];
      normalizeMergeRequestEventTypes({ eventTypes, filter: {} });

      expect(eventTypes).toEqual([4]);
    });
  });

  describe('denormalizeMergeRequestEventTypes', () => {
    const readyFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready'] }] },
    };
    const readyApprovedFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready', 'approved'] }] },
    };
    const approvedFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['approved'] }] },
    };
    const codeConflictFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['code_conflict'] }] },
    };

    it('returns input untouched when there is no merge_request action filter', () => {
      const result = denormalizeMergeRequestEventTypes({ eventTypes: [0, 1], filter: {} });

      expect(result).toEqual({ eventTypes: [0, 1], filter: {}, goals: {} });
    });

    it('folds a ready action back to event_type 4', () => {
      const result = denormalizeMergeRequestEventTypes({ eventTypes: [6], filter: readyFilter });

      expect(result).toEqual({ eventTypes: [4], filter: {}, goals: {} });
    });

    it('leaves a merged action under event_type 6', () => {
      const mergedFilter = {
        merge_request: { rules: [{ field: 'action', operator: 'in', value: ['merged'] }] },
      };
      const result = denormalizeMergeRequestEventTypes({ eventTypes: [6], filter: mergedFilter });

      expect(result).toEqual({ eventTypes: [6], filter: mergedFilter, goals: {} });
    });

    it('folds a code_conflict action back to event_type 5', () => {
      const result = denormalizeMergeRequestEventTypes({
        eventTypes: [6],
        filter: codeConflictFilter,
      });

      expect(result).toEqual({ eventTypes: [5], filter: {}, goals: {} });
    });

    it('folds both ready and code_conflict back to their own event types', () => {
      const result = denormalizeMergeRequestEventTypes({
        eventTypes: [6],
        filter: {
          merge_request: {
            rules: [{ field: 'action', operator: 'in', value: ['ready', 'code_conflict'] }],
          },
        },
      });

      expect(result.eventTypes.sort()).toEqual([4, 5]);
      expect(result.filter).toEqual({});
    });

    it('keeps approved under event_type 6 while folding ready back to 4', () => {
      const result = denormalizeMergeRequestEventTypes({
        eventTypes: [6],
        filter: readyApprovedFilter,
      });

      expect(result.eventTypes.sort()).toEqual([4, 6]);
      expect(result.filter).toEqual(approvedFilter);
    });

    it('leaves an approved-only trigger on event_type 6', () => {
      const result = denormalizeMergeRequestEventTypes({ eventTypes: [6], filter: approvedFilter });

      expect(result).toEqual({ eventTypes: [6], filter: approvedFilter, goals: {} });
    });
  });

  describe('eventTypeValuesToInts', () => {
    it('maps known string values to their numeric ids', () => {
      expect(
        eventTypeValuesToInts([
          'mention',
          'merge_request',
          'merge_request_code_conflict',
          'scheduled',
        ]),
      ).toEqual([0, 6, 5, 9]);
    });

    it('drops unknown values', () => {
      expect(eventTypeValuesToInts(['mention', 'not_a_type'])).toEqual([0]);
    });

    it('returns an empty array by default', () => {
      expect(eventTypeValuesToInts()).toEqual([]);
    });
  });

  describe('eventTypeIntsToValues', () => {
    it('maps numeric ids back to their string values, including foldable actions', () => {
      expect(eventTypeIntsToValues([0, 6, 4, 5, 9])).toEqual([
        'mention',
        'merge_request',
        'merge_request_ready',
        'merge_request_code_conflict',
        'scheduled',
      ]);
    });

    it('drops unknown ids', () => {
      expect(eventTypeIntsToValues([0, 99])).toEqual(['mention']);
    });

    it('returns an empty array by default', () => {
      expect(eventTypeIntsToValues()).toEqual([]);
    });

    it('round-trips with eventTypeValuesToInts', () => {
      const values = ['mention', 'assign', 'merge_request', 'merge_request_ready', 'scheduled'];

      expect(eventTypeIntsToValues(eventTypeValuesToInts(values))).toEqual(values);
    });
  });

  describe('parseScheduleConfig', () => {
    it('returns the schedule object stored under the schedule scope', () => {
      const schedule = { frequency: SCHEDULE_FREQUENCY_DAILY, minute: 15, hour: 9 };

      expect(parseScheduleConfig({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toBe(schedule);
    });

    it('returns null when there is no schedule scope', () => {
      expect(parseScheduleConfig({})).toBe(null);
      expect(parseScheduleConfig(undefined)).toBe(null);
    });
  });

  describe('isScheduleConfigValid', () => {
    it('returns false when there is no schedule or the frequency is unknown', () => {
      expect(isScheduleConfigValid({})).toBe(false);
      expect(isScheduleConfigValid({ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: 'NOPE' } })).toBe(
        false,
      );
    });

    it('returns true for a sub-hour preset that requires no fields', () => {
      expect(
        isScheduleConfigValid({
          [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_EVERY_15_MINUTES },
        }),
      ).toBe(true);
    });

    it('validates a fully configured monthly schedule', () => {
      const schedule = {
        frequency: SCHEDULE_FREQUENCY_MONTHLY,
        minute: 30,
        hour: 23,
        dayOfMonth: 28,
        timezone: 'Etc/UTC',
      };

      expect(isScheduleConfigValid({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toBe(true);
    });

    it('validates a fully configured weekdays schedule (no day field required)', () => {
      const schedule = {
        frequency: SCHEDULE_FREQUENCY_WEEKDAYS,
        minute: 0,
        hour: 9,
        timezone: 'Etc/UTC',
      };

      expect(isScheduleConfigValid({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toBe(true);
    });

    it('validates a fully configured weekly schedule', () => {
      const schedule = {
        frequency: SCHEDULE_FREQUENCY_WEEKLY,
        minute: 0,
        hour: 9,
        dayOfWeek: 3,
        timezone: 'Etc/UTC',
      };

      expect(isScheduleConfigValid({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toBe(true);
    });

    it.each`
      description                  | schedule
      ${'minute off the 15s'}      | ${{ frequency: SCHEDULE_FREQUENCY_DAILY, minute: 7, hour: 9, timezone: 'Etc/UTC' }}
      ${'hour out of range'}       | ${{ frequency: SCHEDULE_FREQUENCY_DAILY, minute: 0, hour: 24, timezone: 'Etc/UTC' }}
      ${'missing timezone'}        | ${{ frequency: SCHEDULE_FREQUENCY_DAILY, minute: 0, hour: 9 }}
      ${'weekly without day'}      | ${{ frequency: SCHEDULE_FREQUENCY_WEEKLY, minute: 0, hour: 9, timezone: 'Etc/UTC' }}
      ${'day-of-week above 6'}     | ${{ frequency: SCHEDULE_FREQUENCY_WEEKLY, minute: 0, hour: 9, dayOfWeek: 7, timezone: 'Etc/UTC' }}
      ${'day-of-week non-integer'} | ${{ frequency: SCHEDULE_FREQUENCY_WEEKLY, minute: 0, hour: 9, dayOfWeek: 1.5, timezone: 'Etc/UTC' }}
      ${'day-of-month above 28'}   | ${{ frequency: SCHEDULE_FREQUENCY_MONTHLY, minute: 0, hour: 9, dayOfMonth: 29, timezone: 'Etc/UTC' }}
      ${'day-of-month below 1'}    | ${{ frequency: SCHEDULE_FREQUENCY_MONTHLY, minute: 0, hour: 9, dayOfMonth: 0, timezone: 'Etc/UTC' }}
    `('returns false for $description', ({ schedule }) => {
      expect(isScheduleConfigValid({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toBe(false);
    });
  });

  describe('scheduleSummaryLabels', () => {
    beforeEach(() => {
      __.mockImplementation((key) => key);
      s__.mockImplementation((key) => key.split('|')[1]);
      sprintf.mockImplementation((message, params) =>
        message.replace(/%\{(\w+)\}/g, (_match, name) => params[name]),
      );
    });

    it.each`
      frequency                              | fields                                                         | label
      ${SCHEDULE_FREQUENCY_EVERY_15_MINUTES} | ${{}}                                                          | ${'Every 15 minutes'}
      ${SCHEDULE_FREQUENCY_EVERY_30_MINUTES} | ${{}}                                                          | ${'Every 30 minutes'}
      ${SCHEDULE_FREQUENCY_HOURLY}           | ${{ minute: 0, timezone: 'Etc/UTC' }}                          | ${'Hourly at 00 minutes past the hour Etc/UTC'}
      ${SCHEDULE_FREQUENCY_HOURLY}           | ${{ minute: 30, timezone: 'Asia/Kolkata' }}                    | ${'Hourly at 30 minutes past the hour Asia/Kolkata'}
      ${SCHEDULE_FREQUENCY_DAILY}            | ${{ minute: 30, hour: 9, timezone: 'Etc/UTC' }}                | ${'Daily at 09:30 Etc/UTC'}
      ${SCHEDULE_FREQUENCY_WEEKDAYS}         | ${{ minute: 0, hour: 17, timezone: 'Europe/London' }}          | ${'Weekdays at 17:00 Europe/London'}
      ${SCHEDULE_FREQUENCY_WEEKLY}           | ${{ minute: 45, hour: 9, dayOfWeek: 1, timezone: 'Etc/UTC' }}  | ${'Weekly on Monday at 09:45 Etc/UTC'}
      ${SCHEDULE_FREQUENCY_MONTHLY}          | ${{ minute: 0, hour: 0, dayOfMonth: 15, timezone: 'Etc/UTC' }} | ${'Monthly on day 15 at 00:00 Etc/UTC'}
    `('describes a $frequency schedule', ({ frequency, fields, label }) => {
      const filter = { [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency, ...fields } };

      expect(scheduleSummaryLabels(filter)).toEqual([label]);
    });

    it('formats the timezone like the timezone picker when it is in timezoneData', () => {
      const filter = {
        [FLOW_TRIGGER_MODE_SCHEDULE]: {
          frequency: SCHEDULE_FREQUENCY_DAILY,
          minute: 30,
          hour: 9,
          timezone: 'America/New_York',
        },
      };
      const timezoneData = [
        { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
      ];

      expect(scheduleSummaryLabels(filter, timezoneData)).toEqual([
        'Daily at 09:30 [UTC-5] Eastern Time (US & Canada)',
      ]);
    });

    it('returns [] when there is no schedule', () => {
      expect(scheduleSummaryLabels({})).toEqual([]);
    });

    it('returns [] when the schedule is incomplete', () => {
      const schedule = { frequency: SCHEDULE_FREQUENCY_WEEKLY, minute: 0, hour: 9 };

      expect(scheduleSummaryLabels({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toEqual([]);
    });
  });

  describe('scheduleTokenLabels', () => {
    beforeEach(() => {
      __.mockImplementation((key) => key);
      s__.mockImplementation((key) => key.split('|')[1]);
      sprintf.mockImplementation((message, params) =>
        message.replace(/%\{(\w+)\}/g, (_match, name) => params[name]),
      );
    });

    it.each`
      frequency                              | fields                                                         | label
      ${SCHEDULE_FREQUENCY_EVERY_15_MINUTES} | ${{}}                                                          | ${'Every 15 minutes'}
      ${SCHEDULE_FREQUENCY_EVERY_30_MINUTES} | ${{}}                                                          | ${'Every 30 minutes'}
      ${SCHEDULE_FREQUENCY_HOURLY}           | ${{ minute: 30, timezone: 'Asia/Kolkata' }}                    | ${'Hourly at 30 minutes past the hour'}
      ${SCHEDULE_FREQUENCY_DAILY}            | ${{ minute: 30, hour: 9, timezone: 'Etc/UTC' }}                | ${'Daily at 09:30'}
      ${SCHEDULE_FREQUENCY_WEEKDAYS}         | ${{ minute: 0, hour: 17, timezone: 'Europe/London' }}          | ${'Weekdays at 17:00'}
      ${SCHEDULE_FREQUENCY_WEEKLY}           | ${{ minute: 45, hour: 9, dayOfWeek: 1, timezone: 'Etc/UTC' }}  | ${'Weekly on Monday at 09:45'}
      ${SCHEDULE_FREQUENCY_MONTHLY}          | ${{ minute: 0, hour: 0, dayOfMonth: 15, timezone: 'Etc/UTC' }} | ${'Monthly on day 15 at 00:00'}
    `('describes a $frequency schedule without the timezone', ({ frequency, fields, label }) => {
      const filter = { [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency, ...fields } };

      expect(scheduleTokenLabels(filter)).toEqual([label]);
    });

    it('returns [] when there is no schedule', () => {
      expect(scheduleTokenLabels({})).toEqual([]);
    });

    it('returns [] when the schedule is incomplete', () => {
      const schedule = { frequency: SCHEDULE_FREQUENCY_WEEKLY, minute: 0, hour: 9 };

      expect(scheduleTokenLabels({ [FLOW_TRIGGER_MODE_SCHEDULE]: schedule })).toEqual([]);
    });
  });

  describe('scheduleTimezoneLabel', () => {
    describe('with a schedule that has a timezone', () => {
      const filter = {
        [FLOW_TRIGGER_MODE_SCHEDULE]: {
          frequency: SCHEDULE_FREQUENCY_DAILY,
          minute: 30,
          hour: 9,
          timezone: 'America/New_York',
        },
      };

      it('formats the timezone like the timezone picker when it is in timezoneData', () => {
        const timezoneData = [
          { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
        ];

        expect(scheduleTimezoneLabel(filter, timezoneData)).toBe(
          '[UTC-5] Eastern Time (US & Canada)',
        );
      });

      it('falls back to the IANA identifier when it is not in timezoneData', () => {
        expect(scheduleTimezoneLabel(filter)).toBe('America/New_York');
      });
    });

    it.each`
      description                                  | filter
      ${'no schedule'}                             | ${{}}
      ${'a frequency with no zone'}                | ${{ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_EVERY_15_MINUTES } }}
      ${'a stray zone on a frequency without one'} | ${{ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_EVERY_15_MINUTES, timezone: 'Etc/UTC' } }}
      ${'an incomplete schedule'}                  | ${{ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_DAILY, hour: 9 } }}
    `('returns an empty string for $description', ({ filter }) => {
      expect(scheduleTimezoneLabel(filter)).toBe('');
    });
  });

  describe('getEnabledFlowTriggerTypes', () => {
    const valuesOf = (types) => types.map(({ value }) => value);

    it('keeps types that declare neither a predicate nor a flag', () => {
      const alwaysOn = FLOW_TRIGGER_TYPES.filter(
        ({ isAvailable, featureFlag }) => !isAvailable && !featureFlag,
      );

      expect(valuesOf(getEnabledFlowTriggerTypes())).toEqual(
        expect.arrayContaining(valuesOf(alwaysOn)),
      );
    });

    it('drops types whose predicate rejects the flags', () => {
      const gated = FLOW_TRIGGER_TYPES.filter(({ isAvailable }) => isAvailable?.({}) === false);

      expect(gated.length).toBeGreaterThan(0);
      expect(valuesOf(getEnabledFlowTriggerTypes({}))).not.toEqual(
        expect.arrayContaining(valuesOf(gated)),
      );
    });

    it('keeps a flag-gated type only while its flag is on', () => {
      const gatedType = { value: 'gated', text: 'Gated', featureFlag: 'someFlag' };
      FLOW_TRIGGER_TYPES.push(gatedType);

      try {
        expect(valuesOf(getEnabledFlowTriggerTypes({ someFlag: false }))).not.toContain('gated');
        expect(valuesOf(getEnabledFlowTriggerTypes({ someFlag: true }))).toContain('gated');
      } finally {
        FLOW_TRIGGER_TYPES.pop();
      }
    });

    it.each`
      aiFlowSchedules | autonomousServiceAccountExecution | available
      ${false}        | ${false}                          | ${false}
      ${true}         | ${false}                          | ${false}
      ${false}        | ${true}                           | ${false}
      ${true}         | ${true}                           | ${true}
    `(
      'schedule available=$available for aiFlowSchedules=$aiFlowSchedules, autonomous=$autonomousServiceAccountExecution',
      ({ aiFlowSchedules, autonomousServiceAccountExecution, available }) => {
        const values = valuesOf(
          getEnabledFlowTriggerTypes({ aiFlowSchedules, autonomousServiceAccountExecution }),
        );

        expect(values.includes('scheduled')).toBe(available);
      },
    );
  });

  describe('toFlowTriggerTypeOption', () => {
    // `~/locale` is mocked for this suite, so give sprintf just enough behaviour to show the
    // template and the item type reach it.
    beforeEach(() => {
      sprintf.mockImplementation((template, { itemType }) =>
        template.replace('%{itemType}', itemType),
      );
    });

    it('templates the description with the item type', () => {
      const option = toFlowTriggerTypeOption(
        { value: 'mention', text: 'Mention', description: 'Trigger %{itemType} on mention.' },
        'flow',
      );

      expect(option).toEqual({
        value: 'mention',
        text: 'Mention',
        description: 'Trigger flow on mention.',
      });
    });

    it('leaves the description undefined when the type has none', () => {
      const option = toFlowTriggerTypeOption({ value: 'assign', text: 'Assign' }, 'flow');

      expect(option.description).toBeUndefined();
    });
  });

  describe('flowTriggerModeFor', () => {
    it('reports the schedule type as a schedule', () => {
      expect(flowTriggerModeFor(FLOW_TRIGGER_MODE_SCHEDULE)).toBe(FLOW_TRIGGER_MODE_SCHEDULE);
    });

    it.each(['mention', 'pipeline_hooks', 'not_an_event', undefined])(
      'reports %p as an event',
      (typeValue) => {
        expect(flowTriggerModeFor(typeValue)).toBe(FLOW_TRIGGER_MODE_EVENT);
      },
    );
  });

  describe('randomizeScheduleDefaults', () => {
    beforeEach(() => {
      jest.spyOn(Math, 'random').mockReturnValue(0);
    });

    it('fills only the fields the daily preset needs and defaults the timezone', () => {
      expect(randomizeScheduleDefaults(SCHEDULE_FREQUENCY_DAILY, { timezone: 'Etc/UTC' })).toEqual({
        frequency: SCHEDULE_FREQUENCY_DAILY,
        minute: 0,
        hour: 0,
        timezone: 'Etc/UTC',
      });
    });

    it('adds a day-of-week for weekly and a day-of-month for monthly', () => {
      expect(randomizeScheduleDefaults(SCHEDULE_FREQUENCY_WEEKLY)).toMatchObject({ dayOfWeek: 0 });
      expect(randomizeScheduleDefaults(SCHEDULE_FREQUENCY_MONTHLY)).toMatchObject({
        dayOfMonth: 1,
      });
    });

    it('adds only a minute and timezone for the hourly preset', () => {
      expect(randomizeScheduleDefaults(SCHEDULE_FREQUENCY_HOURLY, { timezone: 'Etc/UTC' })).toEqual(
        {
          frequency: SCHEDULE_FREQUENCY_HOURLY,
          minute: 0,
          timezone: 'Etc/UTC',
        },
      );
    });

    it('stores only the frequency for sub-hour presets and defaults timezone to an empty string', () => {
      expect(randomizeScheduleDefaults(SCHEDULE_FREQUENCY_EVERY_15_MINUTES)).toEqual({
        frequency: SCHEDULE_FREQUENCY_EVERY_15_MINUTES,
      });
    });

    it('keeps randomized values within their domains across many runs', () => {
      jest.restoreAllMocks();

      Array.from({ length: 50 }).forEach(() => {
        const { minute, hour, dayOfMonth } = randomizeScheduleDefaults(SCHEDULE_FREQUENCY_MONTHLY);

        expect([0, 15, 30, 45]).toContain(minute);
        expect(hour).toBeGreaterThanOrEqual(0);
        expect(hour).toBeLessThanOrEqual(23);
        expect(dayOfMonth).toBeGreaterThanOrEqual(1);
        expect(dayOfMonth).toBeLessThanOrEqual(28);
      });
    });
  });

  describe('merge_request goal fan-out', () => {
    const readyFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready'] }] },
    };
    const readyConflictFilter = {
      merge_request: {
        rules: [{ field: 'action', operator: 'in', value: ['ready', 'code_conflict'] }],
      },
    };
    const readyApprovedFilter = {
      merge_request: { rules: [{ field: 'action', operator: 'in', value: ['ready', 'approved'] }] },
    };

    describe('denormalizeMergeRequestEventTypes', () => {
      it('moves the goal onto the restored event type', () => {
        const result = denormalizeMergeRequestEventTypes({
          eventTypes: [6],
          filter: readyFilter,
          goals: { merge_request: 'Summarise the diff.' },
        });

        expect(result.goals).toEqual({ merge_request_ready: 'Summarise the diff.' });
      });

      it('copies the goal onto every restored event type', () => {
        const result = denormalizeMergeRequestEventTypes({
          eventTypes: [6],
          filter: readyConflictFilter,
          goals: { merge_request: 'Summarise the diff.' },
        });

        expect(result.goals).toEqual({
          merge_request_ready: 'Summarise the diff.',
          merge_request_code_conflict: 'Summarise the diff.',
        });
      });

      // merge_request survives because `approved` is not foldable, so the goal stays on it too.
      it('keeps the goal on merge_request when a non-foldable action remains', () => {
        const result = denormalizeMergeRequestEventTypes({
          eventTypes: [6],
          filter: readyApprovedFilter,
          goals: { merge_request: 'Summarise the diff.' },
        });

        expect(result.goals).toEqual({
          merge_request: 'Summarise the diff.',
          merge_request_ready: 'Summarise the diff.',
        });
      });

      it('leaves other goals alone', () => {
        const result = denormalizeMergeRequestEventTypes({
          eventTypes: [0, 6],
          filter: readyFilter,
          goals: { mention: 'Reply to the thread.' },
        });

        expect(result.goals).toEqual({ mention: 'Reply to the thread.' });
      });
    });

    describe('normalizeMergeRequestEventTypes', () => {
      it('folds the goal back onto merge_request', () => {
        const result = normalizeMergeRequestEventTypes({
          eventTypes: [4],
          filter: {},
          goals: { merge_request_ready: 'Summarise the diff.' },
        });

        expect(result.goals).toEqual({ merge_request: 'Summarise the diff.' });
      });

      it('collapses agreeing goals into one', () => {
        const result = normalizeMergeRequestEventTypes({
          eventTypes: [4, 5],
          filter: {},
          goals: {
            merge_request_ready: 'Summarise the diff.',
            merge_request_code_conflict: 'Summarise the diff.',
          },
        });

        expect(result.goals).toEqual({ merge_request: 'Summarise the diff.' });
      });

      // Only reachable on a hand-made trigger: the form writes them together.
      it('prefers the goal already on merge_request when they disagree', () => {
        const result = normalizeMergeRequestEventTypes({
          eventTypes: [4, 6],
          filter: {
            merge_request: { rules: [{ field: 'action', operator: 'in', value: ['approved'] }] },
          },
          goals: {
            merge_request: 'Check the approvals.',
            merge_request_ready: 'Summarise the diff.',
          },
        });

        expect(result.goals).toEqual({ merge_request: 'Check the approvals.' });
      });
    });

    it('round-trips a goal through denormalize and normalize', () => {
      const saved = denormalizeMergeRequestEventTypes({
        eventTypes: [6],
        filter: readyConflictFilter,
        goals: { merge_request: 'Summarise the diff.' },
      });

      const loaded = normalizeMergeRequestEventTypes(saved);

      expect(loaded.goals).toEqual({ merge_request: 'Summarise the diff.' });
    });
  });
});
