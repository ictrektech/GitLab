import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  screen,
  waitForAssertion,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { groupNewestNpmPackage, groupNpmPackage } from './handlers';
import {
  GROUP_PACKAGES_PATH,
  deleteFirstOtherVersion,
  findHeading,
  findOtherVersionsBadge,
  findOtherVersionsPanel,
  findOtherVersionsTab,
  findPackageRows,
  mountGroupPackagesApp,
  packageDetailsRoute,
  waitForPackageRows,
} from './test_setup';

const waitForDetails = (packageEntity) =>
  waitForAssertion(() => {
    expect(getText(findHeading())).toBe(packageEntity.name);
  });

describe('Group package registry details', () => {
  describe('when opening a package from the list', () => {
    beforeEach(async () => {
      mountGroupPackagesApp();
      await waitForPackageRows(2);

      const [npmRow] = findPackageRows();
      within(npmRow).getByTestId('details-link').click();
      await waitForDetails(groupNpmPackage);
    });

    it('routes to the package details page', () => {
      expect(window.location.pathname).toBe(
        `${GROUP_PACKAGES_PATH}${packageDetailsRoute(groupNpmPackage)}`,
      );
    });

    it('shows the Install button and no other versions', () => {
      expect(screen.queryByTestId('install-button')).not.toBe(null);
      expect(getText(findOtherVersionsTab())).toBe('Other versions 0');
    });
  });

  describe('when the package has other versions', () => {
    beforeEach(async () => {
      mountGroupPackagesApp({ route: packageDetailsRoute(groupNewestNpmPackage) });
      await waitForDetails(groupNewestNpmPackage);
    });

    it('shows their count on the Other versions tab', () => {
      expect(getText(findOtherVersionsBadge())).toBe('2');
    });

    describe('when deleting a version', () => {
      beforeEach(async () => {
        findOtherVersionsTab().click();
        await waitForAssertion(() => {
          expect(getText(findOtherVersionsPanel())).toContain('1.0.0');
        });

        await deleteFirstOtherVersion();
      });

      it('removes the version and decrements the count', async () => {
        await waitForAssertion(() => {
          expect(getText(document.body)).toContain('Package deleted successfully');
        });
        await waitForAssertion(() => {
          expect(getText(findOtherVersionsTab())).toBe('Other versions 1');
        });

        const versionsText = getText(findOtherVersionsPanel());
        expect(versionsText).not.toContain('1.0.0');
        expect(versionsText).toContain('1.1.0');
        expect(getText(findHeading())).toBe(groupNewestNpmPackage.name);
        expect(getText(document.body)).toContain(groupNewestNpmPackage.version);
        expect(lastRequestVariables('destroyPackages').ids).toEqual([groupNpmPackage.id]);
      });
    });
  });
});
