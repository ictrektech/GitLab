import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  mountHeaderArea,
  mountTreeHeaderArea,
  findCodeDropdownToggle,
  findDownloadSourceCodeGroup,
  findDownloadDirectoryGroup,
  findSshCloneItem,
  PROJECT_FULL_PATH,
} from './test_setup';

const ARCHIVE_FORMATS = ['zip', 'tar.gz', 'tar.bz2', 'tar'];
const ARCHIVE_BASE = `/${PROJECT_FULL_PATH}/-/archive/master/gitlab-test-master`;
const CDN_ORIGIN = 'https://cdn.gitlab.com';
const STATIC_OBJECT_TOKEN = 'secret-user-token';

// Shape produced by TreeHelper#download_links: one { text, path } entry per
// Workhorse archive format. Any external-storage CDN host and user token are
// already baked into the path by the backend before it reaches the frontend.
const DEFAULT_LINKS = ARCHIVE_FORMATS.map((format) => ({
  text: format,
  path: `${ARCHIVE_BASE}.${format}?ref_type=heads`,
}));

const CDN_LINKS = ARCHIVE_FORMATS.map((format) => ({
  text: format,
  path: `${CDN_ORIGIN}${ARCHIVE_BASE}.${format}?ref_type=heads&token=${STATIC_OBJECT_TOKEN}`,
}));

const openCodeDropdown = () => waitAndClick(findCodeDropdownToggle);

const findFormatLink = (group, format) =>
  Array.from(group.querySelectorAll('a')).find((link) => getText(link) === format);

describe('Code dropdown archive download buttons', () => {
  describe('on the project overview page', () => {
    it('lists a download link per archive format and no directory group', async () => {
      await mountHeaderArea({ downloadLinks: DEFAULT_LINKS });
      await openCodeDropdown();

      const group = await waitForElement(findDownloadSourceCodeGroup);

      ARCHIVE_FORMATS.forEach((format) => {
        const link = findFormatLink(group, format);

        expect(link.getAttribute('href')).toBe(`${ARCHIVE_BASE}.${format}?ref_type=heads`);
        expect(link.getAttribute('rel')).toBe('nofollow');
        expect(link.hasAttribute('download')).toBe(true);
      });

      expect(findDownloadDirectoryGroup()).toBe(null);
    });

    it('renders external-storage hrefs (CDN host and token) untouched', async () => {
      await mountHeaderArea({ downloadLinks: CDN_LINKS });
      await openCodeDropdown();

      const group = await waitForElement(findDownloadSourceCodeGroup);

      ARCHIVE_FORMATS.forEach((format) => {
        expect(findFormatLink(group, format).getAttribute('href')).toBe(
          `${CDN_ORIGIN}${ARCHIVE_BASE}.${format}?ref_type=heads&token=${STATIC_OBJECT_TOKEN}`,
        );
      });
    });
  });

  describe('on the repository tree page', () => {
    it('adds a directory download group with the current path merged into each link', async () => {
      await mountTreeHeaderArea({ downloadLinks: DEFAULT_LINKS });
      await openCodeDropdown();

      const sourceGroup = await waitForElement(findDownloadSourceCodeGroup);

      ARCHIVE_FORMATS.forEach((format) => {
        expect(findFormatLink(sourceGroup, format).getAttribute('href')).toBe(
          `${ARCHIVE_BASE}.${format}?ref_type=heads`,
        );
      });

      const directoryGroup = findDownloadDirectoryGroup();

      ARCHIVE_FORMATS.forEach((format) => {
        const href = findFormatLink(directoryGroup, format).getAttribute('href');
        const url = new URL(href, window.location.origin);

        expect(url.pathname).toBe(`${ARCHIVE_BASE}.${format}`);
        expect(url.searchParams.get('path')).toBe('encoding');
        expect(url.searchParams.get('ref_type')).toBe('heads');
      });
    });

    it('keeps the CDN origin and token in directory links and does not escape nested paths', async () => {
      await mountHeaderArea({ route: '/-/tree/master/files/ruby', downloadLinks: CDN_LINKS });
      await openCodeDropdown();

      const directoryGroup = await waitForElement(findDownloadDirectoryGroup);

      ARCHIVE_FORMATS.forEach((format) => {
        const href = findFormatLink(directoryGroup, format).getAttribute('href');
        const url = new URL(href);

        expect(url.origin).toBe(CDN_ORIGIN);
        expect(url.searchParams.get('token')).toBe(STATIC_OBJECT_TOKEN);
        // mergeUrlParams escapes the slash; the component un-escapes it on purpose.
        expect(href).toContain('path=files/ruby');
      });
    });
  });

  describe('when the repository has no archives to download', () => {
    it('shows no download groups', async () => {
      await mountHeaderArea({ downloadLinks: [] });
      await openCodeDropdown();

      // The clone item proves the dropdown content rendered, so absence is meaningful.
      await waitForElement(findSshCloneItem);

      expect(findDownloadSourceCodeGroup()).toBe(null);
      expect(findDownloadDirectoryGroup()).toBe(null);
    });
  });
});
