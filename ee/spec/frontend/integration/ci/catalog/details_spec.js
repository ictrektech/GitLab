import { waitFor } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import versionsVariants from './fixture_variants/get_ci_catalog_resource_versions';
import sharedDataVariants from './fixture_variants/get_ci_catalog_resource_shared_data';
import { LATEST_VERSION, PREVIOUS_VERSION } from './constants';
import {
  findEmptyState,
  findReadme,
  findSelectedVersion,
  findTab,
  findVersionBadge,
  findVersionOption,
  mountCatalogDetails,
} from './test_setup';

const expectReadmeFor = (version) =>
  waitFor(() => {
    expect(getText(findReadme())).toBe(`Readme for ${version}`);
  });

describe('CI/CD Catalog resource details page', () => {
  describe('when the resource is published', () => {
    beforeEach(() => {
      mountCatalogDetails();
    });

    it('shows the Readme tab', async () => {
      await waitForElement(() => findTab('Readme'));
    });

    it('shows the latest version in the header', async () => {
      await waitFor(() => {
        expect(getText(findVersionBadge())).toContain(LATEST_VERSION);
      });
    });

    describe('when the Readme tab is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Readme'));
      });

      it('renders the README of the latest version', async () => {
        await expectReadmeFor(LATEST_VERSION);
      });
    });

    describe('when a previous version is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findVersionOption(PREVIOUS_VERSION));
      });

      it('marks the previous version as selected', async () => {
        await waitFor(() => {
          expect(getText(findSelectedVersion())).toContain(PREVIOUS_VERSION);
        });
      });

      describe('when the Readme tab is selected', () => {
        beforeEach(async () => {
          await waitAndClick(() => findTab('Readme'));
        });

        it('renders the README of the previous version', async () => {
          await expectReadmeFor(PREVIOUS_VERSION);
        });
      });
    });
  });

  describe('when the URL links to a previous version', () => {
    beforeEach(() => {
      mountCatalogDetails({ query: `?tab=readme&version=${PREVIOUS_VERSION}` });
    });

    it('selects the linked version', async () => {
      await waitFor(() => {
        expect(getText(findSelectedVersion())).toContain(PREVIOUS_VERSION);
      });
    });

    it('renders the README of the linked version', async () => {
      await expectReadmeFor(PREVIOUS_VERSION);
    });
  });

  describe('when the resource is not available', () => {
    beforeEach(() => {
      setQueryVariant(versionsVariants).notAvailable();
      setQueryVariant(sharedDataVariants).notAvailable();
      mountCatalogDetails();
    });

    it('shows the "No component available" empty state', async () => {
      const emptyState = await waitForElement(findEmptyState);

      expect(getText(emptyState)).toContain('No component available');
    });
  });
});
