import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AgenticChatVerificationCheck from 'ee/ai/settings/components/functional_verifications/agentic_chat_verification_check.vue';
import FunctionalVerificationCheck from 'ee/ai/settings/components/functional_verifications/functional_verification_check.vue';
import getFunctionalVerificationStatusQuery from 'ee/ai/settings/graphql/queries/get_functional_verification_status.query.graphql';
import createFunctionalVerificationWorkflowMutation from 'ee/ai/settings/components/functional_verifications/graphql/mutations/create_functional_verification_workflow.mutation.graphql';
import { runChatTurn, CHAT_TURN_OUTCOME } from 'ee/ai/duo_agentic_chat';
import {
  FUNCTIONAL_VERIFICATION_STATUS,
  MODEL_PROVIDERS,
  VERIFICATION_GOAL,
  VERIFICATION_WATCHDOG_MS,
} from 'ee/ai/settings/components/functional_verifications/constants';

jest.mock('ee/ai/duo_agentic_chat', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat'),
  runChatTurn: jest.fn(),
}));

Vue.use(VueApollo);

describe('AgenticChatVerificationCheck', () => {
  let wrapper;
  let mutationHandler;
  let cancelTurn;
  let settleTurn;

  const mockNamespace = { id: 'gid://gitlab/Group/1', fullPath: 'group-a' };
  const mockWorkflowId = 'gid://gitlab/Ai::DuoWorkflows::Workflow/7';

  const findFunctionalVerificationCheck = () => wrapper.findComponent(FunctionalVerificationCheck);

  const runStatusHandler = (run = null) =>
    jest.fn().mockResolvedValue({ data: { functionalVerificationStatus: run } });

  const failedStatusHandler = () => jest.fn().mockRejectedValue(new Error('error'));

  const runCheck = () => findFunctionalVerificationCheck().vm.$emit('run');

  const settleTurnWith = async (outcome) => {
    settleTurn(outcome);
    await waitForPromises();
  };

  const createComponent = async ({ props = {}, statusHandler = runStatusHandler() } = {}) => {
    mutationHandler = jest.fn().mockResolvedValue({
      data: { createFunctionalVerificationWorkflow: { workflowId: mockWorkflowId, errors: [] } },
    });

    wrapper = mountExtended(AgenticChatVerificationCheck, {
      apolloProvider: createMockApollo([
        [getFunctionalVerificationStatusQuery, statusHandler],
        [createFunctionalVerificationWorkflowMutation, mutationHandler],
      ]),
      propsData: { namespace: mockNamespace, ...props },
    });

    await waitForPromises();
  };

  beforeEach(() => {
    cancelTurn = jest.fn();
    runChatTurn.mockImplementation(() => ({
      outcome: new Promise((resolve) => {
        settleTurn = resolve;
      }),
      cancel: cancelTurn,
    }));
  });

  it('renders the static name and description', async () => {
    await createComponent();

    expect(findFunctionalVerificationCheck().props()).toMatchObject({
      name: 'Agentic Chat',
      description: 'Verifies the request flow of Agentic Chat end to end.',
    });
  });

  describe('when there is no verification run', () => {
    it('defaults to a not-run status', async () => {
      await createComponent({ statusHandler: runStatusHandler(null) });

      expect(findFunctionalVerificationCheck().props()).toMatchObject({
        status: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
        lastRunAt: null,
        errorText: '',
      });
    });
  });

  describe('when there is a persisted verification run', () => {
    it('passes through the status from the query', async () => {
      await createComponent({
        statusHandler: runStatusHandler({
          state: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
          updatedAt: '2026-09-04T12:00:00Z',
        }),
      });

      expect(findFunctionalVerificationCheck().props()).toMatchObject({
        status: FUNCTIONAL_VERIFICATION_STATUS.PASSED,
        lastRunAt: '2026-09-04T12:00:00Z',
      });
    });
  });

  it('passes the model prop through', async () => {
    const model = { provider: MODEL_PROVIDERS.SELF_HOSTED, name: 'Mixtral 8x7B' };

    await createComponent({ props: { model } });

    expect(findFunctionalVerificationCheck().props('model')).toEqual(model);
  });

  it('passes null for the model when there is no model info', async () => {
    await createComponent();

    expect(findFunctionalVerificationCheck().props('model')).toBeNull();
  });

  it('passes the disabled prop through and skips the query', async () => {
    const statusHandler = runStatusHandler();

    await createComponent({ props: { disabled: true }, statusHandler });

    expect(findFunctionalVerificationCheck().props('disabled')).toBe(true);
    expect(statusHandler).not.toHaveBeenCalled();
  });

  it('emits updated with the run whenever the query loads or changes', async () => {
    await createComponent({
      statusHandler: runStatusHandler({
        state: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
        updatedAt: '2026-09-04T12:00:00Z',
      }),
    });

    const emitted = wrapper.emitted('updated');

    expect(emitted[emitted.length - 1][0]).toMatchObject({
      state: FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      checkedAt: '2026-09-04T12:00:00Z',
    });
  });

  it('shows an error when the query fails', async () => {
    await createComponent({ statusHandler: failedStatusHandler() });

    expect(findFunctionalVerificationCheck().props('errorText')).toBe(
      'Failed to load last run details.',
    );
  });

  describe('running a check', () => {
    it('shows a running status as soon as the mutation is in flight', async () => {
      await createComponent();

      runCheck();
      await nextTick();

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.RUNNING,
      );
      expect(mutationHandler).toHaveBeenCalledWith({
        checkType: 'AGENTIC_CHAT',
        fullPath: mockNamespace.fullPath,
      });
    });

    it('emits updated as soon as the mutation is in flight', async () => {
      await createComponent();

      runCheck();
      await nextTick();

      const emitted = wrapper.emitted('updated');

      expect(emitted[emitted.length - 1][0]).toMatchObject({
        state: FUNCTIONAL_VERIFICATION_STATUS.RUNNING,
      });
    });

    it('starts a chat turn once the mutation resolves', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();

      expect(runChatTurn).toHaveBeenCalledTimes(1);
      expect(runChatTurn).toHaveBeenCalledWith({
        namespaceId: mockNamespace.id,
        workflowId: mockWorkflowId,
        text: VERIFICATION_GOAL,
        timeoutMs: VERIFICATION_WATCHDOG_MS,
      });
    });

    it('marks the check passed when the agent hands the turn back to the user', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({ type: CHAT_TURN_OUTCOME.AWAITING_USER });

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.PASSED,
      );
    });

    it('marks the check failed when the run ends without asking the user', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({ type: CHAT_TURN_OUTCOME.RUN_ENDED, errorMessage: null });

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toBe(
        'View Workhorse logs for more details.',
      );
    });

    it('surfaces the failure reported by the run', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.RUN_ENDED,
        errorMessage: 'model not found',
      });

      expect(findFunctionalVerificationCheck().props('errorText')).toBe(
        'Error: model not found. View Workhorse logs for more details.',
      );
    });

    it('does not duplicate the period when the reported error already ends with one', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.RUN_ENDED,
        errorMessage:
          'There was an error processing your request in the Duo Agent Platform, please contact support if the issue persists.',
      });

      expect(findFunctionalVerificationCheck().props('errorText')).toBe(
        'Error: There was an error processing your request in the Duo Agent Platform, please contact support if the issue persists. View Workhorse logs for more details.',
      );
    });

    it('marks the check failed when the connection drops after opening', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.DISCONNECTED,
        connectionOpened: true,
        close: { code: 1006, category: 'error' },
      });

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toContain('1006');
      expect(findFunctionalVerificationCheck().props('errorText')).toContain(
        'Reason: abnormal_close',
      );
    });

    it('hints at a reverse proxy issue when the connection never opens and closes with 1006', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.DISCONNECTED,
        connectionOpened: false,
        close: { code: 1006, category: 'error' },
      });

      expect(findFunctionalVerificationCheck().props('errorText')).toContain(
        'Reason: handshake_failed',
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toContain(
        'If using a reverse proxy, verify it supports WebSocket upgrades',
      );
    });

    it('hints at a reverse proxy issue when the turn times out before the connection opens', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({ type: CHAT_TURN_OUTCOME.TIMED_OUT, connectionOpened: false });

      expect(findFunctionalVerificationCheck().props('errorText')).toContain(
        'Reason: handshake_failed',
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toContain(
        'If using a reverse proxy, verify it supports WebSocket upgrades',
      );
    });

    it('reports a timeout when the turn times out after the connection opens', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({ type: CHAT_TURN_OUTCOME.TIMED_OUT, connectionOpened: true });

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toBe(
        'Reason: timeout. Verification run timed out.',
      );
    });

    it('includes the close reason in the error text when present', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.DISCONNECTED,
        connectionOpened: false,
        close: { code: 4400, category: 'invalid_request', reason: 'bad token' },
      });

      expect(findFunctionalVerificationCheck().props('errorText')).toContain('bad token');
    });

    it('tags a stream error with a reason, consistent with other failures', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      await settleTurnWith({
        type: CHAT_TURN_OUTCOME.STREAM_ERROR,
        errorMessage: 'decode failed',
      });

      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toBe(
        'Reason: unexpected_error. decode failed',
      );
    });

    it('marks the check failed when the mutation returns errors', async () => {
      await createComponent();
      mutationHandler.mockResolvedValue({
        data: { createFunctionalVerificationWorkflow: { workflowId: null, errors: ['boom'] } },
      });

      runCheck();
      await waitForPromises();

      expect(runChatTurn).not.toHaveBeenCalled();
      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toBe('boom');
    });

    it('marks the check failed when the mutation rejects', async () => {
      await createComponent();
      mutationHandler.mockRejectedValue(new Error('network error'));

      runCheck();
      await waitForPromises();

      expect(runChatTurn).not.toHaveBeenCalled();
      expect(findFunctionalVerificationCheck().props('status')).toBe(
        FUNCTIONAL_VERIFICATION_STATUS.FAILED,
      );
      expect(findFunctionalVerificationCheck().props('errorText')).toBe('network error');
    });

    it('cancels the previous turn before starting a new one', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();

      runCheck();
      await waitForPromises();

      expect(cancelTurn).toHaveBeenCalledTimes(1);
      expect(runChatTurn).toHaveBeenCalledTimes(2);
    });
  });

  describe('on destroy', () => {
    it('cancels an in-flight turn', async () => {
      await createComponent();

      runCheck();
      await waitForPromises();
      wrapper.destroy();

      expect(cancelTurn).toHaveBeenCalledTimes(1);
    });
  });
});
