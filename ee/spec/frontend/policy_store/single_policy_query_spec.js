import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import singlePolicyQuery from 'ee/policy_store/single_policy_query';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('singlePolicyQuery', () => {
  let wrapper;
  let policyHandler;

  const notFoundResponse = {
    data: {
      organization: {
        __typename: 'Organization',
        id: 'gid://gitlab/Organizations::Organization/1',
        policyStore: {
          __typename: 'PolicyStore',
          policies: {
            __typename: 'GovernPolicyConnection',
            nodes: [],
            pageInfo: { __typename: 'PageInfo', hasNextPage: false, endCursor: null },
          },
          triggers: [],
        },
      },
    },
  };

  // Renders the policy and the flag so the specs assert what a template shows.
  const host = {
    name: 'SinglePolicyQueryHost',
    inject: ['organizationId', 'namespacePath', 'namespaceType', 'policyId'],
    data() {
      return { policy: null, policyError: false };
    },
    apollo: {
      policy: singlePolicyQuery,
    },
    render(h) {
      return h('div', [
        h('span', { attrs: { 'data-testid': 'policy' } }, this.policy ? this.policy.name : 'null'),
        h('span', { attrs: { 'data-testid': 'policy-error' } }, String(this.policyError)),
      ]);
    },
  };

  const findPolicy = () => wrapper.findByTestId('policy').text();
  const findPolicyError = () => wrapper.findByTestId('policy-error').text();

  const createComponent = async ({ policyId = '7' } = {}) => {
    wrapper = shallowMountExtended(host, {
      provide: {
        organizationId: '1',
        namespacePath: '',
        namespaceType: 'organization',
        policyId,
      },
      apolloProvider: createMockApollo([
        [getPolicyStorePolicies, policyHandler],
        [getGroupPolicyStorePolicies, jest.fn()],
      ]),
    });
    await waitForPromises();
  };

  beforeEach(() => {
    policyHandler = jest.fn().mockResolvedValue(notFoundResponse);
  });

  // Not found is not a fault, so the query sets no flag and reports nothing.
  it('leaves the policy null without an error or a report when the policy is not found', async () => {
    await createComponent();

    expect(policyHandler).toHaveBeenCalledWith({
      id: 'gid://gitlab/Organizations::Organization/1',
      ids: [7],
    });
    expect(findPolicy()).toBe('null');
    expect(findPolicyError()).toBe('false');
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('sets policyError and reports the error when the request fails', async () => {
    const error = new Error('API is down');
    policyHandler.mockRejectedValue(error);

    await createComponent();

    expect(findPolicyError()).toBe('true');
    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });

  // A project is read-only, so no detail page mounts on one; reaching here is a
  // wiring bug to surface rather than a path to send as an organization's id.
  it('refuses to build variables for a project', () => {
    const buildVariables = () =>
      singlePolicyQuery.variables.call({
        namespaceType: 'project',
        namespacePath: 'my-org/my-group/my-project',
        policyId: '7',
      });

    expect(buildVariables).toThrow('Policy store has no project detail page');
  });

  // The ids argument is a 32-bit Int, so a larger id would fail the request.
  // Skipping it leaves the policy null, which the host reads as not found.
  it('skips the request and leaves the host state alone for an id that is not a valid Int', async () => {
    await createComponent({ policyId: '99999999999' });

    expect(policyHandler).not.toHaveBeenCalled();
    expect(findPolicy()).toBe('null');
    expect(findPolicyError()).toBe('false');
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('skips the request without an error when there is no id to resolve', async () => {
    await createComponent({ policyId: '' });

    expect(policyHandler).not.toHaveBeenCalled();
    expect(findPolicyError()).toBe('false');
  });
});
