import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMount } from '@vue/test-utils';
import { GlBadge, GlSprintf } from '@gitlab/ui';
import waitForPromises from 'helpers/wait_for_promises';
import { stubComponent } from 'helpers/stub_component';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import { visitUrl } from '~/lib/utils/url_utility';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import App from 'ee/policy_store/components/detail/app.vue';
import SummarySection from 'ee/policy_store/components/detail/summary_section.vue';
import EvaluationsSection from 'ee/policy_store/components/detail/evaluations_section.vue';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';
import governPolicyUpdateMutation from 'ee/policy_store/graphql/govern_policy_update.mutation.graphql';
import governPolicyDeleteMutation from 'ee/policy_store/graphql/govern_policy_delete.mutation.graphql';
import getPolicyEvaluations from 'ee/policy_store/graphql/get_policy_evaluations.query.graphql';
import getGroupPolicyEvaluations from 'ee/policy_store/graphql/get_group_policy_evaluations.query.graphql';
import {
  mockGraphqlPolicy,
  mockPolicyGroup,
  mockOrganizationPoliciesResponse,
  mockGroupPoliciesResponse,
  mockOrganizationInactiveStoreResponse,
  mockGroupInactiveStoreResponse,
  mockGraphqlEvaluation,
  mockOrganizationEvaluationsResponse,
  mockGroupEvaluationsResponse,
} from '../../mock_data';
import { createPolicyStoreMockApollo } from '../../mock_apollo';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/alert');
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');

Vue.use(VueApollo);

const RESOURCE_NOT_AVAILABLE =
  "The resource that you are attempting to access does not exist or you don't have permission to perform this action";

describe('PolicyStoreDetailRoot', () => {
  let wrapper;

  const updateResponse = ({ policy = mockGraphqlPolicy(), errors = [] } = {}) => ({
    data: {
      governPolicyUpdate: { __typename: 'GovernPolicyUpdatePayload', policy, errors },
    },
  });

  const deleteResponse = ({ errors = [] } = {}) => ({
    data: { governPolicyDelete: { __typename: 'GovernPolicyDeletePayload', errors } },
  });

  const graphqlErrorResponse = (message) => ({ errors: [{ message }] });

  let policyHandler;
  let groupPolicyHandler;
  let updateHandler;
  let deleteHandler;
  let evaluationsHandler;
  let groupEvaluationsHandler;

  const mountComponent = (provide = {}) => {
    wrapper = shallowMount(App, {
      provide: {
        organizationId: '1',
        namespaceType: 'organization',
        policyId: '7',
        canUpdatePolicy: true,
        canDeletePolicy: true,
        listPath: '/-/security/policy_store',
        editPath: '/-/security/policy_store/7/edit',
        ...provide,
      },
      stubs: {
        GlSprintf,
        SummarySection: stubComponent(SummarySection, {
          template: '<section><slot></slot></section>',
        }),
      },
      apolloProvider: createPolicyStoreMockApollo([
        [getPolicyStorePolicies, policyHandler],
        [getGroupPolicyStorePolicies, groupPolicyHandler],
        [governPolicyUpdateMutation, updateHandler],
        [governPolicyDeleteMutation, deleteHandler],
        [getPolicyEvaluations, evaluationsHandler],
        [getGroupPolicyEvaluations, groupEvaluationsHandler],
      ]),
    });
  };

  const createComponent = async (provide = {}) => {
    mountComponent(provide);
    await waitForPromises();
  };

  const findByTestId = (id) => wrapper.find(`[data-testid="${id}"]`);
  const findBadges = () => wrapper.findAllComponents(GlBadge);
  const findSections = () => wrapper.findAllComponents(SummarySection);
  const findSection = (testid) =>
    findSections().wrappers.find((section) => section.props('testid') === testid);
  const findEvaluationsSection = () => wrapper.findComponent(EvaluationsSection);
  const findToggleButton = () => wrapper.findComponent('[data-testid="toggle-status-button"]');
  const findDeleteButton = () => wrapper.findComponent('[data-testid="delete-policy-button"]');
  const findEditButton = () => wrapper.findComponent('[data-testid="edit-policy-button"]');
  const findActionsPopover = () => wrapper.find('[data-testid="policy-actions-popover"]');

  const requestToggle = async () => {
    findToggleButton().vm.$emit('click');
    await waitForPromises();
  };

  const requestDelete = async () => {
    findDeleteButton().vm.$emit('click');
    await waitForPromises();
  };

  beforeEach(() => {
    policyHandler = jest.fn().mockResolvedValue(mockOrganizationPoliciesResponse());
    groupPolicyHandler = jest.fn().mockResolvedValue(mockGroupPoliciesResponse());
    updateHandler = jest
      .fn()
      .mockResolvedValue(
        updateResponse({ policy: mockGraphqlPolicy({ lifecycleState: 'disabled', version: 4 }) }),
      );
    deleteHandler = jest.fn().mockResolvedValue(deleteResponse());
    evaluationsHandler = jest.fn().mockResolvedValue(mockOrganizationEvaluationsResponse());
    groupEvaluationsHandler = jest.fn().mockResolvedValue(mockGroupEvaluationsResponse());
    confirmAction.mockResolvedValue(true);
  });

  it('reads the policy by id through the organization policies query', async () => {
    await createComponent();

    expect(policyHandler).toHaveBeenCalledTimes(1);
    expect(policyHandler).toHaveBeenCalledWith({
      id: 'gid://gitlab/Organizations::Organization/1',
      ids: [7],
    });
    expect(groupPolicyHandler).not.toHaveBeenCalled();
  });

  it('renders the header with name, badges, and description', async () => {
    await createComponent();

    expect(findByTestId('policy-name').text()).toBe('Production gate');
    expect(findByTestId('policy-description').text()).toBe('Gates production deployments');
    expect(findBadges().wrappers.map((badge) => badge.text())).toEqual([
      'Deployment requested',
      'Enforce',
      'Active',
    ]);
  });

  it('labels the trigger from the catalog the same document carries', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse(
        [mockGraphqlPolicy({ triggerType: 'merge_requested' })],
        [{ __typename: 'PolicyStoreTrigger', id: 'merge_requested', name: 'Merge request' }],
      ),
    );

    await createComponent();

    expect(findByTestId('policy-type').text()).toBe('Merge request');
  });

  it('renders no description paragraph when the policy has none', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([mockGraphqlPolicy({ description: '' })]),
    );

    await createComponent();

    expect(findByTestId('policy-description').exists()).toBe(false);
  });

  it('passes catalog-resolved entries to the trigger, rules, and actions sections', async () => {
    await createComponent();

    expect(findSections().wrappers.map((section) => section.props('label'))).toEqual([
      'Trigger',
      'Rules',
      'Actions',
      'Scope',
    ]);
    expect(findSection('trigger').props('entries')).toEqual([
      expect.objectContaining({ label: 'Deployment requested' }),
    ]);
    expect(findSection('rules').props('entries')).toEqual([
      expect.objectContaining({ label: 'Custom Rule (Rego)' }),
    ]);
    expect(findSection('actions').props('entries')).toEqual([
      expect.objectContaining({ label: 'Block' }),
    ]);
  });

  it('falls back to the raw id for an entry the catalog no longer knows', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([
        mockGraphqlPolicy({ rules: [{ type: 'retired_rule', value: {} }] }),
      ]),
    );

    await createComponent();

    expect(findSection('rules').props('entries')).toEqual([
      expect.objectContaining({ id: 'retired_rule', label: 'retired_rule', icon: 'question-o' }),
    ]);
  });

  it('passes no entries for a section with nothing configured', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([mockGraphqlPolicy({ actions: [] })]),
    );

    await createComponent();

    expect(findSection('actions').props('entries')).toEqual([]);
  });

  it('resolves configured values into labelled config items on each entry', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([
        mockGraphqlPolicy({
          rules: [
            { type: 'custom', value: 'input.vulnerabilities.critical == 0' },
            {
              type: 'calendar',
              value: {
                windows: [
                  {
                    name: 'eoq-freeze',
                    tiers: ['production', 'staging'],
                    starts_at: '2026-12-24T00:00:00Z',
                    ends_at: '2027-01-02T00:00:00Z',
                  },
                ],
              },
            },
          ],
          actions: [{ type: 'require_approval', value: { roles: ['maintainer', 'owner'] } }],
        }),
      ]),
    );

    await createComponent();

    const [customRule, calendarRule] = findSection('rules').props('entries');
    expect(customRule.configItems).toEqual([
      expect.objectContaining({
        label: 'Rego policy definition',
        code: true,
        value: 'input.vulnerabilities.critical == 0',
      }),
    ]);
    expect(calendarRule.configItems).toEqual([
      expect.objectContaining({
        label: 'Freeze windows',
        value: 'eoq-freeze · Production / Staging · 2026-12-24T00:00:00Z → 2027-01-02T00:00:00Z',
      }),
    ]);
    expect(findSection('actions').props('entries')[0].configItems).toEqual([
      expect.objectContaining({ label: 'Role approvers', value: 'Maintainer, Owner' }),
    ]);
  });

  it('omits config items for fields the policy leaves unset', async () => {
    await createComponent();

    expect(findSection('trigger').props('entries')[0].configItems).toEqual([]);
    expect(findSection('actions').props('entries')[0].configItems).toEqual([]);
  });

  it('summarises the scope in a summary section from the scoped project count', async () => {
    await createComponent();

    expect(findSection('scope').props('label')).toBe('Scope');
    expect(findSection('scope').text()).toContain('3 projects');
  });

  it('labels an unscoped policy as applying to all projects', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([mockGraphqlPolicy({ policyScope: null })]),
    );

    await createComponent();

    expect(findSection('scope').text()).toContain('All projects');
  });

  describe('when the policy has compiled scope Rego', () => {
    beforeEach(async () => {
      policyHandler.mockResolvedValue(
        mockOrganizationPoliciesResponse([
          mockGraphqlPolicy({ scopeRego: 'package gitlab.scope\n\napplicable = true' }),
        ]),
      );

      await createComponent();
    });

    it('shows it in a read-only code block', () => {
      expect(findSection('scope-rego').props('label')).toBe('Compiled scope Rego');
      expect(findSection('scope-rego').find('pre code').text()).toBe(
        'package gitlab.scope\n\napplicable = true',
      );
    });

    it('makes the scrollable code block focusable and named for keyboard users', () => {
      expect(findSection('scope-rego').find('pre').attributes()).toMatchObject({
        tabindex: '0',
        role: 'region',
        'aria-label': 'Compiled scope Rego',
      });
    });
  });

  it('omits the scope Rego section when the store compiled none', async () => {
    await createComponent();

    expect(findSection('scope-rego')).toBeUndefined();
  });

  describe('when the policy has compiled policy Rego', () => {
    beforeEach(async () => {
      policyHandler.mockResolvedValue(
        mockOrganizationPoliciesResponse([
          mockGraphqlPolicy({
            policyRego: 'package governance\n\nviolation contains {"msg": "no"}',
          }),
        ]),
      );

      await createComponent();
    });

    it('shows it in a read-only code block', () => {
      expect(findSection('policy-rego').props('label')).toBe('Compiled policy Rego');
      expect(findSection('policy-rego').find('pre code').text()).toBe(
        'package governance\n\nviolation contains {"msg": "no"}',
      );
    });

    it('makes the scrollable code block focusable and named for keyboard users', () => {
      expect(findSection('policy-rego').find('pre').attributes()).toMatchObject({
        tabindex: '0',
        role: 'region',
        'aria-label': 'Compiled policy Rego',
      });
    });
  });

  it('omits the policy Rego section when the store compiled none', async () => {
    await createComponent();

    expect(findSection('policy-rego')).toBeUndefined();
  });

  it('shows the version and the created and updated times', async () => {
    await createComponent();

    expect(findByTestId('policy-version').text()).toBe('Version 3');
    expect(findByTestId('policy-created-at').findComponent(TimeAgoTooltip).props('time')).toBe(
      '2026-08-19T23:41:12.686Z',
    );
    expect(findByTestId('policy-updated-at').findComponent(TimeAgoTooltip).props('time')).toBe(
      '2026-08-20T09:12:44.120Z',
    );
  });

  it('omits the timestamps the store did not set', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([mockGraphqlPolicy({ createdAt: null, updatedAt: null })]),
    );

    await createComponent();

    expect(findByTestId('policy-created-at').exists()).toBe(false);
    expect(findByTestId('policy-updated-at').exists()).toBe(false);
  });

  it('omits the version when the store did not set one', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([mockGraphqlPolicy({ version: null })]),
    );

    await createComponent();

    expect(findByTestId('policy-version').exists()).toBe(false);
  });

  it('omits the whole meta line when the store set none of its fields', async () => {
    policyHandler.mockResolvedValue(
      mockOrganizationPoliciesResponse([
        mockGraphqlPolicy({ version: null, createdAt: null, updatedAt: null }),
      ]),
    );

    await createComponent();

    expect(findByTestId('policy-meta').exists()).toBe(false);
  });

  it('links the edit button to the edit path', async () => {
    await createComponent();

    expect(findByTestId('edit-policy-button').attributes('href')).toBe(
      '/-/security/policy_store/7/edit',
    );
  });

  it('shows a loading icon instead of the page while the policy loads', () => {
    policyHandler.mockReturnValue(new Promise(() => {}));

    mountComponent();

    expect(findByTestId('policy-loading').exists()).toBe(true);
    expect(findByTestId('policy-name').exists()).toBe(false);
  });

  it('shows an error instead of the page when the query fails', async () => {
    policyHandler.mockRejectedValue(new Error('API is down'));

    await createComponent();

    expect(findByTestId('policy-error').text()).toContain(
      'The policy could not be loaded from the Policy Store API.',
    );
    expect(findByTestId('policy-name').exists()).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ message: expect.stringContaining('API is down') }),
    );
  });

  // The resolver answers an unknown id with an empty list, a denied read with
  // a null connection and an inactive store with a null policyStore, never
  // with an error, so each one has to reach the same page state.
  it.each`
    description                       | response
    ${'the container lacks the id'}   | ${mockOrganizationPoliciesResponse([])}
    ${'the policies are unreadable'}  | ${mockOrganizationPoliciesResponse(null)}
    ${'the policy store is inactive'} | ${mockOrganizationInactiveStoreResponse()}
  `('shows an error instead of the page when $description', async ({ response }) => {
    policyHandler.mockResolvedValue(response);

    await createComponent();

    expect(findByTestId('policy-error').exists()).toBe(true);
    expect(findByTestId('policy-name').exists()).toBe(false);
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  // The route only lets digits through, but the ids argument is a 32-bit
  // [Int!], so an id above that range would fail the request rather than come
  // back as not found; it is the not-found state up front.
  it('shows an error without asking the store when the policy id is not a valid Int', async () => {
    await createComponent({ policyId: '99999999999' });

    expect(findByTestId('policy-error').exists()).toBe(true);
    expect(findByTestId('policy-name').exists()).toBe(false);
    expect(policyHandler).not.toHaveBeenCalled();
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  // A failed refetch re-emits the last cached policy with the error attached;
  // the page must keep the error state rather than re-render stale data.
  it('keeps the error state and hides the stale policy when a refetch fails', async () => {
    await createComponent();
    expect(findByTestId('policy-name').exists()).toBe(true);

    policyHandler.mockRejectedValue(new Error('API is down'));
    await wrapper.vm.$apollo.queries.policy.refetch().catch(() => {});
    await waitForPromises();

    expect(findByTestId('policy-error').exists()).toBe(true);
    expect(findByTestId('policy-name').exists()).toBe(false);
  });

  describe('toggling the policy status', () => {
    it('offers Disable for an active policy and Enable for a disabled one', async () => {
      await createComponent();
      expect(findToggleButton().text()).toBe('Disable');

      policyHandler.mockResolvedValue(
        mockOrganizationPoliciesResponse([mockGraphqlPolicy({ lifecycleState: 'disabled' })]),
      );
      await createComponent();
      expect(findToggleButton().text()).toBe('Enable');
    });

    it('disables an active policy through the update mutation', async () => {
      await createComponent();

      await requestToggle();

      expect(updateHandler).toHaveBeenCalledWith({
        organizationId: 'gid://gitlab/Organizations::Organization/1',
        policyId: 7,
        lifecycleState: 'disabled',
      });
      expect(visitUrl).not.toHaveBeenCalled();
    });

    it('refreshes the badge from the mutation result without reading the policy again', async () => {
      await createComponent();

      await requestToggle();

      expect(findByTestId('policy-status').text()).toBe('Disabled');
      expect(findToggleButton().text()).toBe('Enable');
      expect(policyHandler).toHaveBeenCalledTimes(1);
    });

    it('keeps the compiled Rego and refreshes the version after a toggle', async () => {
      const policyRego = 'package governance\n\nviolation contains {"msg": "no"}';
      policyHandler.mockResolvedValue(
        mockOrganizationPoliciesResponse([mockGraphqlPolicy({ policyRego })]),
      );
      updateHandler.mockResolvedValue(
        updateResponse({
          policy: mockGraphqlPolicy({
            lifecycleState: 'disabled',
            version: 4,
            updatedAt: '2026-08-20T20:00:00.000Z',
            policyRego,
          }),
        }),
      );
      await createComponent();

      await requestToggle();

      expect(findSection('policy-rego').find('pre code').text()).toBe(policyRego);
      expect(findByTestId('policy-version').text()).toBe('Version 4');
      expect(findByTestId('policy-updated-at').findComponent(TimeAgoTooltip).props('time')).toBe(
        '2026-08-20T20:00:00.000Z',
      );
    });

    it('re-enables a disabled policy', async () => {
      policyHandler.mockResolvedValue(
        mockOrganizationPoliciesResponse([mockGraphqlPolicy({ lifecycleState: 'disabled' })]),
      );
      updateHandler.mockResolvedValue(updateResponse());
      await createComponent();

      await requestToggle();

      expect(updateHandler).toHaveBeenCalledWith(
        expect.objectContaining({ policyId: 7, lifecycleState: 'active' }),
      );
      expect(findByTestId('policy-status').text()).toBe('Active');
    });

    it('marks the button busy while the request is in flight', async () => {
      updateHandler.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestToggle();

      expect(findToggleButton().props('loading')).toBe(true);
    });

    it('keeps the status and alerts generically when the request fails', async () => {
      updateHandler.mockRejectedValue(new Error('API is down'));
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be updated. Try again.',
      });
      expect(findByTestId('policy-status').text()).toBe('Active');
      expect(findToggleButton().props('loading')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining('API is down') }),
      );
    });

    it('keeps the status and alerts generically when the update returns no payload', async () => {
      updateHandler.mockResolvedValue({ data: { governPolicyUpdate: null } });
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be updated. Try again.',
      });
      expect(findByTestId('policy-status').text()).toBe('Active');
      expect(Sentry.captureException).toHaveBeenCalledWith(
        new Error('Policy store mutation returned no governPolicyUpdate payload'),
      );
    });

    it("surfaces the store's message when the update is rejected as invalid", async () => {
      updateHandler.mockResolvedValue(
        updateResponse({ policy: null, errors: ['Lifecycle state is invalid'] }),
      );
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Lifecycle state is invalid' });
      expect(findByTestId('policy-status').text()).toBe('Active');
    });

    it('surfaces a top-level GraphQL error message, such as the policy no longer existing', async () => {
      updateHandler.mockResolvedValue(graphqlErrorResponse(RESOURCE_NOT_AVAILABLE));
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({ message: RESOURCE_NOT_AVAILABLE });
      expect(findByTestId('policy-status').text()).toBe('Active');
    });
  });

  describe('deleting the policy', () => {
    it('asks for confirmation naming the policy', async () => {
      await createComponent();

      await requestDelete();

      expect(confirmAction).toHaveBeenCalledWith(
        'Are you sure you want to delete Production gate? This action cannot be undone.',
        expect.objectContaining({ primaryBtnVariant: 'danger' }),
      );
    });

    it('deletes the policy through the delete mutation and returns to the list', async () => {
      await createComponent();

      await requestDelete();

      expect(deleteHandler).toHaveBeenCalledWith({
        organizationId: 'gid://gitlab/Organizations::Organization/1',
        id: 7,
      });
      expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
    });

    it('does not delete when the confirmation is declined', async () => {
      confirmAction.mockResolvedValue(false);
      await createComponent();

      await requestDelete();

      expect(deleteHandler).not.toHaveBeenCalled();
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('ignores further clicks while the confirmation is pending', async () => {
      confirmAction.mockReturnValue(new Promise(() => {}));
      await createComponent();

      findDeleteButton().vm.$emit('click');
      findDeleteButton().vm.$emit('click');
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledTimes(1);
      expect(findDeleteButton().props('loading')).toBe(true);
    });

    it('resets the busy state after deleting when there is no list path to return to', async () => {
      await createComponent({ listPath: '' });

      await requestDelete();

      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('marks the delete button busy while the request is in flight', async () => {
      deleteHandler.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestDelete();

      expect(findDeleteButton().props('loading')).toBe(true);
    });

    it('stays on the page and alerts when the request fails', async () => {
      deleteHandler.mockRejectedValue(new Error('API is down'));
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be deleted. Try again.',
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining('API is down') }),
      );
    });

    it('stays on the page and alerts generically when the delete returns no payload', async () => {
      deleteHandler.mockResolvedValue({ data: { governPolicyDelete: null } });
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be deleted. Try again.',
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        new Error('Policy store mutation returned no governPolicyDelete payload'),
      );
    });

    it('surfaces a top-level GraphQL error message when the delete is refused', async () => {
      deleteHandler.mockResolvedValue(graphqlErrorResponse(RESOURCE_NOT_AVAILABLE));
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: RESOURCE_NOT_AVAILABLE });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('alerts with the store message when the store rejects the delete', async () => {
      deleteHandler.mockResolvedValue(deleteResponse({ errors: ['Policy was not found'] }));
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Policy was not found' });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('joins multiple store messages so none is silently dropped', async () => {
      deleteHandler.mockResolvedValue(
        deleteResponse({ errors: ['Policy is stale', 'Policy is locked'] }),
      );
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Policy is stale, Policy is locked' });
    });
  });

  describe('without the permission to change the policy', () => {
    it('hides the edit and disable buttons but keeps delete', async () => {
      await createComponent({ canUpdatePolicy: false });

      expect(findEditButton().exists()).toBe(false);
      expect(findToggleButton().exists()).toBe(false);
      expect(findDeleteButton().exists()).toBe(true);
    });

    it('hides the delete button but keeps edit and disable', async () => {
      await createComponent({ canDeletePolicy: false });

      expect(findDeleteButton().exists()).toBe(false);
      expect(findEditButton().exists()).toBe(true);
    });

    it('hides the whole action group when the user may do none of it', async () => {
      await createComponent({ canUpdatePolicy: false, canDeletePolicy: false });

      expect(findEditButton().exists()).toBe(false);
      expect(findToggleButton().exists()).toBe(false);
      expect(findDeleteButton().exists()).toBe(false);
    });
  });

  describe('the recent evaluations', () => {
    it("reads the policy's evaluations and hands the rows to the section", async () => {
      await createComponent();

      expect(evaluationsHandler).toHaveBeenCalledWith({
        id: 'gid://gitlab/Organizations::Organization/1',
        policyId: 7,
        first: 20,
      });
      expect(groupEvaluationsHandler).not.toHaveBeenCalled();
      expect(findEvaluationsSection().props('evaluations')).toEqual([
        expect.objectContaining({
          mode: 'enforce',
          verdict: 'deny',
          trigger: expect.objectContaining({ label: 'Project settings change requested' }),
        }),
      ]);
    });

    it('hands the section an empty list when the policy has never run', async () => {
      evaluationsHandler.mockResolvedValue(mockOrganizationEvaluationsResponse([]));

      await createComponent();

      expect(findEvaluationsSection().props('evaluations')).toEqual([]);
    });

    // Null is the read the viewer is not allowed, not an empty history, and the
    // section says so. Either way the policy page itself still renders.
    it.each`
      description                         | setup
      ${'the evaluations are unreadable'} | ${() => evaluationsHandler.mockResolvedValue(mockOrganizationEvaluationsResponse(null))}
      ${'the policy store is inactive'}   | ${() => evaluationsHandler.mockResolvedValue(mockOrganizationInactiveStoreResponse())}
      ${'the request fails'}              | ${() => evaluationsHandler.mockRejectedValue(new Error('network'))}
    `('hands the section null when $description', async ({ setup }) => {
      setup();

      await createComponent();

      expect(findEvaluationsSection().props('evaluations')).toBe(null);
      expect(findByTestId('policy-name').exists()).toBe(true);
      expect(findByTestId('policy-error').exists()).toBe(false);
    });

    // The policy resolves first, so the section renders busy rather than the page.
    it('marks the section busy while the evaluations are in flight', async () => {
      evaluationsHandler.mockReturnValue(new Promise(() => {}));

      await createComponent();

      expect(findEvaluationsSection().props('loading')).toBe(true);
      expect(findByTestId('policy-name').exists()).toBe(true);
    });

    it('passes through an evaluation that produced no violations', async () => {
      evaluationsHandler.mockResolvedValue(
        mockOrganizationEvaluationsResponse([mockGraphqlEvaluation({ violations: [] })]),
      );

      await createComponent();

      expect(findEvaluationsSection().props('evaluations')[0].violations).toEqual([]);
    });
  });

  describe('when in group context', () => {
    const ownedPolicy = mockGraphqlPolicy({
      group: { ...mockPolicyGroup, name: 'My group', fullPath: 'my-org/my-group' },
    });

    const createGroupComponent = (provide = {}) =>
      createComponent({ namespaceType: 'group', namespacePath: 'my-org/my-group', ...provide });

    // The store only accepts a write from the policy's own container, so the
    // default here is the one case a group page can act on.
    beforeEach(() => {
      groupPolicyHandler.mockResolvedValue(mockGroupPoliciesResponse([ownedPolicy]));
    });

    it('reads the policy by id through the group policies query', async () => {
      await createGroupComponent();

      expect(groupPolicyHandler).toHaveBeenCalledWith({ fullPath: 'my-org/my-group', ids: [7] });
      expect(policyHandler).not.toHaveBeenCalled();
      expect(findByTestId('policy-name').text()).toBe('Production gate');
    });

    it.each`
      description                       | response
      ${'the group lacks the id'}       | ${mockGroupPoliciesResponse([])}
      ${'the policies are unreadable'}  | ${mockGroupPoliciesResponse(null)}
      ${'the policy store is inactive'} | ${mockGroupInactiveStoreResponse()}
    `('shows an error instead of the page when $description', async ({ response }) => {
      groupPolicyHandler.mockResolvedValue(response);

      await createGroupComponent();

      expect(findByTestId('policy-error').exists()).toBe(true);
      expect(findByTestId('policy-name').exists()).toBe(false);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('toggles the status with the group path instead of an organization id', async () => {
      await createGroupComponent();

      await requestToggle();

      expect(updateHandler).toHaveBeenCalledWith({
        groupPath: 'my-org/my-group',
        policyId: 7,
        lifecycleState: 'disabled',
      });
      expect(findByTestId('policy-status').text()).toBe('Disabled');
      expect(groupPolicyHandler).toHaveBeenCalledTimes(1);
    });

    it('deletes with the group path and returns to the list', async () => {
      await createGroupComponent();

      await requestDelete();

      expect(deleteHandler).toHaveBeenCalledWith({ groupPath: 'my-org/my-group', id: 7 });
      expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
    });

    it("reads the policy's evaluations through the group document", async () => {
      await createGroupComponent();

      expect(groupEvaluationsHandler).toHaveBeenCalledWith({
        fullPath: 'my-org/my-group',
        policyId: 7,
        first: 20,
      });
      expect(evaluationsHandler).not.toHaveBeenCalled();
      expect(findEvaluationsSection().props('evaluations')).toHaveLength(1);
    });

    it('shows the store message when the delete fails', async () => {
      deleteHandler.mockResolvedValue(deleteResponse({ errors: ['Policy is locked'] }));
      await createGroupComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Policy is locked' });
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('enables the actions and explains nothing for a policy the group owns', async () => {
      await createGroupComponent();

      expect(findEditButton().props('disabled')).toBe(false);
      expect(findToggleButton().props('disabled')).toBe(false);
      expect(findDeleteButton().props('disabled')).toBe(false);
      expect(findActionsPopover().exists()).toBe(false);
    });

    it('names the owning group for a policy the group owns', async () => {
      await createGroupComponent();

      expect(findByTestId('policy-source').text()).toBe('Owned by My group');
    });

    describe('a policy the group cannot change', () => {
      it.each`
        description           | policy                                                            | source                               | explanation
        ${'from an ancestor'} | ${mockGraphqlPolicy({ inherited: true, group: mockPolicyGroup })} | ${'Inherited from Flight'}           | ${'This policy belongs to Flight and can only be changed there.'}
        ${'from the org'}     | ${mockGraphqlPolicy({ inherited: true })}                         | ${'Inherited from the organization'} | ${'This policy belongs to the organization and can only be changed there.'}
      `(
        '$description names its source and disables the actions',
        async ({ policy, source, explanation }) => {
          groupPolicyHandler.mockResolvedValue(mockGroupPoliciesResponse([policy]));

          await createGroupComponent();

          expect(findByTestId('policy-source').text()).toBe(source);
          expect(findEditButton().props('disabled')).toBe(true);
          expect(findToggleButton().props('disabled')).toBe(true);
          expect(findDeleteButton().props('disabled')).toBe(true);
          expect(findActionsPopover().text()).toBe(explanation);
        },
      );

      it('leaves the edit button without a link to follow', async () => {
        groupPolicyHandler.mockResolvedValue(
          mockGroupPoliciesResponse([mockGraphqlPolicy({ inherited: true })]),
        );

        await createGroupComponent();

        expect(findEditButton().attributes('href')).toBeUndefined();
      });

      it('points the actions at the source line for assistive technology', async () => {
        groupPolicyHandler.mockResolvedValue(
          mockGroupPoliciesResponse([mockGraphqlPolicy({ inherited: true })]),
        );

        await createGroupComponent();

        const sourceId = findByTestId('policy-source').attributes('id');

        expect(sourceId).toEqual(expect.stringContaining('policy-source-'));
        expect(findEditButton().attributes('aria-describedby')).toBe(sourceId);
        expect(findToggleButton().attributes('aria-describedby')).toBe(sourceId);
        expect(findDeleteButton().attributes('aria-describedby')).toBe(sourceId);
      });

      it('sends no mutation when a disabled action is triggered anyway', async () => {
        groupPolicyHandler.mockResolvedValue(
          mockGroupPoliciesResponse([mockGraphqlPolicy({ inherited: true })]),
        );

        await createGroupComponent();
        await requestToggle();
        await requestDelete();

        expect(updateHandler).not.toHaveBeenCalled();
        expect(deleteHandler).not.toHaveBeenCalled();
        expect(confirmAction).not.toHaveBeenCalled();
      });
    });
  });
});
