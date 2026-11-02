import { HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_UNPROCESSABLE_ENTITY } from '~/lib/utils/http_status';
import { s__ } from '~/locale';

export const ORBIT_GQL_LANGUAGE = 'orbit-gql';

/* eslint-disable @gitlab/require-i18n-strings -- GQL keywords, not UI text */
export const GQL_KEYWORDS = [
  'MATCH',
  'WHERE',
  'RETURN',
  'ORDER BY',
  'SKIP',
  'OFFSET',
  'LIMIT',
  'AS',
  'AND',
  'IN',
  'IS NULL',
  'IS NOT NULL',
  'TRUE',
  'FALSE',
  'ASC',
  'DESC',
  'COUNT',
  'CONTAINS',
  'STARTS WITH',
  'ENDS WITH',
];
/* eslint-enable @gitlab/require-i18n-strings */

export const QUERY_ERROR_KIND = {
  INVALID_QUERY: 'invalid_query',
  BILLING_GROUP_REQUIRED: 'billing_group_required',
  REQUEST_REJECTED: 'request_rejected',
  NO_ACCESS: 'no_access',
  SERVER: 'server',
};

export const INVALID_QUERY_STATUSES = [HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_UNPROCESSABLE_ENTITY];

export const QUERY_STORAGE_KEY_PREFIX = 'orbit-query-editor-text';

// The code of the 422 that the Orbit API returns when the user has no Orbit default group.
export const BILLING_NAMESPACE_REQUIRED_CODE = 'billing_namespace_required';

export const COMPLETION_KIND = {
  ENTITY: 'entity',
  RELATIONSHIP: 'relationship',
  PROPERTY: 'property',
  KEYWORD: 'keyword',
};

/* eslint-disable @gitlab/require-i18n-strings -- GQL code samples, not UI text */
export const GQL_STARTER = [
  {
    code: 'MATCH (u:User)-[:AUTHORED]->(mr:MergeRequest)',
    description: s__('Orbit|Find entities and how they connect.'),
  },
  {
    code: "WHERE mr.state = 'merged'",
    description: s__('Orbit|Keep the matches that meet a condition. Join conditions with AND.'),
  },
  {
    code: 'RETURN u.username, mr.title',
    description: s__('Orbit|Choose the columns.'),
  },
  {
    code: 'RETURN u.username, count(mr) AS merged',
    description: s__(
      'Orbit|Count, or use sum, avg, min, and max. The other columns become groups.',
    ),
  },
  {
    code: 'ORDER BY mr.merged_at DESC',
    description: s__('Orbit|Sort by one column.'),
  },
  {
    code: 'SKIP 25',
    description: s__('Orbit|Skip this many rows, up to 10,000, to get the next page.'),
  },
  {
    code: 'LIMIT 25',
    description: s__('Orbit|Return at most this many rows, up to 1,000.'),
  },
];

export const GQL_MORE_SYNTAX = [
  {
    title: s__('Orbit|Patterns'),
    items: [
      {
        code: '(mr:MergeRequest)-[:CLOSES|MENTIONS]->(wi:WorkItem)',
        description: s__('Orbit|Match one of several relationships.'),
      },
      {
        code: "(g:Group {full_path: 'gitlab-org'})-[:CONTAINS*1..3]->(s:Group)",
        description: s__('Orbit|Follow a relationship for 1 to 3 hops.'),
      },
      {
        code: '(n)--(wi:WorkItem {id: 42})',
        description: s__('Orbit|Find everything linked to one node.'),
      },
      {
        code: 'p = ANY SHORTEST (u:User {id: 1})-[*1..3]->(pr:Project {id: 2})',
        description: s__('Orbit|Find the shortest path between two nodes.'),
      },
    ],
  },
  {
    title: s__('Orbit|Filters'),
    items: [
      {
        code: "WHERE mr.state IN ['opened', 'merged']",
        description: s__('Orbit|Match one of several values.'),
      },
      {
        code: "WHERE p.full_path STARTS WITH 'gitlab-org/'",
        description: s__('Orbit|Match text that starts with a value. Also ENDS WITH and CONTAINS.'),
      },
      {
        code: 'WHERE mr.merged_at IS NOT NULL',
        description: s__('Orbit|Find present values, or missing values with IS NULL.'),
      },
      {
        code: "WHERE mr.created_at >= date('2026-10-01')",
        description: s__(
          'Orbit|Compare with a date. To compare with a date and time, use datetime().',
        ),
      },
      {
        code: "WHERE any_tokens(wi.title, 'flaky spec')",
        description: s__('Orbit|Search for words in text. Also all_tokens and token_match.'),
      },
    ],
  },
  {
    title: s__('Orbit|Columns'),
    items: [
      {
        code: 'RETURN u{.username, .name}, properties(mr)',
        description: s__('Orbit|Choose some properties of a node, or all of them.'),
      },
      {
        code: "RETURN date_trunc('month', mr.merged_at) AS month, count(mr)",
        description: s__('Orbit|Group by minute, hour, day, week, month, quarter, or year.'),
      },
    ],
  },
];
/* eslint-enable @gitlab/require-i18n-strings */

export const GQL_REFERENCE_URL = 'https://docs.gitlab.com/orbit/remote/queries/query-language/';

export const OPEN_CYPHER_URL = 'https://opencypher.org/resources/';

export const EDITOR_OPTIONS = {
  minimap: { enabled: false },
  scrollBeyondLastLine: false,
  lineNumbers: 'on',
  renderLineHighlight: 'none',
  glyphMargin: false,
  folding: false,
  lineDecorationsWidth: 10,
  lineNumbersMinChars: 3,
  fontSize: 13,
  tabSize: 2,
};
