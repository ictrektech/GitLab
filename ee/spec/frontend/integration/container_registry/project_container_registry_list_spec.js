import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { screen } from 'ee_jest/integration/helpers/test_helpers';
import { manyRepository, namelessRepository, projectRepository } from './handlers';
import {
  PROJECT_REGISTRY_PATH,
  PROJECT_SETTINGS_PATH,
  deleteImageFromList,
  detailsRoute,
  findBodyText,
  findImageLinkTexts,
  findTagNames,
  listedImageName,
  manyImageNames,
  goToNextPage,
  mountProjectRegistry,
  openImageDetails,
  useRepositoriesVariant,
  waitForBodyText,
  waitForImages,
  waitForTags,
} from './test_setup';

const findSettingsLink = () => screen.queryByRole('link', { name: 'Configure in settings' });

describe('Project container registry list', () => {
  describe('when there are image repositories', () => {
    beforeEach(async () => {
      mountProjectRegistry();
      await waitForImages([listedImageName(projectRepository)]);
    });

    it('shows the image count and the image', async () => {
      await waitForBodyText('1 Image repository');
      expect(findImageLinkTexts()).toEqual(['registry-project/my/image']);
    });

    it('schedules the repository for deletion', async () => {
      await deleteImageFromList(projectRepository);

      await waitForBodyText(`${projectRepository.path} was successfully scheduled for deletion`);
      expect(lastRequestVariables('destroyContainerRepository').id).toBe(projectRepository.id);
    });

    it('opens the details page with its tags', async () => {
      await openImageDetails(listedImageName(projectRepository));
      await waitForTags(1);

      expect(findTagNames()).toEqual(['latest']);
      expect(window.location.pathname).toBe(
        `${PROJECT_REGISTRY_PATH}${detailsRoute(projectRepository)}`,
      );
    });
  });

  describe('when showContainerRegistrySettings is true', () => {
    beforeEach(async () => {
      mountProjectRegistry({ showContainerRegistrySettings: 'true' });
      await waitForImages([listedImageName(projectRepository)]);
    });

    it('shows the link to the settings', () => {
      expect(findSettingsLink().getAttribute('href')).toBe(PROJECT_SETTINGS_PATH);
    });
  });

  describe('when showContainerRegistrySettings is false', () => {
    beforeEach(async () => {
      mountProjectRegistry({ showContainerRegistrySettings: 'false' });
      await waitForImages([listedImageName(projectRepository)]);
    });

    it('hides the link to the settings', () => {
      expect(findSettingsLink()).toBe(null);
    });
  });

  describe('when there are no image repositories', () => {
    beforeEach(() => {
      useRepositoriesVariant('empty');
      mountProjectRegistry();
    });

    it('shows the empty state with the CLI commands', async () => {
      await waitForBodyText('There are no container images stored for this project');
      expect(findBodyText()).toContain('CLI commands');
      expect(findImageLinkTexts()).toEqual([]);
    });
  });

  describe('when the image has no name', () => {
    beforeEach(async () => {
      useRepositoriesVariant('nameless');
      mountProjectRegistry();
      await waitForImages([listedImageName(namelessRepository)]);
    });

    it('opens the details page with its tags', async () => {
      await openImageDetails(listedImageName(namelessRepository));
      await waitForTags(1);

      expect(findTagNames()).toEqual(['latest']);
    });
  });

  describe.each`
    isMetadataDatabaseEnabled | pageSize
    ${'true'}                 | ${20}
    ${'false'}                | ${10}
  `(
    'when isMetadataDatabaseEnabled is $isMetadataDatabaseEnabled and there are more images than fit one page',
    ({ isMetadataDatabaseEnabled, pageSize }) => {
      const pageOf = (page) => manyImageNames.slice(page * pageSize, (page + 1) * pageSize);
      const lastPage = Math.ceil(manyImageNames.length / pageSize) - 1;

      beforeEach(async () => {
        useRepositoriesVariant('many');
        mountProjectRegistry({ isMetadataDatabaseEnabled });
        await waitForImages(pageOf(0));
      });

      it('requests one page at a time', () => {
        expect(lastRequestVariables('getProjectContainerRepositories').first).toBe(pageSize);
        expect(findImageLinkTexts()).not.toContain(listedImageName(manyRepository));
      });

      it('keeps the page when going back from the details page', async () => {
        const goToLastPage = async (page = 1) => {
          if (page > lastPage) return;

          await goToNextPage();
          await waitForImages(pageOf(page));
          await goToLastPage(page + 1);
        };

        await goToLastPage();
        expect(findImageLinkTexts()).toEqual([listedImageName(manyRepository)]);
        const pageUrl = `${window.location.pathname}${window.location.search}`;

        await openImageDetails(listedImageName(manyRepository));
        await waitForTags(1);

        window.history.back();

        await waitForImages([listedImageName(manyRepository)]);
        expect(`${window.location.pathname}${window.location.search}`).toBe(pageUrl);
      });
    },
  );

  describe.each(['connectionError', 'invalidPathError'])('when %s is true', (errorKey) => {
    beforeEach(() => {
      mountProjectRegistry({ [errorKey]: 'true' });
    });

    it('shows the connection error', async () => {
      await waitForBodyText('We are having trouble connecting to the container registry');
      expect(findImageLinkTexts()).toEqual([]);
    });
  });
});
