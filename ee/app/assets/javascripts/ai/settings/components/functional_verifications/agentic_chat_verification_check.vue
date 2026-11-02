<script>
import { s__, sprintf } from '~/locale';
import { runChatTurn, CHAT_TURN_OUTCOME } from 'ee/ai/duo_agentic_chat';
import getFunctionalVerificationStatusQuery from '../../graphql/queries/get_functional_verification_status.query.graphql';
import FunctionalVerificationCheck from './functional_verification_check.vue';
import createFunctionalVerificationWorkflow from './graphql/mutations/create_functional_verification_workflow.mutation.graphql';
import {
  CHECK_TYPES,
  FUNCTIONAL_VERIFICATION_STATUS,
  NOT_RUN_STATE,
  VERIFICATION_GOAL,
  VERIFICATION_WATCHDOG_MS,
} from './constants';

const FAILURE_REASON = {
  HANDSHAKE_FAILED: 'handshake_failed',
  ABNORMAL_CLOSE: 'abnormal_close',
  TIMEOUT: 'timeout',
  UNEXPECTED_ERROR: 'unexpected_error',
};

export default {
  name: 'AgenticChatVerificationCheck',
  components: {
    FunctionalVerificationCheck,
  },
  props: {
    model: {
      type: Object,
      required: false,
      default: null,
    },
    namespace: {
      type: Object,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['updated'],
  data() {
    return {
      run: NOT_RUN_STATE,
      queryError: false,
    };
  },
  apollo: {
    run: {
      query: getFunctionalVerificationStatusQuery,
      variables: {
        checkType: CHECK_TYPES.AGENTIC_CHAT,
      },
      update(data) {
        this.queryError = false;

        const run = data.functionalVerificationStatus;

        if (!run) {
          return NOT_RUN_STATE;
        }

        return { state: run.state, checkedAt: run.updatedAt };
      },
      error() {
        this.queryError = true;
      },
      skip() {
        return this.disabled;
      },
    },
  },
  computed: {
    status() {
      return this.run?.state ?? FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN;
    },
    lastRunAt() {
      return this.run?.checkedAt;
    },
    errorText() {
      if (this.run?.message) {
        return this.run.message;
      }

      if (this.queryError) {
        return s__('AiPowered|Failed to load last run details.');
      }

      return '';
    },
  },
  watch: {
    run: {
      immediate: true,
      handler(run) {
        this.$emit('updated', run);
      },
    },
  },
  beforeDestroy() {
    this.teardownRun();
  },
  methods: {
    runCheck() {
      this.teardownRun();
      this.run = { state: FUNCTIONAL_VERIFICATION_STATUS.RUNNING, checkedAt: null, message: '' };

      this.$apollo
        .mutate({
          mutation: createFunctionalVerificationWorkflow,
          variables: {
            checkType: CHECK_TYPES.AGENTIC_CHAT,
            fullPath: this.namespace.fullPath,
          },
        })
        .then(({ data }) => {
          const result = data?.createFunctionalVerificationWorkflow;
          const errors = result?.errors ?? [];

          if (errors.length > 0) {
            this.resolveFailedRun(errors.join(', '));
            return;
          }

          this.startVerificationTurn(result.workflowId);
        })
        .catch((error) => {
          this.resolveFailedRun(error.message);
        });
    },
    startVerificationTurn(workflowId) {
      const turn = runChatTurn({
        namespaceId: this.namespace.id,
        workflowId,
        text: VERIFICATION_GOAL,
        timeoutMs: VERIFICATION_WATCHDOG_MS,
      });

      this.cancelTurn = turn.cancel;

      return turn.outcome.then((outcome) => {
        if (outcome.type === CHAT_TURN_OUTCOME.AWAITING_USER) {
          this.resolveRun(FUNCTIONAL_VERIFICATION_STATUS.PASSED, '');
          return;
        }

        this.resolveFailedRun(this.buildFailureMessage(outcome));
      });
    },
    resolveRun(state, message) {
      if (this.run?.state !== FUNCTIONAL_VERIFICATION_STATUS.RUNNING) return;

      this.teardownRun();
      this.run = { state, message, checkedAt: new Date().toISOString() };
    },
    resolveFailedRun(message) {
      this.resolveRun(FUNCTIONAL_VERIFICATION_STATUS.FAILED, message);
    },
    teardownRun() {
      this.cancelTurn?.();
      this.cancelTurn = null;
    },
    withReason(reason, message) {
      return sprintf(s__('AiPowered|Reason: %{reason}. %{message}'), { reason, message });
    },
    buildProxyMessage() {
      return this.withReason(
        FAILURE_REASON.HANDSHAKE_FAILED,
        s__(
          'AiPowered|No response from the WebSocket connection. If using a reverse proxy, verify it supports WebSocket upgrades.',
        ),
      );
    },
    buildFailureMessage(outcome) {
      switch (outcome.type) {
        case CHAT_TURN_OUTCOME.RUN_ENDED:
          return this.buildChatFailureMessage(outcome.errorMessage);
        case CHAT_TURN_OUTCOME.TIMED_OUT:
          return this.buildTimeoutMessage(outcome.connectionOpened);
        case CHAT_TURN_OUTCOME.DISCONNECTED:
          return this.buildCloseMessage(outcome.close, outcome.connectionOpened);
        default:
          return this.withReason(FAILURE_REASON.UNEXPECTED_ERROR, outcome.errorMessage);
      }
    },
    buildTimeoutMessage(connectionOpened) {
      if (!connectionOpened) {
        return this.buildProxyMessage();
      }

      return this.withReason(FAILURE_REASON.TIMEOUT, s__('AiPowered|Verification run timed out.'));
    },
    buildCloseMessage(close, connectionOpened) {
      const isProxyLikeClose = !connectionOpened && close.code === 1006 && !close.reason;

      if (isProxyLikeClose) {
        return this.buildProxyMessage();
      }

      const reasonSuffix = close.reason ? `: ${close.reason}` : '';
      const detail = sprintf(
        s__('AiPowered|Connection closed unexpectedly (%{category}, code %{code})%{reasonSuffix}'),
        { category: close.category, code: close.code, reasonSuffix },
      );

      return this.withReason(
        connectionOpened ? FAILURE_REASON.ABNORMAL_CLOSE : FAILURE_REASON.HANDSHAKE_FAILED,
        detail,
      );
    },
    buildChatFailureMessage(errorMessage) {
      if (!errorMessage) {
        return s__('AiPowered|View Workhorse logs for more details.');
      }

      return sprintf(s__('AiPowered|Error: %{error}. View Workhorse logs for more details.'), {
        error: errorMessage.replace(/\.+$/, ''),
      });
    },
  },
};
</script>

<template>
  <functional-verification-check
    :name="s__('AiPowered|Agentic Chat')"
    :description="s__('AiPowered|Verifies the request flow of Agentic Chat end to end.')"
    :status="status"
    :model="model"
    :last-run-at="lastRunAt"
    :error-text="errorText"
    :disabled="disabled"
    @run="runCheck"
  />
</template>
