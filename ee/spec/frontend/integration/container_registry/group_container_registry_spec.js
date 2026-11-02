import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { getText, within } from 'ee_jest/integration/helpers/test_helpers';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { groupRepository, sameNameRepository } from './handlers';
import {
  deleteFirstTag,
  findBreadcrumb,
  findImageLinkTexts,
  findImageTitle,
  findTagNames,
  listedImageName,
  mountGroupRegistry,
  openImageDetails,
  useRepositoriesVariant,
  waitForBodyText,
  waitForImages,
  waitForTags,
  waitForTagsCount,
} from './test_setup';

describe('Group container registry', () => {
  describe('when there are image repositories', () => {
    beforeEach(async () => {
      mountGroupRegistry();
      await waitForImages([listedImageName(groupRepository)]);
    });

    it('shows the image count and the image', async () => {
      await waitForBodyText('1 Image repository');
      expect(findImageLinkTexts()).toEqual(['group-project/my/image']);
    });

    describe('when opening the image details', () => {
      beforeEach(async () => {
        await openImageDetails(listedImageName(groupRepository));
        await waitForTags(1);
      });

      it('shows the repository id in the breadcrumb', () => {
        expect(
          within(findBreadcrumb()).queryByRole('link', {
            name: String(getIdFromGraphQLId(groupRepository.id)),
          }),
        ).not.toBe(null);
      });

      it('shows the image title, tag count and first tag', async () => {
        await waitForTagsCount('1 tag');
        expect(getText(findImageTitle())).toBe(groupRepository.name);
        expect(findTagNames()).toEqual(['latest']);
      });

      it('removes the tag', async () => {
        await waitForTagsCount('1 tag');

        await deleteFirstTag();

        await waitForTagsCount('0 tags');
        expect(findTagNames()).toEqual([]);
        expect(lastRequestVariables('destroyContainerRepositoryTags')).toEqual({
          id: groupRepository.id,
          tagNames: ['latest'],
        });
      });
    });
  });

  describe('when there are no image repositories', () => {
    beforeEach(() => {
      useRepositoriesVariant('groupEmpty');
      mountGroupRegistry();
    });

    it('shows the empty state', async () => {
      await waitForBodyText('There are no container images available in this group');
      expect(findImageLinkTexts()).toEqual([]);
    });
  });

  describe('when an image has the same name as the group', () => {
    beforeEach(async () => {
      useRepositoriesVariant('groupSameName');
      mountGroupRegistry();
      await waitForImages([listedImageName(sameNameRepository)]);
    });

    it('opens the details page with its tags', async () => {
      await openImageDetails(listedImageName(sameNameRepository));
      await waitForTags(1);

      expect(findTagNames()).toEqual(['latest']);
    });
  });

  describe.each(['connectionError', 'invalidPathError'])('when %s is true', (errorKey) => {
    beforeEach(() => {
      mountGroupRegistry({ [errorKey]: 'true' });
    });

    it('shows the connection error', async () => {
      await waitForBodyText('We are having trouble connecting to the container registry');
      expect(findImageLinkTexts()).toEqual([]);
    });
  });
});
