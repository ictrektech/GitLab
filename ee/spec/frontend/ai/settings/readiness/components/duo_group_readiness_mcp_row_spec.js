import Vue from 'vue';
import VueApollo from 'vue-apollo';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoGroupReadinessMcpRow from 'ee/ai/settings/readiness/components/duo_group_readiness_mcp_row.vue';
import duoGroupMcpServerNamesQuery from 'ee/ai/settings/readiness/graphql/queries/duo_group_mcp_server_names.query.graphql';

Vue.use(VueApollo);

describe('DuoGroupReadinessMcpRow', () => {
  let wrapper;

  const namesResponse = (names) => ({
    data: { group: { id: 'gid://gitlab/Group/1', duoMcpServerNames: names } },
  });

  const createComponent = ({ names = [], handler, provide = {} } = {}) => {
    const queryHandler = handler || jest.fn().mockResolvedValue(namesResponse(names));

    wrapper = shallowMountExtended(DuoGroupReadinessMcpRow, {
      apolloProvider: createMockApollo([[duoGroupMcpServerNamesQuery, queryHandler]]),
      provide: {
        groupFullPath: 'my-group',
        groupMcpServersPath: '/groups/my-group/-/automate/mcp-servers',
        ...provide,
      },
    });

    return queryHandler;
  };

  const findRow = () => wrapper.findComponent(DuoReadinessRow);
  const findAction = () => wrapper.findComponentByTestId('group-mcp-row-action');

  describe('while the names are loading', () => {
    it('shows a loading row with its control disabled', () => {
      const queryHandler = createComponent();

      expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'my-group' });
      expect(findRow().props()).toMatchObject({
        title: 'External MCP tools',
        status: 'loading',
        description: 'Checking connected MCP tools.',
      });
      expect(findAction().props('disabled')).toBe(true);
    });
  });

  describe('when no servers are connected', () => {
    beforeEach(async () => {
      createComponent({ names: [] });
      await waitForPromises();
    });

    it('stays to-do and points at the documentation', () => {
      expect(findRow().props()).toMatchObject({
        status: 'todo',
        description:
          'Experiment. Connect to tools your team already uses, such as Jira or Linear. None connected yet.',
      });
      expect(findAction().text()).toBe('How to connect');
      expect(findAction().attributes('href')).toBe(
        '/help/user/gitlab_duo/model_context_protocol/ai_catalog_mcp_servers.md',
      );
      expect(findAction().attributes('target')).toBe('_blank');
    });
  });

  describe('when servers are connected', () => {
    it.each`
      names                                         | description
      ${['Atlassian']}                              | ${'Experiment. Atlassian connected. Agents can use it.'}
      ${['Atlassian', 'Linear']}                    | ${'Experiment. Atlassian and Linear connected. Agents can use both.'}
      ${['Atlassian', 'GitHub', 'Linear', 'Slack']} | ${'Experiment. Atlassian, GitHub, and 2 more connected. Agents can use them all.'}
    `('names $names and links to the servers page', async ({ names, description }) => {
      createComponent({ names });
      await waitForPromises();

      expect(findRow().props()).toMatchObject({ status: 'done', description });
      expect(findAction().text()).toBe('View tools');
      expect(findAction().attributes('href')).toBe('/groups/my-group/-/automate/mcp-servers');
    });

    it('renders server names as text, without HTML escaping', async () => {
      createComponent({ names: ['R&D tools'] });
      await waitForPromises();

      expect(findRow().props('description')).toBe(
        'Experiment. R&D tools connected. Agents can use it.',
      );
    });
  });

  describe('when the check cannot be read', () => {
    it.each`
      reason                      | handler
      ${'the request fails'}      | ${jest.fn().mockRejectedValue(new Error('boom'))}
      ${'the answer is redacted'} | ${jest.fn().mockResolvedValue(namesResponse(null))}
    `('stays to-do and offers a re-check when $reason', async ({ handler }) => {
      createComponent({ handler });
      await waitForPromises();

      expect(findRow().props()).toMatchObject({
        status: 'todo',
        description: 'Could not check for connected MCP tools.',
      });
      expect(findAction().text()).toBe('Check again');
    });

    it('re-checks in place', async () => {
      const queryHandler = jest
        .fn()
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValueOnce(namesResponse(['Atlassian']));
      createComponent({ handler: queryHandler });
      await waitForPromises();

      findAction().vm.$emit('click');
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(findRow().props('status')).toBe('done');
    });
  });

  describe('without a path to the servers', () => {
    it('skips the query and says the tools are set up on the top-level group', async () => {
      const queryHandler = createComponent({
        provide: { groupMcpServersPath: null, groupIsRoot: false },
      });
      await waitForPromises();

      expect(queryHandler).not.toHaveBeenCalled();
      expect(findRow().props('status')).toBe('todo');
      expect(findRow().props('description')).toBe(
        'Experiment. External MCP tools are set up on the top-level group.',
      );
      expect(findAction().exists()).toBe(false);
    });

    it('says IDE access is off on a top-level group', async () => {
      const queryHandler = createComponent({
        provide: { groupMcpServersPath: null, groupIsRoot: true },
      });
      await waitForPromises();

      expect(queryHandler).not.toHaveBeenCalled();
      expect(findRow().props('description')).toBe(
        'Experiment. Turn on IDE access to connect external MCP tools.',
      );
      expect(findAction().exists()).toBe(false);
    });

    it('says the tools are unavailable to the user when IDE access is already on', async () => {
      const queryHandler = createComponent({
        provide: { groupMcpServersPath: null, groupIsRoot: true, duoWorkflowMcpRootEnabled: true },
      });
      await waitForPromises();

      expect(queryHandler).not.toHaveBeenCalled();
      expect(findRow().props('description')).toBe(
        'Experiment. External MCP tools are not available to you in this group.',
      );
      expect(findAction().exists()).toBe(false);
    });
  });
});
