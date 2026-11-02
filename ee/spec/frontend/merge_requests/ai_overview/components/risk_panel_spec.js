import Vue from 'vue';
import VueApollo from 'vue-apollo';
import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import SeverityMeter from 'ee/vue_shared/components/severity_meter/severity_meter.vue';
import RiskPanel from 'ee/merge_requests/ai_overview/components/risk_panel.vue';
import RiskConfidenceNotice from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_confidence_notice.vue';
import RiskRationale from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_rationale.vue';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_signal_breakdown.vue';
import riskAssessmentQuery from 'ee/vue_merge_request_widget/widgets/risk_assessment/graphql/risk_assessment.query.graphql';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_CREATED } from '~/lib/utils/http_status';
import { makeRiskAssessment, riskAssessmentResponse } from '../mock_data';

Vue.use(VueApollo);

describe('AI Overview risk panel', () => {
  let wrapper;
  let mockAxios;
  let queryHandler;

  const workflowsPath = '/api/v4/ai/duo_workflows/workflows';

  const configuredFlowsResponse = () => ({
    data: {
      aiCatalogConfiguredItems: {
        __typename: 'AiCatalogItemConsumerConnection',
        nodes: [
          { __typename: 'AiCatalogItemConsumer', id: 'gid://gitlab/Ai::Catalog::ItemConsumer/5' },
        ],
      },
    },
  });

  const duoChatAvailableResponse = (available) => ({
    data: {
      currentUser: {
        __typename: 'CurrentUser',
        id: 'gid://gitlab/User/1',
        duoChatAvailable: available,
      },
    },
  });

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(riskAssessmentResponse()),
    duoChatAvailable = true,
  } = {}) => {
    queryHandler = handler;

    wrapper = mountExtended(RiskPanel, {
      apolloProvider: createMockApollo([
        [riskAssessmentQuery, queryHandler],
        [getConfiguredFlows, jest.fn().mockResolvedValue(configuredFlowsResponse())],
        [
          duoChatAvailableQuery,
          jest.fn().mockResolvedValue(duoChatAvailableResponse(duoChatAvailable)),
        ],
      ]),
      provide: { projectPath: 'group/proj', iid: '1' },
      // It links to the session page, which is not what is under test here.
      stubs: { ViewSessionButton: stubComponent(ViewSessionButton) },
    });
  };

  const createWithAssessment = async (overrides, options = {}) => {
    createComponent({
      handler: jest.fn().mockResolvedValue(riskAssessmentResponse(makeRiskAssessment(overrides))),
      ...options,
    });
    await waitForPromises();
  };

  const findPanel = () => wrapper.findByTestId('risk-panel');
  const findTitle = () => wrapper.findByTestId('risk-title');
  const findMeter = () => wrapper.findComponent(SeverityMeter);
  const findUpdating = () => wrapper.findByTestId('risk-updating');
  const findDetails = () => wrapper.findByTestId('risk-details');
  const findRationale = () => wrapper.findComponent(RiskRationale);
  const findBreakdown = () => wrapper.findComponent(RiskSignalBreakdown);
  const findLowConfidence = () => wrapper.findComponent(RiskConfidenceNotice);
  const findStaleWarning = () => wrapper.findByTestId('risk-stale-warning');
  const findRefresh = () => wrapper.findByTestId('risk-refresh-button');
  const findSessionButton = () => wrapper.findComponent(ViewSessionButton);
  const findToggle = () => wrapper.findByTestId('risk-details-toggle');

  beforeEach(() => {
    window.gon = { api_version: 'v4' };
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  it('asks for the assessment of this merge request', async () => {
    createComponent();
    await waitForPromises();

    expect(queryHandler).toHaveBeenCalledWith({ projectPath: 'group/proj', iid: '1' });
  });

  it('renders nothing while the assessment loads', () => {
    createComponent();

    expect(findPanel().exists()).toBe(false);
  });

  // The field is null when the flow is not available to the project, or has not run yet.
  it('renders nothing when there is no assessment', async () => {
    createComponent({ handler: jest.fn().mockResolvedValue(riskAssessmentResponse(null)) });
    await waitForPromises();

    expect(findPanel().exists()).toBe(false);
  });

  describe('with a completed assessment', () => {
    beforeEach(async () => {
      await createWithAssessment();
    });

    it('shows the risk and confidence tiers in the headline', () => {
      expect(findTitle().text()).toBe('Risk assessment: High with medium confidence');
      expect(findTitle().find('strong').text()).toBe('Risk assessment:');
      expect(findUpdating().exists()).toBe(false);
    });

    it('fills the meter to the risk tier', () => {
      expect(findMeter().props()).toMatchObject({
        severity: 'HIGH',
        label: 'Risk level: High risk',
        loading: false,
      });
    });

    it('explains the score with the same details as the merge widget', () => {
      expect(findRationale().props('rationale')).toBe('Changes the merge path without new tests.');
      expect(findBreakdown().props('contributions')).toHaveLength(1);
      expect(findBreakdown().text()).toContain('Size of change');
      expect(findBreakdown().text()).toContain('Major increase');
      expect(findLowConfidence().exists()).toBe(false);
    });

    it('does not warn about staleness', () => {
      expect(findStaleWarning().exists()).toBe(false);
    });

    it('offers no session link without a session', () => {
      expect(findSessionButton().exists()).toBe(false);
    });

    describe('details', () => {
      it('are collapsed by default, leaving the headline and meter on show', () => {
        expect(findDetails().element.style.display).toBe('none');
        expect(findMeter().props('severity')).toBe('HIGH');
        expect(findToggle().attributes()).toMatchObject({
          'aria-label': 'Show details',
          'aria-expanded': 'false',
          'aria-controls': findDetails().attributes('id'),
        });
      });

      it('expand and collapse from the toggle', async () => {
        await findToggle().trigger('click');

        expect(findDetails().element.style.display).toBe('');
        expect(findToggle().attributes()).toMatchObject({
          'aria-label': 'Hide details',
          'aria-expanded': 'true',
        });

        await findToggle().trigger('click');

        expect(findDetails().element.style.display).toBe('none');
      });
    });
  });

  describe('when the assessment predates the latest changes', () => {
    it('warns and offers a refresh', async () => {
      await createWithAssessment({ stale: true });

      expect(findStaleWarning().exists()).toBe(true);
      expect(findRefresh().exists()).toBe(true);
    });

    it('starts a new assessment and reloads it on refresh', async () => {
      mockAxios.onPost(workflowsPath).reply(HTTP_STATUS_CREATED, {});
      await createWithAssessment({ stale: true });

      await findRefresh().trigger('click');
      await waitForPromises();

      expect(mockAxios.history.post).toHaveLength(1);
      expect(JSON.parse(mockAxios.history.post[0].data)).toMatchObject({
        project_id: 7,
        ai_catalog_item_consumer_id: 5,
        start_workflow: true,
        source_branch: 'feature',
        merge_request_id: '1',
      });
      expect(queryHandler).toHaveBeenCalledTimes(2);
    });

    it.each(['QUEUED', 'SCORING'])('stops warning once a refresh is %s', async (status) => {
      await createWithAssessment({ stale: true, status });

      expect(findStaleWarning().exists()).toBe(false);
    });

    it('still warns after a failed run', async () => {
      await createWithAssessment({ stale: true, status: 'FAILED' });

      expect(findStaleWarning().exists()).toBe(true);
      expect(findRationale().exists()).toBe(false);
    });
  });

  it('names the signals it could not measure when confidence is low', async () => {
    await createWithAssessment({
      confidenceTier: 'LOW',
      missingSignals: [
        { __typename: 'MergeRequestRiskMissingSignal', signal: 'test_coverage', label: 'Tests' },
        { __typename: 'MergeRequestRiskMissingSignal', signal: 'some_claim', label: null },
      ],
    });

    expect(findTitle().text()).toBe('Risk assessment: High with low confidence');
    expect(findLowConfidence().props('missingLabels')).toEqual(['Tests']);
  });

  // The backend scores tier and confidence independently, so confidence can come back empty.
  it('still names the tier when confidence did not resolve', async () => {
    await createWithAssessment({ confidenceTier: null });

    expect(findTitle().text()).toBe('Risk assessment: High');
  });

  describe('the Duo session that produced it', () => {
    it('is linked from the details', async () => {
      await createWithAssessment({ duoWorkflowId: 42 });

      expect(findSessionButton().props('sessionId')).toBe(42);
      expect(findDetails().element.contains(findSessionButton().element)).toBe(true);
    });

    it('is not linked when the user cannot use Duo Chat', async () => {
      await createWithAssessment({ duoWorkflowId: 42 }, { duoChatAvailable: false });

      expect(findSessionButton().exists()).toBe(false);
    });
  });

  it.each(['QUEUED', 'SCORING'])(
    'keeps the previous result while a refresh is %s, without its details',
    async (status) => {
      await createWithAssessment({ status });

      expect(findTitle().text()).toBe('Risk assessment: High with medium confidence');
      expect(findUpdating().text()).toBe('Updating…');
      expect(findMeter().props('severity')).toBe('HIGH');
      expect(findToggle().exists()).toBe(false);
    },
  );

  it.each`
    status       | title
    ${'PENDING'} | ${'Risk assessment: Pending'}
    ${'QUEUED'}  | ${'Risk assessment: Queued'}
    ${'SCORING'} | ${'Risk assessment: Queued'}
    ${'FAILED'}  | ${'Risk assessment: Unavailable'}
  `('says "$title" with no result to show when $status', async ({ status, title }) => {
    await createWithAssessment({ status, riskTier: null, confidenceTier: null });

    expect(findTitle().text()).toBe(title);
    expect(findMeter().props()).toMatchObject({
      severity: null,
      label: 'Risk level not available',
    });
    expect(findBreakdown().exists()).toBe(false);
    expect(findToggle().exists()).toBe(false);
  });

  it('does not trust the last result of a failed run', async () => {
    await createWithAssessment({ status: 'FAILED' });

    expect(findTitle().text()).toBe('Risk assessment: Unavailable');
    expect(findMeter().props('severity')).toBe(null);
    expect(findRationale().exists()).toBe(false);
  });

  it('says so when the assessment cannot be loaded', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
    await waitForPromises();

    expect(findTitle().text()).toBe('Risk assessment: Not available');
    expect(findPanel().text()).toContain('Failed to load the risk assessment');
    expect(findMeter().props('severity')).toBe(null);
    expect(findToggle().exists()).toBe(false);
  });
});
