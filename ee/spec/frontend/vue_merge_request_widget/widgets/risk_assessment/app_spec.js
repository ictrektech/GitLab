import Vue from 'vue';
import VueApollo from 'vue-apollo';
import MockAdapter from 'axios-mock-adapter';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import RiskAssessmentApp from 'ee/vue_merge_request_widget/widgets/risk_assessment/app.vue';
import RiskAssessmentWidget from 'ee/vue_merge_request_widget/widgets/risk_assessment/index.vue';
import riskAssessmentQuery from 'ee/vue_merge_request_widget/widgets/risk_assessment/graphql/risk_assessment.query.graphql';
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_CREATED } from '~/lib/utils/http_status';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('WidgetRiskAssessmentApp', () => {
  let wrapper;
  let mockAxios;

  const workflowsPath = '/api/v4/ai/duo_workflows/workflows';

  const mergeRequest = {
    iid: 1,
    targetProjectFullPath: 'gitlab-org/gitlab',
    sourceProjectFullPath: 'gitlab-org/gitlab-fork',
  };

  const completedAssessment = {
    status: 'COMPLETE',
    riskTier: 'LOW',
    confidenceTier: 'HIGH',
    rationale: null,
    stale: false,
    duoWorkflowId: null,
    contributingSignals: [],
    missingSignals: [],
  };

  const queryResponse = (riskAssessment, canRefresh = false) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        duoWorkflowStatusCheck: {
          createDuoWorkflowForCiAllowed: canRefresh,
        },
        mergeRequest: {
          id: 'gid://gitlab/MergeRequest/1',
          sourceBranch: 'feature',
          riskAssessment,
        },
      },
    },
  });

  const configuredFlowsResponse = (
    nodes = [{ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' }],
  ) => ({
    data: { aiCatalogConfiguredItems: { nodes } },
  });

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(queryResponse(completedAssessment)),
    flowsHandler = jest.fn().mockResolvedValue(configuredFlowsResponse()),
    propsData = {},
    scopedSlots,
  } = {}) => {
    wrapper = shallowMountExtended(RiskAssessmentApp, {
      propsData: { mergeRequest, ...propsData },
      scopedSlots,
      apolloProvider: createMockApollo([
        [riskAssessmentQuery, handler],
        [getConfiguredFlows, flowsHandler],
      ]),
    });

    return handler;
  };

  const findWidget = () => wrapper.findComponent(RiskAssessmentWidget);

  beforeEach(() => {
    window.gon = { api_version: 'v4' };
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('while the assessment is loading', () => {
    it('does not render the widget', () => {
      createComponent();

      expect(findWidget().exists()).toBe(false);
    });
  });

  describe('once the assessment arrives', () => {
    it('requests the assessment for the target project', async () => {
      const handler = createComponent();
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({ projectPath: 'gitlab-org/gitlab', iid: '1' });
    });

    it('falls back to the source project when there is no target project', async () => {
      const handler = createComponent({
        propsData: { mergeRequest: { ...mergeRequest, targetProjectFullPath: null } },
      });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        projectPath: 'gitlab-org/gitlab-fork',
        iid: '1',
      });
    });

    it('passes the assessment to the widget', async () => {
      createComponent();
      await waitForPromises();

      expect(findWidget().props()).toMatchObject({
        riskAssessment: completedAssessment,
        isLoading: false,
        hasError: false,
      });
    });
  });

  describe('when the project is not assessing merge requests', () => {
    it('does not render the widget', async () => {
      createComponent({ handler: jest.fn().mockResolvedValue(queryResponse(null)) });
      await waitForPromises();

      expect(findWidget().exists()).toBe(false);
    });
  });

  describe('when the query fails', () => {
    it('renders the widget in its error state', async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
      await waitForPromises();

      expect(findWidget().props()).toMatchObject({
        riskAssessment: null,
        isLoading: false,
        hasError: true,
      });
    });
  });

  describe('refreshing the assessment', () => {
    const staleAssessment = { ...completedAssessment, stale: true };

    it('lets the widget offer a refresh when the user may run the enabled flow', async () => {
      const flowsHandler = jest.fn().mockResolvedValue(configuredFlowsResponse());
      createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(staleAssessment, true)),
        flowsHandler,
      });
      await waitForPromises();

      expect(flowsHandler).toHaveBeenCalledWith({
        projectId: 'gid://gitlab/Project/1',
        foundationalFlowReference: 'risk_classification/v1',
      });
      expect(findWidget().props('canRefresh')).toBe(true);
    });

    it('offers no refresh when the flow is not enabled for the project', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(staleAssessment, true)),
        flowsHandler: jest.fn().mockResolvedValue(configuredFlowsResponse([])),
      });
      await waitForPromises();

      expect(findWidget().props('canRefresh')).toBe(false);
    });

    it('offers no refresh when the user may not run flows', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(staleAssessment, false)),
      });
      await waitForPromises();

      expect(findWidget().props('canRefresh')).toBe(false);
    });

    it('starts the flow for the same merge request and refetches the assessment', async () => {
      mockAxios.onPost(workflowsPath).reply(HTTP_STATUS_CREATED, {});
      const handler = createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(staleAssessment, true)),
      });
      await waitForPromises();

      findWidget().vm.$emit('refresh');
      await waitForPromises();

      expect(mockAxios.history.post).toHaveLength(1);
      expect(JSON.parse(mockAxios.history.post[0].data)).toEqual({
        project_id: 1,
        ai_catalog_item_consumer_id: 7,
        start_workflow: true,
        source_branch: 'feature',
        merge_request_id: 1,
      });
      expect(handler).toHaveBeenCalledTimes(2);
      expect(findWidget().props('isSubmitting')).toBe(false);
    });

    it('alerts and does not refetch when the flow cannot start', async () => {
      mockAxios.onPost(workflowsPath).reply(HTTP_STATUS_BAD_REQUEST, { message: 'nope' });
      const handler = createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(staleAssessment, true)),
      });
      await waitForPromises();

      findWidget().vm.$emit('refresh');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Could not start a new risk assessment.' }),
      );
      expect(handler).toHaveBeenCalledTimes(1);
      expect(findWidget().props('isSubmitting')).toBe(false);
    });

    it('does not claim the flow failed to start when only the refetch fails', async () => {
      mockAxios.onPost(workflowsPath).reply(HTTP_STATUS_CREATED, {});
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(queryResponse(staleAssessment, true))
          .mockRejectedValueOnce(new Error('nope')),
      });
      await waitForPromises();

      findWidget().vm.$emit('refresh');
      await waitForPromises();

      expect(createAlert).not.toHaveBeenCalled();
      expect(findWidget().props()).toMatchObject({ hasError: true, isSubmitting: false });
    });
  });

  // The merge request overview draws the assessment its own way from the same data.
  describe('when another surface renders the assessment', () => {
    let slotProps;

    const createWithSlot = (options = {}) =>
      createComponent({
        ...options,
        scopedSlots: {
          default(props) {
            slotProps = props;
            return this.$createElement('div', { attrs: { 'data-testid': 'custom-risk' } });
          },
        },
      });

    beforeEach(() => {
      slotProps = null;
    });

    it('renders the slot in place of the widget, with the data the widget would get', async () => {
      createWithSlot({
        handler: jest.fn().mockResolvedValue(queryResponse(completedAssessment, true)),
      });
      await waitForPromises();

      expect(findWidget().exists()).toBe(false);
      expect(wrapper.findByTestId('custom-risk').exists()).toBe(true);
      expect(slotProps).toMatchObject({
        riskAssessment: completedAssessment,
        isLoading: false,
        hasError: false,
        canRefresh: true,
        isSubmitting: false,
      });
    });

    it('lets the slot start a refresh', async () => {
      mockAxios.onPost(workflowsPath).reply(HTTP_STATUS_CREATED, {});
      const handler = createWithSlot({
        handler: jest.fn().mockResolvedValue(queryResponse(completedAssessment, true)),
      });
      await waitForPromises();

      slotProps.refresh();
      await waitForPromises();

      expect(mockAxios.history.post).toHaveLength(1);
      expect(handler).toHaveBeenCalledTimes(2);
    });

    it('renders nothing, slot included, when there is no assessment to show', async () => {
      createWithSlot({ handler: jest.fn().mockResolvedValue(queryResponse(null)) });
      await waitForPromises();

      expect(wrapper.findByTestId('custom-risk').exists()).toBe(false);
      expect(slotProps).toBeNull();
    });
  });
});
