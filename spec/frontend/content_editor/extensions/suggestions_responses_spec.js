import tippy from 'tippy.js';
import { nextTick } from 'vue';
import waitForPromises from 'helpers/wait_for_promises';
import Suggestions from '~/content_editor/extensions/suggestions';
import Reference from '~/content_editor/extensions/reference';
import { createTestEditor } from '../test_utils';

jest.mock('tippy.js');

const ROSIE = { username: 'rosie', name: 'Rosie Rivers' };
const ROOT = { username: 'root', name: 'Administrator' };
const RONNIE = { username: 'ronnie', name: 'Ronnie Rhodes' };

// The popup receives its items through VueRenderer.updateProps, which cannot
// mutate props under @vue/compat, so the popup never gets them. Tracked in
// https://gitlab.com/groups/gitlab-org/-/epics/6252
const describeSkipVue3 = process.env.VUE_VERSION === '3' ? describe.skip : describe;

describeSkipVue3('content_editor/extensions/suggestions responses', () => {
  let editor;
  let popupContent;
  let searches;

  const type = async (text) => {
    editor.commands.insertContent(text);
    await waitForPromises();
    await nextTick();
  };

  const respond = async (query, items) => {
    searches[query].resolve(items);
    await waitForPromises();
    await nextTick();
  };

  // Each item reads like "R rosie Rosie Rivers": avatar initial, username, name.
  const shownUsernames = () =>
    [...popupContent.querySelectorAll('li')].map((li) => li.textContent.match(/\b[a-z]+\b/)[0]);

  beforeEach(() => {
    searches = {};
    tippy.mockImplementation((_, options) => {
      popupContent = options.content;
      return [{ setProps: jest.fn(), destroy: jest.fn(), hide: jest.fn() }];
    });

    const autocompleteHelper = {
      getDataSource: () => ({
        search: (_prefixCommand, query, { onRefine }) =>
          new Promise((resolve) => {
            searches[query] = { resolve, onRefine };
          }),
      }),
    };

    editor = createTestEditor({
      extensions: [
        Reference.configure({ assetResolver: { resolveReference: () => Promise.resolve({}) } }),
        Suggestions.configure({ autocompleteHelper, serializer: { serialize: () => '' } }),
      ],
    });
  });

  afterEach(() => {
    editor.destroy();
  });

  it('keeps the list when an earlier search finishes after a later one started', async () => {
    await type('@');
    await respond('', [ROSIE, ROOT]);
    await type('r');
    await type('o');

    await respond('r', [ROSIE, ROOT]);

    // Still the list for "@", sorted alphabetically for the empty query.
    expect(shownUsernames()).toEqual(['root', 'rosie']);

    await respond('ro', [ROSIE]);

    expect(shownUsernames()).toEqual(['rosie']);
  });

  it('shows refined results for the current query', async () => {
    await type('@ro');
    await respond('ro', [ROSIE]);

    searches.ro.onRefine([ROSIE, RONNIE]);
    await nextTick();

    expect(shownUsernames()).toEqual(['rosie', 'ronnie']);
  });

  it('ignores refined results for a query that is no longer typed', async () => {
    await type('@r');
    await respond('r', [ROSIE, ROOT]);
    await type('o');
    await respond('ro', [ROSIE]);

    searches.r.onRefine([ROSIE, ROOT, RONNIE]);
    await nextTick();

    expect(shownUsernames()).toEqual(['rosie']);
  });

  it('ignores refined results for an earlier mention of the same query', async () => {
    await type('@ro');
    await respond('ro', [ROSIE]);
    const { onRefine: refineFirstMention } = searches.ro;
    await type(' and @ro');
    await respond('ro', [ROSIE]);

    refineFirstMention([ROSIE, RONNIE]);
    await nextTick();

    expect(shownUsernames()).toEqual(['rosie']);
  });
});
