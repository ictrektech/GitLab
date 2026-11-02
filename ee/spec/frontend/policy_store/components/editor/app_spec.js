import Vue from 'vue';
import { omit } from 'lodash-es';
import VueApollo from 'vue-apollo';
import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { visitUrl, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import App from 'ee/policy_store/components/editor/app.vue';
import StepWizard from 'ee/policy_store/components/editor/step_wizard.vue';
import { createAlert } from '~/alert';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';
import governPolicyCreateMutation from 'ee/policy_store/graphql/govern_policy_create.mutation.graphql';
import governPolicyUpdateMutation from 'ee/policy_store/graphql/govern_policy_update.mutation.graphql';
import {
  mockWizardState,
  mockPolicyParams,
  mockGraphqlPolicy,
  mockMappedPolicy,
  mockOrganizationPoliciesResponse,
  mockGroupPoliciesResponse,
} from '../../mock_data';
import { createPolicyStoreMockApollo } from '../../mock_apollo';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/alert');
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
  visitUrlWithAlerts: jest.fn(),
}));

Vue.use(VueApollo);

const DUPLICATE_NAME_ERROR = 'A policy with this name already exists. Choose a different name.';

describe('PolicyStoreEditorRoot', () => {
  let wrapper;
  let policyHandler;
  let groupPolicyHandler;
  let createHandler;
  let updateHandler;

  // mockPolicyParams as policyMutationVariables spells them for the documents.
  const { policy_scope: policyScope, trigger_type: triggerType, ...plainParams } = mockPolicyParams;
  const mutationParams = { ...plainParams, policyScope, triggerType };
  const organizationId = 'gid://gitlab/Organizations::Organization/1';

  const createResponse = ({ errors = [] } = {}) => ({
    data: {
      governPolicyCreate: {
        __typename: 'GovernPolicyCreatePayload',
        policy: errors.length ? null : { __typename: 'GovernPolicy', id: 9 },
        errors,
      },
    },
  });

  const updateResponse = ({ errors = [] } = {}) => ({
    data: {
      governPolicyUpdate: {
        __typename: 'GovernPolicyUpdatePayload',
        policy: errors.length ? null : mockGraphqlPolicy({ name: 'Prod gate', version: 2 }),
        errors,
      },
    },
  });

  const graphqlErrorResponse = (message) => ({ errors: [{ message }] });

  const findWizard = () => wrapper.findComponent(StepWizard);

  const mountComponent = (provide = {}) => {
    wrapper = shallowMount(App, {
      provide: { organizationId: '1', namespaceType: 'organization', ...provide },
      apolloProvider: createPolicyStoreMockApollo([
        [getPolicyStorePolicies, policyHandler],
        [getGroupPolicyStorePolicies, groupPolicyHandler],
        [governPolicyCreateMutation, createHandler],
        [governPolicyUpdateMutation, updateHandler],
      ]),
    });
  };

  const createComponent = async (provide = {}) => {
    mountComponent(provide);
    await waitForPromises();
  };

  const requestSave = async (state = mockWizardState) => {
    findWizard().vm.$emit('save', state);
    await waitForPromises();
  };

  beforeEach(() => {
    policyHandler = jest.fn().mockResolvedValue(mockOrganizationPoliciesResponse());
    groupPolicyHandler = jest.fn().mockResolvedValue(mockGroupPoliciesResponse());
    createHandler = jest.fn().mockResolvedValue(createResponse());
    updateHandler = jest.fn().mockResolvedValue(updateResponse());
  });

  it('resolves the edited policy through the policies query, mapped for the wizard', async () => {
    await createComponent({ policyId: '2' });

    expect(policyHandler).toHaveBeenCalledTimes(1);
    expect(policyHandler).toHaveBeenCalledWith({ id: organizationId, ids: [2] });
    expect(findWizard().props('policy')).toEqual(mockMappedPolicy);
  });

  // The wizard reads its policy prop once, on mount, so it must not mount
  // until the read settles.
  it('shows a loading icon instead of the wizard while the policy loads', () => {
    policyHandler.mockReturnValue(new Promise(() => {}));

    mountComponent({ policyId: '2' });

    expect(wrapper.find('[data-testid="policy-loading"]').exists()).toBe(true);
    expect(findWizard().exists()).toBe(false);
  });

  it('shows an error instead of a blank editor when the query fails', async () => {
    policyHandler.mockRejectedValue(new Error('not found'));

    await createComponent({ policyId: '2' });

    expect(wrapper.find('[data-testid="policy-error"]').text()).toContain(
      'The policy could not be loaded from the Policy Store API.',
    );
    expect(findWizard().exists()).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ message: expect.stringContaining('not found') }),
    );
  });

  it('shows an error instead of a blank editor when the container lacks the id', async () => {
    policyHandler.mockResolvedValue(mockOrganizationPoliciesResponse([]));

    await createComponent({ policyId: '2' });

    expect(wrapper.find('[data-testid="policy-error"]').exists()).toBe(true);
    expect(findWizard().exists()).toBe(false);
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('shows an error without asking the store when the policy id is not a valid Int', async () => {
    await createComponent({ policyId: '99999999999' });

    expect(wrapper.find('[data-testid="policy-error"]').exists()).toBe(true);
    expect(findWizard().exists()).toBe(false);
    expect(policyHandler).not.toHaveBeenCalled();
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('does not query and renders a blank wizard when there is no policy id', async () => {
    await createComponent();

    expect(policyHandler).not.toHaveBeenCalled();
    expect(groupPolicyHandler).not.toHaveBeenCalled();
    expect(findWizard().props('policy')).toBe(null);
  });

  it('returns to the list when a new policy is cancelled', async () => {
    await createComponent({ listPath: '/-/security/policy_store' });

    findWizard().vm.$emit('cancel');

    expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
  });

  it('returns to the detail view when an edit is cancelled', async () => {
    await createComponent({ policyId: '2', listPath: '/-/security/policy_store' });

    findWizard().vm.$emit('cancel');

    expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store/2');
  });

  describe('saving the policy', () => {
    it('creates a new policy and returns to the list with a success confirmation', async () => {
      await createComponent({ listPath: '/-/security/policy_store' });

      await requestSave();

      expect(createHandler).toHaveBeenCalledWith({ organizationId, ...mutationParams });
      expect(updateHandler).not.toHaveBeenCalled();
      expect(visitUrlWithAlerts).toHaveBeenCalledWith('/-/security/policy_store', [
        {
          id: 'policy-store-policy-created',
          message: 'Policy Prod gate was created.',
          variant: 'success',
        },
      ]);
    });

    it('updates the edited policy and returns to its detail view with a success confirmation', async () => {
      await createComponent({ policyId: '2', listPath: '/-/security/policy_store' });

      await requestSave();

      expect(updateHandler).toHaveBeenCalledWith({
        organizationId,
        policyId: 2,
        ...mutationParams,
      });
      expect(createHandler).not.toHaveBeenCalled();
      expect(visitUrlWithAlerts).toHaveBeenCalledWith('/-/security/policy_store/2', [
        {
          id: 'policy-store-policy-updated',
          message: 'Policy Prod gate was updated.',
          variant: 'success',
        },
      ]);
    });

    it('does not overwrite the stored scope when the Scope step was not touched', async () => {
      await createComponent({ policyId: '2' });

      await requestSave({ ...mockWizardState, scopeChanged: false });

      expect(updateHandler).toHaveBeenCalledWith({
        organizationId,
        policyId: 2,
        ...omit(mutationParams, 'policyScope'),
      });
      expect(updateHandler.mock.calls[0][0]).not.toHaveProperty('policyScope');
    });

    it('sends an untouched scope on create, where there is nothing to overwrite', async () => {
      await createComponent();

      await requestSave({ ...mockWizardState, scopeChanged: false });

      expect(createHandler).toHaveBeenCalledWith({ organizationId, ...mutationParams });
    });

    it('marks the wizard as saving while the request is in flight', async () => {
      createHandler.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestSave();

      expect(findWizard().props('saving')).toBe(true);
    });

    it('stays on the editor and alerts generically when the request fails', async () => {
      createHandler.mockRejectedValue(new Error('API is down'));
      await createComponent();

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be saved. Try again.',
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(visitUrlWithAlerts).not.toHaveBeenCalled();
      expect(findWizard().props('saving')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining('API is down') }),
      );
    });

    // A response with neither a payload nor a top-level error is malformed;
    // the generic alert is right, and Sentry gets the specific reason.
    it('stays on the editor and alerts generically when the mutation returns no payload', async () => {
      createHandler.mockResolvedValue({ data: { governPolicyCreate: null } });
      await createComponent();

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be saved. Try again.',
      });
      expect(visitUrlWithAlerts).not.toHaveBeenCalled();
      expect(Sentry.captureException).toHaveBeenCalledWith(
        new Error('Policy store mutation returned no governPolicyCreate payload'),
      );
    });

    it("surfaces the store's validation message when the mutation rejects the save", async () => {
      createHandler.mockResolvedValue(
        createResponse({ errors: ['rule 0: unsupported rule type "calendar"'] }),
      );
      await createComponent();

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'rule 0: unsupported rule type "calendar"',
      });
      expect(visitUrlWithAlerts).not.toHaveBeenCalled();
    });

    it("surfaces the store's validation message when the mutation rejects an update", async () => {
      updateHandler.mockResolvedValue(updateResponse({ errors: ['Rules is invalid'] }));
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Rules is invalid' });
    });

    it('surfaces a top-level GraphQL error message when the update is refused', async () => {
      updateHandler.mockResolvedValue(
        graphqlErrorResponse('Could not complete the policy store request'),
      );
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Could not complete the policy store request',
      });
      expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('Could not complete the policy store request'),
        }),
      );
    });

    describe('when the save is rejected because a rule does not parse', () => {
      const refusal = 'rules[0] is invalid: expecting expression (at 5:1)';

      beforeEach(async () => {
        createHandler.mockResolvedValue(createResponse({ errors: [refusal] }));
        await createComponent();

        await requestSave();
      });

      it('surfaces the refusal and leaves the author on the editor', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: refusal });
        expect(visitUrl).not.toHaveBeenCalled();
        expect(visitUrlWithAlerts).not.toHaveBeenCalled();
        expect(findWizard().props('saving')).toBe(false);
      });

      it('does not report the rejection to Sentry, since it is author input', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    it('leaves a parse refusal unreported on the edit page too', async () => {
      updateHandler.mockResolvedValue(
        updateResponse({ errors: ['rules[0] is invalid: unexpected token; missing value'] }),
      );
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'rules[0] is invalid: unexpected token; missing value',
      });
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('reports a merged-module failure, which the store raises as an engine error', async () => {
      createHandler.mockResolvedValue(
        graphqlErrorResponse('policy_merged_program is invalid: var msg is unsafe (at 3:3)'),
      );
      await createComponent();

      await requestSave();

      expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('policy_merged_program is invalid'),
        }),
      );
    });

    describe('when the save is rejected because the name is taken', () => {
      beforeEach(async () => {
        createHandler.mockResolvedValue(
          createResponse({ errors: ['Name has already been taken'] }),
        );
        await createComponent();

        await requestSave();
      });

      it('puts the rejection on the name field instead of a page alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
        expect(findWizard().props('nameError')).toBe(DUPLICATE_NAME_ERROR);
        expect(findWizard().props('saving')).toBe(false);
      });

      it('does not report the rejection to Sentry, since it is ordinary user input', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('clears the name error once the name is not a duplicate', async () => {
        await findWizard().vm.$emit('name-update');

        expect(findWizard().props('nameError')).toBe('');
      });

      it('clears the name error as soon as another save attempt starts', async () => {
        createHandler.mockReturnValue(new Promise(() => {}));

        await requestSave();

        expect(findWizard().props('nameError')).toBe('');
      });
    });

    it('routes a duplicate-name rejection to the name field on the edit page too', async () => {
      updateHandler.mockResolvedValue(updateResponse({ errors: ['Name has already been taken'] }));
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).not.toHaveBeenCalled();
      expect(findWizard().props('nameError')).toBe(DUPLICATE_NAME_ERROR);
    });
  });

  describe('when in group context', () => {
    const createGroupComponent = (provide = {}) =>
      createComponent({ namespaceType: 'group', namespacePath: 'my-org/my-group', ...provide });

    it('resolves the edited policy through the group policies query', async () => {
      await createGroupComponent({ policyId: '2' });

      expect(groupPolicyHandler).toHaveBeenCalledWith({ fullPath: 'my-org/my-group', ids: [2] });
      expect(policyHandler).not.toHaveBeenCalled();
      expect(findWizard().props('policy')).toEqual(mockMappedPolicy);
    });

    it('creates a new policy with the group path instead of an organization id', async () => {
      await createGroupComponent({ listPath: '/-/security/policy_store' });

      await requestSave();

      expect(createHandler).toHaveBeenCalledWith({
        groupPath: 'my-org/my-group',
        ...mutationParams,
      });
      expect(createHandler.mock.calls[0][0]).not.toHaveProperty('organizationId');
    });

    it('updates a policy with the group path instead of an organization id', async () => {
      await createGroupComponent({ policyId: '2', listPath: '/-/security/policy_store' });

      await requestSave();

      expect(updateHandler).toHaveBeenCalledWith({
        groupPath: 'my-org/my-group',
        policyId: 2,
        ...mutationParams,
      });
      expect(updateHandler.mock.calls[0][0]).not.toHaveProperty('organizationId');
    });

    it('routes a duplicate-name rejection to the name field for a group policy', async () => {
      createHandler.mockResolvedValue(createResponse({ errors: ['Name has already been taken'] }));
      await createGroupComponent({ listPath: '/-/security/policy_store' });

      await requestSave();

      expect(createAlert).not.toHaveBeenCalled();
      expect(findWizard().props('nameError')).toBe(DUPLICATE_NAME_ERROR);
    });
  });
});
