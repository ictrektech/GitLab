import { GlLink, GlSprintf, GlAlert } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import AncestorNotice from '~/clusters_list/components/ancestor_notice.vue';
import { useClustersList } from '~/clusters_list/store';

Vue.use(PiniaVuePlugin);

describe('ClustersAncestorNotice', () => {
  let pinia;
  let store;
  let wrapper;

  const createWrapper = async () => {
    pinia = createTestingPinia({ stubActions: false });
    store = useClustersList();
    store.setInitialState({ ancestorHelpPath: '/some/ancestor/path' });
    wrapper = shallowMount(AncestorNotice, { pinia, stubs: { GlSprintf, GlAlert } });
    await nextTick();
  };

  beforeEach(() => {
    return createWrapper();
  });

  describe('when cluster does not have ancestors', () => {
    beforeEach(async () => {
      store.hasAncestorClusters = false;
      await nextTick();
    });

    it('displays no notice', () => {
      expect(wrapper.find('*').exists()).toBe(false);
    });
  });

  describe('when cluster has ancestors', () => {
    beforeEach(async () => {
      store.hasAncestorClusters = true;
      await nextTick();
    });

    it('displays notice text', () => {
      expect(wrapper.text()).toContain(
        'Clusters are utilized by selecting the nearest ancestor with a matching environment scope. For example, project clusters will override group clusters.',
      );
    });

    it('displays link', () => {
      expect(wrapper.findComponent(GlLink).exists()).toBe(true);
    });
  });
});
