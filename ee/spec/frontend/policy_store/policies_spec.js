import { print } from 'graphql';
import {
  toListPolicies,
  toPolicy,
  policyStoreId,
  policyMutationVariables,
  containerQueryVariables,
  policyStoreFrom,
} from 'ee/policy_store/policies';
import {
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
  NAMESPACE_TYPE_PROJECT,
} from 'ee/policy_store/constants';
import governPolicyCreateMutation from 'ee/policy_store/graphql/govern_policy_create.mutation.graphql';
import governPolicyUpdateMutation from 'ee/policy_store/graphql/govern_policy_update.mutation.graphql';
import governPolicyDeleteMutation from 'ee/policy_store/graphql/govern_policy_delete.mutation.graphql';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';

import { mockGraphqlPolicy, mockMappedPolicy, mockPolicyGroup, mockPolicyStore } from './mock_data';

describe('policy store policies', () => {
  const triggers = [
    { id: 'deployment_requested', name: 'Deployment requested' },
    { id: 'merge_requested', name: 'Merge Request' },
  ];

  const store = (policies, remoteTriggers = triggers) => mockPolicyStore(policies, remoteTriggers);

  describe('toListPolicies', () => {
    it('maps each node to the row the list renders, snake_cased where the row details read it', () => {
      expect(toListPolicies(store([mockGraphqlPolicy()]))).toEqual([
        {
          id: 7,
          name: 'Production gate',
          mode: 'enforce',
          inherited: false,
          group: null,
          source: 'Organization',
          trigger_type: 'deployment_requested',
          rules: [{ type: 'custom', value: 'package governance' }],
          actions: [{ type: 'block' }],
          updated_at: '2026-08-20T09:12:44.120Z',
          type: 'Deployment requested',
          status: 'active',
          scopedProjectsCount: 3,
        },
      ]);
    });

    it('sorts the source column on the owner, not on the rendered label', () => {
      const owned = mockGraphqlPolicy({ group: mockPolicyGroup });
      const inherited = mockGraphqlPolicy({ group: mockPolicyGroup, inherited: true });

      expect(toListPolicies(store([owned]))[0].source).toBe('Flight');
      expect(toListPolicies(store([inherited]))[0].source).toBe('Flight');
      expect(toListPolicies(store([mockGraphqlPolicy()]))[0].source).toBe('Organization');
    });

    it("labels the trigger from the store's catalog, falling back to the id", () => {
      const policy = mockGraphqlPolicy({ triggerType: 'merge_requested' });

      expect(toListPolicies(store([policy]))[0].type).toBe('Merge Request');
      expect(toListPolicies(store([policy], []))[0].type).toBe('merge_requested');
      expect(toListPolicies(store([policy], null))[0].type).toBe('merge_requested');
      expect(toListPolicies(store([policy], [{ id: null, name: 'broken' }]))[0].type).toBe(
        'merge_requested',
      );
    });

    it('counts scoped projects whether the criterion holds ids or { id } hashes', () => {
      const rows = toListPolicies(
        store([
          mockGraphqlPolicy({ id: 1, policyScope: { projects: { including: [{ id: 9 }] } } }),
          mockGraphqlPolicy({ id: 2, policyScope: null }),
        ]),
      );

      expect(rows.map((row) => row.scopedProjectsCount)).toEqual([1, 0]);
    });

    it.each`
      description                        | policyStore
      ${'the container has no policies'} | ${store([])}
      ${'the policies are unreadable'}   | ${store(null)}
      ${'the policy store is inactive'}  | ${null}
    `('returns no rows when $description', ({ policyStore }) => {
      expect(toListPolicies(policyStore)).toEqual([]);
    });
  });

  describe('toPolicy', () => {
    it('maps the first node like the list, snake_cased for the editor to read back', () => {
      expect(toPolicy(store([mockGraphqlPolicy()]))).toEqual(mockMappedPolicy);
    });

    it('snake_cases the compiled Rego fields the detail page reads', () => {
      const policy = toPolicy(
        store([
          mockGraphqlPolicy({
            policyRego: 'package governance\n',
            scopeRego: 'package gitlab.scope\n',
          }),
        ]),
      );

      expect(policy).toMatchObject({
        policy_rego: 'package governance\n',
        scope_rego: 'package gitlab.scope\n',
      });
      expect(policy).not.toHaveProperty('policyRego');
      expect(policy).not.toHaveProperty('scopeRego');
    });

    it('keeps the stored shape of the free-form JSON fields', () => {
      const policy = toPolicy(
        store([mockGraphqlPolicy({ policyScope: { projects: { including: [{ id: 9 }] } } })]),
      );

      expect(policy.policy_scope).toEqual({ projects: { including: [{ id: 9 }] } });
      expect(policy.scopedProjectsCount).toBe(1);
    });

    it("labels the trigger from the same document's catalog, falling back to the id", () => {
      const policy = mockGraphqlPolicy({ triggerType: 'merge_requested' });

      expect(toPolicy(store([policy])).type).toBe('Merge Request');
      expect(toPolicy(store([policy], [])).type).toBe('merge_requested');
      expect(toPolicy(store([policy], null)).type).toBe('merge_requested');
      expect(toPolicy(store([policy], [{ id: null, name: 'broken' }])).type).toBe(
        'merge_requested',
      );
    });

    it.each`
      description                       | policyStore
      ${'the container lacks the id'}   | ${store([])}
      ${'the policies are unreadable'}  | ${store(null)}
      ${'the policy store is inactive'} | ${null}
    `('returns null when $description', ({ policyStore }) => {
      expect(toPolicy(policyStore)).toBeNull();
    });
  });

  describe('containerQueryVariables', () => {
    it('names an organization by its global id', () => {
      expect(containerQueryVariables(NAMESPACE_TYPE_ORGANIZATION, 1)).toEqual({
        id: 'gid://gitlab/Organizations::Organization/1',
      });
    });

    it('names a group by its full path', () => {
      expect(containerQueryVariables(NAMESPACE_TYPE_GROUP, 'my-org/my-group')).toEqual({
        fullPath: 'my-org/my-group',
      });
    });

    it('names a project by its full path', () => {
      expect(containerQueryVariables(NAMESPACE_TYPE_PROJECT, 'my-org/my-group/my-project')).toEqual(
        {
          fullPath: 'my-org/my-group/my-project',
        },
      );
    });

    // The query documents do not require their container variable, so a blank
    // one would reach the server as an empty path or no container.
    it.each`
      namespaceType                  | namespaceIdentifier
      ${NAMESPACE_TYPE_ORGANIZATION} | ${undefined}
      ${NAMESPACE_TYPE_ORGANIZATION} | ${0}
      ${NAMESPACE_TYPE_GROUP}        | ${''}
      ${NAMESPACE_TYPE_PROJECT}      | ${''}
    `(
      'rejects the blank $namespaceType identifier $namespaceIdentifier',
      ({ namespaceType, namespaceIdentifier }) => {
        expect(() => containerQueryVariables(namespaceType, namespaceIdentifier)).toThrow(
          'Policy store container identifier is blank',
        );
      },
    );
  });

  describe('policyStoreFrom', () => {
    const policyStore = { triggers: [] };

    it('reads the organization root field for an organization', () => {
      expect(
        policyStoreFrom(
          { organization: { policyStore }, group: null },
          NAMESPACE_TYPE_ORGANIZATION,
        ),
      ).toBe(policyStore);
    });

    it('reads the group root field for a group', () => {
      expect(
        policyStoreFrom({ group: { policyStore }, organization: null }, NAMESPACE_TYPE_GROUP),
      ).toBe(policyStore);
    });

    it('reads the project root field for a project', () => {
      expect(
        policyStoreFrom({ project: { policyStore }, group: null }, NAMESPACE_TYPE_PROJECT),
      ).toBe(policyStore);
    });

    it('passes a denied read through as null', () => {
      expect(policyStoreFrom({ group: { policyStore: null } }, NAMESPACE_TYPE_GROUP)).toBe(null);
    });

    it('reads missing data as undefined', () => {
      expect(policyStoreFrom(undefined, NAMESPACE_TYPE_GROUP)).toBe(undefined);
    });
  });

  describe('policyMutationVariables', () => {
    const params = { name: 'Prod gate', lifecycle_state: 'disabled' };

    it('maps the params and adds the organization id for an organization', () => {
      expect(
        policyMutationVariables({
          document: governPolicyUpdateMutation,
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          params,
        }),
      ).toEqual({
        organizationId: 'gid://gitlab/Organizations::Organization/1',
        name: 'Prod gate',
        lifecycleState: 'disabled',
      });
    });

    it('maps the params and adds the group path for a group', () => {
      expect(
        policyMutationVariables({
          document: governPolicyUpdateMutation,
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          params,
        }),
      ).toEqual({ groupPath: 'my-org/my-group', name: 'Prod gate', lifecycleState: 'disabled' });
    });

    it('sends the policy id under the name the document declares', () => {
      const scope = { namespaceType: NAMESPACE_TYPE_ORGANIZATION, namespaceIdentifier: 1 };

      expect(
        policyMutationVariables({ ...scope, document: governPolicyUpdateMutation, policyId: '7' }),
      ).toEqual({ organizationId: 'gid://gitlab/Organizations::Organization/1', policyId: 7 });
      expect(
        policyMutationVariables({ ...scope, document: governPolicyDeleteMutation, policyId: '7' }),
      ).toEqual({ organizationId: 'gid://gitlab/Organizations::Organization/1', id: 7 });
    });

    it('sends only the container argument when there are no params', () => {
      expect(
        policyMutationVariables({
          document: governPolicyDeleteMutation,
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
        }),
      ).toEqual({ groupPath: 'my-org/my-group' });
    });

    it.each`
      description     | policyId
      ${'null'}       | ${null}
      ${'undefined'}  | ${undefined}
      ${'a blank id'} | ${''}
    `('sends no id argument for $description', ({ policyId }) => {
      expect(
        policyMutationVariables({
          document: governPolicyDeleteMutation,
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          policyId,
        }),
      ).toEqual({ groupPath: 'my-org/my-group' });
    });

    it('throws for a project, which has no mutable container', () => {
      expect(() =>
        policyMutationVariables({
          document: governPolicyUpdateMutation,
          namespaceType: NAMESPACE_TYPE_PROJECT,
          namespaceIdentifier: 'my-org/my-group/my-project',
          policyId: '7',
        }),
      ).toThrow('Policy store mutations have no project container');
    });

    it('throws on a policy id that is not a valid Int instead of sending null', () => {
      expect(() =>
        policyMutationVariables({
          document: governPolicyUpdateMutation,
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 'abc',
        }),
      ).toThrow('Policy store id is not a valid Int');
    });

    // The create mutation declares neither id name, so the id would be dropped
    // as silently as any other undeclared variable.
    it('throws when the document declares no id argument', () => {
      expect(() =>
        policyMutationVariables({
          document: governPolicyCreateMutation,
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: '7',
        }),
      ).toThrow('Policy store mutation declares no id argument');
    });

    it.each`
      description                                    | document                      | badParams                          | message
      ${'a param the document does not declare'}     | ${governPolicyUpdateMutation} | ${{ policy_rego: 'package x' }}    | ${'Policy store param not declared by the mutation: policy_rego'}
      ${'a param only the update mutation declares'} | ${governPolicyCreateMutation} | ${{ lifecycle_state: 'disabled' }} | ${'Policy store param not declared by the mutation: lifecycle_state'}
      ${'a param naming the other container'}        | ${governPolicyUpdateMutation} | ${{ organizationId: 'gid://x/1' }} | ${'Policy store param is a container argument: organizationId'}
      ${'a param naming the same container'}         | ${governPolicyUpdateMutation} | ${{ groupPath: 'other/group' }}    | ${'Policy store param is a container argument: groupPath'}
      ${'a snake_case param naming a container'}     | ${governPolicyUpdateMutation} | ${{ organization_id: 1 }}          | ${'Policy store param is a container argument: organization_id'}
      ${'a snake_case param naming this container'}  | ${governPolicyUpdateMutation} | ${{ group_path: 'other/group' }}   | ${'Policy store param is a container argument: group_path'}
    `('throws on $description', ({ document, badParams, message }) => {
      expect(() =>
        policyMutationVariables({
          document,
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          params: badParams,
        }),
      ).toThrow(message);
    });

    // Neither document requires its container variable, so a blank identifier
    // would reach the server as no container and surface its raw error.
    it.each`
      description                  | namespaceType                  | namespaceIdentifier
      ${'an undefined group path'} | ${NAMESPACE_TYPE_GROUP}        | ${undefined}
      ${'an empty group path'}     | ${NAMESPACE_TYPE_GROUP}        | ${''}
      ${'a missing organization'}  | ${NAMESPACE_TYPE_ORGANIZATION} | ${undefined}
      ${'organization id 0'}       | ${NAMESPACE_TYPE_ORGANIZATION} | ${0}
    `(
      'throws before building variables for $description',
      ({ namespaceType, namespaceIdentifier }) => {
        expect(() =>
          policyMutationVariables({
            document: governPolicyDeleteMutation,
            namespaceType,
            namespaceIdentifier,
            policyId: '7',
          }),
        ).toThrow('Policy store container identifier is blank');
      },
    );
  });

  describe('policyStoreId', () => {
    it.each`
      value           | id
      ${'7'}          | ${7}
      ${7}            | ${7}
      ${'1'}          | ${1}
      ${'2147483647'} | ${2147483647}
    `('parses $value as the Int $id', ({ value, id }) => {
      expect(policyStoreId(value)).toBe(id);
    });

    // Only digits from 1 to the 32-bit Int ceiling: the forms Number() would
    // also accept could quietly name a different policy, or fail the [Int!]
    // argument, and 0 never names one.
    it.each`
      description               | value
      ${'zero'}                 | ${'0'}
      ${'a numeric zero'}       | ${0}
      ${'letters'}              | ${'abc'}
      ${'a decimal'}            | ${'7.5'}
      ${'a hex string'}         | ${'0x10'}
      ${'an exponent string'}   | ${'1e3'}
      ${'a negative number'}    | ${'-7'}
      ${'a signed number'}      | ${'+7'}
      ${'padded digits'}        | ${' 7 '}
      ${'a value above Int'}    | ${'2147483648'}
      ${'a bigint-sized value'} | ${'99999999999'}
      ${'an empty string'}      | ${''}
      ${'a blank string'}       | ${' '}
      ${'null'}                 | ${null}
      ${'undefined'}            | ${undefined}
      ${'NaN'}                  | ${NaN}
      ${'a boolean'}            | ${true}
      ${'an object'}            | ${{ id: 7 }}
    `('returns null for $description', ({ value }) => {
      expect(policyStoreId(value)).toBeNull();
    });

    // The ceiling is the 32-bit Int the documents declare for the id. When they
    // move to a wider type this fails, so MAX_POLICY_STORE_ID moves with them.
    it.each`
      document                       | variable      | type
      ${governPolicyUpdateMutation}  | ${'policyId'} | ${'Int!'}
      ${governPolicyDeleteMutation}  | ${'id'}       | ${'Int!'}
      ${getPolicyStorePolicies}      | ${'ids'}      | ${'[Int!]'}
      ${getGroupPolicyStorePolicies} | ${'ids'}      | ${'[Int!]'}
    `('matches the $type the document declares for $variable', ({ document, variable, type }) => {
      const declared = document.definitions
        .find((definition) => definition.kind === 'OperationDefinition')
        .variableDefinitions.find((definition) => definition.variable.name.value === variable);

      expect(print(declared.type)).toBe(type);
    });
  });
});
