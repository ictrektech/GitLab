import {
  getText,
  screen,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { projectNewestNpmPackage, projectNpmPackage } from './handlers';
import {
  PROJECT_PACKAGES_PATH,
  deleteFirstOtherVersion,
  findHeading,
  findOtherVersionsBadge,
  findOtherVersionsPanel,
  findOtherVersionsTab,
  findPackageRows,
  mountProjectPackagesApp,
  packageDetailsRoute,
  waitForPackageRows,
} from './test_setup';

const findInstallButton = () => screen.queryByTestId('install-button');

describe('Project package registry details', () => {
  describe('when opening a package from the list', () => {
    beforeEach(async () => {
      mountProjectPackagesApp();
      await waitForPackageRows(2);

      const npmRow = findPackageRows().find((row) => getText(row).includes(projectNpmPackage.name));
      within(npmRow).getByTestId('details-link').click();

      await waitForElement(findInstallButton);
    });

    it('navigates to the package details page', () => {
      expect(window.location.pathname).toBe(
        `${PROJECT_PACKAGES_PATH}/${getIdFromGraphQLId(projectNpmPackage.id)}`,
      );
      expect(getText(findHeading())).toContain(projectNpmPackage.name);
      expect(getText(findInstallButton())).toBe('Install');
    });

    it('shows no other versions', () => {
      expect(getText(findOtherVersionsTab())).toBe('Other versions 0');
    });
  });

  describe('when the package has other versions', () => {
    beforeEach(async () => {
      mountProjectPackagesApp({ route: packageDetailsRoute(projectNewestNpmPackage) });
      await waitForElement(findOtherVersionsBadge);
    });

    it('shows the count of other versions on the tab', async () => {
      await waitForAssertion(() => {
        expect(getText(findOtherVersionsBadge())).toBe('2');
      });
    });

    describe('when deleting a version from the Other versions tab', () => {
      beforeEach(async () => {
        findOtherVersionsTab().click();
        await waitForAssertion(() => {
          expect(getText(findOtherVersionsPanel())).toContain('1.0.0');
        });

        await deleteFirstOtherVersion();
      });

      it('confirms the deletion and updates the count', async () => {
        await waitForAssertion(() => {
          expect(getText(document.querySelector('.flash-container'))).toContain(
            'Package deleted successfully',
          );
        });
        await waitForAssertion(() => {
          expect(getText(findOtherVersionsTab())).toBe('Other versions 1');
        });
      });

      it('removes the deleted version and keeps the others', async () => {
        await waitForAssertion(() => {
          const panelText = getText(findOtherVersionsPanel());

          expect(panelText).toContain('1.1.0');
          expect(panelText).not.toContain('1.0.0');
        });
        expect(getText(screen.queryByTestId('sub-header'))).toContain(
          `v${projectNewestNpmPackage.version}`,
        );
      });
    });
  });
});
