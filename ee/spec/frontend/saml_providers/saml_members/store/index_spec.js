import { createTestingPinia } from '@pinia/testing';
import { useSamlMembers } from 'ee/saml_providers/saml_members/store';
import Api from '~/api';
import { createAlert } from '~/alert';

jest.mock('~/alert');
jest.mock('~/api', () => ({
  groupMembers: jest.fn(),
}));

describe('saml_members store', () => {
  let store;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useSamlMembers();
    store.setInitialState({ groupId: 1 });
  });

  afterEach(() => {
    Api.groupMembers.mockClear();
    createAlert.mockClear();
  });

  it('has default state', () => {
    expect(store.$state).toMatchObject({
      isInitialLoadInProgress: true,
      pageInfo: {
        perPage: 10,
        page: 1,
        total: 20,
        totalPages: 1,
        nextPage: 0,
        previousPage: 0,
      },
      members: [],
    });
  });

  describe('setInitialState', () => {
    it('sets the group id', () => {
      expect(store.groupId).toBe(1);
    });
  });

  describe('fetchPage', () => {
    it('requests the members and stores them on correct data', async () => {
      const members = [
        { id: 1, name: 'user 1', group_saml_identity: null, group_scim_identity: null },
        {
          id: 2,
          name: 'user 2',
          group_saml_identity: { extern_uid: 'a' },
          group_scim_identity: { extern_uid: 'a' },
        },
      ];

      Api.groupMembers.mockReturnValue(
        Promise.resolve({
          headers: {
            'x-per-page': '10',
            'x-page': '2',
            'x-total': '30',
            'x-total-pages': '3',
            'x-next-page': '3',
            'x-prev-page': '1',
          },
          data: members,
        }),
      );

      await store.fetchPage();

      expect(Api.groupMembers).toHaveBeenCalledWith(1, {
        with_saml_identity: 'true',
        page: 1,
        per_page: 10,
      });
      expect(store.isInitialLoadInProgress).toBe(false);
      expect(store.members).toEqual([
        { id: 1, name: 'user 1', identity: null, scim_identity: null },
        { id: 2, name: 'user 2', identity: 'a', scim_identity: 'a' },
      ]);
      expect(store.pageInfo).toEqual({
        perPage: 10,
        page: 2,
        total: 30,
        totalPages: 3,
        nextPage: 3,
        previousPage: 1,
      });
    });

    it('requests the given page', async () => {
      Api.groupMembers.mockReturnValue(Promise.resolve({ headers: {}, data: [] }));

      await store.fetchPage(3);

      expect(Api.groupMembers).toHaveBeenCalledWith(1, expect.objectContaining({ page: 3 }));
    });

    it('should show alert on wrong data', async () => {
      Api.groupMembers.mockReturnValue(Promise.reject(new Error()));

      await store.fetchPage();

      expect(createAlert).toHaveBeenCalledTimes(1);
      expect(store.isInitialLoadInProgress).toBe(true);
    });
  });
});
