import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMount } from '@vue/test-utils';
import {
  Blob as BlobMock,
  SimpleViewerMock,
  RichViewerMock,
  RichSnippetContentMock,
  SimpleSnippetContentMock,
} from 'jest/blob/components/mock_data';
import GetBlobContent from 'shared_queries/snippet/snippet_blob_content.query.graphql';
import BlobContent from '~/blob/components/blob_content.vue';
import BlobContentError from '~/blob/components/blob_content_error.vue';
import BlobHeader from '~/blob/components/blob_header.vue';
import {
  BLOB_RENDER_EVENT_LOAD,
  BLOB_RENDER_EVENT_SHOW_SOURCE,
  BLOB_RENDER_ERRORS,
} from '~/blob/components/constants';
import SnippetBlobView from '~/snippets/components/snippet_blob_view.vue';
import { VISIBILITY_LEVEL_PUBLIC_STRING } from '~/visibility_level/constants';
import { RichViewer, SimpleViewer } from '~/blob/components/blob_viewers';
import createMockApollo from 'helpers/mock_apollo_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { TEST_HOST } from 'helpers/test_constants';
import waitForPromises from 'helpers/wait_for_promises';

describe('Blob Embeddable', () => {
  let wrapper;
  let requestHandlers;

  const snippet = {
    id: 'gid://foo.bar/snippet',
    webUrl: 'https://foo.bar',
    visibilityLevel: VISIBILITY_LEVEL_PUBLIC_STRING,
    project: {
      id: 'gid://gitlab/Project/7',
    },
  };
  const dataMock = {
    activeViewerType: SimpleViewerMock.type,
  };

  const mockDefaultHandler = ({ path, nodes } = { path: BlobMock.path }) => {
    const renderedNodes = nodes || [
      { __typename: 'SnippetBlobConnection', path, richData: 'richData', plainData: 'plainData' },
    ];

    return jest.fn().mockResolvedValue({
      data: {
        snippets: {
          __typename: 'SnippetConnection',
          id: '1',
          nodes: [
            {
              __typename: 'Snippet',
              id: '2',
              blobs: {
                __typename: 'SnippetBlobConnection',
                hasUnretrievableBlobs: false,
                nodes: renderedNodes,
              },
            },
          ],
        },
      },
    });
  };

  const createMockApolloProvider = (handler) => {
    Vue.use(VueApollo);

    requestHandlers = handler;
    return createMockApollo([[GetBlobContent, requestHandlers]]);
  };

  function createComponent({
    snippetProps = {},
    data = dataMock,
    blob = BlobMock,
    handler = mockDefaultHandler(),
  } = {}) {
    wrapper = shallowMount(SnippetBlobView, {
      apolloProvider: createMockApolloProvider(handler),
      propsData: {
        snippet: {
          ...snippet,
          ...snippetProps,
        },
        blob,
      },
      data() {
        return {
          ...data,
        };
      },
      stubs: {
        BlobHeader,
        BlobContent,
      },
    });
  }

  const findBlobHeader = () => wrapper.findComponent(BlobHeader);
  const findBlobContent = () => wrapper.findComponent(BlobContent);
  const findBlobContentError = () => wrapper.findComponent(BlobContentError);
  const findSimpleViewer = () => wrapper.findComponent(SimpleViewer);
  const findRichViewer = () => wrapper.findComponent(RichViewer);

  describe('rendering', () => {
    it('renders correct components', () => {
      createComponent();
      expect(findBlobHeader().exists()).toBe(true);
      expect(findBlobContent().exists()).toBe(true);
    });

    it('passes `isBlameLinkHidden = true` to blob content component', () => {
      createComponent();
      expect(findBlobContent().props('isBlameLinkHidden')).toEqual(true);
    });

    it('sets simple viewer correctly', async () => {
      createComponent();
      await waitForPromises();

      expect(findSimpleViewer().exists()).toBe(true);
    });

    it('sets rich viewer correctly', async () => {
      const data = { ...dataMock, activeViewerType: RichViewerMock.type };
      createComponent({
        data,
      });
      await waitForPromises();
      expect(findRichViewer().exists()).toBe(true);
      expect(findRichViewer().props('isSnippet')).toBe(true);
    });

    it('correctly switches viewer type', async () => {
      createComponent();
      await waitForPromises();

      expect(findSimpleViewer().exists()).toBe(true);

      findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, RichViewerMock.type);
      await waitForPromises();

      expect(findRichViewer().exists()).toBe(true);

      findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, SimpleViewerMock.type);
      await waitForPromises();

      expect(findSimpleViewer().exists()).toBe(true);
    });

    it('passes information about render error down to blob header', () => {
      createComponent({
        blob: {
          ...BlobMock,
          simpleViewer: {
            ...SimpleViewerMock,
            renderError: BLOB_RENDER_ERRORS.REASONS.COLLAPSED.id,
          },
        },
      });

      expect(findBlobHeader().props('hasRenderError')).toBe(true);
    });

    describe('bob content in multi-file scenario', () => {
      const SimpleSnippetContentMock2 = {
        ...SimpleSnippetContentMock,
        plainData: 'Another Plain Foo',
      };
      const RichSnippetContentMock2 = {
        ...SimpleSnippetContentMock,
        richData: 'Another Rich Foo',
      };

      const MixedSimpleSnippetContentMock = {
        ...SimpleSnippetContentMock,
        richData: '<h1>Rich</h1>',
      };

      const MixedRichSnippetContentMock = {
        ...RichSnippetContentMock,
        plainData: 'Plain',
      };

      it.each`
        snippetBlobs                                               | description                                  | currentBlob                 | expectedContent                       | activeViewerType
        ${[SimpleSnippetContentMock]}                              | ${'one existing textual blob'}               | ${SimpleSnippetContentMock} | ${SimpleSnippetContentMock.plainData} | ${SimpleViewerMock.type}
        ${[RichSnippetContentMock]}                                | ${'one existing rich blob'}                  | ${RichSnippetContentMock}   | ${RichSnippetContentMock.richData}    | ${RichViewerMock.type}
        ${[SimpleSnippetContentMock, MixedRichSnippetContentMock]} | ${'mixed blobs with current textual blob'}   | ${SimpleSnippetContentMock} | ${SimpleSnippetContentMock.plainData} | ${SimpleViewerMock.type}
        ${[MixedSimpleSnippetContentMock, RichSnippetContentMock]} | ${'mixed blobs with current rich blob'}      | ${RichSnippetContentMock}   | ${RichSnippetContentMock.richData}    | ${RichViewerMock.type}
        ${[SimpleSnippetContentMock, SimpleSnippetContentMock2]}   | ${'textual blobs with current textual blob'} | ${SimpleSnippetContentMock} | ${SimpleSnippetContentMock.plainData} | ${SimpleViewerMock.type}
        ${[RichSnippetContentMock, RichSnippetContentMock2]}       | ${'rich blobs with current rich blob'}       | ${RichSnippetContentMock}   | ${RichSnippetContentMock.richData}    | ${RichViewerMock.type}
      `(
        'renders correct content for $description',
        async ({ snippetBlobs, currentBlob, expectedContent, activeViewerType }) => {
          createComponent({
            handler: mockDefaultHandler({ path: currentBlob.path, nodes: snippetBlobs }),
            data: { activeViewerType },
            blob: {
              ...BlobMock,
              path: currentBlob.path,
            },
          });
          await waitForPromises();

          expect(findBlobContent().props('content')).toBe(expectedContent);
        },
      );
    });

    describe.each`
      url
      ${'/snippets/1?viewer=simple'}
      ${'/snippets/1?viewer=simple&path=foo%2Fbar%2Fdummy.md'}
      ${'/snippets/1?expanded=true&viewer=simple'}
      ${'/snippets/1?expanded=true&viewer=simple&path=another.md'}
    `('URL with viewer=simple without expanding this file at $url', ({ url }) => {
      beforeEach(async () => {
        setWindowLocation(url);
        createComponent({ data: {} });
        await waitForPromises();
      });

      afterEach(() => {
        setWindowLocation(TEST_HOST);
      });

      it('requests and renders content in the rich viewer', () => {
        expect(findRichViewer().exists()).toBe(true);
        expect(requestHandlers).toHaveBeenCalledWith(expect.objectContaining({ rich: true }));
      });
    });

    describe('URLS with hash', () => {
      afterEach(() => {
        window.location.hash = '';
      });

      describe('if hash starts with #LC', () => {
        beforeEach(() => {
          window.location.hash = '#LC2';
        });

        it('renders simple viewer by default', async () => {
          createComponent({
            data: {},
          });
          await waitForPromises();

          expect(findBlobHeader().props('activeViewerType')).toBe(SimpleViewerMock.type);
          expect(findSimpleViewer().exists()).toBe(true);
        });

        describe('switchViewer()', () => {
          it('switches to the passed viewer', async () => {
            createComponent();
            await waitForPromises();

            findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, RichViewerMock.type);
            await waitForPromises();

            expect(findBlobHeader().props('activeViewerType')).toBe(RichViewerMock.type);
            expect(findRichViewer().exists()).toBe(true);

            findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, SimpleViewerMock.type);
            await waitForPromises();

            expect(findBlobHeader().props('activeViewerType')).toBe(SimpleViewerMock.type);
            expect(findSimpleViewer().exists()).toBe(true);
          });
        });
      });

      describe('if hash starts with anything else', () => {
        beforeEach(() => {
          window.location.hash = '#last-headline';
        });

        it('renders rich viewer by default', async () => {
          createComponent({
            data: {},
          });
          await waitForPromises();

          expect(findBlobHeader().props('activeViewerType')).toBe(RichViewerMock.type);
          expect(findRichViewer().exists()).toBe(true);
        });

        describe('switchViewer()', () => {
          it('switches to the passed viewer', async () => {
            createComponent();
            await waitForPromises();

            findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, SimpleViewerMock.type);
            await waitForPromises();

            expect(findBlobHeader().props('activeViewerType')).toBe(SimpleViewerMock.type);
            expect(findSimpleViewer().exists()).toBe(true);

            findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE, RichViewerMock.type);
            await waitForPromises();

            expect(findBlobHeader().props('activeViewerType')).toBe(RichViewerMock.type);
            expect(findRichViewer().exists()).toBe(true);
          });
        });
      });
    });
  });

  describe('functionality', () => {
    describe('render error', () => {
      afterEach(() => {
        setWindowLocation(TEST_HOST);
      });

      describe.each`
        description                               | url                                                                    | renderError    | size
        ${'a collapsed blob without expanded'}    | ${'/snippets/1'}                                                       | ${'collapsed'} | ${1999999}
        ${'a collapsed blob without path'}        | ${'/snippets/1?expanded=true&viewer=simple'}                           | ${'collapsed'} | ${1999999}
        ${'a collapsed blob with another path'}   | ${'/snippets/1?expanded=true&viewer=simple&path=another.md'}           | ${'collapsed'} | ${1999999}
        ${'a too_large blob with expanded=true'}  | ${'/snippets/1?expanded=true&viewer=simple&path=foo%2Fbar%2Fdummy.md'} | ${'too_large'} | ${1999999}
        ${'a collapsed blob at the size limit'}   | ${'/snippets/1?expanded=true&viewer=simple&path=foo%2Fbar%2Fdummy.md'} | ${'collapsed'} | ${2000000}
        ${'a collapsed blob over the size limit'} | ${'/snippets/1?expanded=true&viewer=simple&path=foo%2Fbar%2Fdummy.md'} | ${'collapsed'} | ${2000001}
      `('$description', ({ url, renderError, size }) => {
        beforeEach(async () => {
          setWindowLocation(url);
          createComponent({
            data: {},
            blob: {
              ...BlobMock,
              size,
              richViewer: null,
              simpleViewer: { ...SimpleViewerMock, renderError },
            },
          });
          await waitForPromises();
        });

        it('keeps the error without requesting content', () => {
          expect(requestHandlers).not.toHaveBeenCalled();
          expect(findBlobHeader().props('hasRenderError')).toBe(true);
          expect(findBlobContentError().props('viewerError')).toBe(renderError);
          expect(findSimpleViewer().exists()).toBe(false);
        });
      });

      const collapsedRichViewer = { ...RichViewerMock, renderError: 'collapsed' };

      describe.each`
        url                                                                  | richViewer             | rich     | contentMock                                              | expectedContent
        ${'/snippets/1?expanded=true&viewer=simple&path=foo.js'}             | ${null}                | ${false} | ${SimpleSnippetContentMock}                              | ${'Plain'}
        ${'/snippets/1?expanded=true&path=foo.md'}                           | ${collapsedRichViewer} | ${true}  | ${RichSnippetContentMock}                                | ${'<h1>Rich</h1>'}
        ${'/snippets/1?expanded=true&viewer=simple&path=foo.js'}             | ${collapsedRichViewer} | ${false} | ${SimpleSnippetContentMock}                              | ${'Plain'}
        ${'/snippets/1?expanded=true&viewer=simple&path=dir%2Fa%20b%2Bc.md'} | ${collapsedRichViewer} | ${false} | ${{ ...SimpleSnippetContentMock, path: 'dir/a b+c.md' }} | ${'Plain'}
      `(
        'an expanded blob at $url with richViewer=$richViewer',
        ({ url, richViewer, rich, contentMock, expectedContent }) => {
          beforeEach(async () => {
            setWindowLocation(url);
            createComponent({
              data: {},
              blob: {
                ...BlobMock,
                size: 1999999,
                path: contentMock.path,
                richViewer,
                simpleViewer: { ...SimpleViewerMock, renderError: 'collapsed' },
              },
              handler: mockDefaultHandler({ nodes: [contentMock] }),
            });
            await waitForPromises();
          });

          it('requests and renders content in the expected viewer without mutating the blob', () => {
            const viewer = rich ? findRichViewer() : findSimpleViewer();
            const viewerType = rich ? 'richViewer' : 'simpleViewer';

            expect(requestHandlers).toHaveBeenCalledTimes(1);
            expect(requestHandlers).toHaveBeenCalledWith(expect.objectContaining({ rich }));
            expect(viewer.exists()).toBe(true);
            expect(viewer.props('content')).toBe(expectedContent);
            expect(findBlobHeader().props('hasRenderError')).toBe(false);
            expect(findBlobContentError().exists()).toBe(false);
            expect(findBlobContent().props('blob')[viewerType].renderError).toBe('collapsed');
          });
        },
      );

      it('correctly sets blob on the blob-content-error component', () => {
        createComponent();
        expect(findBlobContent().props('blob')).toEqual(BlobMock);
      });

      it(`refetches blob content on ${BLOB_RENDER_EVENT_LOAD} event`, async () => {
        createComponent();
        await waitForPromises();

        expect(requestHandlers).toHaveBeenCalledTimes(1);

        findBlobContent().vm.$emit(BLOB_RENDER_EVENT_LOAD);
        await waitForPromises();

        expect(requestHandlers).toHaveBeenCalledTimes(2);
      });

      it(`sets '${SimpleViewerMock.type}' as active on ${BLOB_RENDER_EVENT_SHOW_SOURCE} event`, () => {
        createComponent({
          data: {
            activeViewerType: RichViewerMock.type,
          },
        });

        findBlobContent().vm.$emit(BLOB_RENDER_EVENT_SHOW_SOURCE);
        expect(wrapper.vm.activeViewerType).toEqual(SimpleViewerMock.type);
      });
    });
  });

  describe('GetBlobContent query', () => {
    it('renders empty content when the response contains no snippet', async () => {
      const handler = jest.fn().mockResolvedValue({
        data: { snippets: { __typename: 'SnippetConnection', id: '1', nodes: [] } },
      });
      createComponent({ handler });
      await waitForPromises();

      expect(findBlobContent().props('content')).toBe('');
    });

    it('renders empty content when the response contains no matching blob', async () => {
      createComponent({ handler: mockDefaultHandler({ nodes: [] }) });
      await waitForPromises();

      expect(findBlobContent().props('content')).toBe('');
    });

    it('renders empty content when the query fails', async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('GraphQL error')) });
      await waitForPromises();

      expect(findBlobContent().props('content')).toBe('');
    });

    it('passes projectId when snippet has a project', async () => {
      const handler = mockDefaultHandler();
      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({
          projectId: 'gid://gitlab/Project/7',
        }),
      );
    });

    it('does not pass projectId when snippet has no project', async () => {
      const handler = mockDefaultHandler();
      createComponent({
        snippetProps: { project: null },
        handler,
      });
      await waitForPromises();

      expect(handler).not.toHaveBeenCalledWith(
        expect.objectContaining({
          projectId: expect.anything(),
        }),
      );
    });
  });
});
