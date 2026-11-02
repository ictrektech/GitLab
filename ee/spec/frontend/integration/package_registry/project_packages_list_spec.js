import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findSortDirectionButton,
  selectSortOption,
} from 'ee_jest/integration/helpers/registry_helpers';
import { getPackages, getPackagesCount } from './fixture_variants';
import { projectMavenPackage, projectNpmPackage } from './handlers';
import {
  currentQueryParams,
  deletePackageFromRow,
  filterByType,
  findPackageRowTexts,
  findPackageRows,
  mountProjectPackagesApp,
  waitForPackageRows,
} from './test_setup';

const findPackageCount = () => screen.queryByTestId('metadata-item-text');
const expectRowsInOrder = (packages) => {
  const rows = findPackageRowTexts();

  expect(rows).toHaveLength(packages.length);
  packages.forEach(({ name, version }, index) => {
    expect(rows[index]).toContain(name);
    expect(rows[index]).toContain(version);
  });
};

const waitForSortRequest = (sort) =>
  waitForAssertion(() => {
    expect(lastRequestVariables('getPackages').sort).toBe(sort);
  });

describe('Project package registry list', () => {
  describe('when there are packages', () => {
    beforeEach(async () => {
      mountProjectPackagesApp();
      await waitForPackageRows(2);
    });

    it('lists each package with its name and version, newest first', () => {
      expectRowsInOrder([projectNpmPackage, projectMavenPackage]);
    });

    it('shows the latest pipeline and its user on the package row', () => {
      const [npmRow] = findPackageRowTexts();

      expect(npmRow).toContain('d83d6e39');
      expect(npmRow).toContain('Published by Package Publisher');
    });

    it('deletes a package from its row actions and updates the count', async () => {
      await waitForAssertion(() => {
        expect(getText(findPackageCount())).toBe('2 packages');
      });

      const [firstRow] = findPackageRows();
      await deletePackageFromRow(firstRow);

      await waitForAssertion(() => {
        expect(getText(document.querySelector('.flash-container'))).toContain(
          'Package deleted successfully',
        );
      });
      await waitForAssertion(() => {
        expect(getText(findPackageCount())).toBe('1 package');
      });
      expectRowsInOrder([projectMavenPackage]);
    });

    describe.each`
      label          | orderBy         | direction | sort              | packages
      ${'Type'}      | ${'type'}       | ${'desc'} | ${'TYPE_DESC'}    | ${[projectNpmPackage, projectMavenPackage]}
      ${'Type'}      | ${'type'}       | ${'asc'}  | ${'TYPE_ASC'}     | ${[projectMavenPackage, projectNpmPackage]}
      ${'Name'}      | ${'name'}       | ${'desc'} | ${'NAME_DESC'}    | ${[projectNpmPackage, projectMavenPackage]}
      ${'Name'}      | ${'name'}       | ${'asc'}  | ${'NAME_ASC'}     | ${[projectMavenPackage, projectNpmPackage]}
      ${'Version'}   | ${'version'}    | ${'desc'} | ${'VERSION_DESC'} | ${[projectMavenPackage, projectNpmPackage]}
      ${'Version'}   | ${'version'}    | ${'asc'}  | ${'VERSION_ASC'}  | ${[projectNpmPackage, projectMavenPackage]}
      ${'Published'} | ${'created_at'} | ${'asc'}  | ${'CREATED_ASC'}  | ${[projectMavenPackage, projectNpmPackage]}
    `('when sorted by $label $direction', ({ label, orderBy, direction, sort, packages }) => {
      beforeEach(async () => {
        if (orderBy !== 'created_at') {
          await selectSortOption(label);
          await waitForSortRequest(sort.replace(/_ASC$/, '_DESC'));
        }
        if (direction === 'asc') {
          findSortDirectionButton().click();
        }
        await waitForSortRequest(sort);
      });

      it('lists the packages in that order', async () => {
        await waitForAssertion(() => {
          expectRowsInOrder(packages);
        });
      });
    });

    describe('when sorted by name ascending', () => {
      beforeEach(async () => {
        await selectSortOption('Name');
        await waitForSortRequest('NAME_DESC');
        findSortDirectionButton().click();
        await waitForSortRequest('NAME_ASC');
      });

      it('puts orderBy and sort in the query params', () => {
        expect(currentQueryParams()).toMatchObject({ orderBy: 'name', sort: 'asc' });
      });
    });
  });

  describe('when filtering by type npm', () => {
    beforeEach(async () => {
      mountProjectPackagesApp();
      await waitForPackageRows(2);
      await filterByType('npm');
    });

    it('requests and lists only npm packages', async () => {
      await waitForAssertion(() => {
        expect(lastRequestVariables('getPackages')).toMatchObject({
          packageType: 'NPM',
          sort: 'CREATED_DESC',
        });
      });
      await waitForPackageRows(1);
      expectRowsInOrder([projectNpmPackage]);
    });

    it('puts the type and the sort in the query params', async () => {
      await waitForAssertion(() => {
        expect(currentQueryParams()).toEqual({ type: 'npm', orderBy: 'created_at', sort: 'desc' });
      });
    });

    describe('when the filter is cleared', () => {
      beforeEach(async () => {
        await waitForPackageRows(1);
        await waitAndClick(() => screen.queryByTestId('filtered-search-clear-button'));
      });

      it('lists every package again and keeps only the sort in the query params', async () => {
        await waitForPackageRows(2);
        await waitForAssertion(() => {
          expect(currentQueryParams()).toEqual({ orderBy: 'created_at', sort: 'desc' });
        });
      });
    });
  });

  describe('when there are no packages', () => {
    beforeEach(() => {
      setQueryVariant(getPackages).empty();
      setQueryVariant(getPackagesCount).empty();
      mountProjectPackagesApp();
    });

    it('shows the empty message', async () => {
      await waitForAssertion(() => {
        expect(getText(document.body)).toContain('There are no packages yet');
      });
      expect(findPackageRows()).toHaveLength(0);
    });
  });
});
