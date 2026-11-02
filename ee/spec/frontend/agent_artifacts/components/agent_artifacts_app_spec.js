import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { updateHistory } from '~/lib/utils/url_utility';
import AgentArtifactsApp from 'ee/agent_artifacts/components/agent_artifacts_app.vue';
import AgentArtifactsTable from 'ee/agent_artifacts/components/agent_artifacts_table.vue';
import AgentArtifactsFilteredSearch from 'ee/agent_artifacts/components/agent_artifacts_filtered_search.vue';
import SessionDetailsDrawer from 'ee/agent_artifacts/components/session_details_drawer.vue';

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  updateHistory: jest.fn(),
}));

describe('AgentArtifactsApp', () => {
  let wrapper;

  const mockItem = {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1',
    sessionId: '1',
    name: 'test-agent',
  };
  const mockEvent = { id: 'event-1', eventName: 'tool_execution' };

  const createComponent = () => {
    wrapper = shallowMountExtended(AgentArtifactsApp);
  };

  const findTable = () => wrapper.findComponent(AgentArtifactsTable);
  const findDrawer = () => wrapper.findComponent(SessionDetailsDrawer);

  const openDrawer = () => findTable().vm.$emit('row-click', mockItem);

  beforeEach(() => {
    createComponent();
  });

  describe('deep link from the dashboard', () => {
    const originalLocation = window.location;

    afterEach(() => {
      window.location = originalLocation;
    });

    const withSearch = (search) => {
      // The DAP session page 404s for anyone who did not run the session, so
      // the dashboard links here with ?session= instead.
      delete window.location;
      window.location = { ...originalLocation, search };
      createComponent();
    };

    it('passes the session id from the URL to the table', () => {
      withSearch('?tab=agent-artifacts&session=42');

      expect(findTable().props('deepLinkedSessionId')).toBe('42');
    });

    it('passes null when there is no session param', () => {
      withSearch('?tab=agent-artifacts');

      expect(findTable().props('deepLinkedSessionId')).toBe(null);
    });

    it('stops passing the id once a row has opened, so paging does not reopen it', async () => {
      withSearch('?session=42');

      await findTable().vm.$emit('row-click', mockItem);

      expect(findTable().props('deepLinkedSessionId')).toBe(null);
      expect(findDrawer().exists()).toBe(true);
    });
  });

  // The URL has to follow what is open, or copying it after switching rows
  // shares the wrong session and a refresh reopens the wrong one.
  describe('keeping ?session= in step with the drawer', () => {
    beforeEach(() => {
      updateHistory.mockClear();
    });

    it('sets the param to the session that was opened', async () => {
      await findTable().vm.$emit('row-click', mockItem);

      expect(updateHistory).toHaveBeenCalledWith(
        expect.objectContaining({ url: expect.stringContaining('session=1'), replace: true }),
      );
    });

    it('sets the param to the source session id, never the global id', async () => {
      await findTable().vm.$emit('row-click', {
        id: 'gid://gitlab/Ai::Governance::Session/501',
        sessionId: 'abc-123',
      });

      const { url } = updateHistory.mock.calls[0][0];
      expect(url).toContain('session=abc-123');
      expect(url).not.toContain('501');
    });

    it('drops the param when the drawer closes', async () => {
      await findTable().vm.$emit('row-click', mockItem);
      updateHistory.mockClear();

      await findDrawer().vm.$emit('close');

      expect(updateHistory).toHaveBeenCalledWith(
        expect.objectContaining({ url: expect.not.stringContaining('session='), replace: true }),
      );
    });

    it('drops the param when filtering, since the open row may vanish', async () => {
      await findTable().vm.$emit('row-click', mockItem);
      updateHistory.mockClear();

      await wrapper.findComponent(AgentArtifactsFilteredSearch).vm.$emit('filter', { x: 1 });

      expect(updateHistory).toHaveBeenCalledWith(
        expect.objectContaining({ url: expect.not.stringContaining('session='), replace: true }),
      );
    });

    it('drops a deep link that matched nothing, rather than leaving a dead param', async () => {
      await findTable().vm.$emit('deep-link-missed');

      expect(findTable().props('deepLinkedSessionId')).toBe(null);
      expect(updateHistory).toHaveBeenCalledWith(
        expect.objectContaining({ url: expect.not.stringContaining('session='), replace: true }),
      );
    });
  });

  it('renders the agent artifacts filtered search', () => {
    expect(wrapper.findComponent(AgentArtifactsFilteredSearch).exists()).toBe(true);
  });

  it('renders the agent artifacts table', () => {
    expect(wrapper.findComponent(AgentArtifactsTable).exists()).toBe(true);
  });

  describe('SessionDetailsDrawer', () => {
    it('does not render drawer when no active item', () => {
      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(false);
    });

    it('renders drawer when row is clicked', async () => {
      await wrapper.findComponent(AgentArtifactsTable).vm.$emit('row-click', mockItem);

      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(true);
      expect(wrapper.findComponent(SessionDetailsDrawer).props('activeItem')).toEqual(mockItem);
    });

    it('closes drawer when close event is emitted', async () => {
      await wrapper.findComponent(AgentArtifactsTable).vm.$emit('row-click', mockItem);
      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(true);

      await wrapper.findComponent(SessionDetailsDrawer).vm.$emit('close');
      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(false);
    });
  });

  describe('filtering', () => {
    it('closes session details drawer when filter changes', async () => {
      await wrapper
        .findComponent(AgentArtifactsTable)
        .vm.$emit('row-click', { id: '1', name: 'test-agent' });
      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(true);

      await wrapper
        .findComponent(AgentArtifactsFilteredSearch)
        .vm.$emit('filter', { name: 'another-agent' });

      expect(wrapper.findComponent(SessionDetailsDrawer).exists()).toBe(false);
    });
  });

  describe('event selection', () => {
    it('sets the selected event when the drawer emits select', async () => {
      await openDrawer();

      await findDrawer().vm.$emit('select', mockEvent);

      expect(findDrawer().props('selectedEvent')).toEqual(mockEvent);
    });

    it('clears the selected event when the drawer emits back', async () => {
      await openDrawer();
      await findDrawer().vm.$emit('select', mockEvent);

      await findDrawer().vm.$emit('back');

      expect(findDrawer().props('selectedEvent')).toBeNull();
    });

    it('clears the selected event when another session row is clicked', async () => {
      const otherItem = { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/2', name: 'other-agent' };

      await openDrawer();
      await findDrawer().vm.$emit('select', mockEvent);

      await findTable().vm.$emit('row-click', otherItem);

      expect(findDrawer().props('activeItem')).toEqual(otherItem);
      expect(findDrawer().props('selectedEvent')).toBeNull();
    });

    it('clears the selected event when the same session row is clicked again', async () => {
      await openDrawer();
      await findDrawer().vm.$emit('select', mockEvent);

      await findTable().vm.$emit('row-click', mockItem);

      expect(findDrawer().props('selectedEvent')).toBeNull();
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks an audit event opened from the drawer', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      await openDrawer();

      await findDrawer().vm.$emit('select', mockEvent);

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'open_audit_event_on_ai_audit_events_report',
        {},
        undefined,
      );
      expect(findDrawer().props('selectedEvent')).toEqual(mockEvent);
    });

    it('does not track opening or closing the drawer itself', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      await openDrawer();

      await findDrawer().vm.$emit('back');
      await findDrawer().vm.$emit('close');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });
});
