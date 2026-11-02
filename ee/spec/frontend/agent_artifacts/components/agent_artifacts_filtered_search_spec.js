import { nextTick } from 'vue';
import { GlFilteredSearch } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import AgentArtifactsFilteredSearch from 'ee/agent_artifacts/components/agent_artifacts_filtered_search.vue';

describe('AgentArtifactsFilteredSearch', () => {
  let wrapper;

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(AgentArtifactsFilteredSearch, {
      provide: {
        groupId: null,
        groupFullPath: null,
        projectFullPath: null,
        ...provide,
      },
    });
  };

  const findFilteredSearch = () => wrapper.findComponent(GlFilteredSearch);

  beforeEach(() => {
    createComponent();
  });

  it('renders GlFilteredSearch component', () => {
    expect(findFilteredSearch().exists()).toBe(true);
  });

  describe('available tokens', () => {
    const tokenTypes = () =>
      findFilteredSearch()
        .props('availableTokens')
        .map((token) => token.type);

    it('shows the date, triggered-by and agent class tokens in project mode', () => {
      createComponent({ provide: { projectFullPath: 'g/p' } });

      expect(tokenTypes()).toEqual([
        'startTimeAfter',
        'startTimeBefore',
        'triggeredByUserId',
        'agentClass',
      ]);
    });

    it('shows the project token as well in group mode', () => {
      createComponent({ provide: { groupId: 'gid://gitlab/Group/1' } });

      expect(tokenTypes()).toEqual([
        'startTimeAfter',
        'startTimeBefore',
        'projectPath',
        'triggeredByUserId',
        'agentClass',
      ]);
    });

    it('offers the dashboard agent classes on the agent class token, with = only', () => {
      const token = findFilteredSearch()
        .props('availableTokens')
        .find((t) => t.type === 'agentClass');

      expect(token.options).toEqual([
        { value: 'INTERNAL_DAP', title: 'DAP' },
        { value: 'EXTERNAL', title: 'Connected' },
      ]);
      expect(token.operators.map(({ value }) => value)).toEqual(['=']);
      expect(token.unique).toBe(true);
    });

    describe('triggeredByUserId token config', () => {
      it('uses groupFullPath as fullPath in group mode', () => {
        createComponent({
          provide: { groupId: 'gid://gitlab/Group/1', groupFullPath: 'my-group' },
        });

        const token = findFilteredSearch()
          .props('availableTokens')
          .find((t) => t.type === 'triggeredByUserId');

        expect(token.fullPath).toBe('my-group');
        expect(token.isProject).toBe(false);
      });

      it('uses projectFullPath as fullPath in project mode', () => {
        createComponent({ provide: { projectFullPath: 'my-group/my-project' } });

        const token = findFilteredSearch()
          .props('availableTokens')
          .find((t) => t.type === 'triggeredByUserId');

        expect(token.fullPath).toBe('my-group/my-project');
        expect(token.isProject).toBe(true);
      });

      it('sets valueField to id', () => {
        createComponent();

        const token = findFilteredSearch()
          .props('availableTokens')
          .find((t) => t.type === 'triggeredByUserId');

        expect(token.valueField).toBe('id');
      });

      it('sets defaultUsers to empty array', () => {
        createComponent();

        const token = findFilteredSearch()
          .props('availableTokens')
          .find((t) => t.type === 'triggeredByUserId');

        expect(token.defaultUsers).toEqual([]);
      });
    });
  });

  describe('handleSubmit', () => {
    it('emits filter event with variables for = operator', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'name',
          value: {
            data: 'False Positive Detection',
            operator: '=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        name: 'False Positive Detection',
      });
    });

    it('emits filter event with not variables for != operator', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'name',
          value: {
            data: 'Code Review Assistant',
            operator: '!=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        not: {
          name: 'Code Review Assistant',
        },
      });
    });

    it('handles multiple filters with mixed operators', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'name',
          value: {
            data: 'Agent 1',
            operator: '=',
          },
        },
        {
          type: 'status',
          value: {
            data: 'active',
            operator: '!=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        name: 'Agent 1',
        not: {
          status: 'active',
        },
      });
    });

    it('ignores filters without value data', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'name',
          value: {},
        },
        {
          type: 'status',
          value: {
            data: 'active',
            operator: '=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        status: 'active',
      });
    });

    it('emits empty object when no filters applied', () => {
      findFilteredSearch().vm.$emit('input', []);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({});
    });

    it('routes triggeredByUserId with = operator to triggeredByUserId variable', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'triggeredByUserId',
          value: {
            data: 'gid://gitlab/User/42',
            operator: '=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        triggeredByUserId: 'gid://gitlab/User/42',
      });
    });

    it('routes triggeredByUserId with != operator to not.triggeredByUserId variable', () => {
      findFilteredSearch().vm.$emit('input', [
        {
          type: 'triggeredByUserId',
          value: {
            data: 'gid://gitlab/User/42',
            operator: '!=',
          },
        },
      ]);

      findFilteredSearch().vm.$emit('submit');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        not: {
          triggeredByUserId: 'gid://gitlab/User/42',
        },
      });
    });
  });

  describe('when clearing filter', () => {
    it('emits filter event with empty object when clear is clicked', () => {
      findFilteredSearch().vm.$emit('clear');

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(wrapper.emitted('filter')[0][0]).toEqual({});
    });
  });

  describe('seeding from the URL', () => {
    it('pre-applies known filter params from the query string on load', async () => {
      setWindowLocation(
        '?tab=agent-artifacts&triggeredByUserId=gid://gitlab/User/7&projectPath=g/p&agentClass=EXTERNAL&startTimeAfter=2026-10-12',
      );
      createComponent({ provide: { groupId: 'gid://gitlab/Group/1' } });

      expect(findFilteredSearch().props('value')).toEqual([
        { type: 'triggeredByUserId', value: { data: 'gid://gitlab/User/7', operator: '=' } },
        { type: 'projectPath', value: { data: 'g/p', operator: '=' } },
        { type: 'startTimeAfter', value: { data: '2026-10-12', operator: '=' } },
        { type: 'agentClass', value: { data: 'EXTERNAL', operator: '=' } },
      ]);

      // The filter is emitted after the initial render so the table applies it.
      await nextTick();
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        triggeredByUserId: 'gid://gitlab/User/7',
        projectPath: 'g/p',
        startTimeAfter: '2026-10-12',
        agentClass: 'EXTERNAL',
      });
    });

    it('skips a URL filter type whose token is unavailable in the current mode', async () => {
      setWindowLocation(
        '?tab=agent-artifacts&triggeredByUserId=gid://gitlab/User/7&projectPath=g/p',
      );
      // Project mode has no projectPath token, so only triggeredByUserId seeds.
      createComponent({ provide: { projectFullPath: 'g/p' } });

      expect(findFilteredSearch().props('value')).toEqual([
        { type: 'triggeredByUserId', value: { data: 'gid://gitlab/User/7', operator: '=' } },
      ]);

      await nextTick();
      expect(wrapper.emitted('filter')[0][0]).toEqual({
        triggeredByUserId: 'gid://gitlab/User/7',
      });
    });

    it('does not seed or emit when no known filter params are present', () => {
      setWindowLocation('?tab=agent-artifacts');
      createComponent();

      expect(findFilteredSearch().props('value')).toEqual([]);
      expect(wrapper.emitted('filter')).toBeUndefined();
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const APPLY_FILTER_EVENT = 'apply_filter_on_ai_audit_events_report';

    const submitFilters = (filters) => {
      findFilteredSearch().vm.$emit('input', filters);
      findFilteredSearch().vm.$emit('submit');
    };

    it('tracks one apply event per applied filter, labelled by filter type', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submitFilters([
        { type: 'startTimeAfter', value: { data: '2026-01-01', operator: '=' } },
        { type: 'startTimeBefore', value: { data: '2026-02-01', operator: '=' } },
        { type: 'projectPath', value: { data: 'g/p', operator: '!=' } },
        { type: 'triggeredByUserId', value: { data: 'gid://gitlab/User/42', operator: '=' } },
        { type: 'agent', value: { data: 'cursor', operator: '=' } },
      ]);

      expect(trackEventSpy.mock.calls).toEqual([
        [APPLY_FILTER_EVENT, { label: 'created_after' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'created_before' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'project' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'triggered_by' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'agent' }, undefined],
      ]);
      expect(wrapper.emitted('filter')).toHaveLength(1);
    });

    it('tracks the agent token under the agent label, whichever name the token has', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submitFilters([{ type: 'agentType', value: { data: 'cursor', operator: '=' } }]);
      submitFilters([{ type: 'agent', value: { data: 'cursor', operator: '=' } }]);

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
      expect(trackEventSpy).toHaveBeenNthCalledWith(
        1,
        APPLY_FILTER_EVENT,
        { label: 'agent' },
        undefined,
      );
      expect(trackEventSpy).toHaveBeenNthCalledWith(
        2,
        APPLY_FILTER_EVENT,
        { label: 'agent' },
        undefined,
      );
    });

    it('tracks a token type it does not know under its snake_case name', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submitFilters([{ type: 'someNewToken', value: { data: 'x', operator: '=' } }]);

      expect(trackEventSpy).toHaveBeenCalledWith(
        APPLY_FILTER_EVENT,
        { label: 'some_new_token' },
        undefined,
      );
    });

    it('tracks nothing for filters without a value or for an empty submit', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submitFilters([{ type: 'projectPath', value: {} }]);
      submitFilters([]);

      expect(trackEventSpy).not.toHaveBeenCalled();
      expect(wrapper.emitted('filter')).toHaveLength(2);
    });

    it('tracks only the filters added or changed since the last search', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      const project = (data) => ({ type: 'projectPath', value: { data, operator: '=' } });
      const user = {
        type: 'triggeredByUserId',
        value: { data: 'gid://gitlab/User/42', operator: '=' },
      };

      submitFilters([project('g/a')]);
      submitFilters([project('g/a'), user]);
      submitFilters([project('g/b'), user]);

      expect(trackEventSpy.mock.calls).toEqual([
        [APPLY_FILTER_EVENT, { label: 'project' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'triggered_by' }, undefined],
        [APPLY_FILTER_EVENT, { label: 'project' }, undefined],
      ]);
    });

    it('counts a filter again when it is applied after a clear', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      const filters = [{ type: 'projectPath', value: { data: 'g/a', operator: '=' } }];

      submitFilters(filters);
      findFilteredSearch().vm.$emit('clear');
      submitFilters(filters);

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
    });

    it('does not track a clear', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findFilteredSearch().vm.$emit('clear');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('does not track the filters seeded from the URL', async () => {
      setWindowLocation(
        '?tab=agent-artifacts&triggeredByUserId=gid://gitlab/User/7&agentClass=EXTERNAL&startTimeAfter=2026-10-12',
      );
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await nextTick();

      expect(wrapper.emitted('filter')).toHaveLength(1);
      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('does not count the filters seeded from the URL on a later search', async () => {
      setWindowLocation('?tab=agent-artifacts&triggeredByUserId=gid://gitlab/User/7');
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      await nextTick();

      submitFilters([
        { type: 'triggeredByUserId', value: { data: 'gid://gitlab/User/7', operator: '=' } },
        { type: 'startTimeAfter', value: { data: '2026-01-01', operator: '=' } },
      ]);

      expect(trackEventSpy.mock.calls).toEqual([
        [APPLY_FILTER_EVENT, { label: 'created_after' }, undefined],
      ]);
    });
  });
});
