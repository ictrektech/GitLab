import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findSortDirectionButton,
  findSortDropdown,
} from 'ee_jest/integration/helpers/registry_helpers';
import { getPackages, getPackagesCount } from './fixture_variants';
import { groupMavenPackage, groupNpmPackage } from './handlers';
import {
  currentQueryParams,
  deletePackageFromRow,
  filterByType,
  findPackageRows,
  mountGroupPackagesApp,
  waitForPackageRows,
} from './test_setup';

const findSortOption = (orderBy) => screen.queryByTestId(`listbox-item-${orderBy}`);

const expectRowOrder = (packages) =>
  waitForAssertion(() => {
    const rows = findPackageRows();

    expect(rows).toHaveLength(packages.length);
    packages.forEach(({ name, version, project }, index) => {
      expect(getText(within(rows[index]).getByTestId('details-link'))).toBe(name);
      expect(getText(rows[index])).toContain(version);
      expect(getText(rows[index])).toContain(project.name);
    });
  });

const expectPackageCount = (text) =>
  waitForAssertion(() => {
    expect(getText(document.body)).toContain(text);
  });

describe('Group package registry list', () => {
  describe('when there are packages', () => {
    beforeEach(async () => {
      mountGroupPackagesApp();
      await waitForPackageRows(2);
    });

    it('shows the name, version and project of each package, newest first', async () => {
      await expectRowOrder([groupNpmPackage, groupMavenPackage]);
    });

    it('shows the latest pipeline and who published it to which project', () => {
      const [npmRow] = findPackageRows();

      expect(getText(within(npmRow).getByTestId('pipeline-sha'))).toBe('d83d6e39');
      expect(getText(npmRow)).toContain(
        `Published to ${groupNpmPackage.project.name} by Package Publisher`,
      );
    });

    it('links each package to its project', () => {
      const [npmRow] = findPackageRows();
      const projectLink = within(npmRow).getByRole('link', { name: groupNpmPackage.project.name });

      expect(projectLink.getAttribute('href')).toMatch(
        new RegExp(`/${groupNpmPackage.project.fullPath}$`),
      );
    });

    it('deletes a package from the row actions', async () => {
      await expectPackageCount('2 packages');

      const [npmRow] = findPackageRows();
      await deletePackageFromRow(npmRow);

      await expectPackageCount('Package deleted successfully');
      await expectPackageCount('1 package');
      await expectRowOrder([groupMavenPackage]);
      expect(lastRequestVariables('destroyPackages').ids).toEqual([groupNpmPackage.id]);
    });
  });

  describe('sorting', () => {
    const sortCases = [
      {
        label: 'Type',
        orderBy: 'type',
        sort: 'desc',
        groupSort: 'TYPE_DESC',
        packages: [groupNpmPackage, groupMavenPackage],
      },
      {
        label: 'Type',
        orderBy: 'type',
        sort: 'asc',
        groupSort: 'TYPE_ASC',
        packages: [groupMavenPackage, groupNpmPackage],
      },
      {
        label: 'Name',
        orderBy: 'name',
        sort: 'desc',
        groupSort: 'NAME_DESC',
        packages: [groupNpmPackage, groupMavenPackage],
      },
      {
        label: 'Name',
        orderBy: 'name',
        sort: 'asc',
        groupSort: 'NAME_ASC',
        packages: [groupMavenPackage, groupNpmPackage],
      },
      {
        label: 'Version',
        orderBy: 'version',
        sort: 'desc',
        groupSort: 'VERSION_DESC',
        packages: [groupMavenPackage, groupNpmPackage],
      },
      {
        label: 'Version',
        orderBy: 'version',
        sort: 'asc',
        groupSort: 'VERSION_ASC',
        packages: [groupNpmPackage, groupMavenPackage],
      },
      {
        label: 'Published',
        orderBy: 'created_at',
        sort: 'asc',
        groupSort: 'CREATED_ASC',
        packages: [groupMavenPackage, groupNpmPackage],
      },
      {
        label: 'Project',
        orderBy: 'project_path',
        sort: 'desc',
        groupSort: 'PROJECT_PATH_DESC',
        packages: [groupNpmPackage, groupMavenPackage],
      },
      {
        label: 'Project',
        orderBy: 'project_path',
        sort: 'asc',
        groupSort: 'PROJECT_PATH_ASC',
        packages: [groupMavenPackage, groupNpmPackage],
      },
    ];

    describe.each(sortCases)(
      'when sorted by $label $sort',
      ({ label, orderBy, sort, groupSort, packages }) => {
        beforeEach(async () => {
          mountGroupPackagesApp();
          await waitForPackageRows(2);

          await waitAndClick(() => findSortOption(orderBy));
          if (sort === 'asc') {
            await waitAndClick(findSortDirectionButton);
          }
        });

        it('requests that sort and lists the packages in its order', async () => {
          await waitForAssertion(() => {
            expect(lastRequestVariables('getPackages').groupSort).toBe(groupSort);
          });
          await expectRowOrder(packages);
          expect(getText(within(findSortDropdown()).getByRole('option', { selected: true }))).toBe(
            label,
          );
        });
      },
    );

    describe('when sorted by name ascending', () => {
      beforeEach(async () => {
        mountGroupPackagesApp();
        await waitForPackageRows(2);

        await waitAndClick(() => findSortOption('name'));
        await waitAndClick(findSortDirectionButton);
      });

      it('stores the sort in the query params', async () => {
        await waitForAssertion(() => {
          expect(currentQueryParams()).toEqual({ orderBy: 'name', sort: 'asc' });
        });
      });
    });
  });

  describe('filtering by type', () => {
    beforeEach(async () => {
      mountGroupPackagesApp();
      await waitForPackageRows(2);
      await filterByType('npm');
    });

    it('requests npm packages and lists only them', async () => {
      await waitForAssertion(() => {
        expect(lastRequestVariables('getPackages').packageType).toBe('NPM');
      });
      await expectRowOrder([groupNpmPackage]);
    });

    it('stores the filter and the sort in the query params', async () => {
      await waitForAssertion(() => {
        expect(currentQueryParams()).toEqual({ type: 'npm', orderBy: 'created_at', sort: 'desc' });
      });
    });

    describe('when cleared', () => {
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
      setQueryVariant(getPackages).groupEmpty();
      setQueryVariant(getPackagesCount).groupEmpty();
      mountGroupPackagesApp();
    });

    it('shows the empty message', async () => {
      await waitForAssertion(() => {
        expect(getText(document.body)).toContain('There are no packages yet');
      });
      expect(findPackageRows()).toHaveLength(0);
    });
  });
});
