import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ResourcesTable from 'ee/organizations/access/components/resources_table.vue';
import { createAlert } from '~/alert';

Vue.use(VueApollo);

jest.mock('~/alert');

jest.mock('ee/organizations/access/constants', () => {
  const actual = jest.requireActual('ee/organizations/access/constants');
  const registry = actual.RESOURCES[actual.RESOURCE_ARTIFACT_REGISTRY];

  return {
    ...actual,
    RESOURCES: {
      [actual.RESOURCE_ARTIFACT_REGISTRY]: registry,
      unlinked: {
        ...registry,
        key: 'unlinked',
        label: 'Unlinked resource',
        icon: 'deployments',
        membersPath: undefined,
      },
    },
  };
});

const owner = (id) => ({
  __typename: 'UserCore',
  id: `gid://gitlab/User/${id}`,
  name: `Owner ${id}`,
  username: `owner${id}`,
  webPath: `/owner${id}`,
});

const roleCount = (role, count) => ({ __typename: 'ArtifactRegistryRoleCount', role, count });

const countsResolver = (total, byRole) => () => ({
  __typename: 'ArtifactRegistryRoleAssignmentCounts',
  total,
  byRole,
});

const assignmentsResolver = (owners) =>
  jest.fn((_, { first }) => ({
    __typename: 'ArtifactRegistryRoleAssignmentConnection',
    nodes: owners.slice(0, first).map((assignee) => ({
      __typename: 'ArtifactRegistryRoleAssignment',
      resourceId: '',
      role: 'ARTIFACT_MANAGER',
      assignee,
    })),
  }));

const defaultCounts = countsResolver(240, [
  roleCount('ARTIFACT_ADMIN', 3),
  roleCount('ARTIFACT_MANAGER', 16),
  roleCount('ARTIFACT_CONTRIBUTOR', 120),
  roleCount('ARTIFACT_VIEWER', 101),
]);

describe('OrganizationAccessResourcesTable', () => {
  let wrapper;
  let assignments;

  const createComponent = ({
    counts = defaultCounts,
    owners = [1, 2, 3, 4].map(owner),
    assignmentsQuery = assignmentsResolver(owners),
  } = {}) => {
    assignments = assignmentsQuery;

    wrapper = mountExtended(ResourcesTable, {
      apolloProvider: createMockApollo([], {
        Query: {
          artifactRegistryRoleAssignmentCounts: counts,
          artifactRegistryRoleAssignments: assignments,
        },
      }),
      propsData: { organizationPath: 'my-org' },
    });
  };

  const findRows = () => wrapper.findAll('tbody tr');
  const findInRow = (index, testId) => findRows().at(index).find(`[data-testid="${testId}"]`);
  const findOwnerLinks = () => findRows().at(0).findAll('[data-testid="owner"] a').wrappers;

  it('shows a loading icon while the summary loads', () => {
    createComponent();

    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
  });

  describe('when the summary has loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('asks for up to 3 holders of the owner role', () => {
      expect(assignments).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ roles: ['ARTIFACT_MANAGER'], first: 3 }),
        expect.anything(),
        expect.anything(),
      );
    });

    it('renders one row per resource', () => {
      expect(findRows()).toHaveLength(2);
    });

    it('renders the resource icon and label', () => {
      const cell = findInRow(0, 'resource-cell');

      expect(cell.findComponent(GlIcon).props('name')).toBe('infrastructure-registry');
      expect(cell.text()).toBe('Artifact Registry');
    });

    it('links the member count to the members page', () => {
      const link = findInRow(0, 'members-link');

      expect(link.text()).toBe('240 members');
      expect(link.attributes('href')).toBe('/o/my-org/-/access/artifact-registry');
    });

    it('renders the role breakdown joined by middle dots', () => {
      expect(findInRow(0, 'role-breakdown').text()).toBe(
        '3 Admins · 16 Managers · 120 Contributors · 101 Viewers',
      );
    });

    it('renders at most 3 owners as links to their profiles', () => {
      const links = findOwnerLinks();

      expect(links.map((link) => link.text())).toEqual(['Owner 1', 'Owner 2', 'Owner 3']);
      expect(links.map((link) => link.attributes('href'))).toEqual([
        '/owner1',
        '/owner2',
        '/owner3',
      ]);
      expect(findInRow(0, 'owners').text()).toBe('Owner 1, Owner 2, Owner 3');
    });

    it('renders a resource with no summary as 0 members, plain text, and no owners', () => {
      expect(findInRow(1, 'members-link').exists()).toBe(false);
      expect(findInRow(1, 'members-text').text()).toBe('0 members');
      expect(findInRow(1, 'role-breakdown').text()).toBe(
        '0 Admins · 0 Managers · 0 Contributors · 0 Viewers',
      );
      expect(findInRow(1, 'owners').text()).toBe('');
    });
  });

  it('renders 0 for a role missing from the counts', async () => {
    createComponent({
      counts: countsResolver(1, [roleCount('ARTIFACT_ADMIN', 1)]),
      owners: [owner(5)],
    });
    await waitForPromises();

    expect(findInRow(0, 'members-link').text()).toBe('1 member');
    expect(findInRow(0, 'role-breakdown').text()).toBe(
      '1 Admin · 0 Managers · 0 Contributors · 0 Viewers',
    );
    expect(findInRow(0, 'owners').text()).toBe('Owner 5');
  });

  it('renders no owners when the assignments connection is null', async () => {
    createComponent({ assignmentsQuery: () => null });
    await waitForPromises();

    expect(findInRow(0, 'members-link').text()).toBe('240 members');
    expect(findInRow(0, 'owners').text()).toBe('');
  });

  it('skips owners with a null assignee', async () => {
    createComponent({ owners: [owner(1), null, owner(3)] });
    await waitForPromises();

    expect(findInRow(0, 'owners').text()).toBe('Owner 1, Owner 3');
  });

  it.each`
    description      | nodes
    ${'a null node'} | ${[null]}
    ${'null nodes'}  | ${null}
  `('renders no owners for $description', async ({ nodes }) => {
    createComponent({
      assignmentsQuery: () => ({ __typename: 'ArtifactRegistryRoleAssignmentConnection', nodes }),
    });
    await waitForPromises();

    expect(findInRow(0, 'members-link').text()).toBe('240 members');
    expect(findInRow(0, 'owners').text()).toBe('');
  });

  it('formats large counts', async () => {
    createComponent({ counts: countsResolver(1200, [roleCount('ARTIFACT_VIEWER', 1200)]) });
    await waitForPromises();

    expect(findInRow(0, 'members-link').text()).toBe('1,200 members');
    expect(findInRow(0, 'role-breakdown').text()).toContain('1,200 Viewers');
  });

  describe('when the summary fails to load', () => {
    const error = new Error('GraphQL error');

    beforeEach(async () => {
      createComponent({ counts: jest.fn().mockRejectedValue(error) });
      await waitForPromises();
    });

    it('shows an alert and captures the error', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred loading resource access. Please refresh the page to try again.',
        error: expect.any(Error),
        captureError: true,
      });
    });

    it('does not render the table with zero counts', () => {
      expect(findRows()).toHaveLength(0);
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(false);
    });
  });
});
