import { GlEmptyState, GlKeysetPagination } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import AgentFlowList from 'ee/ai/duo_agents_platform/components/common/agent_flow_list.vue';
import AgentSessionRetentionNotice from 'ee/ai/duo_agents_platform/components/common/agent_session_retention_notice.vue';
import AgentFlowListItem from 'ee/ai/duo_agents_platform/components/common/agent_flow_list_item.vue';
import { mockAgentFlows } from 'ee_jest/ai/mocks';

describe('AgentFlowList', () => {
  let wrapper;

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findEmptyResult = () => wrapper.findComponent(EmptyResult);
  const findAgentFlowListItems = () => wrapper.findAllComponents(AgentFlowListItem);
  const findKeysetPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findRetentionNotice = () => wrapper.findComponent(AgentSessionRetentionNotice);

  const createWrapper = (props = {}, { provide = {}, stubs = {} } = {}) => {
    wrapper = shallowMountExtended(AgentFlowList, {
      propsData: {
        showEmptyState: false,
        initialSort: 'CREATED_DESC',
        workflows: mockAgentFlows,
        workflowsPageInfo: {},
        ...props,
      },
      provide,
      stubs,
    });
  };

  describe('when component is mounted', () => {
    beforeEach(() => {
      createWrapper();
    });

    describe('and there are no workflows', () => {
      beforeEach(() => {
        createWrapper({ showEmptyState: true, workflows: [] });
      });

      it('renders the emptyState', () => {
        expect(findEmptyState().exists()).toBe(true);
        expect(findEmptyState().props()).toMatchObject({
          title: 'No agent sessions yet',
          description: 'New agent sessions will appear here.',
        });
        expect(findEmptyState().props('svgPath')).toBeDefined();
        expect(findEmptyState().props('svgHeight')).toBe(144);
      });

      it('does not render the agent flow list items', () => {
        expect(findAgentFlowListItems()).toHaveLength(0);
      });
    });

    describe('and there are no workflows in the side panel', () => {
      beforeEach(() => {
        createWrapper(
          { showEmptyState: true, workflows: [] },
          {
            provide: { isSidePanelView: true },
            stubs: {
              GlEmptyState: stubComponent(GlEmptyState, { template: RENDER_ALL_SLOTS_TEMPLATE }),
            },
          },
        );
      });

      it('renders a panel-sized empty state', () => {
        expect(findEmptyState().props()).toMatchObject({
          svgHeight: 72,
          contentClass: { 'gl-text-balance': true },
        });
      });

      it('renders a panel-sized heading', () => {
        const heading = findEmptyState().find('h4');

        expect(heading.text()).toBe('No agent sessions yet');
        expect(heading.classes()).toContain('gl-heading-4');
      });
    });

    describe('and a search returns no workflows', () => {
      beforeEach(() => {
        createWrapper({ showEmptyState: false, workflows: [] });
      });

      it('renders the empty search results state at the full-page size', () => {
        expect(findEmptyResult().props()).toMatchObject({ type: 'search', svgHeight: 144 });
      });
    });

    describe('and a search returns no workflows in the side panel', () => {
      beforeEach(() => {
        createWrapper(
          { showEmptyState: false, workflows: [] },
          { provide: { isSidePanelView: true } },
        );
      });

      it('renders the empty search results state at the side panel size', () => {
        expect(findEmptyResult().props('svgHeight')).toBe(72);
      });
    });

    describe('when there are workflows', () => {
      beforeEach(() => {
        createWrapper({
          showEmptyState: false,
          workflows: mockAgentFlows,
          workflowsPageInfo: {
            startCursor: 'start',
            endCursor: 'end',
            hasNextPage: true,
            hasPreviousPage: false,
          },
        });
      });

      describe('when no row slot is supplied', () => {
        it('renders one AgentFlowListItem per workflow', () => {
          expect(findAgentFlowListItems()).toHaveLength(mockAgentFlows.length);
        });
      });

      describe('when showProjectInfo is false', () => {
        beforeEach(() => {
          createWrapper({
            showEmptyState: false,
            showProjectInfo: false,
          });
        });

        it('passes showProjectInfo as false to each AgentFlowListItem', () => {
          findAgentFlowListItems().wrappers.forEach((item) => {
            expect(item.props('showProjectInfo')).toBe(false);
          });
        });
      });

      describe('when showProjectInfo is true', () => {
        beforeEach(() => {
          createWrapper({
            showEmptyState: false,
            showProjectInfo: true,
          });
        });

        it('passes showProjectInfo as true to each AgentFlowListItem', () => {
          findAgentFlowListItems().wrappers.forEach((item) => {
            expect(item.props('showProjectInfo')).toBe(true);
          });
        });
      });

      describe('when showProjectInfo is not provided', () => {
        beforeEach(() => {
          createWrapper({ showEmptyState: false });
        });

        it('defaults showProjectInfo to false for each AgentFlowListItem', () => {
          findAgentFlowListItems().wrappers.forEach((item) => {
            expect(item.props('showProjectInfo')).toBe(false);
          });
        });
      });
    });
  });

  describe('retention notice', () => {
    describe('when showRetentionNotice is false', () => {
      beforeEach(() => {
        createWrapper();
      });

      it('does not render the retention notice', () => {
        expect(findRetentionNotice().exists()).toBe(false);
      });
    });

    describe('when showRetentionNotice is true', () => {
      const workflowsPageInfo = { hasNextPage: true };

      describe('on the full page', () => {
        beforeEach(() => {
          createWrapper({ showRetentionNotice: true, workflowsPageInfo });
        });

        it('renders the full-page retention notice above the pagination', () => {
          expect(findRetentionNotice().props('sidePanel')).toBe(false);
          expect(findRetentionNotice().element.nextElementSibling).toBe(
            findKeysetPagination().element,
          );
        });
      });

      describe('in the side panel', () => {
        beforeEach(() => {
          createWrapper(
            { showRetentionNotice: true, workflowsPageInfo },
            { provide: { isSidePanelView: true } },
          );
        });

        it('renders the side panel retention notice below the pagination', () => {
          expect(findRetentionNotice().props('sidePanel')).toBe(true);
          expect(findKeysetPagination().element.nextElementSibling).toBe(
            findRetentionNotice().element,
          );
        });
      });

      describe('when a search returns no workflows', () => {
        beforeEach(() => {
          createWrapper({ showRetentionNotice: true, showEmptyState: false, workflows: [] });
        });

        it('renders the retention notice below the empty search results', () => {
          expect(findRetentionNotice().exists()).toBe(true);
          expect(findEmptyResult().element.nextElementSibling).toBe(findRetentionNotice().element);
        });
      });

      describe('when there are no sessions yet', () => {
        beforeEach(() => {
          createWrapper({ showRetentionNotice: true, showEmptyState: true, workflows: [] });
        });

        it('does not render the retention notice', () => {
          expect(findRetentionNotice().exists()).toBe(false);
        });
      });
    });
  });

  describe('keyset pagination controls', () => {
    describe('when there is no pagination data', () => {
      beforeEach(() => {
        wrapper = shallowMountExtended(AgentFlowList, {
          propsData: {
            showEmptyState: true,
            initialSort: 'CREATED_DESC',
            workflows: mockAgentFlows,
            workflowsPageInfo: {},
          },
        });
      });

      it('does not render pagination controls', () => {
        expect(findKeysetPagination().exists()).toBe(false);
      });
    });

    describe('when there is pagination data', () => {
      const createPaginationData = (hasNextPage, hasPreviousPage) => ({
        startCursor: 'start',
        endCursor: 'end',
        hasNextPage,
        hasPreviousPage,
      });

      describe('when hasNextPage is false and hasPreviousPage is false', () => {
        beforeEach(() => {
          createWrapper({
            showEmptyState: true,
            workflows: mockAgentFlows,
            workflowsPageInfo: createPaginationData(false, false),
          });
        });

        it('does not render keyset pagination', () => {
          expect(findKeysetPagination().exists()).toBe(false);
        });
      });

      describe.each([
        { hasNextPage: true, hasPreviousPage: false },
        { hasNextPage: false, hasPreviousPage: true },
        { hasNextPage: true, hasPreviousPage: true },
      ])(
        'when hasNextPage is $hasNextPage and hasPreviousPage is $hasPreviousPage',
        ({ hasNextPage, hasPreviousPage }) => {
          beforeEach(() => {
            createWrapper({
              showEmptyState: false,
              workflows: mockAgentFlows,
              workflowsPageInfo: createPaginationData(hasNextPage, hasPreviousPage),
            });
          });

          it('renders keyset pagination', () => {
            expect(findKeysetPagination().exists()).toBe(true);
          });

          it('binds the correct page info to pagination controls', () => {
            expect(findKeysetPagination().props()).toMatchObject({
              startCursor: 'start',
              endCursor: 'end',
              hasNextPage,
              hasPreviousPage,
            });
          });

          describe('when clicking on the next page', () => {
            beforeEach(() => {
              findKeysetPagination().vm.$emit('next');
            });

            it('emit next-page', () => {
              expect(wrapper.emitted('next-page')).toHaveLength(1);
            });
          });

          describe('when clicking on the previous page', () => {
            beforeEach(() => {
              findKeysetPagination().vm.$emit('prev');
            });

            it('emit prev-page', () => {
              expect(wrapper.emitted('prev-page')).toHaveLength(1);
            });
          });
        },
      );
    });
  });
});
