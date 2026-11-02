import { GlIcon, GlLink, GlSprintf, GlTruncate } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PageHeading from '~/vue_shared/components/page_heading.vue';

import AgentFlowList from 'ee/ai/duo_agents_platform/components/common/agent_flow_list.vue';
import AgentFlowFilteredSearch from 'ee/ai/duo_agents_platform/components/common/agent_flow_filtered_search.vue';
import AgentsPlatformIndex from 'ee/ai/duo_agents_platform/pages/index/duo_agents_platform_index.vue';
import NoCreditsBanner from 'ee/ai/duo_agents_platform/components/common/no_credits_banner.vue';
import UsageBillingForbiddenBanner from 'ee/ai/duo_agents_platform/components/common/usage_billing_forbidden_banner.vue';

import { mockAgentFlowsResponse } from 'ee_jest/ai/mocks';

describe('AgentsPlatformIndex', () => {
  let wrapper;

  const defaultProps = {
    initialSort: 'UPDATED_DESC',
    hasInitialWorkflows: true,
    isLoadingWorkflows: false,
    workflows: mockAgentFlowsResponse.data.project.duoWorkflowWorkflows.edges.map(
      (edge) => edge.node,
    ),
    workflowsPageInfo: { startCursor: 'asdf', endCursor: 'asdf' },
  };

  const createWrapper = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(AgentsPlatformIndex, {
      propsData: { ...defaultProps, ...props },
      provide: {
        isSidePanelView: false,
        creditsAvailable: true,
        ...provide,
      },
      stubs: { GlSprintf },
    });
  };

  const findWorkflowsList = () => wrapper.findComponent(AgentFlowList);
  const findLoadingIcon = () => wrapper.findByTestId('loading-container');
  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findFilteredSearch = () => wrapper.findComponent(AgentFlowFilteredSearch);
  const findNoCreditsBanner = () => wrapper.findComponent(NoCreditsBanner);
  const findUsageBillingForbiddenBanner = () => wrapper.findComponent(UsageBillingForbiddenBanner);
  const findScopedProjectTagline = () => wrapper.findByTestId('scoped-project-tagline');

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('when not in side panel view', () => {
    beforeEach(() => {
      createWrapper({ provide: { isSidePanelView: false } });
    });

    it('loads the page heading', () => {
      expect(findPageHeading().props('heading')).toBe('Sessions');
    });
  });

  describe('when in side panel view', () => {
    beforeEach(() => {
      createWrapper({ provide: { isSidePanelView: true } });
    });

    it('does not render the page heading', () => {
      expect(findPageHeading().exists()).toBe(false);
    });
  });

  describe('scoped project tagline', () => {
    describe('when scoped to a project', () => {
      beforeEach(() => {
        createWrapper({ props: { scopedProjectPath: 'my-group/my-project' } });
      });

      it('tells the user the list is scoped to that project', () => {
        expect(findScopedProjectTagline().text()).toBe('Showing sessions in');
        expect(findScopedProjectTagline().findComponent(GlTruncate).props()).toMatchObject({
          text: 'my-group / my-project',
          position: 'middle',
          withTooltip: true,
        });
      });

      it('shows the project icon before the project name', () => {
        expect(findScopedProjectTagline().findComponent(GlIcon).props('name')).toBe('project');
      });

      it('links the project name to the project', () => {
        const link = findScopedProjectTagline().findComponent(GlLink);

        expect(link.attributes('href')).toBe('/my-group/my-project');
        expect(link.findComponent(GlTruncate).exists()).toBe(true);
      });
    });

    describe.each`
      description                        | props                                                                       | provide
      ${'not scoped to a project'}       | ${{}}                                                                       | ${{}}
      ${'there are no initial sessions'} | ${{ scopedProjectPath: 'my-group/my-project', hasInitialWorkflows: false }} | ${{}}
      ${'in side panel view'}            | ${{ scopedProjectPath: 'my-group/my-project' }}                             | ${{ isSidePanelView: true }}
    `('when $description', ({ props, provide }) => {
      beforeEach(() => {
        createWrapper({ props, provide });
      });

      it('does not render the tagline', () => {
        expect(findScopedProjectTagline().exists()).toBe(false);
      });
    });
  });

  describe('when loading the queries', () => {
    beforeEach(() => {
      createWrapper({ props: { isLoadingWorkflows: true } });
    });

    it('renders the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });

    it('does not render the workflow list', () => {
      expect(findWorkflowsList().exists()).toBe(false);
    });
  });

  describe('when component is mounted', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders the workflows list component', () => {
      expect(findWorkflowsList().exists()).toBe(true);
    });

    it('does not render the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('passes correct props to AgentFlowList', () => {
      expect(findWorkflowsList().props()).toMatchObject({
        showProjectInfo: false,
        showEmptyState: false,
        showRetentionNotice: true,
        workflows: expect.any(Array),
        workflowsPageInfo: expect.any(Object),
      });
    });

    it('renders AgentFlowFilteredSearch with hasInitialWorkflows and initialSort bound', () => {
      expect(findFilteredSearch().props('hasInitialWorkflows')).toBe(true);
      expect(findFilteredSearch().props('initialSort')).toBe('UPDATED_DESC');
    });

    it('leaves the project filter off, since the page can be scoped to one project currently', () => {
      expect(findFilteredSearch().props('showProjectFilter')).toBe(false);
    });
  });

  describe('when showProjectFilter is true', () => {
    beforeEach(() => {
      createWrapper({ props: { showProjectFilter: true } });
    });

    it('passes it on to AgentFlowFilteredSearch', () => {
      expect(findFilteredSearch().props('showProjectFilter')).toBe(true);
    });
  });

  describe('when AgentFlowFilteredSearch emits search-variables-updated', () => {
    beforeEach(() => {
      createWrapper();
      findFilteredSearch().vm.$emit('search-variables-updated', {
        sort: 'CREATED_ASC',
        filters: { statusGroup: 'ACTIVE' },
        updatedAfter: null,
      });
    });

    it('emits query-variables-updated with the merged search variables and reset pagination', () => {
      expect(wrapper.emitted('query-variables-updated')).toEqual([
        [
          {
            sort: 'CREATED_ASC',
            filters: { statusGroup: 'ACTIVE' },
            updatedAfter: null,
            pagination: { first: 20, before: null, after: null, last: null },
          },
        ],
      ]);
    });

    describe('when the next page is then requested', () => {
      beforeEach(() => {
        findWorkflowsList().vm.$emit('next-page');
      });

      it('preserves the search variables across the page turn', () => {
        const emitted = wrapper.emitted('query-variables-updated');

        expect(emitted).toHaveLength(2);
        expect(emitted[1]).toEqual([
          {
            sort: 'CREATED_ASC',
            filters: { statusGroup: 'ACTIVE' },
            updatedAfter: null,
            pagination: { before: null, after: 'asdf', first: 20, last: null },
          },
        ]);
      });
    });
  });

  describe('when mounted with filters restored from a previous visit', () => {
    const initialFilters = { statusGroup: 'ACTIVE', updatedAfter: '2020-06-06T00:00:00.000Z' };

    beforeEach(() => {
      createWrapper({ props: { initialFilters } });
    });

    it('passes the restored filters to AgentFlowFilteredSearch', () => {
      expect(findFilteredSearch().props('initialFilters')).toEqual(initialFilters);
    });

    describe('when the next page is requested before any filter interaction', () => {
      beforeEach(() => {
        findWorkflowsList().vm.$emit('next-page');
      });

      it('keeps the restored filters and sends updatedAfter as its own variable', () => {
        expect(wrapper.emitted('query-variables-updated')).toEqual([
          [
            {
              sort: 'UPDATED_DESC',
              filters: { statusGroup: 'ACTIVE' },
              updatedAfter: '2020-06-06T00:00:00.000Z',
              pagination: { before: null, after: 'asdf', first: 20, last: null },
            },
          ],
        ]);
      });
    });
  });

  describe('pagination', () => {
    beforeEach(() => {
      createWrapper();
    });

    describe('when next page is requested', () => {
      beforeEach(() => {
        findWorkflowsList().vm.$emit('next-page');
      });

      it('emits query-variables-updated event with correct parameters', () => {
        expect(wrapper.emitted('query-variables-updated')).toEqual([
          [
            {
              sort: 'UPDATED_DESC',
              pagination: {
                before: null,
                after: 'asdf',
                first: 20,
                last: null,
              },
              filters: {},
              updatedAfter: null,
            },
          ],
        ]);
      });
    });

    describe('when previous page is requested', () => {
      beforeEach(() => {
        findWorkflowsList().vm.$emit('prev-page');
      });

      it('emits query-variables-updated event with correct parameters', () => {
        expect(wrapper.emitted('query-variables-updated')).toEqual([
          [
            {
              sort: 'UPDATED_DESC',
              pagination: {
                after: null,
                before: 'asdf',
                first: null,
                last: 20,
              },
              filters: {},
              updatedAfter: null,
            },
          ],
        ]);
      });
    });
  });

  describe('no credits banner', () => {
    it.each`
      creditsAvailable | shouldShow
      ${true}          | ${false}
      ${false}         | ${true}
    `(
      '$shouldShow when creditsAvailable is $creditsAvailable',
      ({ creditsAvailable, shouldShow }) => {
        createWrapper({ provide: { creditsAvailable } });

        expect(findNoCreditsBanner().exists()).toBe(shouldShow);
      },
    );

    it('does not render the no credits banner when billing is forbidden', () => {
      createWrapper({ provide: { creditsAvailable: false, billingForbidden: true } });

      expect(findNoCreditsBanner().exists()).toBe(false);
    });
  });

  describe('usage billing forbidden banner', () => {
    it('does not render when credits are available', () => {
      createWrapper({ provide: { creditsAvailable: true, billingForbidden: true } });

      expect(findUsageBillingForbiddenBanner().exists()).toBe(false);
    });

    it('does not render when billing is not forbidden', () => {
      createWrapper({ provide: { creditsAvailable: false, billingForbidden: false } });

      expect(findUsageBillingForbiddenBanner().exists()).toBe(false);
    });

    it('renders when credits are unavailable and billing is forbidden', () => {
      createWrapper({ provide: { creditsAvailable: false, billingForbidden: true } });

      expect(findUsageBillingForbiddenBanner().exists()).toBe(true);
    });
  });
});
