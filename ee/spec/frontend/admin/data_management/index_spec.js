import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { convertObjectPropsToSnakeCase } from '~/lib/utils/common_utils';
import { initAdminDataManagementApp } from 'ee/admin/data_management';
import AdminDataManagementApp from 'ee/admin/data_management/components/app.vue';
import { formatListboxItems } from 'ee/admin/data_management/filters';
import {
  FILTERED_SEARCH_TOKEN_OPTIONS,
  SORT_OPTIONS_ARRAY,
} from 'ee/admin/data_management/constants';
import { createRouter } from 'ee/admin/data_management/router';
import { MOCK_MODEL_TYPES } from './mock_data';

jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('ee/admin/data_management/router', () => ({
  createRouter: jest.fn(() => 'data-management-router'),
}));

const BASE_PATH = '/admin/data_management';

describe('initAdminDataManagementApp', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('without the mount element', () => {
    it('mounts nothing', () => {
      expect(initAdminDataManagementApp()).toBe(null);
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });

  describe('with the mount element', () => {
    beforeEach(() => {
      const el = document.createElement('div');
      el.id = 'js-admin-data-management';
      // The Rails helper serializes model types as snake_case JSON.
      Object.assign(el.dataset, {
        initialModelTypeName: 'uploads',
        basePath: BASE_PATH,
        modelTypes: JSON.stringify(
          MOCK_MODEL_TYPES.map((type) => convertObjectPropsToSnakeCase(type)),
        ),
      });
      document.body.appendChild(el);

      initAdminDataManagementApp();
    });

    it('builds the router on the base path', () => {
      expect(createRouter).toHaveBeenCalledWith(BASE_PATH);
    });

    it('mounts the data management app with the values parsed from the data attributes', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          el: document.getElementById('js-admin-data-management'),
          component: AdminDataManagementApp,
          router: 'data-management-router',
          provide: {
            basePath: BASE_PATH,
            listboxItems: formatListboxItems(MOCK_MODEL_TYPES),
            filteredSearchTokens: FILTERED_SEARCH_TOKEN_OPTIONS,
            sortOptions: SORT_OPTIONS_ARRAY,
          },
          props: {
            initialModelTypeName: 'uploads',
            modelTypes: MOCK_MODEL_TYPES,
          },
        }),
      );
    });
  });
});
