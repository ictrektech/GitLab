import Vue, { nextTick } from 'vue';
import { GlTable, GlSkeletonLoader } from '@gitlab/ui';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMount } from '@vue/test-utils';
import MembersApp from 'ee/saml_providers/saml_members/index.vue';
import { useSamlMembers } from 'ee/saml_providers/saml_members/store';
import TablePagination from '~/vue_shared/components/pagination/table_pagination.vue';

Vue.use(PiniaVuePlugin);

describe('SAML providers members app', () => {
  let wrapper;
  let pinia;
  let store;

  const createWrapper = (state = {}) => {
    store = useSamlMembers();
    Object.assign(store, state);

    wrapper = shallowMount(MembersApp, {
      pinia,
    });
  };

  beforeEach(() => {
    pinia = createTestingPinia();
  });

  describe('on mount', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('calls fetchPage', () => {
      expect(store.fetchPage).toHaveBeenCalled();
    });

    it('renders loader', () => {
      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
    });
  });

  describe('when loaded', () => {
    beforeEach(() => {
      createWrapper({
        isInitialLoadInProgress: false,
      });
    });

    it('does not render loader', () => {
      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(false);
    });

    it('renders table', () => {
      expect(wrapper.findComponent(GlTable).exists()).toBe(true);
    });

    it('requests next page when pagination component performs change', async () => {
      const changeFn = wrapper.findComponent(TablePagination).props('change');
      changeFn(2);
      await nextTick();
      expect(store.fetchPage).toHaveBeenCalledWith(2);
    });
  });
});
