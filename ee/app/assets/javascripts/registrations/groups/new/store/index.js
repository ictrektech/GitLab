import { defineStore } from 'pinia';
import { DEFAULT_GROUP_PATH } from '../constants';

export const useGroupRegistration = defineStore('groupRegistration', {
  state() {
    return {
      storeGroupName: '',
      storeGroupPath: DEFAULT_GROUP_PATH,
    };
  },
  actions: {
    setStoreGroupName(groupName) {
      this.storeGroupName = groupName;
    },
    setStoreGroupPath(groupPath) {
      this.storeGroupPath = groupPath;
    },
  },
});
