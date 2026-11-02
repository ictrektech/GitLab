import { queryToObject, setUrlParams } from '~/lib/utils/url_utility';
import {
  isAttributeParam,
  queryParamsToTokens,
  tokensToQueryParams,
  withReadableParams,
} from 'ee/security_inventory/filter_url_sync';
import { getAttributeCategoryTokens } from 'ee/security_dashboard/utils/attribute_utils';
import { toolCoverageTokens } from 'ee/security_inventory/components/tool_coverage_tokens';
import { vulnerabilityCountTokens } from 'ee/security_inventory/components/vulnerability_count_tokens';
import { statusTokens } from 'ee/security_inventory/components/status_tokens';

const securityCategories = [
  {
    id: 'gid://gitlab/Security::Category/1',
    name: 'Business Impact',
    securityAttributes: [
      { id: 'gid://gitlab/Security::Attribute/10', name: 'High' },
      { id: 'gid://gitlab/Security::Attribute/11', name: 'Low' },
    ],
  },
  {
    id: 'gid://gitlab/Security::Category/2',
    name: 'Data Sensitivity',
    securityAttributes: [{ id: 'gid://gitlab/Security::Attribute/20', name: 'Public' }],
  },
];

const tokenDefinitions = [
  ...toolCoverageTokens,
  ...statusTokens,
  ...getAttributeCategoryTokens(securityCategories),
  ...vulnerabilityCountTokens,
];

const definedParams = (params) =>
  Object.fromEntries(Object.entries(params).filter(([, value]) => value != null));

describe('security inventory filter URL sync', () => {
  describe('tokensToQueryParams', () => {
    it('returns one param for plain text search terms', () => {
      const params = tokensToQueryParams(
        [
          { type: 'filtered-search-term', value: { data: 'foo' } },
          { type: 'filtered-search-term', value: { data: 'bar' } },
        ],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ search: 'foo bar' });
    });

    it('returns params for a tool coverage token', () => {
      const params = tokensToQueryParams(
        [{ type: 'SAST', value: { data: 'SUCCESS', operator: '=' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ sast: 'success' });
    });

    it('returns a param for a status token', () => {
      const params = tokensToQueryParams(
        [{ type: 'STATUS', value: { data: 'NEEDS_ATTENTION', operator: '=' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ status: 'needs_attention' });
    });

    it.each`
      operator | expected
      ${'<='}  | ${{ 'lte[critical]': '5' }}
      ${'='}   | ${{ critical: '5' }}
      ${'>='}  | ${{ 'gte[critical]': '5' }}
    `('puts the $operator operator on a count token in the param key', ({ operator, expected }) => {
      const params = tokensToQueryParams(
        [{ type: 'critical', value: { data: '5', operator } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual(expected);
    });

    it('keeps a count of zero', () => {
      const params = tokensToQueryParams(
        [{ type: 'critical', value: { data: '0', operator: '=' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ critical: '0' });
    });

    it('returns params for a multi-select attribute token', () => {
      const params = tokensToQueryParams(
        [{ type: 'attribute~business_impact', value: { data: ['10', '11'], operator: '||' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ 'or[attribute~business_impact]': '10,11' });
    });

    it('returns the negation key for an excluded token', () => {
      const params = tokensToQueryParams(
        [{ type: 'attribute~business_impact', value: { data: ['10'], operator: '!=' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ 'not[attribute~business_impact]': '10' });
    });

    it('clears every owned param for no tokens', () => {
      const params = tokensToQueryParams([], tokenDefinitions);

      expect(definedParams(params)).toEqual({});
      expect(params).toMatchObject({
        search: null,
        sast: null,
        critical: null,
        status: null,
        'attribute~business_impact': null,
        'not[attribute~business_impact]': null,
      });
    });

    it('removes attribute ids outside the category', () => {
      const params = tokensToQueryParams(
        [{ type: 'attribute~business_impact', value: { data: ['10', '999'], operator: '||' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({ 'or[attribute~business_impact]': '10' });
    });

    it('returns no params for an unknown token type', () => {
      const params = tokensToQueryParams(
        [{ type: 'not-a-real-token', value: { data: 'x', operator: '=' } }],
        tokenDefinitions,
      );

      expect(definedParams(params)).toEqual({});
    });
  });

  describe('queryParamsToTokens', () => {
    it('returns a tool coverage token', () => {
      expect(queryParamsToTokens({ sast: 'success' }, tokenDefinitions)).toEqual([
        { type: 'SAST', value: { data: 'SUCCESS', operator: '=' } },
      ]);
    });

    it('returns a status token', () => {
      expect(queryParamsToTokens({ status: 'needs_attention' }, tokenDefinitions)).toEqual([
        { type: 'STATUS', value: { data: 'NEEDS_ATTENTION', operator: '=' } },
      ]);
    });

    it.each`
      query                       | operator
      ${{ 'lte[critical]': '5' }} | ${'<='}
      ${{ critical: '5' }}        | ${'='}
      ${{ 'gte[critical]': '5' }} | ${'>='}
    `('reads the $operator operator on a count token off the param key', ({ query, operator }) => {
      expect(queryParamsToTokens(query, tokenDefinitions)).toEqual([
        { type: 'critical', value: { data: '5', operator } },
      ]);
    });

    it('returns a multi-select attribute token', () => {
      expect(
        queryParamsToTokens({ 'attribute~business_impact': '10,11' }, tokenDefinitions),
      ).toEqual([
        { type: 'attribute~business_impact', value: { data: ['10', '11'], operator: '=' } },
      ]);
    });

    it('reads an OR attribute token from its own key', () => {
      expect(
        queryParamsToTokens({ 'or[attribute~business_impact]': '10,11' }, tokenDefinitions),
      ).toEqual([
        { type: 'attribute~business_impact', value: { data: ['10', '11'], operator: '||' } },
      ]);
    });

    it('keeps every operator through a round trip', () => {
      const tokens = [
        { type: 'attribute~business_impact', value: { data: ['10'], operator: '||' } },
        { type: 'attribute~data_sensitivity', value: { data: ['20'], operator: '!=' } },
      ];

      const params = tokensToQueryParams(tokens, tokenDefinitions);

      expect(queryParamsToTokens(definedParams(params), tokenDefinitions)).toEqual(tokens);
    });

    it('reads an excluded token from the negation key', () => {
      expect(
        queryParamsToTokens({ 'not[attribute~business_impact]': '10' }, tokenDefinitions),
      ).toEqual([{ type: 'attribute~business_impact', value: { data: ['10'], operator: '!=' } }]);
    });

    it('returns a plain text search term', () => {
      expect(queryParamsToTokens({ search: 'foo bar' }, tokenDefinitions)).toEqual([
        { type: 'filtered-search-term', value: { data: 'foo bar' } },
      ]);
    });

    describe('when the URL contains values the tokens do not accept', () => {
      it.each`
        description                 | query
        ${'an unknown option'}      | ${{ sast: 'not-a-status' }}
        ${'an unknown status'}      | ${{ status: 'made-up' }}
        ${'an unknown operator'}    | ${{ 'between[critical]': '5' }}
        ${'a non-numeric count'}    | ${{ 'gte[critical]': 'many' }}
        ${'a partly numeric count'} | ${{ 'gte[critical]': '5abc' }}
        ${'a count with no value'}  | ${{ 'gte[critical]': '' }}
        ${'a negative count'}       | ${{ 'gte[critical]': '-1' }}
        ${'unknown attribute ids'}  | ${{ 'attribute~business_impact': '998,999' }}
        ${'an unknown token param'} | ${{ nonsense: 'value' }}
        ${'an empty value'}         | ${{ sast: '' }}
      `('drops $description', ({ query }) => {
        expect(queryParamsToTokens(query, tokenDefinitions)).toEqual([]);
      });
    });

    it('returns no tokens for suggestion group headers', () => {
      expect(
        queryParamsToTokens(
          { gl_filtered_search_suggestion_group_tool_coverage: 'x' },
          tokenDefinitions,
        ),
      ).toEqual([]);
    });
  });

  describe('round trip', () => {
    it('keeps a full set of filters in both directions', () => {
      const tokens = [
        { type: 'STATUS', value: { data: 'STALE_SCANS', operator: '=' } },
        { type: 'attribute~business_impact', value: { data: ['10', '11'], operator: '=' } },
        { type: 'critical', value: { data: '3', operator: '>=' } },
        { type: 'high', value: { data: '0', operator: '<=' } },
        { type: 'DAST', value: { data: 'FAILED', operator: '=' } },
        { type: 'filtered-search-term', value: { data: 'gitlab' } },
      ];

      const params = tokensToQueryParams(tokens, tokenDefinitions);
      const restored = queryParamsToTokens(definedParams(params), tokenDefinitions);

      expect(restored).toEqual(expect.arrayContaining(tokens));
      expect(restored).toHaveLength(tokens.length);
    });

    it('returns readable params with no GraphQL ids', () => {
      const params = tokensToQueryParams(
        [
          { type: 'attribute~business_impact', value: { data: ['10'], operator: '||' } },
          { type: 'critical', value: { data: '5', operator: '>=' } },
        ],
        tokenDefinitions,
      );

      const url = setUrlParams(params, {
        url: 'http://gdk.test/groups/gitlab-org/-/security/inventory',
        decodeParams: true,
      });

      expect(url).toBe(
        'http://gdk.test/groups/gitlab-org/-/security/inventory?or[attribute~business_impact]=10&gte[critical]=5',
      );
      expect(url).not.toContain('gid');
    });

    it.each`
      description             | searchTerm
      ${'a percent sign'}     | ${'50%'}
      ${'an ampersand'}       | ${'a&b'}
      ${'an equals sign'}     | ${'x=1'}
      ${'a plus sign'}        | ${'a+b'}
      ${'a hash'}             | ${'a#b'}
      ${'an encoded percent'} | ${'100%25'}
    `('round trips a search term containing $description', ({ searchTerm }) => {
      const params = tokensToQueryParams(
        [{ type: 'filtered-search-term', value: { data: searchTerm } }],
        tokenDefinitions,
      );

      const url = withReadableParams(
        setUrlParams(params, { url: 'http://gdk.test/groups/gitlab-org/-/security/inventory' }),
      );

      expect(queryToObject(new URL(url).search)).toEqual({ search: searchTerm });
    });

    it('keeps attribute and operator characters readable', () => {
      const params = tokensToQueryParams(
        [
          { type: 'attribute~business_impact', value: { data: ['10', '11'], operator: '||' } },
          { type: 'critical', value: { data: '5', operator: '>=' } },
        ],
        tokenDefinitions,
      );

      const url = withReadableParams(
        setUrlParams(params, { url: 'http://gdk.test/groups/gitlab-org/-/security/inventory' }),
      );

      expect(new URL(url).search).toBe('?or[attribute~business_impact]=10,11&gte[critical]=5');
    });

    it('keeps the subgroup hash intact', () => {
      const params = tokensToQueryParams(
        [{ type: 'DAST', value: { data: 'FAILED', operator: '=' } }],
        tokenDefinitions,
      );

      const url = setUrlParams(params, {
        url: 'http://gdk.test/groups/gitlab-org/-/security/inventory?stale=1#gitlab-org/subgroup',
        decodeParams: true,
      });

      expect(url).toBe(
        'http://gdk.test/groups/gitlab-org/-/security/inventory?stale=1&dast=failed#gitlab-org/subgroup',
      );
    });
  });

  describe('isAttributeParam', () => {
    it('detects an attribute param for every operator', () => {
      expect(isAttributeParam('attribute~business_impact')).toBe(true);
      expect(isAttributeParam('not[attribute~business_impact]')).toBe(true);
      expect(isAttributeParam('or[attribute~business_impact]')).toBe(true);
    });

    it('returns false for a param of another token', () => {
      expect(isAttributeParam('search')).toBe(false);
      expect(isAttributeParam('dast')).toBe(false);
      expect(isAttributeParam('gte[critical]')).toBe(false);
    });
  });
});
