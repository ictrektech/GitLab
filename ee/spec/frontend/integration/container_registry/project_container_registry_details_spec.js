import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText, waitForAssertion, within } from 'ee_jest/integration/helpers/test_helpers';
import { selectSortOption } from 'ee_jest/integration/helpers/registry_helpers';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { getContainerRepositoryMetadata, getContainerRepositoryTags } from './fixture_variants';
import {
  manyTags,
  manyTagsNameAsc,
  manyTagsNameDesc,
  manyTagsSecondPage,
  manyTagsTotal,
  projectRepository,
} from './handlers';
import {
  deleteFirstTag,
  detailsRoute,
  findBodyText,
  findBreadcrumb,
  findImageTitle,
  findTagNames,
  goToNextPage,
  mountProjectRegistry,
  toggleSortDirection,
  waitForTags,
  waitForTagsCount,
} from './test_setup';

const namesOf = (tags) => tags.map(({ name }) => name);

const waitForTagNames = (tags) =>
  waitForAssertion(() => {
    expect(findTagNames()).toEqual(namesOf(tags));
  });

const sortByNameAscending = async () => {
  await selectSortOption('Name');
  await waitForTagNames(manyTagsNameDesc);
  await toggleSortDirection();
  await waitForTagNames(manyTagsNameAsc);
};

describe('Project container registry details', () => {
  describe('when the image has more tags than fit one page', () => {
    beforeEach(async () => {
      setQueryVariant(getContainerRepositoryTags).many();
      setQueryVariant(getContainerRepositoryMetadata).many();
      mountProjectRegistry({ route: detailsRoute(projectRepository) });
      await waitForTags(20);
    });

    it('shows the repository id in the breadcrumb', () => {
      expect(
        within(findBreadcrumb()).queryByRole('link', {
          name: String(getIdFromGraphQLId(projectRepository.id)),
        }),
      ).not.toBe(null);
    });

    it('shows the image title and tag count', async () => {
      await waitForTagsCount(`${manyTagsTotal} tags`);
      expect(getText(findImageTitle())).toBe(projectRepository.name);
    });

    it('lists the first page of tags, last published first', () => {
      expect(findTagNames()).toEqual(namesOf(manyTags));
      expect(lastRequestVariables('getContainerRepositoryTags').sort).toBe('PUBLISHED_AT_DESC');
    });

    it('sorts the tags by name in both directions', async () => {
      await selectSortOption('Name');

      await waitForTagNames(manyTagsNameDesc);
      expect(lastRequestVariables('getContainerRepositoryTags').sort).toBe('NAME_DESC');

      await toggleSortDirection();

      await waitForTagNames(manyTagsNameAsc);
      expect(lastRequestVariables('getContainerRepositoryTags').sort).toBe('NAME_ASC');
      expect(findTagNames()[0]).toBe('1');
    });

    describe('when sorted by name ascending', () => {
      beforeEach(async () => {
        await sortByNameAscending();
      });

      it('removes a tag and shows one fewer', async () => {
        await waitForTagsCount(`${manyTagsTotal} tags`);
        const [firstTag] = manyTagsNameAsc;

        await deleteFirstTag();

        await waitForTagsCount(`${manyTagsTotal - 1} tags`);
        await waitForAssertion(() => {
          expect(findTagNames()).not.toContain(firstTag.name);
        });
        expect(lastRequestVariables('destroyContainerRepositoryTags')).toEqual({
          id: projectRepository.id,
          tagNames: [firstTag.name],
        });
      });

      it('navigates to the second page of tags', async () => {
        await goToNextPage();

        await waitForTagNames(manyTagsSecondPage());
        expect(lastRequestVariables('getContainerRepositoryTags').sort).toBe('NAME_ASC');
      });
    });
  });

  describe('when a tag has no digest', () => {
    beforeEach(async () => {
      setQueryVariant(getContainerRepositoryTags).missingDigest();
      mountProjectRegistry({ route: detailsRoute(projectRepository) });
      await waitForTags(2);
    });

    it('lists the tags and shows the digest as not applicable', () => {
      expect(findTagNames()).toEqual(expect.arrayContaining(['latest', 'stable']));
      expect(findBodyText()).toContain('Digest: Not applicable.');
    });
  });
});
