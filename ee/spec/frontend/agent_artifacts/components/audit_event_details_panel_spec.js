import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AuditEventDetailsPanel from 'ee/agent_artifacts/components/audit_event_details_panel.vue';
import SummarySection from 'ee/agent_artifacts/components/summary_section.vue';
import DetailsSection from 'ee/agent_artifacts/components/details_section.vue';

describe('AuditEventDetailsPanel', () => {
  let wrapper;

  const mockEvent = {
    eventName: 'tool_execution',
    workflowId: '1908',
    details: { input_prompt: 'hello' },
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AuditEventDetailsPanel, {
      propsData: {
        event: mockEvent,
        flowName: 'false_positive_detection/v1',
        sessionId: '1908',
        ...props,
      },
    });
  };

  const findPanel = () => wrapper.findByTestId('audit-event-details-panel');
  const findTitle = () => wrapper.findByTestId('audit-event-title');
  const findSummarySection = () => wrapper.findComponent(SummarySection);
  const findDetailsSection = () => wrapper.findComponent(DetailsSection);
  const findDownloadSlot = () => wrapper.findByTestId('download-slot-content');

  beforeEach(() => {
    createComponent();
  });

  it('renders the panel', () => {
    expect(findPanel().exists()).toBe(true);
  });

  it('renders the formatted event name as the title', () => {
    expect(findTitle().text()).toBe('Tool execution');
  });

  it('renders the SummarySection with the event', () => {
    expect(findSummarySection().exists()).toBe(true);
    expect(findSummarySection().props('event')).toEqual(mockEvent);
  });

  describe('target', () => {
    it.each([
      ['unset (sessions API flag off)', null, 'Ai::DuoWorkflows::Workflow'],
      ['GITLAB_DUO', 'GITLAB_DUO', 'Ai::DuoWorkflows::Workflow'],
      ['CLAUDE_CODE_GLAB', 'CLAUDE_CODE_GLAB', 'Ai::Governance::Session'],
      ['CLAUDE_CODE_COMPLIANCE_API', 'CLAUDE_CODE_COMPLIANCE_API', 'Ai::Governance::Session'],
    ])('passes the target type for a source of %s', (_, source, targetType) => {
      createComponent({ source });

      expect(findSummarySection().props('targetType')).toBe(targetType);
    });

    it('builds the target details from the flow name and session id', () => {
      expect(findSummarySection().props('targetDetails')).toBe(
        'false_positive_detection/v1 session 1908',
      );
    });

    it('builds the target details for an external session from the session, not the event', () => {
      createComponent({
        event: { ...mockEvent, workflowId: null },
        flowName: 'Claude Code (glab)',
        sessionId: 'abc-123',
        source: 'CLAUDE_CODE_GLAB',
      });

      expect(findSummarySection().props('targetDetails')).toBe(
        'Claude Code (glab) session abc-123',
      );
    });

    it.each([
      ['flow name', { flowName: '' }],
      ['session id', { sessionId: '' }],
    ])('leaves the target details blank when the %s is missing', (_, props) => {
      createComponent(props);

      expect(findSummarySection().props('targetDetails')).toBe('');
    });
  });

  it('renders the DetailsSection with the event details', () => {
    expect(findDetailsSection().exists()).toBe(true);
    expect(findDetailsSection().props('details')).toEqual(mockEvent.details);
  });

  it('renders the download action slot alongside the title', () => {
    wrapper = shallowMountExtended(AuditEventDetailsPanel, {
      propsData: { event: mockEvent, flowName: 'false_positive_detection/v1', sessionId: '1908' },
      slots: { 'download-action': '<span data-testid="download-slot-content">Download</span>' },
    });

    expect(findDownloadSlot().exists()).toBe(true);
  });
});
