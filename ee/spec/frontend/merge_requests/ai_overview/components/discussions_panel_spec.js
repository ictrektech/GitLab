import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DiscussionsPanel from 'ee/merge_requests/ai_overview/components/discussions_panel.vue';
import ConversationForm from 'ee/merge_requests/ai_overview/components/conversation_form.vue';
import FileIcon from '~/vue_shared/components/file_icon.vue';
import discussionsQuery from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_discussions.query.graphql';
import createNoteMutation from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_create_note.mutation.graphql';
import toggleResolveMutation from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_toggle_resolve.mutation.graphql';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import {
  author,
  diffLine,
  diffRefs,
  discussionsResponse,
  makeDiscussion,
  makeMergeRequest,
  makeNote,
  makeSuggestion,
  suggestions,
} from '../mock_data';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const user = (overrides) => ({ ...author, bot: false, ...overrides });
const reviewer = user({ id: 'gid://gitlab/User/2', username: 'marco', name: 'Marco Diaz' });
const commenter = user({ id: 'gid://gitlab/User/5', username: 'ada', name: 'Ada Chen' });
const bot = user({
  id: 'gid://gitlab/User/9',
  username: 'duo',
  name: 'Duo Code Review',
  bot: true,
});

const openThread = makeDiscussion({
  notes: [
    makeNote(),
    makeNote({
      id: 'gid://gitlab/DiffNote/15',
      bodyFirstLineHtml: '<p>Agreed, renaming it.</p>',
      author: reviewer,
    }),
  ],
});

const resolvedThread = makeDiscussion({
  id: 'gid://gitlab/Discussion/2',
  resolved: true,
  notes: [
    makeNote({
      id: 'gid://gitlab/DiffNote/12',
      bodyFirstLineHtml: '<p>Fixed.</p>',
      author: commenter,
    }),
  ],
});

const agentComment = makeDiscussion({
  id: 'gid://gitlab/Discussion/3',
  resolvable: false,
  notes: [
    makeNote({
      id: 'gid://gitlab/Note/13',
      bodyFirstLineHtml: '<p>Duo Code Review has started.</p>',
      author: bot,
      position: null,
    }),
  ],
});

const toggleResolveResponse = ({ id, resolved, errors = [] }) => ({
  data: {
    discussionToggleResolve: {
      __typename: 'DiscussionToggleResolvePayload',
      discussion: { __typename: 'Discussion', id, resolved },
      errors,
    },
  },
});

const createNoteResponse = ({ discussion = makeDiscussion(), errors = [] } = {}) => ({
  data: {
    createNote: {
      __typename: 'CreateNotePayload',
      note: errors.length ? null : { __typename: 'Note', id: 'gid://gitlab/Note/99', discussion },
      errors,
    },
  },
});

const reply = makeNote({
  id: 'gid://gitlab/DiffNote/99',
  bodyFirstLineHtml: '<p>On it.</p>',
  author: commenter,
});
const repliedThread = makeDiscussion({ notes: [...openThread.notes.nodes, reply] });
const newThread = makeDiscussion({
  id: 'gid://gitlab/Discussion/5',
  resolvable: false,
  notes: [
    makeNote({
      id: 'gid://gitlab/Note/98',
      bodyFirstLineHtml: '<p>Looks good.</p>',
      author: commenter,
      position: null,
    }),
  ],
});

describe('AI Overview discussions panel', () => {
  let wrapper;
  let queryHandler;
  let toggleResolveHandler;
  let createNoteHandler;

  const createComponent = ({
    handler,
    resolveHandler = jest.fn(({ id, resolve }) =>
      Promise.resolve(toggleResolveResponse({ id, resolved: resolve })),
    ),
    noteHandler = jest.fn().mockResolvedValue(createNoteResponse()),
    mergeRequest = makeMergeRequest(),
  } = {}) => {
    queryHandler =
      handler ??
      jest
        .fn()
        .mockResolvedValue(
          discussionsResponse({ nodes: [openThread, resolvedThread, agentComment] }),
        );
    toggleResolveHandler = resolveHandler;
    createNoteHandler = noteHandler;

    wrapper = mountExtended(DiscussionsPanel, {
      apolloProvider: createMockApollo([
        [discussionsQuery, queryHandler],
        [toggleResolveMutation, toggleResolveHandler],
        [createNoteMutation, createNoteHandler],
      ]),
      propsData: { mergeRequest },
      provide: { projectPath: 'group/proj', iid: '1' },
    });
  };

  const findRows = () => wrapper.findAllByTestId('conversation-row');
  const findRow = (index) => findRows().at(index);
  const findInRow = (index, testId) => findRow(index).find(`[data-testid="${testId}"]`);
  const findStateIcon = (index) =>
    findRow(index)
      .findAllComponents(GlIcon)
      .filter((icon) => icon.attributes('data-testid') === 'conversation-state')
      .at(0);
  const findOpeningBodies = () =>
    findRows().wrappers.map((row) => row.find('[data-testid="conversation-body"]').text());
  const findFilter = () => wrapper.findByTestId('conversations-filter');
  const findBody = () => wrapper.findByTestId('conversations-body');
  const findToggle = () => wrapper.findByTestId('conversations-toggle');
  const findOpenCount = () => wrapper.findByTestId('conversations-open-count');
  const findLoadMore = () => wrapper.findComponentByTestId('conversations-load-more');
  const findForm = () => wrapper.findComponent(ConversationForm);
  const findCommentForm = () => wrapper.findComponentByTestId('conversations-comment-form');
  const FILTER_TEXT = { action: 'Needs action', people: 'People', agents: 'Agents', all: 'All' };
  const findFilterButtons = () => findFilter().findAll('button').wrappers;
  const activeFilterText = () =>
    findFilterButtons()
      .find((button) => button.attributes('aria-pressed') === 'true')
      ?.text();
  const selectFilter = async (filter) => {
    await findFilterButtons()
      .find((button) => button.text() === FILTER_TEXT[filter])
      .trigger('click');
  };

  describe('by default', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('shows only the threads that need action', () => {
      expect(activeFilterText()).toBe('Needs action');
      expect(findOpeningBodies()).toEqual(['Rename this method.']);
    });

    it('offers All last', () => {
      expect(findFilterButtons().map((button) => button.text())).toEqual([
        'Needs action',
        'People',
        'Agents',
        'All',
      ]);
    });
  });

  describe('when nothing needs action', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(discussionsResponse({ nodes: [resolvedThread, agentComment] })),
      });
      await waitForPromises();
      await findToggle().trigger('click');
    });

    it('opens on All instead of an empty list', () => {
      expect(activeFilterText()).toBe('All');
      expect(findOpeningBodies()).toEqual(['Fixed.', 'Duo Code Review has started.']);
    });
  });

  describe('with conversations', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      await selectFilter('all');
    });

    it('fetches only the comment threads for the merge request', () => {
      expect(queryHandler).toHaveBeenCalledWith({ projectPath: 'group/proj', iid: '1' });
    });

    it('lists the threads in the order they were started', () => {
      expect(findOpeningBodies()).toEqual([
        'Rename this method.',
        'Fixed.',
        'Duo Code Review has started.',
      ]);
    });

    it('counts the open threads', () => {
      expect(findOpenCount().text()).toBe('1 open');
    });

    it('links the author', () => {
      const link = findInRow(0, 'conversation-author');

      expect(link.text()).toBe('Priya Nair');
      expect(link.attributes()).toMatchObject({
        href: '/priya',
        'data-user-id': '1',
        'data-username': 'priya',
      });
    });

    it('renders the note as HTML', () => {
      expect(findInRow(0, 'conversation-body').find('code').text()).toBe('method');
    });

    it('shows the state of each thread', () => {
      expect(findStateIcon(0).props()).toMatchObject({
        name: 'check-circle',
        variant: 'default',
        ariaLabel: 'Unresolved',
      });
      expect(findStateIcon(1).props()).toMatchObject({
        name: 'check-circle-filled',
        variant: 'success',
        ariaLabel: 'Resolved',
      });
      expect(findInRow(2, 'conversation-state').exists()).toBe(false);
    });

    it('dims resolved threads', () => {
      expect(findRow(0).classes()).not.toContain('gl-opacity-7');
      expect(findRow(1).classes()).toContain('gl-opacity-7');
    });

    it('shows the replies under the opening note', () => {
      const replies = findInRow(0, 'conversation-replies');

      expect(replies.find('[data-testid="conversation-author"]').text()).toBe('Marco Diaz');
      expect(replies.find('[data-testid="conversation-body"]').text()).toBe('Agreed, renaming it.');
      expect(findInRow(1, 'conversation-replies').exists()).toBe(false);
    });

    it('links a diff thread to its place on the Changes tab', () => {
      const location = findInRow(0, 'conversation-location');

      expect(location.text()).toBe('app/models/user.rb:12');
      expect(location.findComponent(FileIcon).props('fileName')).toBe('app/models/user.rb');
      expect(location.attributes('href')).toBe(
        'http://test.host/group/proj/-/merge_requests/1/diffs?file_path=app%2Fmodels%2Fuser.rb#note_11',
      );
    });

    it('gives a thread outside the diff no location', () => {
      expect(findInRow(2, 'conversation-location').exists()).toBe(false);
    });

    it.each`
      filter      | bodies
      ${'action'} | ${['Rename this method.']}
      ${'people'} | ${['Rename this method.', 'Fixed.']}
      ${'agents'} | ${['Duo Code Review has started.']}
      ${'all'}    | ${['Rename this method.', 'Fixed.', 'Duo Code Review has started.']}
    `('shows only the matching threads for the $filter filter', async ({ filter, bodies }) => {
      await selectFilter(filter);
      await waitForPromises();

      expect(findOpeningBodies()).toEqual(bodies);
    });

    it('does not offer more when there is no next page', () => {
      expect(findLoadMore().exists()).toBe(false);
    });
  });

  describe('with a thread on an older version of the diff', () => {
    beforeEach(async () => {
      const note = makeNote();
      createComponent({
        handler: jest.fn().mockResolvedValue(
          discussionsResponse({
            nodes: [
              makeDiscussion({
                notes: [
                  {
                    ...note,
                    position: { ...note.position, diffRefs: { ...diffRefs, headSha: 'ccc333' } },
                  },
                ],
              }),
            ],
          }),
        ),
      });
      await waitForPromises();
    });

    it('names the file without linking to the Changes tab, where the thread is not shown', () => {
      const location = findInRow(0, 'conversation-location');

      expect(location.text()).toContain('app/models/user.rb:12');
      expect(location.attributes('title')).toBe(
        'Outdated: this thread is on an older version of the diff.',
      );
      // The tooltip is not read out while browsing, so the same text is there for screen readers.
      expect(location.find('.gl-sr-only').text()).toBe(
        'Outdated: this thread is on an older version of the diff.',
      );
      expect(location.attributes('tabindex')).toBe('0');
      expect(location.findComponent(FileIcon).props('fileName')).toBe('app/models/user.rb');
      expect(location.find('a').exists()).toBe(false);
    });
  });

  describe('collapsing', () => {
    it('starts open when threads need attention', async () => {
      createComponent();
      await waitForPromises();

      expect(findBody().element.style.display).toBe('');
      expect(findFilter().exists()).toBe(true);
      expect(findToggle().attributes()).toMatchObject({
        'aria-label': 'Collapse',
        'aria-expanded': 'true',
        'aria-controls': findBody().attributes('id'),
      });
    });

    it('starts closed when nothing needs attention', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(discussionsResponse({ nodes: [resolvedThread, agentComment] })),
      });
      await waitForPromises();

      expect(findBody().element.style.display).toBe('none');
      expect(findToggle().attributes()).toMatchObject({
        'aria-label': 'Expand',
        'aria-expanded': 'false',
      });

      await findToggle().trigger('click');

      expect(findBody().element.style.display).toBe('');
    });

    it('collapses to the heading and open count, and expands again from the toggle', async () => {
      createComponent();
      await waitForPromises();

      await findToggle().trigger('click');

      expect(findBody().element.style.display).toBe('none');
      expect(findOpenCount().text()).toBe('1 open');
      expect(findFilter().exists()).toBe(false);
      expect(findToggle().attributes()).toMatchObject({
        'aria-label': 'Expand',
        'aria-expanded': 'false',
      });

      await findToggle().trigger('click');

      expect(findBody().element.style.display).toBe('');
      expect(findFilter().exists()).toBe(true);
    });
  });

  describe('without conversations', () => {
    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockResolvedValue(discussionsResponse({ nodes: [] })) });
      await waitForPromises();
    });

    it('says there are none', () => {
      expect(wrapper.text()).toContain('No conversations to show.');
    });

    it('does not offer the filter or an open count', () => {
      expect(findFilter().exists()).toBe(false);
      expect(findOpenCount().exists()).toBe(false);
    });
  });

  describe('when no thread matches the filter', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(discussionsResponse({ nodes: [openThread] })),
      });
      await waitForPromises();
      await selectFilter('agents');
      await waitForPromises();
    });

    it('says there are none and keeps the filter', () => {
      expect(findRows()).toHaveLength(0);
      expect(wrapper.text()).toContain('No conversations to show.');
      expect(activeFilterText()).toBe('Agents');
    });
  });

  it('opens to show a loading icon while loading', () => {
    createComponent();

    expect(findBody().element.style.display).toBe('');
    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
  });

  it('opens to report the error when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
    await waitForPromises();

    expect(findBody().element.style.display).toBe('');
    expect(wrapper.text()).toContain('Could not load conversations.');
    expect(Sentry.captureException).toHaveBeenCalled();
  });

  describe('when there are more conversations', () => {
    const nextThread = makeDiscussion({
      id: 'gid://gitlab/Discussion/4',
      notes: [makeNote({ id: 'gid://gitlab/DiffNote/14', bodyFirstLineHtml: '<p>Next page.</p>' })],
    });

    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(
            discussionsResponse({
              nodes: [openThread],
              pageInfo: { hasNextPage: true, endCursor: 'cursor-1' },
            }),
          )
          .mockResolvedValueOnce(discussionsResponse({ nodes: [nextThread] })),
      });
      await waitForPromises();
    });

    it('fetches the next page and appends it', async () => {
      findLoadMore().vm.$emit('click');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith({
        projectPath: 'group/proj',
        iid: '1',
        after: 'cursor-1',
      });
      expect(findOpeningBodies()).toEqual(['Rename this method.', 'Next page.']);
      expect(findLoadMore().exists()).toBe(false);
    });
  });

  describe('when loading more conversations fails', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(
            discussionsResponse({
              nodes: [openThread],
              pageInfo: { hasNextPage: true, endCursor: 'cursor-1' },
            }),
          )
          .mockRejectedValueOnce(new Error('nope')),
      });
      await waitForPromises();
    });

    it('keeps the loaded threads and raises an alert', async () => {
      findLoadMore().vm.$emit('click');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Could not load conversations.' }),
      );
      expect(findOpeningBodies()).toEqual(['Rename this method.']);
    });
  });

  describe('thread actions', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      await selectFilter('all');
    });

    it('offers reply and resolve on an open thread, reopen on a resolved one, nothing on a comment', () => {
      expect(findInRow(0, 'conversation-reply').exists()).toBe(true);
      expect(findInRow(0, 'conversation-resolve').exists()).toBe(true);
      expect(findInRow(1, 'conversation-reopen').exists()).toBe(true);
      expect(findInRow(1, 'conversation-reply').exists()).toBe(false);
      expect(findRow(2).findAll('button')).toHaveLength(0);
    });

    it('highlights the opening note on hover or focus, without a tab stop of its own', () => {
      const opening = findInRow(0, 'conversation-opening');

      expect(opening.attributes('tabindex')).toBeUndefined();
      expect(opening.classes()).toEqual(
        expect.arrayContaining(['gl-group', 'hover:gl-bg-subtle', 'focus-within:gl-bg-subtle']),
      );
      expect(opening.find('[data-testid="conversation-actions"]').exists()).toBe(true);
    });

    it('keeps the replies out of the opening note, each highlighting on its own', () => {
      const opening = findInRow(0, 'conversation-opening');
      const replyRow = findInRow(0, 'conversation-reply-row');

      expect(opening.text()).toContain('Rename this method.');
      expect(opening.text()).not.toContain('Agreed, renaming it.');
      expect(opening.element.contains(replyRow.element)).toBe(false);
      expect(replyRow.text()).toContain('Agreed, renaming it.');
      expect(replyRow.classes()).toContain('hover:gl-bg-subtle');
      expect(replyRow.find('[data-testid="conversation-actions"]').exists()).toBe(false);
    });

    // Transparent rather than hidden, so the buttons stay in the tab order and accessibility tree.
    it('fades the floating actions in on hover, or as soon as one of them takes focus', () => {
      const actions = findInRow(0, 'conversation-actions');

      expect(actions.classes()).toEqual(
        expect.arrayContaining([
          'gl-opacity-0',
          'gl-absolute',
          'group-hover:gl-opacity-10',
          'group-focus-within:gl-opacity-10',
        ]),
      );
      expect(actions.classes()).not.toContain('gl-invisible');
      expect(actions.find('[data-testid="conversation-reply"]').exists()).toBe(true);
      expect(actions.find('[data-testid="conversation-resolve"]').exists()).toBe(true);
    });

    it('labels each action with text beside its icon', () => {
      expect(findInRow(0, 'conversation-reply').text()).toBe('Reply');
      expect(findInRow(0, 'conversation-resolve').text()).toBe('Resolve');
      expect(findInRow(1, 'conversation-reopen').text()).toBe('Reopen thread');
    });

    it('resolves an open thread', async () => {
      findInRow(0, 'conversation-resolve').trigger('click');
      await waitForPromises();

      expect(toggleResolveHandler).toHaveBeenCalledWith({
        id: 'gid://gitlab/Discussion/1',
        resolve: true,
      });
      expect(findStateIcon(0).props('name')).toBe('check-circle-filled');
      expect(findRow(0).classes()).toContain('gl-opacity-7');
      expect(findInRow(0, 'conversation-reopen').exists()).toBe(true);
      expect(findOpenCount().exists()).toBe(false);
      expect(findBody().element.style.display).toBe('');
    });

    it('reopens a resolved thread', async () => {
      findInRow(1, 'conversation-reopen').trigger('click');
      await waitForPromises();

      expect(toggleResolveHandler).toHaveBeenCalledWith({
        id: 'gid://gitlab/Discussion/2',
        resolve: false,
      });
      expect(findStateIcon(1).props('name')).toBe('check-circle');
    });

    describe('when replying', () => {
      beforeEach(async () => {
        findInRow(0, 'conversation-reply').trigger('click');
        await nextTick();
      });

      it('opens the reply form in the thread, in place of the actions', () => {
        expect(findRow(0).findComponent(ConversationForm).exists()).toBe(true);
        expect(findInRow(0, 'conversation-actions').exists()).toBe(false);
      });

      it('posts the reply and shows it under the thread without reloading', async () => {
        createNoteHandler.mockResolvedValue(createNoteResponse({ discussion: repliedThread }));
        findForm().vm.$emit('submit', 'On it.');
        await waitForPromises();

        expect(createNoteHandler).toHaveBeenCalledWith({
          input: {
            noteableId: 'gid://gitlab/MergeRequest/3',
            body: 'On it.',
            discussionId: 'gid://gitlab/Discussion/1',
          },
        });
        expect(queryHandler).toHaveBeenCalledTimes(1);
        // The new-comment form below the threads is always there, so look in the thread.
        expect(findRow(0).findComponent(ConversationForm).exists()).toBe(false);
        expect(
          findInRow(0, 'conversation-replies')
            .findAll('[data-testid="conversation-body"]')
            .wrappers.map((body) => body.text()),
        ).toEqual(['Agreed, renaming it.', 'On it.']);
      });

      it('closes the form on cancel', async () => {
        findForm().vm.$emit('cancel');
        await nextTick();

        expect(findRow(0).findComponent(ConversationForm).exists()).toBe(false);
        expect(findInRow(0, 'conversation-reply').exists()).toBe(true);
      });
    });

    describe('when adding a comment', () => {
      it('posts a new comment, lists it last without reloading, and clears the form', async () => {
        const findTextarea = () => findCommentForm().find('textarea');
        createNoteHandler.mockResolvedValue(createNoteResponse({ discussion: newThread }));
        await findTextarea().setValue('Looks good.');
        await findCommentForm().find('form').trigger('submit');
        await waitForPromises();
        await selectFilter('all');

        expect(createNoteHandler).toHaveBeenCalledWith({
          input: { noteableId: 'gid://gitlab/MergeRequest/3', body: 'Looks good.' },
        });
        expect(queryHandler).toHaveBeenCalledTimes(1);
        expect(findTextarea().element.value).toBe('');
        expect(findOpeningBodies()).toEqual([
          'Rename this method.',
          'Fixed.',
          'Duo Code Review has started.',
          'Looks good.',
        ]);
      });

      it('shows only the submitted form as posting', async () => {
        createNoteHandler.mockReturnValue(new Promise(() => {}));
        findInRow(0, 'conversation-reply').trigger('click');
        await nextTick();
        const [replyForm, commentForm] = wrapper.findAllComponents(ConversationForm).wrappers;
        commentForm.vm.$emit('submit', 'Looks good.');
        await nextTick();

        expect(commentForm.props('loading')).toBe(true);
        expect(replyForm.props('loading')).toBe(false);
      });

      it('leaves an open reply form alone when the comment is posted', async () => {
        createNoteHandler.mockResolvedValue(createNoteResponse({ discussion: newThread }));
        findInRow(0, 'conversation-reply').trigger('click');
        await nextTick();
        const [, commentForm] = wrapper.findAllComponents(ConversationForm).wrappers;
        commentForm.vm.$emit('submit', 'Looks good.');
        await waitForPromises();

        expect(findRow(0).findComponent(ConversationForm).exists()).toBe(true);
        expect(findCommentForm().exists()).toBe(true);
      });
    });

    describe('when adding a comment with pages still to load', () => {
      it('reloads the conversations instead of guessing where the comment goes', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(
            discussionsResponse({
              nodes: [openThread],
              pageInfo: { hasNextPage: true, endCursor: 'cursor-1' },
            }),
          ),
          noteHandler: jest.fn().mockResolvedValue(createNoteResponse({ discussion: newThread })),
        });
        await waitForPromises();
        findCommentForm().vm.$emit('submit', 'Looks good.');
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(2);
        expect(findOpeningBodies()).toEqual(['Rename this method.']);
      });
    });
  });

  describe('when resolving fails', () => {
    beforeEach(async () => {
      createComponent({
        resolveHandler: jest.fn().mockResolvedValue(
          toggleResolveResponse({
            id: 'gid://gitlab/Discussion/1',
            resolved: false,
            errors: ['nope'],
          }),
        ),
      });
      await waitForPromises();
      findInRow(0, 'conversation-resolve').trigger('click');
      await waitForPromises();
    });

    it('raises an alert and leaves the thread open', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Could not update the thread.' }),
      );
      expect(findStateIcon(0).props('name')).toBe('check-circle');
    });
  });

  describe('when posting fails', () => {
    beforeEach(async () => {
      createComponent({
        noteHandler: jest.fn().mockResolvedValue(createNoteResponse({ errors: ['nope'] })),
      });
      await waitForPromises();
      findInRow(0, 'conversation-reply').trigger('click');
      await nextTick();
      findForm().vm.$emit('submit', 'On it.');
      await waitForPromises();
    });

    it('raises an alert and keeps the form open', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Could not post your comment.' }),
      );
      expect(findForm().exists()).toBe(true);
      expect(queryHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('without permission to comment or resolve', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(
          discussionsResponse({
            nodes: [
              makeDiscussion({ resolveNote: false }),
              makeDiscussion({
                id: 'gid://gitlab/Discussion/2',
                resolved: true,
                resolveNote: false,
              }),
            ],
          }),
        ),
        mergeRequest: makeMergeRequest({
          userPermissions: { __typename: 'MergeRequestPermissions', createNote: false },
        }),
      });
      await waitForPromises();
      await selectFilter('all');
    });

    it('offers no reply, resolve, reopen or new comment', () => {
      expect(findRows()).toHaveLength(2);
      expect(wrapper.findAll('button[data-testid^="conversation-"]')).toHaveLength(0);
      expect(findCommentForm().exists()).toBe(false);
    });

    it('leaves no empty actions row behind', () => {
      const blankDivs = Array.from(findRow(0).element.querySelectorAll(':scope > div')).filter(
        (el) => !el.textContent.trim(),
      );

      expect(blankDivs).toHaveLength(0);
    });
  });

  describe('code snippets and suggestions', () => {
    let mockAxios;

    const suggestionNote = (overrides = {}) =>
      makeNote({ suggestions: suggestions(makeSuggestion()), ...overrides });
    const suggestionThread = makeDiscussion({ notes: [suggestionNote()] });
    const outdatedSuggestionThread = makeDiscussion({
      notes: [
        suggestionNote({
          position: { ...makeNote().position, diffRefs: { ...diffRefs, headSha: 'ccc333' } },
        }),
      ],
    });
    const appliedSuggestionThread = makeDiscussion({
      notes: [suggestionNote({ suggestions: suggestions(makeSuggestion({ applied: true })) })],
    });
    const resolvedSuggestionThread = makeDiscussion({ notes: [suggestionNote()], resolved: true });

    const findSnippetLines = (index) =>
      findRow(index)
        .findAll('[data-testid="conversation-snippet"] > div')
        .wrappers.map((line) => line.text().replace(/\s+/g, ' '));
    const findApply = (index) => findInRow(index, 'conversation-apply');

    const createWith = async (nodes, mergeRequest = makeMergeRequest()) => {
      createComponent({
        handler: jest.fn().mockResolvedValue(discussionsResponse({ nodes })),
        mergeRequest,
      });
      await waitForPromises();
    };

    beforeEach(() => {
      window.gon.api_version = 'v4';
      mockAxios = new MockAdapter(axios);
    });

    afterEach(() => {
      mockAxios.restore();
    });

    it('shows a suggestion as the lines it removes and adds', async () => {
      await createWith([suggestionThread]);

      expect(findSnippetLines(0)).toEqual(['- def greet', '+ def say_hello']);
    });

    it('shows the last commented lines of a diff thread without a suggestion', async () => {
      await createWith([
        makeDiscussion({
          truncatedDiffLines: [
            diffLine('match', '@@ -1,3 +1,4 @@'),
            diffLine(null, ' class Greeter'),
            diffLine('old', '-  def hello'),
            diffLine('new', '+  def greet'),
            diffLine('new', '+    puts "hi"'),
          ],
        }),
      ]);

      expect(findSnippetLines(0)).toEqual(['- def hello', '+ def greet', '+ puts "hi"']);
    });

    it('shows no snippet for a thread outside the diff', async () => {
      await createWith([makeDiscussion({ notes: [makeNote({ position: null })] })]);

      expect(findInRow(0, 'conversation-snippet').exists()).toBe(false);
    });

    it('offers to apply a pending suggestion on an open, current thread', async () => {
      await createWith([suggestionThread]);

      expect(findInRow(0, 'conversation-suggestion').text()).toContain('Suggested change ready');
      expect(findApply(0).exists()).toBe(true);
    });

    const cannotPush = makeMergeRequest({
      userPermissions: {
        __typename: 'MergeRequestPermissions',
        createNote: true,
        pushToSourceBranch: false,
      },
    });

    it.each`
      description                                    | thread                      | mergeRequest
      ${'the thread is outdated'}                    | ${outdatedSuggestionThread} | ${undefined}
      ${'the suggestion is already applied'}         | ${appliedSuggestionThread}  | ${undefined}
      ${'the thread is resolved'}                    | ${resolvedSuggestionThread} | ${undefined}
      ${'the user cannot push to the source branch'} | ${suggestionThread}         | ${cannotPush}
    `('does not offer to apply when $description', async ({ thread, mergeRequest }) => {
      await createWith([thread], mergeRequest);

      expect(findInRow(0, 'conversation-suggestion').exists()).toBe(false);
    });

    describe('when applying', () => {
      beforeEach(async () => {
        await createWith([suggestionThread]);
      });

      it('applies the suggestion, resolves the thread and reloads the conversations', async () => {
        mockAxios.onPut('/api/v4/suggestions/18/apply').reply(HTTP_STATUS_OK, {});

        findApply(0).trigger('click');
        await waitForPromises();

        expect(mockAxios.history.put).toHaveLength(1);
        expect(toggleResolveHandler).toHaveBeenCalledWith({
          id: 'gid://gitlab/Discussion/1',
          resolve: true,
        });
        expect(queryHandler).toHaveBeenCalledTimes(2);
      });

      it('shows the reason when the suggestion cannot be applied', async () => {
        mockAxios
          .onPut('/api/v4/suggestions/18/apply')
          .reply(HTTP_STATUS_BAD_REQUEST, { message: 'A suggestion is not applicable.' });

        findApply(0).trigger('click');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'A suggestion is not applicable.' }),
        );
        expect(toggleResolveHandler).not.toHaveBeenCalled();
      });
    });

    it('applies several suggestions from one note together', async () => {
      await createWith([
        makeDiscussion({
          notes: [
            makeNote({
              suggestions: suggestions(
                makeSuggestion(),
                makeSuggestion({ id: 'gid://gitlab/Suggestion/19' }),
              ),
            }),
          ],
        }),
      ]);
      mockAxios.onPut('/api/v4/suggestions/batch_apply').reply(HTTP_STATUS_OK, {});

      findApply(0).trigger('click');
      await waitForPromises();

      expect(JSON.parse(mockAxios.history.put[0].data)).toEqual({ ids: [18, 19] });
    });
  });
});
