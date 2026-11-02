export const check = (identifier, status) => ({
  __typename: 'MergeRequestMergeabilityCheck',
  identifier,
  status,
});

export const failingChecks = [
  check('NOT_APPROVED', 'FAILED'),
  check('DISCUSSIONS_NOT_RESOLVED', 'FAILED'),
  check('CI_MUST_PASS', 'CHECKING'),
  check('CONFLICT', 'SUCCESS'),
  check('DRAFT_STATUS', 'SUCCESS'),
];

export const passingChecks = failingChecks.map(({ identifier }) => check(identifier, 'SUCCESS'));

// Overriding one check means restating the list: `slice` used to leave a second entry for the
// same identifier, and the last one won, so the check under test never took effect.
export const checksWith = (...overrides) => {
  const byIdentifier = new Map(passingChecks.map((c) => [c.identifier, c]));

  overrides.forEach((c) => byIdentifier.set(c.identifier, c));

  return [...byIdentifier.values()];
};

export const pipeline = (text = 'Running') => ({
  __typename: 'Pipeline',
  id: 'gid://gitlab/Ci::Pipeline/9',
  detailedStatus: { __typename: 'DetailedStatus', id: 'status-9', text },
});

export const interaction = (overrides = {}) => ({
  __typename: 'UserMergeRequestInteraction',
  approved: true,
  reviewState: 'APPROVED',
  ...overrides,
});

export const makeReviewer = (overrides = {}) => ({
  __typename: 'MergeRequestReviewer',
  id: 'gid://gitlab/User/2',
  username: 'elena',
  name: 'Elena Kowalski',
  avatarUrl: '/avatar.png',
  webUrl: 'http://test.host/elena',
  webPath: '/elena',
  mergeRequestInteraction: interaction(),
  ...overrides,
});

export const reviewers = (...nodes) => ({
  __typename: 'MergeRequestReviewerConnection',
  nodes,
});

export const author = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/1',
  username: 'priya',
  name: 'Priya Nair',
  avatarUrl: '/priya.png',
  webUrl: 'http://test.host/priya',
  webPath: '/priya',
};

export const diffRefs = {
  __typename: 'DiffRefs',
  baseSha: 'aaa111',
  startSha: 'aaa111',
  headSha: 'bbb222',
};

export const makeLabel = (overrides = {}) => ({
  __typename: 'Label',
  id: 'gid://gitlab/ProjectLabel/1',
  title: 'backend',
  color: '#428BCA',
  description: 'Server-side changes',
  ...overrides,
});

export const labels = (...nodes) => ({
  __typename: 'LabelConnection',
  nodes,
});

export const milestone = {
  __typename: 'Milestone',
  id: 'gid://gitlab/Milestone/4',
  title: '19.5',
  webPath: '/group/proj/-/milestones/4',
  startDate: '2026-09-12',
  dueDate: '2026-10-09',
  expired: false,
};

export const makeMetadata = (overrides = {}) => ({
  __typename: 'MergeRequest',
  id: 'gid://gitlab/MergeRequest/3',
  labels: labels(makeLabel()),
  milestone,
  ...overrides,
});

export const metadataResponse = (mergeRequest = makeMetadata()) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/7',
      mergeRequest,
    },
  },
});

export const makeMergeRequest = (overrides = {}) => ({
  __typename: 'MergeRequest',
  id: 'gid://gitlab/MergeRequest/3',
  iid: '1',
  webPath: '/group/proj/-/merge_requests/1',
  state: 'opened',
  diffRefs,
  descriptionHtml: '<p data-sourcepos="1:1-1:19" dir="auto">Adds rate limiting.</p>',
  author,
  conflicts: false,
  approvalsRequired: 2,
  approvalsLeft: 1,
  resolvableDiscussionsCount: 4,
  resolvedDiscussionsCount: 1,
  mergeabilityChecks: failingChecks,
  headPipeline: pipeline(),
  reviewers: reviewers(makeReviewer()),
  userPermissions: {
    __typename: 'MergeRequestPermissions',
    updateMergeRequest: true,
    createNote: true,
    pushToSourceBranch: true,
  },
  ...overrides,
});

export const overviewResponse = (mergeRequest = makeMergeRequest()) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/7',
      mergeRequest,
    },
  },
});

export const makeRiskAssessment = (overrides = {}) => ({
  __typename: 'MergeRequestRiskAssessment',
  status: 'COMPLETE',
  riskTier: 'HIGH',
  confidenceTier: 'MEDIUM',
  rationale: 'Changes the merge path without new tests.',
  stale: false,
  duoWorkflowId: null,
  contributingSignals: [
    {
      __typename: 'MergeRequestRiskContributingSignal',
      signal: 'diff_shape.churn',
      label: 'Size of change',
      contribution: 12,
      detail: '640 lines changed',
    },
  ],
  missingSignals: [],
  ...overrides,
});

export const riskAssessmentResponse = (riskAssessment = makeRiskAssessment()) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/7',
      duoWorkflowStatusCheck: {
        __typename: 'DuoWorkflowEnablement',
        createDuoWorkflowForCiAllowed: true,
      },
      mergeRequest: {
        __typename: 'MergeRequest',
        id: 'gid://gitlab/MergeRequest/3',
        sourceBranch: 'feature',
        riskAssessment,
      },
    },
  },
});

export const makeNote = (overrides = {}) => ({
  __typename: 'Note',
  id: 'gid://gitlab/DiffNote/11',
  bodyFirstLineHtml: '<p>Rename this <code>method</code>.</p>',
  createdAt: '2026-09-20T10:00:00Z',
  suggestions: { __typename: 'SuggestionConnection', nodes: [] },
  author: { ...author, bot: false },
  position: {
    __typename: 'DiffPosition',
    filePath: 'app/models/user.rb',
    oldPath: 'app/models/user.rb',
    newPath: 'app/models/user.rb',
    oldLine: null,
    newLine: 12,
    diffRefs,
  },
  ...overrides,
});

export const makeDiscussion = ({
  id = 'gid://gitlab/Discussion/1',
  notes = [makeNote()],
  resolveNote = true,
  truncatedDiffLines = null,
  ...overrides
} = {}) => ({
  __typename: 'Discussion',
  id,
  replyId: id,
  resolvable: true,
  resolved: false,
  userPermissions: { __typename: 'DiscussionPermissions', resolveNote },
  truncatedDiffLines,
  notes: { __typename: 'NoteConnection', nodes: notes },
  ...overrides,
});

export const discussionsResponse = ({ nodes = [makeDiscussion()], pageInfo = {} } = {}) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/7',
      mergeRequest: {
        __typename: 'MergeRequest',
        id: 'gid://gitlab/MergeRequest/3',
        discussionsWithActivity: {
          __typename: 'DiscussionConnection',
          pageInfo: { __typename: 'PageInfo', hasNextPage: false, endCursor: null, ...pageInfo },
          nodes,
        },
      },
    },
  },
});

export const diffLine = (type, text) => ({ __typename: 'DiffLine', type, text });

export const makeSuggestion = (overrides = {}) => ({
  __typename: 'Suggestion',
  id: 'gid://gitlab/Suggestion/18',
  fromContent: '  def greet\n',
  toContent: '  def say_hello\n',
  applied: false,
  ...overrides,
});

export const suggestions = (...nodes) => ({ __typename: 'SuggestionConnection', nodes });
