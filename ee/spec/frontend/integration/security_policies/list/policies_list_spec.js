import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import { getText, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import projectSecurityPolicies from '../fixture_variants/project_security_policies';
import groupSecurityPolicies from '../fixture_variants/group_security_policies';
import {
  NAMESPACE_PATHS,
  expectListToShow,
  findAlert,
  findEmptyFilterState,
  findEmptyListState,
  findPolicyRows,
  mountPoliciesList,
} from '../test_setup';

describe.each`
  namespaceType              | operation                    | variants
  ${NAMESPACE_TYPES.PROJECT} | ${'projectSecurityPolicies'} | ${projectSecurityPolicies}
  ${NAMESPACE_TYPES.GROUP}   | ${'groupSecurityPolicies'}   | ${groupSecurityPolicies}
`('Security policies list for a $namespaceType', ({ namespaceType, operation, variants }) => {
  it('lists every policy the namespace returns for the inherited relationship', async () => {
    mountPoliciesList({ namespaceType });

    await expectListToShow([
      'Run DAST in every pipeline',
      'Disabled DAST policy',
      'critical vulnerability CS approvals Malware blocking is available but turned off. This merge request approval policy can block known malware — enable it when editing the policy.',
    ]);

    expect(lastRequestVariables(operation)).toMatchObject({
      fullPath: NAMESPACE_PATHS[namespaceType],
      relationship: 'INHERITED',
      includeAttributeScopes: true,
    });
  });

  it('renders the type and status of each policy', async () => {
    mountPoliciesList({ namespaceType });

    await expectListToShow([
      'Run DAST in every pipeline',
      'Disabled DAST policy',
      'critical vulnerability CS approvals Malware blocking is available but turned off. This merge request approval policy can block known malware — enable it when editing the policy.',
    ]);

    const cellText = (testId) =>
      findPolicyRows().map((row) => getText(row.querySelector(`[data-testid="${testId}"]`)));

    expect(cellText('policy-type-cell')).toEqual([
      'Scan execution',
      'Scan execution',
      'Merge request approval',
    ]);
    expect(cellText('policy-status-cell')).toEqual(['Enabled', 'Not enabled', 'Enabled']);
  });

  describe('when the namespace has no policies', () => {
    beforeEach(() => {
      setQueryVariant(variants).empty();
    });

    it('replaces the list with the empty state', async () => {
      mountPoliciesList({ namespaceType });

      await waitForElement(findEmptyListState);

      expect(findPolicyRows()).toHaveLength(0);
      expect(getText(findEmptyListState())).toContain('No policies found');
      // This copy is the has-a-policy-project branch; without the `id` in the dataset the
      // description would instead read "is not linked to a security policy project".
      expect(getText(findEmptyListState())).toContain(
        `This ${namespaceType} does not contain any security policies.`,
      );
    });
  });

  // The fixture holds no vulnerability management policy, so the client-side type
  // filter is what empties the list here, not the response.
  describe('when a type filter matches no policies', () => {
    it('offers the filtered-out empty state instead', async () => {
      mountPoliciesList({ namespaceType, queryString: '?type=vulnerability_management' });

      await waitForElement(findEmptyFilterState);

      expect(findPolicyRows()).toHaveLength(0);
      expect(getText(findEmptyFilterState())).toContain('Sorry, your filter produced no results.');
      expect(lastRequestVariables(operation)).toMatchObject({
        type: 'VULNERABILITY_MANAGEMENT_POLICY',
      });
    });
  });

  describe('when the policies query fails', () => {
    beforeEach(() => {
      setQueryVariant(variants).error();
    });

    it('surfaces the failure in an alert', async () => {
      mountPoliciesList({ namespaceType });

      await waitForElement(findAlert);

      expect(getText(findAlert())).toContain('The policy configuration could not be read');
    });
  });
});
