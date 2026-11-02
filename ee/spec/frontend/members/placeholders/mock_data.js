export const mockEnterpriseUser1 = {
  username: 'Administrator',
  web_url: '/root',
  web_path: '/root',
  avatar_url: '/avatar1',
  id: 1,
  name: 'Admin',
};

export const mockEnterpriseUser2 = {
  username: 'Rookie',
  web_url: '/rookie',
  web_path: '/rookie',
  avatar_url: '/avatar2',
  id: 2,
  name: 'Rookie',
};

export const mockEnterpriseUsersQueryResponse = ({
  enterpriseUser = mockEnterpriseUser1,
} = {}) => ({
  data: [enterpriseUser],
  headers: { 'X-Next-Page': null },
});

export const mockEnterpriseUsersWithPaginationQueryResponse = {
  data: [mockEnterpriseUser2],
  headers: { 'X-Next-Page': 2 },
};

export const mockNonEnterpriseMember1 = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/1',
  avatarUrl: '/avatar1',
  name: 'Admin',
  username: 'Administrator',
  webUrl: '/root',
  webPath: '/root',
};

export const mockNonEnterpriseMember2 = {
  __typename: 'UserCore',
  id: 'gid://gitlab/User/2',
  avatarUrl: '/avatar2',
  name: 'Rookie',
  username: 'Rookie',
  webUrl: '/rookie',
  webPath: '/rookie',
};

export const mockNonEnterpriseMembersQueryResponse = ({
  member = mockNonEnterpriseMember1,
} = {}) => ({
  data: {
    users: {
      __typename: 'UserConnection',
      nodes: [member],
      pageInfo: {
        __typename: 'PageInfo',
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: 'end456',
      },
    },
  },
});

export const mockNonEnterpriseMembersWithPaginationQueryResponse = {
  data: {
    users: {
      __typename: 'UserConnection',
      nodes: [mockNonEnterpriseMember2],
      pageInfo: {
        __typename: 'PageInfo',
        hasNextPage: true,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: 'end123',
      },
    },
  },
};
