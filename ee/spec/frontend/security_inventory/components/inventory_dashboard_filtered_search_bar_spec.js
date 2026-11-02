import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import getSecurityCategoriesAndAttributes from 'ee/security_configuration/graphql/group_security_categories_and_attributes.query.graphql';
import InventoryDashboardFilteredSearchBar from 'ee/security_inventory/components/inventory_dashboard_filtered_search_bar.vue';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import { visibleToolCoverageTokens } from 'ee/security_inventory/components/tool_coverage_tokens';
import { vulnerabilityCountTokens } from 'ee/security_inventory/components/vulnerability_count_tokens';
import { statusTokens } from 'ee/security_inventory/components/status_tokens';
import { mockAnalyzerFilter, mockVulnerabilityFilter } from '../mock_data';

Vue.use(VueApollo);

jest.mock('~/lib/utils/url_utility', () => ({
  queryToObject: jest.fn().mockReturnValue({}),
  setUrlParams: jest.fn().mockReturnValue(''),
}));

describe('InventoryDashboardFilteredSearchBar', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(InventoryDashboardFilteredSearchBar, {
      propsData: {
        namespace: 'group1',
        urlQuery: {},
        ...props,
      },
    });
  };

  const findFilteredSearchBar = () => wrapper.findComponent(FilteredSearchBar);
  const findTokenTypes = () =>
    findFilteredSearchBar()
      .props('tokens')
      .map(({ type }) => type);

  const typesOf = (tokens) => tokens.map(({ type }) => type);

  const emptyFilters = {
    securityAnalyzerFilters: [],
    vulnerabilityCountFilters: [],
    attributeFilters: [],
  };

  beforeEach(() => {
    createComponent();
  });

  describe('component rendering', () => {
    it('renders the filtered search component', () => {
      expect(findFilteredSearchBar().exists()).toBe(true);
    });

    describe('without a urlQuery', () => {
      it('renders the filtered search component', () => {
        createComponent({ props: { urlQuery: undefined } });

        expect(findFilteredSearchBar().exists()).toBe(true);
      });

      it('emits empty filters on creation', () => {
        createComponent({ props: { urlQuery: undefined } });

        expect(wrapper.emitted('filters-initialized')[0][0]).toEqual(emptyFilters);
      });
    });

    it('passes the correct props to filtered search', () => {
      expect(findFilteredSearchBar().props()).toMatchObject({
        initialFilterValue: [],
        termsAsTokens: true,
      });
    });

    it('renders the tool coverage tokens first', () => {
      expect(findTokenTypes()).toEqual([
        ...typesOf(visibleToolCoverageTokens()),
        'gl-filtered-search-suggestion-group-attributes',
        ...typesOf(vulnerabilityCountTokens),
      ]);
    });

    it('does not include status tokens when showStatusFilter is not set', () => {
      expect(findFilteredSearchBar().props('tokens')).not.toEqual(
        expect.arrayContaining(statusTokens),
      );
    });

    it('includes status tokens when showStatusFilter is true', () => {
      createComponent({ props: { showStatusFilter: true } });

      expect(findFilteredSearchBar().props('tokens')).toEqual(expect.arrayContaining(statusTokens));
      expect(findTokenTypes()).toEqual([
        ...typesOf(visibleToolCoverageTokens()),
        ...typesOf(statusTokens),
        'gl-filtered-search-suggestion-group-attributes',
        ...typesOf(vulnerabilityCountTokens),
      ]);
    });
  });

  describe('business logic token', () => {
    const findBusinessLogicToken = () =>
      findFilteredSearchBar()
        .props('tokens')
        .find(({ type }) => type === 'BUSINESS_LOGIC');

    it('is not offered while the bl_security_analyzer flag is off', () => {
      expect(findBusinessLogicToken()).toBeUndefined();
    });

    it('is offered when the bl_security_analyzer flag is on', () => {
      window.gon.features = { blSecurityAnalyzer: true };
      createComponent();

      expect(findBusinessLogicToken()).toMatchObject({ title: 'Business logic scanning (BL)' });
    });
  });

  describe('initialFilterValue', () => {
    it('reads a plain text search term from the URL', () => {
      createComponent({ props: { urlQuery: { search: 'url-search' } } });

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'filtered-search-term', value: { data: 'url-search' } },
      ]);
    });

    it('reads filter tokens from the URL', () => {
      createComponent({
        props: { urlQuery: { sast: 'success', 'gte[critical]': '5' }, showStatusFilter: true },
      });

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'SAST', value: { data: 'SUCCESS', operator: '=' } },
        { type: 'critical', value: { data: '5', operator: '>=' } },
      ]);
    });

    it('returns an empty array for a URL with no filters', () => {
      createComponent({ props: { urlQuery: {} } });

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([]);
    });
  });

  describe('filters-initialized', () => {
    it('emits the filters read from the URL on creation', () => {
      createComponent({ props: { urlQuery: { search: 'url-search', 'gte[critical]': '5' } } });

      expect(wrapper.emitted('filters-initialized')[0][0]).toEqual({
        ...emptyFilters,
        search: 'url-search',
        vulnerabilityCountFilters: [
          { severity: 'CRITICAL', operator: 'GREATER_THAN_OR_EQUAL_TO', count: 5 },
        ],
      });
    });

    it('emits empty filters for a URL with no params', () => {
      createComponent({ props: { urlQuery: {} } });

      expect(wrapper.emitted('filters-initialized')[0][0]).toEqual(emptyFilters);
    });
  });

  describe('when the URL holds an attribute filter', () => {
    const categoriesResponse = {
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          securityCategories: [
            {
              id: 'gid://gitlab/Security::Category/1',
              name: 'Business Impact',
              description: null,
              multipleSelection: true,
              editableState: 'EDITABLE',
              templateType: null,
              securityAttributes: [
                {
                  id: 'gid://gitlab/Security::Attribute/1',
                  name: 'Mission Critical',
                  description: null,
                  color: '#fff',
                },
              ],
            },
          ],
        },
      },
    };

    const createWithCategories = (urlQuery = {}) => {
      const apolloProvider = createMockApollo([
        [getSecurityCategoriesAndAttributes, jest.fn().mockResolvedValue(categoriesResponse)],
      ]);
      wrapper = shallowMount(InventoryDashboardFilteredSearchBar, {
        apolloProvider,
        propsData: { namespace: 'gitlab-org', urlQuery },
      });
    };

    it('renders the bar after the categories load', async () => {
      createWithCategories({ 'attribute~business_impact': '1' });

      expect(findFilteredSearchBar().exists()).toBe(false);

      await waitForPromises();

      expect(findFilteredSearchBar().exists()).toBe(true);
    });

    it('emits a single filters-initialized event', async () => {
      createWithCategories({ 'attribute~business_impact': '1' });
      await waitForPromises();

      expect(wrapper.emitted('filters-initialized')).toHaveLength(1);
    });

    it('hides the bar for an or attribute param', () => {
      createWithCategories({ 'or[attribute~business_impact]': '1' });

      expect(findFilteredSearchBar().exists()).toBe(false);
    });

    it('reads the or operator from its prefixed key', async () => {
      createWithCategories({ 'or[attribute~business_impact]': '1' });
      await waitForPromises();

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'attribute~business_impact', value: { data: ['1'], operator: '||' } },
      ]);
    });

    it('includes the is, is not and or operators', async () => {
      createWithCategories();
      await waitForPromises();

      const attributeToken = findFilteredSearchBar()
        .props('tokens')
        .find(({ type }) => type === 'attribute~business_impact');

      expect(attributeToken.operators.map(({ value }) => value)).toEqual(['=', '!=', '||']);
    });

    it('reads the is operator from a plain key', async () => {
      createWithCategories({ 'attribute~business_impact': '1' });
      await waitForPromises();

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'attribute~business_impact', value: { data: ['1'], operator: '=' } },
      ]);
      expect(wrapper.emitted('filters-initialized').at(-1)[0]).toEqual({
        ...emptyFilters,
        attributeFilters: [
          { operator: 'IS_ONE_OF', attributes: ['gid://gitlab/Security::Attribute/1'] },
        ],
      });
    });

    it('emits the attribute token as a GraphQL filter', async () => {
      createWithCategories({ 'not[attribute~business_impact]': '1' });
      await waitForPromises();

      expect(findFilteredSearchBar().props('initialFilterValue')).toEqual([
        { type: 'attribute~business_impact', value: { data: ['1'], operator: '!=' } },
      ]);
      expect(wrapper.emitted('filters-initialized')[0][0]).toEqual({
        ...emptyFilters,
        attributeFilters: [
          { operator: 'IS_NOT_ONE_OF', attributes: ['gid://gitlab/Security::Attribute/1'] },
        ],
      });
    });
  });

  describe('when the query it is given changes', () => {
    it('applies the filters from the new query', async () => {
      createComponent({ props: { urlQuery: { critical: 'gte:5' } } });

      await wrapper.setProps({ urlQuery: { critical: '2' } });

      const emissions = wrapper.emitted('filters-initialized');
      expect(emissions[emissions.length - 1][0]).toEqual({
        ...emptyFilters,
        vulnerabilityCountFilters: [{ severity: 'CRITICAL', operator: 'EQUAL_TO', count: 2 }],
      });
    });

    it('emits no url-params-changed event', async () => {
      createComponent({ props: { urlQuery: { critical: 'gte:5' } } });

      await wrapper.setProps({ urlQuery: { critical: '2' } });

      expect(wrapper.emitted('url-params-changed')).toBeUndefined();
    });
  });

  describe('url-params-changed', () => {
    it('emits query params for the applied filters', async () => {
      createComponent({ props: { urlQuery: {}, showStatusFilter: true } });

      findFilteredSearchBar().vm.$emit('on-filter', [
        { type: 'filtered-search-term', value: { data: 'gitlab' } },
        { type: 'critical', value: { data: '5', operator: '>=' } },
        { type: 'DAST', value: { data: 'FAILED', operator: '=' } },
      ]);
      await nextTick();

      expect(wrapper.emitted('url-params-changed')[0][0]).toMatchObject({
        search: 'gitlab',
        'gte[critical]': '5',
        dast: 'failed',
      });
    });

    it('emits null for params whose tokens were removed', async () => {
      createComponent({ props: { urlQuery: { 'gte[critical]': '5' } } });

      findFilteredSearchBar().vm.$emit('on-filter', []);
      await nextTick();

      expect(wrapper.emitted('url-params-changed')[0][0]).toMatchObject({
        search: null,
        critical: null,
      });
    });
  });

  describe('onFilter method', () => {
    it('emits filter-subgroups-and-projects event with search param when filtered with text', async () => {
      const searchTerm = 'test project';
      const filters = [
        {
          type: 'filtered-search-term',
          value: { data: searchTerm },
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        search: searchTerm,
        ...emptyFilters,
      });
    });

    it('emits filter-subgroups-and-projects event with combined search terms when multiple terms are provided', async () => {
      const searchTerms = ['test', 'project'];
      const filters = searchTerms.map((term) => ({
        type: 'filtered-search-term',
        value: { data: term },
      }));
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        search: 'test project',
        ...emptyFilters,
      });
    });

    it('emits filter-subgroups-and-projects event without search when no search terms are provided', async () => {
      findFilteredSearchBar().vm.$emit('on-filter', []);
      await nextTick();
      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        ...emptyFilters,
      });
    });

    it('emits filter-subgroups-and-projects with vulnerability count filter', async () => {
      const filters = [
        {
          id: 'token-1',
          type: 'critical',
          value: { operator: '=', data: '0' },
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();
      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        securityAnalyzerFilters: [],
        vulnerabilityCountFilters: [mockVulnerabilityFilter],
        attributeFilters: [],
      });
    });

    it('adds combined secret detection to analyzer filters', async () => {
      findFilteredSearchBar().vm.$emit('on-filter', [
        {
          id: 'token-3',
          type: 'SECRET_DETECTION',
          value: { operator: '=', data: 'SUCCESS' },
        },
      ]);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        securityAnalyzerFilters: [{ analyzerType: 'SECRET_DETECTION', status: 'SUCCESS' }],
        vulnerabilityCountFilters: [],
        attributeFilters: [],
      });
    });

    it('sets hasScanners for the has scanners enabled status', async () => {
      findFilteredSearchBar().vm.$emit('on-filter', [
        {
          id: 'token-4',
          type: 'STATUS',
          value: { operator: '=', data: 'HAS_SCANNERS' },
        },
      ]);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        ...emptyFilters,
        hasScanners: true,
      });
    });

    it('emits filter-subgroups-and-projects with tool coverage filter', async () => {
      const filters = [
        {
          id: 'token-2',
          type: 'SAST_ADVANCED',
          value: { operator: '=', data: 'NOT_CONFIGURED' },
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();
      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        securityAnalyzerFilters: [mockAnalyzerFilter],
        vulnerabilityCountFilters: [],
        attributeFilters: [],
      });
    });

    it('emits filter-subgroups-and-projects with business logic tool coverage filter', async () => {
      findFilteredSearchBar().vm.$emit('on-filter', [
        { type: 'BUSINESS_LOGIC', value: { operator: '=', data: 'FAILED' } },
      ]);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        ...emptyFilters,
        securityAnalyzerFilters: [{ analyzerType: 'BUSINESS_LOGIC', status: 'FAILED' }],
      });
    });

    it('emits filter-subgroups-and-projects with attribute filter', async () => {
      const filters = [
        {
          type: 'attribute~location',
          value: {
            operator: '||',
            data: ['6', '7'],
          },
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();
      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        securityAnalyzerFilters: [],
        vulnerabilityCountFilters: [],
        attributeFilters: [
          {
            operator: 'IS_ONE_OF',
            attributes: [
              'gid://gitlab/Security::Attribute/6',
              'gid://gitlab/Security::Attribute/7',
            ],
          },
        ],
      });
    });

    it('skips filters without value data', async () => {
      const filters = [
        {
          type: 'filtered-search-term',
          value: { data: 'test search' },
        },
        {
          type: 'filtered-search-term',
          value: {},
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        search: 'test search',
        ...emptyFilters,
      });
    });

    it('ignores non-text filter types', async () => {
      const filters = [
        {
          type: 'filtered-search-term',
          value: { data: 'test search' },
        },
        {
          type: 'other-type',
          value: { data: 'should be ignored' },
        },
      ];
      findFilteredSearchBar().vm.$emit('on-filter', filters);
      await nextTick();

      expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
        search: 'test search',
        ...emptyFilters,
      });
    });

    describe('status filter', () => {
      it.each`
        selected             | expected
        ${'NEEDS_ATTENTION'} | ${{ hasFailedOrWarning: true }}
        ${'STALE_SCANS'}     | ${{ hasStale: true }}
        ${'UNPROTECTED'}     | ${{ hasScanners: false }}
      `(
        'emits filter-subgroups-and-projects with $expected when status is $selected',
        async ({ selected, expected }) => {
          const filters = [
            {
              type: 'STATUS',
              value: { operator: '=', data: selected },
            },
          ];
          findFilteredSearchBar().vm.$emit('on-filter', filters);
          await nextTick();

          expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
            ...emptyFilters,
            ...expected,
          });
        },
      );

      it('ignores unknown status values', async () => {
        const filters = [
          {
            type: 'STATUS',
            value: { operator: '=', data: 'UNKNOWN_STATUS' },
          },
        ];
        findFilteredSearchBar().vm.$emit('on-filter', filters);
        await nextTick();

        expect(wrapper.emitted('filter-subgroups-and-projects')[0][0]).toEqual({
          ...emptyFilters,
        });
      });
    });
  });
});
