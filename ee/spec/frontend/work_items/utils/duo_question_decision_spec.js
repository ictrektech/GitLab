import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createAlert } from '~/alert';
import {
  buildMockDecision,
  decisionLogResponse,
  mockFullPath,
  mockWorkItemIid,
} from 'ee_jest/work_items/components/decision_log/mock_data';
import decisionLogQuery from 'ee/work_items/components/decision_log/graphql/decision_log.query.graphql';
import resolveDecisionMutation from 'ee/work_items/components/decision_log/graphql/resolve_decision.mutation.graphql';
import {
  buildDuoDecisionResolution,
  findDuoAnswerNote,
  resolveDuoQuestionDecision,
} from 'ee/work_items/utils/duo_question_decision';

jest.mock('~/alert');

Vue.use(VueApollo);

const DISCUSSION_ID = 'gid://gitlab/Discussion/abc';
const DECISION_ID = 'gid://gitlab/WorkItems::Decision/1';
const ANSWER_NOTE_ID = 'gid://gitlab/Note/9';
const NO_ANSWER_RATIONALE = 'The question was resolved without an answer.';

const fenced = (payload) => `Which?\n\n\`\`\`json:duo-question\n${JSON.stringify(payload)}\n\`\`\``;

const CLOSED_QUESTION = {
  type: 'closed',
  question: 'Which cutover approach should we use?',
  multiple: true,
  options: [
    { id: 'hard_removal', label: 'Hard removal' },
    { id: 'staged', label: 'Staged deprecation' },
    { id: 'flagged', label: 'Behind a flag' },
  ],
};
const OPEN_QUESTION = { type: 'open', question: 'Who owns the rollout?' };

const decisionOption = (id, content) => ({
  id: `gid://gitlab/WorkItems::DecisionOption/${id}`,
  content,
});

// The third option stands in for one past the 5 a decision holds.
const OPEN_DECISION = {
  id: DECISION_ID,
  discussionId: DISCUSSION_ID,
  resolvedAt: null,
  options: { nodes: [decisionOption(1, 'Hard removal'), decisionOption(2, 'Staged deprecation')] },
};

const answer = (body) => ({ id: ANSWER_NOTE_ID, body });

describe('findDuoAnswerNote', () => {
  const DUO = { id: 'gid://gitlab/User/99' };
  const PERSON = { id: 'gid://gitlab/User/1' };
  const questionNote = { body: fenced(CLOSED_QUESTION), author: DUO };
  const reply = (body, author = PERSON) => ({ ...answer(body), author });

  const marked = reply('Hard removal\n\n<!-- duo-answer: hard_removal -->');
  const earlier = reply('What are the trade-offs?');
  const latest = reply('Hard cutover, but announce it a release ahead.');
  const fromDuo = reply('Thanks, noted.', DUO);
  const posted = reply('LGTM, thanks');

  it.each`
    scenario                                        | replies              | postedReply  | expected
    ${'a marked answer and later chatter'}          | ${[marked, latest]}  | ${undefined} | ${marked}
    ${'only plain replies'}                         | ${[earlier, latest]} | ${undefined} | ${latest}
    ${'a plain reply posted after a marked answer'} | ${[marked]}          | ${posted}    | ${marked}
    ${'a plain reply posted with no marked answer'} | ${[earlier]}         | ${posted}    | ${posted}
    ${'a reply from GitLab Duo after the answer'}   | ${[latest, fromDuo]} | ${undefined} | ${latest}
    ${'only a reply from GitLab Duo'}               | ${[fromDuo]}         | ${undefined} | ${undefined}
    ${'no replies'}                                 | ${[]}                | ${undefined} | ${undefined}
  `('with $scenario, returns the answering reply', ({ replies, postedReply, expected }) => {
    expect(findDuoAnswerNote({ questionNote, replies, postedReply })).toBe(expected);
  });
});

describe('buildDuoDecisionResolution', () => {
  const resolve = (body, question = CLOSED_QUESTION) =>
    buildDuoDecisionResolution({
      decision: OPEN_DECISION,
      question,
      answerNote: body === undefined ? undefined : answer(body),
    });

  const picked = (ids, rationale = null) => ({
    selectedOptionIds: ids.map((id) => decisionOption(id).id),
    resolutionRationale: rationale,
  });
  const writtenIn = (content) => ({ selectedOptionContent: content });

  it.each`
    scenario                                       | body                                                                  | expected
    ${'one option is picked'}                      | ${'Staged deprecation\n\n<!-- duo-answer: staged -->'}                | ${picked([2])}
    ${'several options are picked'}                | ${'- Hard removal\n- Staged deprecation\n\n<!-- duo-answer: a,b -->'} | ${picked([1, 2])}
    ${'an option is picked alongside a typed one'} | ${'- Hard removal\n- Ship both\n\n<!-- duo-answer: a,rejected -->'}   | ${writtenIn('Hard removal, Ship both')}
    ${'only a typed answer is given'}              | ${'Ship both\n\n<!-- duo-answer: rejected -->'}                       | ${writtenIn('Ship both')}
    ${'a plain reply answers it'}                  | ${"Let's do every pipeline update"}                                   | ${writtenIn("Let's do every pipeline update")}
    ${'only an option the decision lacks'}         | ${'Behind a flag\n\n<!-- duo-answer: flagged -->'}                    | ${picked([], NO_ANSWER_RATIONALE)}
  `('when $scenario', ({ body, expected }) => {
    expect(resolve(body)).toEqual({
      id: DECISION_ID,
      resolvingNoteId: ANSWER_NOTE_ID,
      ...expected,
    });
  });

  it.each`
    scenario                    | label
    ${'doubled spaces'}         | ${'Hard  removal'}
    ${'surrounding whitespace'} | ${' Hard removal '}
  `('matches a picked option whose label has $scenario', ({ label }) => {
    const question = {
      ...CLOSED_QUESTION,
      options: [{ id: 'hard_removal', label }, ...CLOSED_QUESTION.options.slice(1)],
    };

    expect(resolve(`${label}\n\n<!-- duo-answer: hard_removal -->`, question)).toEqual({
      id: DECISION_ID,
      resolvingNoteId: ANSWER_NOTE_ID,
      ...picked([1]),
    });
  });

  it('records no answer when there is no reply', () => {
    expect(resolve(undefined)).toEqual({
      id: DECISION_ID,
      resolvingNoteId: null,
      ...picked([], NO_ANSWER_RATIONALE),
    });
  });

  it('writes in a reply to an open question as the decision, keeping its lines', () => {
    expect(
      resolve('20% improvement\n\nMeasured on p95.', { ...OPEN_QUESTION, options: [] }),
    ).toEqual({
      id: DECISION_ID,
      resolvingNoteId: ANSWER_NOTE_ID,
      ...writtenIn('20% improvement\n\nMeasured on p95.'),
    });
  });

  it.each([501, 600])(
    'truncates a %d-character written-in answer to the 500 an option holds',
    (length) => {
      const { selectedOptionContent } = resolve('a'.repeat(length));

      expect(selectedOptionContent).toHaveLength(500);
      expect(selectedOptionContent.endsWith('…')).toBe(true);
    },
  );
});

describe('resolveDuoQuestionDecision', () => {
  let apolloProvider;
  let decisionsHandler;
  let resolveHandler;

  const buildOptionNodes = (nodes, selectedIds = []) => ({
    __typename: 'WorkItemDecisionOptionConnection',
    nodes: nodes.map((node) => ({
      __typename: 'WorkItemDecisionOption',
      ...node,
      selected: selectedIds.includes(node.id),
    })),
  });
  const openDecision = buildMockDecision({
    id: DECISION_ID,
    title: CLOSED_QUESTION.question,
    discussionId: DISCUSSION_ID,
    resolvedAt: null,
    resolvedBy: null,
    resolutionRationale: null,
    noteUrl: null,
    state: 'OPEN',
    options: buildOptionNodes(OPEN_DECISION.options.nodes),
  });
  const resolveResponse = (errors = []) => ({
    data: {
      workItemDecisionResolve: {
        __typename: 'WorkItemDecisionResolvePayload',
        decision: {
          ...openDecision,
          state: 'RESOLVED',
          resolvedAt: '2026-10-07T00:00:00Z',
          options: buildOptionNodes(OPEN_DECISION.options.nodes, [decisionOption(1).id]),
        },
        errors,
      },
    },
  });

  const resolveDecision = (params = {}) =>
    resolveDuoQuestionDecision({
      apolloClient: apolloProvider.defaultClient,
      fullPath: mockFullPath,
      workItemIid: mockWorkItemIid,
      discussionId: DISCUSSION_ID,
      questionNote: { body: fenced(CLOSED_QUESTION) },
      replies: [answer('Hard removal\n\n<!-- duo-answer: hard_removal -->')],
      ...params,
    });

  beforeEach(() => {
    decisionsHandler = jest.fn().mockResolvedValue(decisionLogResponse([openDecision]));
    resolveHandler = jest.fn().mockResolvedValue(resolveResponse());
    apolloProvider = createMockApollo([
      [decisionLogQuery, decisionsHandler],
      [resolveDecisionMutation, resolveHandler],
    ]);
  });

  describe('when the thread has an open decision', () => {
    it('resolves the decision that matches the thread', async () => {
      await expect(resolveDecision()).resolves.toMatchObject({
        id: DECISION_ID,
        state: 'RESOLVED',
      });

      expect(decisionsHandler).toHaveBeenCalledWith({
        fullPath: mockFullPath,
        iid: mockWorkItemIid,
      });
      expect(resolveHandler).toHaveBeenCalledWith({
        input: {
          id: DECISION_ID,
          selectedOptionIds: [decisionOption(1).id],
          resolutionRationale: null,
          resolvingNoteId: ANSWER_NOTE_ID,
        },
      });
    });

    // Duo posts its question after the page loads and decisions have no subscription, so the
    // cached list can be missing the decision the question opened.
    it('fetches the decisions again when a cached list is missing the decision', async () => {
      apolloProvider.defaultClient.writeQuery({
        query: decisionLogQuery,
        variables: { fullPath: mockFullPath, iid: mockWorkItemIid },
        data: decisionLogResponse([]).data,
      });

      await resolveDecision();

      expect(decisionsHandler).toHaveBeenCalledTimes(1);
      expect(resolveHandler).toHaveBeenCalledTimes(1);
    });

    it('keeps an earlier marked answer over a plain reply posted while resolving', async () => {
      await resolveDecision({ answerNote: answer('LGTM, thanks') });

      expect(resolveHandler).toHaveBeenCalledWith({
        input: expect.objectContaining({
          selectedOptionIds: [decisionOption(1).id],
          resolutionRationale: null,
        }),
      });
    });

    it('prefers the answer the caller passes over the replies', async () => {
      await resolveDecision({
        answerNote: answer('Staged deprecation\n\n<!-- duo-answer: staged -->'),
      });

      expect(resolveHandler).toHaveBeenCalledWith({
        input: expect.objectContaining({ selectedOptionIds: [decisionOption(2).id] }),
      });
    });
  });

  describe('when there is nothing to resolve', () => {
    const otherThreadDecision = { ...openDecision, discussionId: 'gid://gitlab/Discussion/x' };
    const resolvedDecision = { ...openDecision, resolvedAt: '2026-10-01T00:00:00Z' };
    const noDecisionLogResponse = () => {
      const response = decisionLogResponse([]);
      response.data.namespace.workItem.features.decisionLog = null;
      return response;
    };

    const expectNothingResolved = () => {
      expect(resolveHandler).not.toHaveBeenCalled();
      expect(createAlert).not.toHaveBeenCalled();
    };

    it('skips resolving when the first note is not a Duo question', async () => {
      await expect(resolveDecision({ questionNote: { body: 'Hello' } })).resolves.toBeNull();

      expect(decisionsHandler).not.toHaveBeenCalled();
      expectNothingResolved();
    });

    it.each`
      scenario                               | response
      ${'no decision matches the thread'}    | ${() => decisionLogResponse([otherThreadDecision])}
      ${'the decision is already resolved'}  | ${() => decisionLogResponse([resolvedDecision])}
      ${'the work item has no decision log'} | ${noDecisionLogResponse}
    `('skips resolving when $scenario', async ({ response }) => {
      decisionsHandler.mockResolvedValue(response());

      await expect(resolveDecision()).resolves.toBeNull();
      expectNothingResolved();
    });
  });

  describe('when resolving fails', () => {
    it.each`
      scenario                          | setup
      ${'fetching the decisions fails'} | ${() => decisionsHandler.mockRejectedValue(new Error('nope'))}
      ${'the mutation rejects'}         | ${() => resolveHandler.mockRejectedValue(new Error('nope'))}
      ${'the mutation returns errors'}  | ${() => resolveHandler.mockResolvedValue(resolveResponse(['Decision is already resolved']))}
    `('reports it when $scenario', async ({ setup }) => {
      setup();

      await expect(resolveDecision()).resolves.toBeNull();

      expect(createAlert).toHaveBeenCalledWith({
        message:
          'The thread was resolved, but the decision log could not be updated. To try again, reopen the thread and resolve it.',
        captureError: true,
        error: expect.any(Error),
      });
    });
  });
});
