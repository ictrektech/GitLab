import { waitFor } from '@testing-library/vue';
import resourcesFixture from 'test_fixtures/graphql/ci/catalog/integration/get_catalog_resources.query.graphql.json';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import { LATEST_VERSION, PREVIOUS_VERSION } from './constants';
import { findResourceItems, mountCatalogList } from './test_setup';

const RESOURCE_NAME = resourcesFixture.data.ciCatalogResources.nodes[0].name;

describe('CI/CD Catalog list page', () => {
  describe('when a published resource has multiple releases', () => {
    beforeEach(() => {
      mountCatalogList();
    });

    it('lists the resource', async () => {
      await waitFor(() => {
        expect(findResourceItems()).toHaveLength(1);
        expect(getText(findResourceItems()[0])).toContain(RESOURCE_NAME);
      });
    });

    it('shows only the latest version', async () => {
      await waitFor(() => {
        const itemText = getText(findResourceItems()[0]);

        expect(itemText).toContain(LATEST_VERSION);
        expect(itemText).not.toContain(PREVIOUS_VERSION);
      });
    });
  });
});
