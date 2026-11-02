import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { hideGlTooltip, showGlTooltip } from '~/vue_shared/utils/tooltips';
import { useConfigurePathHelpers } from 'helpers/configure_path_helpers';
import AgentFlowListItem from 'ee/ai/duo_agents_platform/components/common/agent_flow_list_item.vue';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { getTimeago } from '~/lib/utils/datetime/timeago_utility';
import { formatAgentFlowTitle, formatAgentStatus } from 'ee/ai/duo_agents_platform/utils';

jest.mock('~/vue_shared/utils/tooltips');
jest.mock('~/lib/utils/datetime/timeago_utility');
jest.mock('ee/ai/duo_agents_platform/utils', () => ({
  formatAgentFlowTitle: jest.fn(),
  formatAgentFlowTitleTooltip: jest.requireActual('ee/ai/duo_agents_platform/utils')
    .formatAgentFlowTitleTooltip,
  formatAgentStatus: jest.fn(),
}));

describe('AgentFlowListItem', () => {
  let wrapper;

  useConfigurePathHelpers();

  const mockTimeago = { format: jest.fn() };
  const mockRouterPush = jest.fn();

  const mockItem = {
    id: 'gid://gitlab/DuoWorkflow::Workflow/1',
    title: 'Custom generated title',
    status: 'FINISHED',
    humanStatus: 'finished',
    updatedAt: '2024-01-01T00:00:00Z',
    workflowDefinition: 'software_development',
    project: {
      id: 'gid://gitlab/Project/1',
      name: 'Test Project',
      fullPath: 'group/project',
    },
  };

  beforeEach(() => {
    formatAgentStatus.mockReturnValue('Finished');
    formatAgentFlowTitle.mockReturnValue('Custom generated title');
    getTimeago.mockReturnValue(mockTimeago);
    mockTimeago.format.mockReturnValue('2 days ago');
    mockRouterPush.mockClear();
  });

  const findLink = () => wrapper.findComponent(GlLink);
  const findStatusIcon = () => wrapper.findComponent(AgentStatusIcon);
  const findItemTitle = () => wrapper.findByTestId('item-title');
  const findItemStatus = () => wrapper.findByTestId('item-status');
  const findUpdatedAt = () => wrapper.findByTestId('item-updated-date');
  const findItemProject = () => wrapper.findByTestId('item-project');

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(AgentFlowListItem, {
      propsData: {
        item: mockItem,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      mocks: {
        $router: { push: mockRouterPush },
      },
    });
  };

  beforeEach(() => {
    createWrapper();
  });

  it('renders the link with a real href to the session page', () => {
    expect(findLink().exists()).toBe(true);
    expect(findLink().attributes('href')).toContain('/group/project/-/automate/agent-sessions/1');
  });

  describe('click behavior', () => {
    let event;

    const clickLink = (modifiers = {}) => {
      event = {
        metaKey: false,
        ctrlKey: false,
        shiftKey: false,
        preventDefault: jest.fn(),
        ...modifiers,
      };
      findLink().vm.$emit('click', event);
    };

    describe('when the link is clicked without a modifier key', () => {
      beforeEach(() => {
        clickLink();
      });

      it('prevents the default navigation', () => {
        expect(event.preventDefault).toHaveBeenCalled();
      });

      it('pushes the session route', () => {
        expect(mockRouterPush).toHaveBeenCalledWith({
          name: AGENTS_PLATFORM_SHOW_ROUTE,
          params: { id: 1 },
        });
      });
    });

    describe.each`
      modifier      | description
      ${'metaKey'}  | ${'Cmd+click opens a new tab'}
      ${'ctrlKey'}  | ${'Ctrl+click opens a new tab'}
      ${'shiftKey'} | ${'Shift+click opens a new window'}
    `('when the link is clicked with $modifier held ($description)', ({ modifier }) => {
      beforeEach(() => {
        clickLink({ [modifier]: true });
      });

      it('does not prevent the default navigation', () => {
        expect(event.preventDefault).not.toHaveBeenCalled();
      });

      it('does not push a route', () => {
        expect(mockRouterPush).not.toHaveBeenCalled();
      });
    });
  });

  describe('when project fullPath is absent', () => {
    beforeEach(() => {
      createWrapper({
        item: { ...mockItem, project: { id: 'gid://gitlab/Project/1', name: 'Test Project' } },
      });
    });

    it('renders the link without an href', () => {
      expect(findLink().attributes('href')).toBeUndefined();
    });
  });

  it('renders the status icon without a label', () => {
    expect(findStatusIcon().exists()).toBe(true);
    expect(findStatusIcon().props('humanStatus')).toBeNull();
  });

  describe('item title', () => {
    it('displays the title', () => {
      expect(findItemTitle().text()).toContain('Custom generated title');
    });

    it('sets the tooltip on the title text to title with numeric id, so it sits over the title', () => {
      expect(getBinding(findItemTitle().element, 'gl-tooltip')).toBeDefined();
      expect(findItemTitle().attributes('title')).toBe('Custom generated title 1');
      expect(findItemTitle().attributes('id')).toMatch(/^agent-session-title-\d+$/);
      expect(findLink().attributes('title')).toBeUndefined();
    });

    it('shows the title tooltip when the link gains focus', async () => {
      await findLink().vm.$emit('focus');

      expect(showGlTooltip).toHaveBeenCalledWith(
        expect.anything(),
        findItemTitle().attributes('id'),
      );
    });

    it('hides the title tooltip when the link loses focus', async () => {
      await findLink().vm.$emit('blur');

      expect(hideGlTooltip).toHaveBeenCalledWith(
        expect.anything(),
        findItemTitle().attributes('id'),
      );
    });

    it('derives the title from the item title and workflow definition', () => {
      expect(formatAgentFlowTitle).toHaveBeenCalledWith(
        'Custom generated title',
        'software_development',
      );
    });
  });

  describe('project info', () => {
    it('does not show project name by default', () => {
      expect(findItemProject().exists()).toBe(false);
    });

    describe('when showProjectInfo is true', () => {
      beforeEach(() => {
        createWrapper({ showProjectInfo: true });
      });

      it('shows the project name', () => {
        expect(findItemProject().text()).toBe('Test Project');
      });
    });
  });

  it('displays the formatted status', () => {
    expect(findItemStatus().text()).toBe('Finished');
  });

  it('displays the formatted updated time', () => {
    expect(findUpdatedAt().text()).toContain('2 days ago');
  });
});
