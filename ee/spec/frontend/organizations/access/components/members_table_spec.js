import {
  GlAvatarLabeled,
  GlAvatarLink,
  GlEmptyState,
  GlLoadingIcon,
  GlTableLite,
} from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import MembersTable from 'ee/organizations/access/components/members_table.vue';
import CreatedAt from '~/members/components/table/created_at.vue';

const resource = {
  key: 'artifact-registry',
  label: 'Artifact Registry',
  noMembersDescription: 'Assign an Artifact role to a user to give them access to this resource.',
  roles: [
    { value: 'ARTIFACT_ADMIN', text: 'Artifact Admin' },
    { value: 'ARTIFACT_VIEWER', text: 'Artifact Viewer' },
  ],
};

const members = [
  {
    assignee: {
      id: 'gid://gitlab/User/1',
      name: 'Alex Garcia',
      username: 'agarcia',
      avatarUrl: 'https://example.com/avatar.png',
      webPath: '/agarcia',
    },
    role: 'ARTIFACT_ADMIN',
    createdAt: '2026-08-14T10:00:00Z',
  },
  {
    assignee: {
      id: 'gid://gitlab/User/2',
      name: 'Jordan Kim',
      username: 'jkim',
      avatarUrl: null,
      webPath: '/jkim',
    },
    role: 'ARTIFACT_VIEWER',
    createdAt: '2026-09-28T16:45:00Z',
  },
];

describe('OrganizationAccessMembersTable', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(MembersTable, {
      propsData: { resource, members, ...props },
    });
  };

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findRows = () => wrapper.findAll('tbody tr');
  const findHeaders = () => wrapper.findAll('thead th').wrappers.map((th) => th.text());

  describe('with members', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the Member, Role, and Access granted columns only', () => {
      expect(findHeaders()).toEqual(['Member', 'Role', 'Access granted']);
    });

    it('renders a row per member', () => {
      expect(findRows()).toHaveLength(2);
    });

    it('renders the member avatar, name, and username linked to the user', () => {
      const row = findRows().at(0);

      expect(row.findComponent(GlAvatarLink).attributes('href')).toBe('/agarcia');
      expect(row.findComponent(GlAvatarLabeled).props()).toMatchObject({
        size: 32,
        src: 'https://example.com/avatar.png',
        label: 'Alex Garcia',
        subLabel: '@agarcia',
      });
    });

    it('renders the role label from the resource config', () => {
      expect(wrapper.findAllByTestId('member-role').wrappers.map((cell) => cell.text())).toEqual([
        'Artifact Admin',
        'Artifact Viewer',
      ]);
    });

    it('renders the granted date', () => {
      const createdAt = findRows().at(0).findComponent(CreatedAt);

      expect(createdAt.props('date')).toBe('2026-08-14T10:00:00Z');
      expect(createdAt.text()).toBe('Aug 14, 2026');
    });
  });

  it('renders a loading icon instead of the table when loading', () => {
    createComponent({ props: { loading: true } });

    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findTable().exists()).toBe(false);
  });

  it.each`
    description                                  | hasActiveFilters | illustrationName     | title                        | text
    ${'there are no members'}                    | ${false}         | ${'empty-user-md'}   | ${'Grant access to members'} | ${'Assign an Artifact role to a user to give them access to this resource.'}
    ${'filters are active and no members match'} | ${true}          | ${'empty-search-md'} | ${'No results found'}        | ${'Edit your search and try again.'}
  `(
    'renders the empty state when $description',
    ({ hasActiveFilters, illustrationName, title, text }) => {
      createComponent({ props: { members: [], hasActiveFilters } });

      expect(wrapper.findComponent(GlEmptyState).props()).toMatchObject({
        illustrationName,
        title,
        description: text,
      });
      expect(findTable().exists()).toBe(false);
    },
  );
});
