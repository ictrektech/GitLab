import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { convertObjectPropsToSnakeCase } from '~/lib/utils/common_utils';
import { getGraphqlClient } from 'ee/geo_shared/graphql/geo_client';
import initGeoReplicable from 'ee/geo_replicable';
import GeoReplicableApp from 'ee/geo_replicable/components/app.vue';
import {
  formatListboxItems,
  getAvailableFilteredSearchTokens,
  getAvailableSortOptions,
} from 'ee/geo_replicable/filters';
import {
  MOCK_REPLICABLE_BASE_PATH,
  MOCK_REPLICABLE_CLASS,
  MOCK_REPLICABLE_TYPES,
} from './mock_data';

jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('ee/geo_shared/graphql/geo_client', () => ({
  getGraphqlClient: jest.fn(() => 'geo-graphql-client'),
}));

describe('initGeoReplicable', () => {
  const createMountElement = (replicableClass = MOCK_REPLICABLE_CLASS) => {
    const el = document.createElement('div');
    el.id = 'js-geo-replicable';
    // The Rails helpers serialize these as snake_case JSON.
    Object.assign(el.dataset, {
      geoCurrentSiteId: '1',
      geoTargetSiteId: '2',
      geoTargetSiteName: 'Secondary site',
      replicableBasePath: MOCK_REPLICABLE_BASE_PATH,
      replicableTypes: JSON.stringify(
        MOCK_REPLICABLE_TYPES.map((type) => convertObjectPropsToSnakeCase(type)),
      ),
      replicatorClassData: JSON.stringify(convertObjectPropsToSnakeCase(replicableClass)),
    });
    document.body.appendChild(el);
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('without the mount element', () => {
    it('mounts nothing', () => {
      expect(initGeoReplicable()).toBe(null);
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });

  describe('with the mount element', () => {
    beforeEach(() => {
      createMountElement();
      initGeoReplicable();
    });

    it('creates the GraphQL client for the current and target sites', () => {
      expect(getGraphqlClient).toHaveBeenCalledWith('1', '2');
      expect(initVueApp.mock.calls[0][0].apolloProvider.defaultClient).toBe('geo-graphql-client');
    });

    it('mounts the replicable app with the values parsed from the data attributes', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          el: document.getElementById('js-geo-replicable'),
          component: GeoReplicableApp,
          provide: {
            replicableBasePath: MOCK_REPLICABLE_BASE_PATH,
            siteName: 'Secondary site',
            replicableClass: MOCK_REPLICABLE_CLASS,
            itemTitle: MOCK_REPLICABLE_CLASS.titlePlural,
            listboxItems: formatListboxItems(MOCK_REPLICABLE_TYPES),
            filteredSearchTokens: getAvailableFilteredSearchTokens(
              MOCK_REPLICABLE_CLASS.verificationEnabled,
            ),
            sortOptions: getAvailableSortOptions(MOCK_REPLICABLE_CLASS.verificationEnabled),
          },
        }),
      );
    });
  });

  describe('when the replicable class has verification disabled', () => {
    beforeEach(() => {
      createMountElement({ ...MOCK_REPLICABLE_CLASS, verificationEnabled: false });
      initGeoReplicable();
    });

    it('provides the filters and sort options without verification', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          provide: expect.objectContaining({
            filteredSearchTokens: getAvailableFilteredSearchTokens(false),
            sortOptions: getAvailableSortOptions(false),
          }),
        }),
      );
    });
  });
});
