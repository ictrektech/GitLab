import { GlButton, GlFilteredSearch } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { useFakeDate } from 'helpers/fake_date';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import InviteMembersModal from 'ee/organizations/access/components/invite_members_modal.vue';
import OrganizationAccessResourceApp from 'ee/organizations/access/components/resource_access_app.vue';
import MemberStats from 'ee/organizations/access/components/member_stats.vue';
import MembersTable from 'ee/organizations/access/components/members_table.vue';
import { createMockResolvers } from 'ee/organizations/access/graphql/mock_resolvers';
import { createAlert } from '~/alert';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import showGlobalToast from '~/vue_shared/plugins/global_toast';

jest.mock('~/alert');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

const assignment = ([id, name, username], role) => ({
  __typename: 'ArtifactRegistryRoleAssignment',
  resourceId: '',
  role,
  createdAt: '2026-09-01T00:00:00Z',
  assignee: {
    __typename: 'UserCore',
    id: `gid://gitlab/User/${id}`,
    name,
    username,
    webPath: '#',
    avatarUrl: null,
  },
});

const ASSIGNMENTS = [
  assignment([1, 'Alex Garcia', 'agarcia'], 'ARTIFACT_ADMIN'),
  assignment([2, 'Priya Shah', 'pshah'], 'ARTIFACT_MANAGER'),
  assignment([3, 'Morgan Lee', 'mlee'], 'ARTIFACT_ADMIN'),
  assignment([4, 'Sam Rivera', 'srivera'], 'ARTIFACT_CONTRIBUTOR'),
  assignment([5, 'Jordan Kim', 'jkim'], 'ARTIFACT_VIEWER'),
];
const ALL = ['agarcia', 'pshah', 'mlee', 'srivera', 'jkim'];

describe('OrganizationAccessResourceApp', () => {
  let wrapper;

  const createComponent = ({ resolvers = createMockResolvers(ASSIGNMENTS) } = {}) => {
    wrapper = shallowMountExtended(OrganizationAccessResourceApp, {
      apolloProvider: createMockApollo([], resolvers),
      propsData: { resourceKey: 'artifact-registry' },
      directives: { GlModal: createMockDirective('gl-modal') },
      stubs: { PageHeading },
    });
  };

  const findMemberStats = () => wrapper.findComponent(MemberStats);
  const findFilteredSearch = () => wrapper.findComponent(GlFilteredSearch);
  const findMembersTable = () => wrapper.findComponent(MembersTable);
  const findInviteButton = () => wrapper.findComponent(GlButton);
  const findInviteModal = () => wrapper.findComponent(InviteMembersModal);
  const findMembers = () =>
    findMembersTable()
      .props('members')
      .map(({ assignee, role, createdAt }) => [assignee.username, role, createdAt]);
  const findUsernames = () =>
    findMembersTable()
      .props('members')
      .map(({ assignee }) => assignee.username);
  const findToken = (type) =>
    findFilteredSearch()
      .props('availableTokens')
      .find((token) => token.type === type);

  const submit = async (terms) => {
    findFilteredSearch().vm.$emit('submit', terms);
    await nextTick();
  };
  const roleToken = (data) => ({ type: 'role', value: { data, operator: '=' } });

  it('passes the loading state to the table while members load', () => {
    createComponent();

    expect(findMembersTable().props('loading')).toBe(true);
    expect(findMemberStats().props('loading')).toBe(true);
  });

  it('passes no members to the table when the assignments connection is null', async () => {
    const resolvers = createMockResolvers(ASSIGNMENTS);
    resolvers.Query.artifactRegistryRoleAssignments = () => null;
    createComponent({ resolvers });
    await waitForPromises();

    expect(findMembersTable().props('members')).toEqual([]);
    expect(findMemberStats().props('stats')[2].value).toBe(5);
  });

  describe('when an assignment has a null assignee', () => {
    beforeEach(async () => {
      createComponent({
        resolvers: createMockResolvers([
          ...ASSIGNMENTS,
          { ...assignment([6, 'Gone User', 'gone'], 'ARTIFACT_VIEWER'), assignee: null },
        ]),
      });
      await waitForPromises();
    });

    it('leaves the assignment out of the table', () => {
      expect(findUsernames()).toEqual(ALL);
    });

    it('still filters by name or username', async () => {
      await submit(['alex']);

      expect(findUsernames()).toEqual(['agarcia']);
    });
  });

  describe('when members have loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the resource label as the heading without a description', () => {
      expect(wrapper.findByTestId('page-heading').text()).toBe('Artifact Registry');
      expect(wrapper.findByTestId('page-heading-description').exists()).toBe(false);
    });

    it('passes the admin, owner, and total counts to the stats', () => {
      expect(findMemberStats().props('stats')).toEqual([
        {
          title: 'Artifact Admins',
          value: 2,
          filter: roleToken('ARTIFACT_ADMIN'),
          filterLabel: 'Filter list for Artifact Admins',
        },
        {
          title: 'Artifact Managers',
          value: 1,
          filter: roleToken('ARTIFACT_MANAGER'),
          filterLabel: 'Filter list for Artifact Managers',
        },
        { title: 'Total members', value: 5 },
      ]);
    });

    it('renders the search with a placeholder', () => {
      expect(findFilteredSearch().props()).toMatchObject({
        placeholder: 'Search by name or username',
        termsAsTokens: true,
      });
    });

    it('offers only a unique Role token with the resource roles', () => {
      expect(findFilteredSearch().props('availableTokens')).toHaveLength(1);
      expect(findToken('role')).toMatchObject({
        title: 'Role',
        unique: true,
        operators: [{ value: '=', description: 'is' }],
        options: [
          { value: 'ARTIFACT_ADMIN', title: 'Artifact Admin' },
          { value: 'ARTIFACT_MANAGER', title: 'Artifact Manager' },
          { value: 'ARTIFACT_CONTRIBUTOR', title: 'Artifact Contributor' },
          { value: 'ARTIFACT_VIEWER', title: 'Artifact Viewer' },
        ],
      });
    });

    it('passes all members, the resource, and no loading state to the table', () => {
      expect(findMembersTable().props('resource').label).toBe('Artifact Registry');
      expect(findMembersTable().props('loading')).toBe(false);
      expect(findMemberStats().props('loading')).toBe(false);
      expect(findUsernames()).toEqual(ALL);
    });

    describe('hasActiveFilters', () => {
      it('is false with no filters', () => {
        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });

      it.each`
        description       | terms
        ${'search text'}  | ${['nobody']}
        ${'a role token'} | ${[roleToken('ARTIFACT_VIEWER')]}
      `('is true with $description', async ({ terms }) => {
        await submit(terms);

        expect(findMembersTable().props('hasActiveFilters')).toBe(true);
      });

      it('is false after the search is cleared', async () => {
        await submit(['nobody']);
        findFilteredSearch().vm.$emit('clear');
        await nextTick();

        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });
    });

    describe('search', () => {
      it.each`
        term          | expected
        ${'priya'}    | ${['pshah']}
        ${'SRIVERA'}  | ${['srivera']}
        ${'  lee '}   | ${['mlee']}
        ${'@agarcia'} | ${['agarcia']}
        ${'nobody'}   | ${[]}
      `('filters by name or username for "$term"', async ({ term, expected }) => {
        await submit([term]);

        expect(findUsernames()).toEqual(expected);
      });

      it('filters by role', async () => {
        await submit([roleToken('ARTIFACT_ADMIN')]);

        expect(findUsernames()).toEqual(['agarcia', 'mlee']);
      });

      it('combines text and role filters', async () => {
        await submit(['alex', roleToken('ARTIFACT_ADMIN')]);

        expect(findUsernames()).toEqual(['agarcia']);
      });

      it('resets the list when cleared', async () => {
        findMemberStats().vm.$emit('filter', roleToken('ARTIFACT_ADMIN'));
        await nextTick();
        findFilteredSearch().vm.$emit('clear');
        await nextTick();

        expect(findUsernames()).toEqual(ALL);
        expect(findFilteredSearch().props('value')).toEqual([]);
      });
    });

    describe('when the role token is removed', () => {
      it('clears the role filter', async () => {
        findMemberStats().vm.$emit('filter', roleToken('ARTIFACT_ADMIN'));
        await nextTick();
        findFilteredSearch().vm.$emit('token-destroy', roleToken('ARTIFACT_ADMIN'));
        await nextTick();

        expect(findUsernames()).toEqual(ALL);
        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });
    });

    describe('when a stat card filters the list', () => {
      it.each`
        title                  | token                            | expected
        ${'Artifact Admins'}   | ${roleToken('ARTIFACT_ADMIN')}   | ${['agarcia', 'mlee']}
        ${'Artifact Managers'} | ${roleToken('ARTIFACT_MANAGER')} | ${['pshah']}
      `('sets the token and filters for $title', async ({ token, expected }) => {
        findMemberStats().vm.$emit('filter', token);
        await nextTick();

        expect(findFilteredSearch().props('value')).toEqual([token]);
        expect(findUsernames()).toEqual(expected);
      });
    });
  });

  describe('inviting members', () => {
    useFakeDate(2026, 9, 23, 12);

    const NOW = '2026-10-23T12:00:00.000Z';
    const invite = async (users, role) => {
      findInviteModal().vm.$emit('invite', { users, role });
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('opens the invite modal from the Invite members button', () => {
      expect(findInviteButton().text()).toBe('Invite members');
      expect(findInviteButton().props('variant')).toBe('confirm');
      expect(getBinding(findInviteButton().element, 'gl-modal').value).toBe(
        'organization-access-invite-members-modal',
      );
      expect(findInviteModal().props('resource').label).toBe('Artifact Registry');
    });

    describe('when new users are invited', () => {
      beforeEach(async () => {
        await invite(
          [
            { id: 7, name: 'Casey Wu', username: 'cwu', avatar_url: '/avatar.png' },
            { id: 8, name: 'Drew Park', username: 'dpark', avatar_url: null },
          ],
          'ARTIFACT_ADMIN',
        );
      });

      it('adds them to the top of the table with the chosen role', () => {
        expect(findMembers()).toEqual([
          ['cwu', 'ARTIFACT_ADMIN', NOW],
          ['dpark', 'ARTIFACT_ADMIN', NOW],
          ['agarcia', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['pshah', 'ARTIFACT_MANAGER', '2026-09-01T00:00:00Z'],
          ['mlee', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['srivera', 'ARTIFACT_CONTRIBUTOR', '2026-09-01T00:00:00Z'],
          ['jkim', 'ARTIFACT_VIEWER', '2026-09-01T00:00:00Z'],
        ]);
        expect(findMembersTable().props('members')[0].assignee).toEqual({
          __typename: 'UserCore',
          id: 'gid://gitlab/User/7',
          name: 'Casey Wu',
          username: 'cwu',
          webPath: '#',
          avatarUrl: '/avatar.png',
        });
      });

      it('updates the stats', () => {
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([4, 1, 7]);
      });

      it('shows a toast', () => {
        expect(showGlobalToast).toHaveBeenCalledWith('Members were successfully added.');
      });
    });

    describe('when one user is invited', () => {
      it('shows a singular toast', async () => {
        await invite([{ id: 7, name: 'Casey Wu', username: 'cwu' }], 'ARTIFACT_VIEWER');

        expect(showGlobalToast).toHaveBeenCalledWith('Member was successfully added.');
      });
    });

    describe('when an invited user already has a role', () => {
      beforeEach(async () => {
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_MANAGER');
      });

      it('replaces their row', () => {
        expect(findMembers()).toEqual([
          ['jkim', 'ARTIFACT_MANAGER', NOW],
          ['agarcia', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['pshah', 'ARTIFACT_MANAGER', '2026-09-01T00:00:00Z'],
          ['mlee', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['srivera', 'ARTIFACT_CONTRIBUTOR', '2026-09-01T00:00:00Z'],
        ]);
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([2, 2, 5]);
      });
    });

    describe('when an invited user moves out of a counted role', () => {
      beforeEach(async () => {
        await invite([{ id: 1, name: 'Alex Garcia', username: 'agarcia' }], 'ARTIFACT_VIEWER');
      });

      it('lowers the count of their old role', () => {
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([1, 1, 5]);
      });
    });

    describe('when an invited user is invited again', () => {
      beforeEach(async () => {
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_MANAGER');
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_ADMIN');
      });

      it('keeps one row with the latest role', () => {
        expect(findMembers().filter(([username]) => username === 'jkim')).toEqual([
          ['jkim', 'ARTIFACT_ADMIN', NOW],
        ]);
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([3, 1, 5]);
      });
    });
  });

  describe('when members fail to load', () => {
    beforeEach(async () => {
      const resolvers = createMockResolvers(ASSIGNMENTS);
      resolvers.Query.artifactRegistryRoleAssignments = jest
        .fn()
        .mockRejectedValue(new Error('GraphQL error'));
      createComponent({ resolvers });
      await waitForPromises();
    });

    it('shows an alert and captures the error', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred loading members. Please refresh the page to try again.',
        error: expect.any(Error),
        captureError: true,
      });
    });

    it('does not render the invite button, stats, search, table, or modal', () => {
      expect(findInviteButton().exists()).toBe(false);
      expect(findInviteModal().exists()).toBe(false);
      expect(findMemberStats().exists()).toBe(false);
      expect(findFilteredSearch().exists()).toBe(false);
      expect(findMembersTable().exists()).toBe(false);
    });
  });
});
