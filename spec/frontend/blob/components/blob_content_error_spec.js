import { GlSprintf, GlLink } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import BlobContentError from '~/blob/components/blob_content_error.vue';

import { BLOB_RENDER_ERRORS } from '~/blob/components/constants';

describe('Blob Content Error component', () => {
  let wrapper;

  function createComponent(props = {}) {
    wrapper = shallowMount(BlobContentError, {
      propsData: {
        ...props,
      },
      stubs: {
        GlSprintf,
      },
    });
  }

  describe('collapsed and too large blobs', () => {
    it.each`
      error                                   | reason                           | options
      ${BLOB_RENDER_ERRORS.REASONS.COLLAPSED} | ${'it is larger than 1.00 MiB'}  | ${[BLOB_RENDER_ERRORS.OPTIONS.LOAD.text, BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD.text]}
      ${BLOB_RENDER_ERRORS.REASONS.TOO_LARGE} | ${'it is larger than 10.00 MiB'} | ${[BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD.text]}
    `('renders correct reason for $error.id', ({ error, reason, options }) => {
      createComponent({
        viewerError: error.id,
      });
      expect(wrapper.text()).toContain(reason);
      options.forEach((option) => {
        expect(wrapper.text()).toContain(option);
      });
    });
  });

  describe.each`
    isSnippet | href
    ${true}   | ${'?expanded=true&viewer=simple&path=foo%2Fbar%20baz%2B.md'}
    ${false}  | ${'?expanded=true&viewer=simple'}
  `('load it anyway link with isSnippet=$isSnippet', ({ isSnippet, href }) => {
    beforeEach(() => {
      createComponent({
        viewerError: BLOB_RENDER_ERRORS.REASONS.COLLAPSED.id,
        blob: { path: 'foo/bar baz+.md', size: 1999999 },
        isSnippet,
      });
    });

    it('links to the expanded blob', () => {
      expect(wrapper.findComponent(GlLink).attributes('href')).toBe(href);
    });
  });

  describe.each`
    isSnippet | size       | options
    ${true}   | ${2000000} | ${['download it']}
    ${true}   | ${2000001} | ${['download it']}
    ${false}  | ${2000001} | ${['load it anyway', 'download it']}
  `('collapsed blob of $size bytes with isSnippet=$isSnippet', ({ isSnippet, size, options }) => {
    beforeEach(() => {
      createComponent({
        viewerError: BLOB_RENDER_ERRORS.REASONS.COLLAPSED.id,
        blob: { size },
        isSnippet,
      });
    });

    it('offers the expected links including download', () => {
      expect(wrapper.findAllComponents(GlLink).wrappers.map((link) => link.text())).toEqual(
        options,
      );
    });
  });

  describe.each`
    isSnippet | size       | showSource
    ${true}   | ${1999999} | ${true}
    ${true}   | ${2000000} | ${false}
    ${true}   | ${3000000} | ${false}
    ${false}  | ${3000000} | ${true}
  `(
    'rich text blob of $size bytes with isSnippet=$isSnippet',
    ({ isSnippet, size, showSource }) => {
      beforeEach(() => {
        createComponent({
          viewerError: BLOB_RENDER_ERRORS.REASONS.COLLAPSED.id,
          blob: { size, richViewer: {}, renderedAsText: true },
          isSnippet,
        });
      });

      it('shows the source link only when source viewing is available', () => {
        const sourceLinkExists = wrapper
          .findAllComponents(GlLink)
          .wrappers.some((link) => link.text() === 'view the source');

        expect(sourceLinkExists).toBe(showSource);
      });
    },
  );

  describe('external blob', () => {
    it.each`
      storageType         | reason                                                     | options
      ${'lfs'}            | ${BLOB_RENDER_ERRORS.REASONS.EXTERNAL.text.lfs}            | ${[BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD.text]}
      ${'build_artifact'} | ${BLOB_RENDER_ERRORS.REASONS.EXTERNAL.text.build_artifact} | ${[BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD.text]}
      ${'default'}        | ${BLOB_RENDER_ERRORS.REASONS.EXTERNAL.text.default}        | ${[BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD.text]}
    `('renders correct reason for $storageType blob', ({ storageType, reason, options }) => {
      createComponent({
        viewerError: BLOB_RENDER_ERRORS.REASONS.EXTERNAL.id,
        blob: {
          externalStorage: storageType,
        },
      });
      expect(wrapper.text()).toContain(reason);
      options.forEach((option) => {
        expect(wrapper.text()).toContain(option);
      });
    });
  });
});
