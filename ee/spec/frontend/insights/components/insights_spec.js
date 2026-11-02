import { GlDisclosureDropdown, GlEmptyState, GlSprintf } from '@gitlab/ui';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import Vue, { nextTick } from 'vue';
import MockAdapter from 'axios-mock-adapter';
import axios from '~/lib/utils/axios_utils';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { INSIGHTS_CONFIGURATION_TEXT } from 'ee/insights/constants';
import Insights from 'ee/insights/components/insights.vue';
import { useInsightsStore } from 'ee/insights/stores';
import { pageInfo } from 'ee_jest/insights/mock_data';
import { TEST_HOST } from 'helpers/test_constants';

Vue.use(PiniaVuePlugin);

const defaultMocks = {
  $route: {
    params: {},
  },
  $router: {
    replace() {},
    push() {},
  },
};

const defaultKey = 'issues';
const selectedKey = 'mrs';
const selectedKeyMocks = {
  $route: {
    params: {
      tabId: selectedKey,
    },
  },
};

const invalidKeyMocks = {
  $route: {
    params: {
      tabId: 'invalid',
    },
  },
};

const createComponent = (pinia, options = {}) => {
  const { mocks = defaultMocks, props = {} } = options;
  return shallowMountExtended(Insights, {
    pinia,
    propsData: {
      endpoint: TEST_HOST,
      queryEndpoint: `${TEST_HOST}/query`,
      ...props,
    },
    stubs: ['router-link', 'router-view'],
    mocks,
  });
};

describe('Insights component', () => {
  let mock;
  let wrapper;
  let pinia;
  let store;

  const findGlDisclosureDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findFilteredOutAlert = () => wrapper.findByTestId('insights-filtered-out-alert');
  const findNoticeAlert = () => wrapper.findByTestId('insights-notice-alert');

  beforeEach(() => {
    mock = new MockAdapter(axios);
    pinia = createTestingPinia();
    store = useInsightsStore();
    wrapper = createComponent(pinia);
  });

  afterEach(() => {
    mock.restore();
  });

  it('fetches config data when mounted', () => {
    expect(store.fetchConfigData).toHaveBeenCalledWith(TEST_HOST);
  });

  it('renders insights configuration text', () => {
    const text = wrapper.findComponent(GlSprintf).attributes('message');

    expect(text).toBe(INSIGHTS_CONFIGURATION_TEXT);
  });

  describe('when loading config', () => {
    it('renders config loading state', () => {
      store.configLoading = true;

      expect(wrapper.find('.insights-config-loading').exists()).toBe(true);
      expect(wrapper.find('.insights-wrapper').exists()).toBe(false);
    });
  });

  describe('when config loaded', () => {
    const title = 'Bugs Per Team';
    const chart1 = { title: 'foo' };
    const chart2 = { title: 'bar' };

    describe('when no charts have been requested', () => {
      const page = {
        title,
        charts: [],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
      });

      it('has the correct nav tabs', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().exists()).toBe(true);
        expect(findGlDisclosureDropdown().props('items')[0].text).toBe(title);
      });

      it('should not disable the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().attributes().disabled).toBeUndefined();
      });
    });

    describe('when charts have not been initialized', () => {
      const page = {
        title,
        charts: [chart1, chart2],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
      });

      it('has the correct nav tabs', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().exists()).toBe(true);
        expect(findGlDisclosureDropdown().props('items')[0].text).toBe(title);
      });

      it('disables the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().props('disabled')).toBe(true);
      });
    });

    describe('when charts have been initialized', () => {
      const page = {
        title,
        charts: [chart1, chart2],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
        store.chartData = {
          [chart1.title]: {},
          [chart2.title]: {},
        };
      });

      it('enables the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().attributes()).toMatchObject({ disabled: 'true' });
      });
    });

    describe('when some charts have been loaded', () => {
      const page = {
        title,
        charts: [chart1],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
        store.chartData = {
          [chart2.title]: { loaded: true },
        };
      });

      it('disables the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().attributes()).toMatchObject({ disabled: 'true' });
      });
    });

    describe('when all charts have loaded', () => {
      const page = {
        title,
        charts: [chart1, chart2],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
        store.chartData = {
          [chart1.title]: { loaded: true },
          [chart2.title]: { loaded: true },
        };
      });

      it('enables the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().attributes().disabled).toBeUndefined();
      });
    });

    describe('when one chart has an error', () => {
      const page = {
        title,
        charts: [chart1, chart2],
      };

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
        store.chartData = {
          [chart1.title]: { error: 'Baz' },
          [chart2.title]: { loaded: true },
        };
      });

      it('enables the tab selector', async () => {
        await nextTick();
        expect(findGlDisclosureDropdown().attributes().disabled).toBeUndefined();
      });
    });

    describe('notice alert', () => {
      const page = {
        title,
        charts: [chart1, chart2],
      };

      const mockNotice = 'Sample notice';

      beforeEach(() => {
        store.configLoading = false;
        store.activePage = page;
        store.configData = {
          bugsPerTeam: page,
        };
      });

      describe('when there is a notice', () => {
        beforeEach(() => {
          wrapper = createComponent(pinia, { props: { notice: mockNotice } });
        });

        it('should display a notice alert with the correct text', () => {
          expect(findNoticeAlert().exists()).toBe(true);
          expect(findNoticeAlert().text()).toBe(mockNotice);
        });
      });

      describe('when there is no notice', () => {
        beforeEach(() => {
          wrapper = createComponent(pinia, { props: { notice: '' } });
        });

        it('should not display a notice alert', () => {
          expect(findNoticeAlert().exists()).toBe(false);
        });
      });
    });
  });

  describe('empty config', () => {
    beforeEach(() => {
      store.configLoading = false;
      store.configData = null;
    });

    it('displays a warning', async () => {
      await nextTick();
      expect(wrapper.findComponent(GlEmptyState).attributes()).toMatchObject({
        title: 'Invalid Insights config file detected',
      });
    });

    it('does not display dropdown', async () => {
      await nextTick();
      expect(findGlDisclosureDropdown().exists()).toBe(false);
    });
  });

  describe('filtered out items', () => {
    beforeEach(() => {
      store.configLoading = false;
      store.configData = {};
    });

    it('displays a warning', async () => {
      await nextTick();
      expect(findFilteredOutAlert().text()).toContain(
        'This project is filtered out in the insights.yml file',
      );
    });

    it('does not display dropdown', async () => {
      await nextTick();
      expect(findGlDisclosureDropdown().exists()).toBe(false);
    });
  });

  describe('hash fragment present', () => {
    const configData = {};
    configData[defaultKey] = { title: 'title1' };
    configData[selectedKey] = { title: 'title2' };

    beforeEach(() => {
      store.configLoading = false;
      store.configData = configData;
      store.activePage = pageInfo;
    });

    it('selects the first tab if invalid', async () => {
      wrapper = createComponent(pinia, { mocks: { ...defaultMocks, ...invalidKeyMocks } });

      jest.runOnlyPendingTimers();

      await nextTick();
      expect(store.setActiveTab).toHaveBeenCalledWith(defaultKey);
    });

    it('selects the specified tab if valid', async () => {
      wrapper = createComponent(pinia, { mocks: { ...defaultMocks, ...selectedKeyMocks } });

      jest.runOnlyPendingTimers();

      await nextTick();
      expect(store.setActiveTab).toHaveBeenCalledWith(selectedKey);
    });
  });

  describe('dropdown title', () => {
    const configData = {};
    configData[defaultKey] = { title: 'Default key title' };
    configData[selectedKey] = { title: 'Selected key title' };

    beforeEach(() => {
      store.configLoading = false;
      store.configData = configData;
      store.activePage = pageInfo;
    });

    it('uses the default title when there is no active tab specified', async () => {
      wrapper = createComponent(pinia, { mocks: { ...defaultMocks, ...selectedKeyMocks } });

      jest.runOnlyPendingTimers();

      await nextTick();
      expect(findGlDisclosureDropdown().props('toggleText')).toBe('Select report');
    });

    it('sets the title when there is an active tab specified', async () => {
      store.activeTab = selectedKey;

      wrapper = createComponent(pinia, { mocks: { ...defaultMocks, ...selectedKeyMocks } });

      jest.runOnlyPendingTimers();

      await nextTick();
      expect(findGlDisclosureDropdown().props('toggleText')).toBe('Selected key title');
    });
  });
});
