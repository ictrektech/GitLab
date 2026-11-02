import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DuoGroupReadinessRunnerRow from 'ee/ai/settings/readiness/components/duo_group_readiness_runner_row.vue';
import runnerAvailableQuery from 'ee/ai/settings/readiness/graphql/queries/duo_group_workflow_runner_available.query.graphql';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';

Vue.use(VueApollo);

const ROOT_GROUP = {
  groupFullPath: 'my-group',
  isSaaS: true,
  showDuoAgentPlatformEnablementSetting: true,
};

const SUBGROUP = {
  ...ROOT_GROUP,
  groupFullPath: 'my-group/sub',
  showDuoAgentPlatformEnablementSetting: false,
};

const SELF_MANAGED = {
  ...ROOT_GROUP,
  isSaaS: false,
  showDuoAgentPlatformEnablementSetting: false,
};

describe('DuoGroupReadinessRunnerRow', () => {
  let wrapper;
  let queryHandler;

  const queryResponse = (available, type = null) => ({
    data: {
      group: {
        id: 'gid://gitlab/Group/1',
        duoWorkflowRunnerAvailable: available,
        duoWorkflowUsableRunnerType: type,
      },
    },
  });

  const createComponent = ({ provide = ROOT_GROUP, handler } = {}) => {
    queryHandler = handler || jest.fn().mockResolvedValue(queryResponse(false));

    wrapper = mountExtended(DuoGroupReadinessRunnerRow, {
      apolloProvider: createMockApollo([[runnerAvailableQuery, queryHandler]]),
      provide,
      propsData: { nested: true },
    });
  };

  const findRow = () => wrapper.findComponent(DuoReadinessRow);
  const findAction = () => wrapper.findComponentByTestId('runner-row-action');
  // The description slot holds a text node plus the docs link; collapse template whitespace.
  const descriptionText = () =>
    wrapper.findByTestId('readiness-row-description').text().replace(/\s+/g, ' ');
  const findHowToConfigureLink = () =>
    wrapper.findByTestId('readiness-row-description').findComponent(GlLink);

  describe('while the initial check runs', () => {
    it('shows a loading row with its control disabled', () => {
      createComponent();

      expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'my-group' });
      expect(findRow().props()).toMatchObject({ nested: true, status: 'loading' });
      expect(descriptionText()).toBe('Checking for a runner this group can use.');
      expect(findAction().props('disabled')).toBe(true);
    });
  });

  describe('when a usable runner exists', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(queryResponse(true, 'group_type')),
      });
      await waitForPromises();
    });

    it('is done', () => {
      expect(findRow().props('status')).toBe('done');
      expect(descriptionText()).toBe('Connected. A runner is available and picking up jobs.');
      expect(findHowToConfigureLink().exists()).toBe(false);
    });

    it('links to the runners page filtered to the runner that qualified', () => {
      expect(findAction().text()).toBe('View runners');
      expect(findAction().attributes('href')).toBe(
        '/groups/my-group/-/runners?runner_type=GROUP_TYPE',
      );
      expect(findAction().attributes('target')).toBe('_blank');
    });

    it('confirms the runner to the parent', () => {
      expect(wrapper.emitted('runner-confirmed')).toEqual([[true]]);
    });
  });

  describe('when no runner exists', () => {
    it.each`
      namespace         | provide         | beforeDocsLink
      ${'root group'}   | ${ROOT_GROUP}   | ${'require a runner.'}
      ${'subgroup'}     | ${SUBGROUP}     | ${'Ask a top-level group Owner to register one.'}
      ${'self-managed'} | ${SELF_MANAGED} | ${'Ask an administrator to register one.'}
    `(
      'stays to-do on a $namespace and links the runner setup docs',
      async ({ provide, beforeDocsLink }) => {
        createComponent({ provide });
        await waitForPromises();

        expect(findRow().props('status')).toBe('todo');
        expect(descriptionText()).toContain('Not connected.');
        expect(descriptionText()).toContain(`${beforeDocsLink} How to configure.`);
        expect(findHowToConfigureLink().attributes('href')).toBe(
          '/help/user/duo_agent_platform/flows/execution/_index.md#configure-runners-to-execute-flows',
        );
        expect(findAction().text()).toBe('Check again');
        expect(findAction().props('disabled')).toBe(false);
        expect(wrapper.emitted('runner-confirmed')).toBeUndefined();
      },
    );
  });

  describe('when the check cannot be read', () => {
    it.each`
      reason                      | handler
      ${'the request fails'}      | ${jest.fn().mockRejectedValue(new Error('boom'))}
      ${'the answer is redacted'} | ${jest.fn().mockResolvedValue(queryResponse(null))}
    `('stays to-do and offers a re-check when $reason', async ({ handler }) => {
      createComponent({ handler });
      await waitForPromises();

      expect(findRow().props('status')).toBe('todo');
      expect(descriptionText()).toBe('Could not check for a runner.');
      expect(findHowToConfigureLink().exists()).toBe(false);
      expect(findAction().text()).toBe('Check again');
    });
  });

  describe('Check again', () => {
    it('updates the row in place once a runner has been registered', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(queryResponse(false))
          .mockResolvedValueOnce(queryResponse(true, 'instance_type')),
      });
      await waitForPromises();

      findAction().vm.$emit('click');
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(findRow().props('status')).toBe('done');
      expect(findAction().attributes('href')).toBe(
        '/groups/my-group/-/runners?runner_type=INSTANCE_TYPE',
      );
      expect(wrapper.emitted('runner-confirmed')).toEqual([[true]]);
    });

    it('stays to-do and keeps the control when the re-check fails', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(queryResponse(false))
          .mockRejectedValueOnce(new Error('boom')),
      });
      await waitForPromises();

      findAction().vm.$emit('click');
      await waitForPromises();

      expect(findRow().props('status')).toBe('todo');
      expect(descriptionText()).toBe('Could not check for a runner.');
      expect(findAction().text()).toBe('Check again');
    });
  });
});
