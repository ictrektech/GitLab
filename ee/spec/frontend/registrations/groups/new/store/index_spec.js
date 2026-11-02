import { createTestingPinia } from '@pinia/testing';
import { DEFAULT_GROUP_PATH } from 'ee/registrations/groups/new/constants';
import { useGroupRegistration } from 'ee/registrations/groups/new/store';

describe('Group registration store', () => {
  let store;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useGroupRegistration();
  });

  it('creates default state', () => {
    expect(store.$state).toEqual({
      storeGroupName: '',
      storeGroupPath: DEFAULT_GROUP_PATH,
    });
  });

  describe('setStoreGroupName', () => {
    it('sets storeGroupName', () => {
      store.setStoreGroupName('name');

      expect(store.storeGroupName).toBe('name');
    });
  });

  describe('setStoreGroupPath', () => {
    it('sets storeGroupPath', () => {
      store.setStoreGroupPath('path');

      expect(store.storeGroupPath).toBe('path');
    });
  });
});
