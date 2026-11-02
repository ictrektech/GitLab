import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DuoDependencyBumpProfileModal from 'ee/ai/settings/components/duo_dependency_bump_profile_modal.vue';
import DuoReadinessOrbitRow from 'ee/ai/settings/readiness/components/duo_readiness_orbit_row.vue';
import DuoReadinessMcpRow from 'ee/ai/settings/readiness/components/duo_readiness_mcp_row.vue';
import duoMcpServerNamesQuery from 'ee/ai/settings/readiness/graphql/queries/duo_mcp_server_names.query.graphql';
import runnerAvailableQuery from 'ee/ai/settings/readiness/graphql/queries/duo_workflow_runner_available.query.graphql';
import projectAutoRemediationProfileQuery from 'ee/ai/settings/graphql/queries/project_auto_remediation_profile.query.graphql';
import attachProfileMutation from 'ee/ai/settings/graphql/mutations/auto_remediation_profile_attach.mutation.graphql';
import GitlabDuoSettings from '~/ai/settings/pages/gitlab_duo_settings.vue';

Vue.use(VueApollo);

const defaultProps = {
  projectId: 123,
  projectFullPath: 'namespace/project',
  projectGlobalId: 'gid://gitlab/Project/123',
  duoFeaturesEnabled: true,
  amazonQAvailable: false,
  amazonQAutoReviewEnabled: false,
  duoFeaturesLocked: false,
  licensedAiFeaturesAvailable: true,
  ultimateFeaturesAvailable: true,
  duoContextExclusionSettings: {
    exclusionRules: ['*.log', 'node_modules/'],
  },
  initialDuoRemoteFlowsAvailability: false,
  initialDuoFoundationalFlowsAvailability: false,
  initialDuoSastFalsePositiveDetectionEnabled: false,
  initialDuoSecretDetectionFpEnabled: false,
  initialDuoDependencyBumpBreakingChangesEnabled: false,
  initialDuoSastVrWorkflowEnabled: false,
};

describe('GitlabDuoSettings EE', () => {
  let wrapper;

  const createWrapper = (props = {}, handlers = []) => {
    const propsData = {
      ...defaultProps,
      ...props,
    };

    // The self-loading rows (runner, MCP) query on mount, so a provider always exists.
    const defaultHandlers = [
      [
        runnerAvailableQuery,
        jest.fn().mockResolvedValue({
          data: {
            project: {
              id: 'gid://gitlab/Project/1',
              duoWorkflowRunnerAvailable: false,
              duoWorkflowUsableRunnerType: null,
            },
          },
        }),
      ],
      [
        duoMcpServerNamesQuery,
        jest.fn().mockResolvedValue({
          data: { project: { id: 'gid://gitlab/Project/1', duoMcpServerNames: [] } },
        }),
      ],
    ];
    const apolloProvider = createMockApollo([...handlers, ...defaultHandlers]);

    return mountExtended(GitlabDuoSettings, {
      propsData,
      apolloProvider,
    });
  };

  const findDuoDependencyBumpToggle = () =>
    wrapper.findComponentByTestId('duo-dependency-bump-breaking-changes-enabled');

  beforeEach(() => {
    wrapper = createWrapper();
  });

  describe('Duo Dependency Bump Breaking Changes settings', () => {
    const findModal = () => wrapper.findComponent(DuoDependencyBumpProfileModal);

    it('shows Agentic Breaking Change Resolution toggle', () => {
      wrapper = createWrapper({
        duoFeaturesEnabled: true,
        amazonQAvailable: false,
      });

      expect(findDuoDependencyBumpToggle().exists()).toBe(true);
      expect(findDuoDependencyBumpToggle().props('disabled')).toBe(false);
    });

    it('does not show Agentic Breaking Change Resolution toggle when ultimateFeaturesAvailable is false', () => {
      wrapper = createWrapper({
        duoFeaturesEnabled: true,
        amazonQAvailable: false,
        ultimateFeaturesAvailable: false,
      });

      expect(findDuoDependencyBumpToggle().exists()).toBe(false);
    });

    it('does not disable Agentic Breaking Change Resolution toggle when Duo features are locked on', () => {
      wrapper = createWrapper({
        duoFeaturesEnabled: true,
        duoFeaturesLocked: true,
        amazonQAvailable: false,
      });

      expect(findDuoDependencyBumpToggle().props('disabled')).toBe(false);
    });

    it('does not render Agentic Breaking Change Resolution toggle when Duo features are not enabled', () => {
      wrapper = createWrapper({
        duoFeaturesEnabled: false,
        amazonQAvailable: false,
      });

      expect(findDuoDependencyBumpToggle().exists()).toBe(false);
    });

    it('disables the toggle directly when turned off without showing modal', async () => {
      wrapper = createWrapper({
        duoFeaturesEnabled: true,
        amazonQAvailable: false,
        initialDuoDependencyBumpBreakingChangesEnabled: true,
      });

      const findHiddenInput = () =>
        wrapper.find(
          'input[name="project[project_setting_attributes][duo_dependency_bump_breaking_changes_enabled]"]',
        );

      expect(parseBoolean(findHiddenInput().attributes('value'))).toBe(true);

      await findDuoDependencyBumpToggle().vm.$emit('change', false);
      await nextTick();

      expect(parseBoolean(findHiddenInput().attributes('value'))).toBe(false);
    });

    describe('when enabling the toggle', () => {
      it('enables toggle directly when profile is already attached', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: {
            project: {
              securityScanProfiles: [{ scanType: 'DEPENDENCY_SCANNING_POST_PROCESSING' }],
            },
          },
        });
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        expect(findModal().props('visible')).toBe(false);
        expect(
          parseBoolean(
            wrapper
              .find(
                'input[name="project[project_setting_attributes][duo_dependency_bump_breaking_changes_enabled]"]',
              )
              .attributes('value'),
          ),
        ).toBe(true);
      });

      it('queries for attached profile when toggle is enabled', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: { project: { securityScanProfiles: [] } },
        });
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
        ]);

        findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            fullPath: 'namespace/project',
          }),
        );
      });

      it('enables toggle directly when query fails', async () => {
        const queryHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        expect(findModal().props('visible')).toBe(false);
        expect(
          parseBoolean(
            wrapper
              .find(
                'input[name="project[project_setting_attributes][duo_dependency_bump_breaking_changes_enabled]"]',
              )
              .attributes('value'),
          ),
        ).toBe(true);
      });
    });

    describe('modal confirm action', () => {
      it('calls attach mutation and enables toggle when confirmed', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: { project: { securityScanProfiles: [] } },
        });
        const mutationHandler = jest
          .fn()
          .mockResolvedValue({ data: { securityScanProfileAttach: { errors: [] } } });
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
          [attachProfileMutation, mutationHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        // Call the parent's confirm handler directly
        await wrapper.vm.onAutoRemediationModalConfirm();
        await waitForPromises();

        expect(mutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: {
              securityScanProfileId:
                'gid://gitlab/Security::ScanProfile/dependency_scanning_post_processing',
              projectIds: ['gid://gitlab/Project/123'],
            },
          }),
        );
        expect(wrapper.vm.duoDependencyBumpBreakingChangesEnabled).toBe(true);
      });

      it('still enables toggle when attach mutation fails', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: { project: { securityScanProfiles: [] } },
        });
        const mutationHandler = jest.fn().mockRejectedValue(new Error('Mutation error'));
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
          [attachProfileMutation, mutationHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        await wrapper.vm.onAutoRemediationModalConfirm();
        await waitForPromises();

        expect(wrapper.vm.duoDependencyBumpBreakingChangesEnabled).toBe(true);
      });
    });

    describe('modal cancel action', () => {
      it('enables toggle without calling attach mutation when cancelled', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: { project: { securityScanProfiles: [] } },
        });
        const mutationHandler = jest.fn();
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
          [attachProfileMutation, mutationHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        wrapper.vm.onAutoRemediationModalCancel();
        await waitForPromises();

        expect(mutationHandler).not.toHaveBeenCalled();
        expect(wrapper.vm.duoDependencyBumpBreakingChangesEnabled).toBe(true);
      });
    });

    describe('modal hide action', () => {
      it('disables toggle and does not call attach mutation when modal is dismissed', async () => {
        const queryHandler = jest.fn().mockResolvedValue({
          data: { project: { securityScanProfiles: [] } },
        });
        const mutationHandler = jest.fn();
        wrapper = createWrapper({ duoFeaturesEnabled: true, amazonQAvailable: false }, [
          [projectAutoRemediationProfileQuery, queryHandler],
          [attachProfileMutation, mutationHandler],
        ]);

        await findDuoDependencyBumpToggle().vm.$emit('change', true);
        await waitForPromises();

        wrapper.vm.onAutoRemediationModalHide();
        await waitForPromises();

        expect(mutationHandler).not.toHaveBeenCalled();
        expect(wrapper.vm.duoDependencyBumpBreakingChangesEnabled).toBe(false);
      });
    });
  });

  describe('Recommended group', () => {
    const duoOrbit = {
      enabled: false,
      canEnable: false,
      rootGroupPath: 'gitlab-org',
      graphPath: '/-/dashboard/orbit',
    };

    const duoMcp = {
      serversPath: '/group/project/-/automate/mcp-servers',
    };

    const duoReadiness = { platformEnabled: true };

    const findRecommendedGroup = () => wrapper.findByTestId('duo-recommended-group');
    const findOrbitRow = () => wrapper.findComponent(DuoReadinessOrbitRow);
    const findMcpRow = () => wrapper.findComponent(DuoReadinessMcpRow);

    it('renders the Orbit and MCP rows inside the readiness card', () => {
      wrapper = createWrapper({ duoReadiness, duoOrbit, duoMcp });

      expect(findRecommendedGroup().text()).toContain('Recommended');
      expect(findRecommendedGroup().text()).toContain(
        'Flows run without these. Set them up for the best results.',
      );
      expect(findOrbitRow().props('orbit')).toEqual(duoOrbit);
      expect(findOrbitRow().props('fullPath')).toBe('namespace/project');
      expect(findMcpRow().props('mcp')).toEqual(duoMcp);
      expect(findMcpRow().props('projectFullPath')).toBe('namespace/project');
    });

    it('renders only the available row', () => {
      wrapper = createWrapper({ duoReadiness, duoMcp });

      expect(findRecommendedGroup().exists()).toBe(true);
      expect(findOrbitRow().exists()).toBe(false);
      expect(findMcpRow().exists()).toBe(true);
    });

    it('keeps the agent configuration file row when neither Orbit nor MCP is available', () => {
      wrapper = createWrapper({ duoReadiness });

      expect(findRecommendedGroup().exists()).toBe(true);
      expect(findOrbitRow().exists()).toBe(false);
      expect(findMcpRow().exists()).toBe(false);
    });

    it('is hidden when the Agent Platform is off above the project', () => {
      wrapper = createWrapper({
        duoReadiness: { platformEnabled: false },
        duoOrbit,
      });

      expect(findRecommendedGroup().exists()).toBe(false);
    });
  });

  describe('when the Agent Platform is off above the project', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        duoFeaturesEnabled: true,
        duoReadiness: { platformEnabled: false },
      });
    });

    it('keeps the GitLab Duo toggle live and reports its own state', () => {
      expect(wrapper.findComponentByTestId('duo-row').props('status')).toBe('done');
      expect(wrapper.findComponentByTestId('duo_features_enabled_toggle').props('disabled')).toBe(
        false,
      );
    });

    it('keeps the flow rows blocked, because they are agent-only settings', () => {
      expect(wrapper.findComponentByTestId('flow-execution-row').props('status')).toBe('blocked');
    });
  });
});
