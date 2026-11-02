import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlBadge, GlCollapsibleListbox } from '@gitlab/ui';
import { fetchGroupEnterpriseUsers } from 'ee_else_ce/api/groups_api';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';

import PlaceholderActions from '~/members/placeholders/components/placeholder_actions.vue';
import groupNonEnterpriseMembersQuery from '~/members/placeholders/graphql/queries/group_non_enterprise_members.query.graphql';
import importSourceUserReassignMutation from '~/members/placeholders/graphql/mutations/reassign.mutation.graphql';

import { mockSourceUsers, mockReassignMutationResponse } from 'jest/members/placeholders/mock_data';

import {
  mockEnterpriseUser1,
  mockEnterpriseUser2,
  mockEnterpriseUsersQueryResponse,
  mockEnterpriseUsersWithPaginationQueryResponse,
  mockNonEnterpriseMember1,
  mockNonEnterpriseMember2,
  mockNonEnterpriseMembersQueryResponse,
  mockNonEnterpriseMembersWithPaginationQueryResponse,
} from '../mock_data';

Vue.use(VueApollo);
jest.mock('~/alert');
jest.mock('ee_component/api/groups_api');

describe('PlaceholderActions', () => {
  let wrapper;

  const defaultProps = {
    sourceUser: mockSourceUsers[0],
  };

  const $toast = {
    show: jest.fn(),
  };

  const nonEnterpriseMembersQueryHandler = jest
    .fn()
    .mockResolvedValue(mockNonEnterpriseMembersQueryResponse());
  const reassignMutationHandler = jest.fn().mockResolvedValue(mockReassignMutationResponse);

  const createComponent = ({
    provide = {},
    nonEnterpriseMembersHandler = nonEnterpriseMembersQueryHandler,
  } = {}) => {
    wrapper = shallowMountExtended(PlaceholderActions, {
      apolloProvider: createMockApollo([
        [groupNonEnterpriseMembersQuery, nonEnterpriseMembersHandler],
        [importSourceUserReassignMutation, reassignMutationHandler],
      ]),
      propsData: defaultProps,
      provide: {
        group: { id: 1, path: 'test-group' },
        ...provide,
      },
      mocks: { $toast },
      stubs: { GlCollapsibleListbox },
    });
  };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findListItems = () => wrapper.findAll('[data-testid^="listbox-item-"]');
  const findListItem = (value) => wrapper.findByTestId(`listbox-item-${value}`);
  const findBadges = () => wrapper.findAllComponents(GlBadge);
  const findBadgesInListItem = (value) => findListItem(value).findAllComponents(GlBadge);

  afterEach(() => {
    fetchGroupEnterpriseUsers.mockClear();
  });

  describe('when restrictReassignmentToEnterprise is false', () => {
    beforeEach(() => {
      createComponent({
        provide: { restrictReassignmentToEnterprise: false },
      });
    });

    it('does not call fetchGroupEnterpriseUsers on listbox `shown` event', async () => {
      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(fetchGroupEnterpriseUsers).not.toHaveBeenCalled();
    });
  });

  describe('when restrictReassignmentToEnterprise is true', () => {
    beforeEach(() => {
      createComponent({
        provide: { restrictReassignmentToEnterprise: true },
      });
    });

    it('calls fetchGroupEnterpriseUsers on listbox `shown` event', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(
        mockEnterpriseUsersWithPaginationQueryResponse,
      );

      await findListbox().vm.$emit('shown');

      expect(findListbox().props('loading')).toBe(true);
      expect(fetchGroupEnterpriseUsers).toHaveBeenCalledTimes(1);
      expect(fetchGroupEnterpriseUsers).toHaveBeenCalledWith(
        1,
        expect.objectContaining({ search: '' }),
      );

      await waitForPromises();

      expect(findListbox().props('loading')).toBe(false);
      expect(findListbox().props('items')).toHaveLength(1);
    });

    it('does not query nonEnterpriseMembers', async () => {
      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(nonEnterpriseMembersQueryHandler).not.toHaveBeenCalled();
    });

    it('does not render the Enterprise badge', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(mockEnterpriseUsersQueryResponse());

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(findListItems().length).toBeGreaterThan(0);
      expect(findBadges()).toHaveLength(0);
    });

    describe('when the component is opened multiple times', () => {
      beforeEach(() => {
        fetchGroupEnterpriseUsers.mockResolvedValueOnce(
          mockEnterpriseUsersWithPaginationQueryResponse,
        );
      });

      it('does not call fetchGroupEnterpriseUsers again', async () => {
        await findListbox().vm.$emit('shown');
        await waitForPromises();

        await findListbox().vm.$emit('shown');
        await waitForPromises();

        expect(fetchGroupEnterpriseUsers).toHaveBeenCalledTimes(1);
      });
    });

    describe('when users query succeeds and has pagination', () => {
      beforeEach(async () => {
        fetchGroupEnterpriseUsers.mockResolvedValueOnce(
          mockEnterpriseUsersWithPaginationQueryResponse,
        );
        fetchGroupEnterpriseUsers.mockResolvedValueOnce(mockEnterpriseUsersQueryResponse());

        await findListbox().vm.$emit('shown');
        await waitForPromises();
      });

      describe('when "bottom-reached" event is emitted', () => {
        beforeEach(async () => {
          await findListbox().vm.$emit('bottom-reached');
        });

        it('calls fetchGroupEnterpriseUsers again to get next page', () => {
          expect(fetchGroupEnterpriseUsers).toHaveBeenCalledTimes(2);
        });

        it('appends query results to "enterpriseUsers"', () => {
          const allUsers = [mockEnterpriseUser2, mockEnterpriseUser1];

          expect(findListbox().props('items')).toHaveLength(allUsers.length);
        });
      });
    });

    describe('when users query succeeds and does not have pagination', () => {
      beforeEach(async () => {
        await findListbox().vm.$emit('shown');
        await waitForPromises();
      });

      describe('when "bottom-reached" event is emitted', () => {
        beforeEach(async () => {
          await findListbox().vm.$emit('bottom-reached');
        });

        it('does not call fetchGroupEnterpriseUsers again', () => {
          expect(fetchGroupEnterpriseUsers).toHaveBeenCalledTimes(1);
        });
      });
    });
  });

  describe('when restrictReassignmentToEnterprise and allowNonEnterprisePlaceholderReassignment are both true', () => {
    beforeEach(() => {
      createComponent({
        provide: {
          restrictReassignmentToEnterprise: true,
          allowNonEnterprisePlaceholderReassignment: true,
        },
      });
    });

    it('does not query nonEnterpriseMembers before the listbox is shown', async () => {
      await waitForPromises();

      expect(nonEnterpriseMembersQueryHandler).not.toHaveBeenCalled();
    });

    it('queries nonEnterpriseMembers with the group id, search term, and active/human filters', async () => {
      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(nonEnterpriseMembersQueryHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          groupId: 'gid://gitlab/Group/1',
          search: '',
          active: true,
          humans: true,
        }),
      );
      expect(findListbox().props('items')).toHaveLength(1);
      expect(findListbox().props('items')[0]).toMatchObject({
        username: mockNonEnterpriseMember1.username,
      });
    });

    it('does not filter by active when allowInactivePlaceholderReassignment is true', async () => {
      createComponent({
        provide: {
          restrictReassignmentToEnterprise: true,
          allowNonEnterprisePlaceholderReassignment: true,
          allowInactivePlaceholderReassignment: true,
        },
      });

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(nonEnterpriseMembersQueryHandler).toHaveBeenCalledWith(
        expect.not.objectContaining({ active: expect.anything() }),
      );
    });

    it('also calls fetchGroupEnterpriseUsers and merges results with nonEnterpriseMembers', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(
        mockEnterpriseUsersQueryResponse({ enterpriseUser: mockEnterpriseUser2 }),
      );

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(fetchGroupEnterpriseUsers).toHaveBeenCalledTimes(1);

      const items = findListbox().props('items');
      expect(items).toHaveLength(2);
      expect(items.map((item) => item.username)).toEqual(
        expect.arrayContaining([mockEnterpriseUser2.username, mockNonEnterpriseMember1.username]),
      );
    });

    it('does not duplicate a user returned by both sources', async () => {
      // mockEnterpriseUser1 (id: 1) and mockNonEnterpriseMember1 (id: gid://gitlab/User/1) are
      // the same underlying user, returned by both sources.
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(mockEnterpriseUsersQueryResponse());

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      const items = findListbox().props('items');
      const matchingItems = items.filter((item) => item.value === 'gid://gitlab/User/1');
      expect(matchingItems).toHaveLength(1);
    });

    it('renders the Enterprise badge only on enterprise users', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(
        mockEnterpriseUsersQueryResponse({ enterpriseUser: mockEnterpriseUser2 }),
      );

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(findListItems().length).toBeGreaterThan(0);

      const enterpriseBadges = findBadgesInListItem('gid://gitlab/User/2');
      expect(enterpriseBadges).toHaveLength(1);
      expect(enterpriseBadges.at(0).props('variant')).toBe('info');
      expect(enterpriseBadges.at(0).text()).toBe('Enterprise');
      expect(findBadgesInListItem(mockNonEnterpriseMember1.id)).toHaveLength(0);
    });

    it('renders the Enterprise badge on a user returned by both sources', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(mockEnterpriseUsersQueryResponse());

      await findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(findListItems().length).toBeGreaterThan(0);
      expect(findBadges()).toHaveLength(1);
      expect(findBadgesInListItem('gid://gitlab/User/1')).toHaveLength(1);
    });

    it('sends the reassign payload with the user id when an enterprise user is selected', async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(
        mockEnterpriseUsersQueryResponse({ enterpriseUser: mockEnterpriseUser2 }),
      );

      await findListbox().vm.$emit('shown');
      await waitForPromises();
      await findListbox().vm.$emit('select', 'gid://gitlab/User/2');

      expect(findListbox().props('toggleText')).toBe(`@${mockEnterpriseUser2.username}`);

      wrapper.findComponentByTestId('confirm-button').vm.$emit('click');
      await waitForPromises();

      expect(reassignMutationHandler).toHaveBeenCalledWith({
        id: mockSourceUsers[0].id,
        userId: 'gid://gitlab/User/2',
      });
    });
  });

  describe('when nonEnterpriseMembers query fails', () => {
    beforeEach(async () => {
      fetchGroupEnterpriseUsers.mockResolvedValueOnce(
        mockEnterpriseUsersQueryResponse({ enterpriseUser: mockEnterpriseUser2 }),
      );

      createComponent({
        provide: {
          restrictReassignmentToEnterprise: true,
          allowNonEnterprisePlaceholderReassignment: true,
        },
        nonEnterpriseMembersHandler: jest.fn().mockRejectedValue(new Error('GraphQL error')),
      });
      await findListbox().vm.$emit('shown');
      await waitForPromises();
    });

    it('creates an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'There was a problem fetching users.',
      });
    });

    it('stops loading and renders enterprise users', () => {
      expect(findListbox().props('loading')).toBe(false);
      expect(findListbox().props('items')).toMatchObject([
        { username: mockEnterpriseUser2.username },
      ]);
    });
  });

  describe('when nonEnterpriseMembers query succeeds and has pagination', () => {
    let nonEnterpriseMembersPaginatedQueryHandler;

    beforeEach(async () => {
      nonEnterpriseMembersPaginatedQueryHandler = jest
        .fn()
        .mockResolvedValueOnce(mockNonEnterpriseMembersWithPaginationQueryResponse)
        .mockResolvedValueOnce(mockNonEnterpriseMembersQueryResponse());

      createComponent({
        provide: {
          restrictReassignmentToEnterprise: true,
          allowNonEnterprisePlaceholderReassignment: true,
        },
        nonEnterpriseMembersHandler: nonEnterpriseMembersPaginatedQueryHandler,
      });
      await findListbox().vm.$emit('shown');
      await waitForPromises();
    });

    describe('when "bottom-reached" event is emitted', () => {
      beforeEach(async () => {
        await findListbox().vm.$emit('bottom-reached');
        await waitForPromises();
      });

      it('calls nonEnterpriseMembers query again to get next page', () => {
        expect(nonEnterpriseMembersPaginatedQueryHandler).toHaveBeenCalledTimes(2);
      });

      it('appends query results to "nonEnterpriseMembers"', () => {
        const allUsers = [mockNonEnterpriseMember2, mockNonEnterpriseMember1];

        expect(findListbox().props('items')).toHaveLength(allUsers.length);
      });
    });
  });
});
