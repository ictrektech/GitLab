import MockAdapter from 'axios-mock-adapter';
import fuzzaldrinPlus from 'fuzzaldrin-plus';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import AutocompleteHelper, {
  defaultSorter,
  commandSorter,
  customSorter,
  createDataSource,
} from '~/content_editor/services/autocomplete_helper';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { EMOJI_THUMBS_UP } from '~/emoji/constants';
import {
  MOCK_MEMBERS,
  MOCK_COMMANDS,
  MOCK_EPICS,
  MOCK_ISSUES,
  MOCK_LABELS,
  MOCK_MILESTONES,
  MOCK_ITERATIONS,
  MOCK_SNIPPETS,
  MOCK_VULNERABILITIES,
  MOCK_MERGE_REQUESTS,
  MOCK_ASSIGNEES,
  MOCK_REVIEWERS,
  MOCK_WIKIS,
  MOCK_NEW_MEMBERS,
} from './autocomplete_mock_data';

jest.mock('~/emoji', () => ({
  initEmojiMap: () => jest.fn(),
  getAllEmoji: () => [{ name: 'thumbsup' }],
}));

jest.mock('~/graphql_shared/issuable_client_state', () => ({
  currentAssignees: jest.fn().mockReturnValue({
    1: [
      {
        type: 'User',
        username: 'errol',
        name: "Linnie O'Connell",
        avatar_url:
          'https://www.gravatar.com/avatar/d3d9a468a9884eb217fad5ca5b2b9bd7?s=80\u0026d=identicon',
        availability: null,
      },
      {
        type: 'User',
        username: 'evelynn_olson',
        name: 'Dimple Dare',
        avatar_url:
          'https://www.gravatar.com/avatar/bc1e51ee3512c2b4442f51732d655107?s=80\u0026d=identicon',
        availability: null,
      },
    ],
  }),
  linkedItems: jest.fn().mockReturnValue({
    'gitlab-org/gitlab-test:1': [
      {
        iid: 31,
        title: 'rdfhdfj',
        id: null,
        workItemType: {
          __typename: 'WorkItemType',
          id: 'gid://gitlab/WorkItems::Type/1',
          name: 'Issue',
          iconName: 'work-item-issue',
        },
      },
      {
        iid: 30,
        title: 'incident1',
        id: null,
        workItemType: {
          __typename: 'WorkItemType',
          id: 'gid://gitlab/WorkItems::Type/1',
          name: 'Issue',
          iconName: 'work-item-issue',
        },
      },
    ],
  }),
  appliedLabels: jest.fn().mockReturnValue({
    1: [
      {
        id: 'gid://gitlab/Label/1',
        title: 'bug',
        color: '#d9534f',
        textColor: '#FFFFFF',
      },
      {
        id: 'gid://gitlab/Label/2',
        title: 'feature',
        color: '#428bca',
        textColor: '#FFFFFF',
      },
    ],
  }),
  availableStatuses: jest.fn().mockReturnValue({
    'gitlab-org/gitlab-test': {
      'gid://gitlab/WorkItems::Type/1': [
        {
          __typename: 'WorkItemStatus',
          id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/1',
          name: 'To do',
          description: null,
          iconName: 'status-waiting',
          color: '#737278',
          position: 0,
        },
        {
          __typename: 'WorkItemStatus',
          id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/2',
          name: 'In progress',
          description: null,
          iconName: 'status-running',
          color: '#1f75cb',
          position: 0,
        },
        {
          __typename: 'WorkItemStatus',
          id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/3',
          name: 'Done',
          description: null,
          iconName: 'status-success',
          color: '#108548',
          position: 0,
        },
        {
          __typename: 'WorkItemStatus',
          id: 'gid://gitlab/WorkItems::Statuses::Custom::Status/4',
          name: "Won't do",
          description: null,
          iconName: 'status-cancelled',
          color: '#DD2B0E',
          position: 0,
        },
      ],
    },
  }),
  supportedConversionTypes: jest.fn().mockReturnValue({
    'gitlab-org/gitlab-test': {
      'gid://gitlab/WorkItems::Type/1': [
        {
          id: 'gid://gitlab/WorkItems::Type/2',
          name: 'Task',
          iconName: 'issue-type-task',
        },
        {
          id: 'gid://gitlab/WorkItems::Type/3',
          name: 'Incident',
          iconName: 'issue-type-incident',
        },
        {
          id: 'gid://gitlab/WorkItems::Type/4',
          name: 'Issue',
          iconName: 'issue-type-issue',
        },
      ],
    },
  }),
}));

describe('defaultSorter', () => {
  it('returns items as is if query is empty', () => {
    const items = [{ name: 'abc' }, { name: 'bcd' }, { name: 'cde' }];
    const sorter = defaultSorter(['name']);
    expect(sorter(items, '')).toEqual(items);
  });

  it('sorts items based on query match', () => {
    const items = [{ name: 'abc' }, { name: 'bcd' }, { name: 'cde' }];
    const sorter = defaultSorter(['name']);
    expect(sorter(items, 'b')).toEqual([{ name: 'bcd' }, { name: 'abc' }, { name: 'cde' }]);
  });

  it('sorts items based on query match in multiple fields', () => {
    const items = [
      { name: 'wabc', description: 'xyz' },
      { name: 'bcd', description: 'wxy' },
      { name: 'cde', description: 'vwx' },
    ];
    const sorter = defaultSorter(['name', 'description']);
    expect(sorter(items, 'w')).toEqual([
      { name: 'wabc', description: 'xyz' },
      { name: 'bcd', description: 'wxy' },
      { name: 'cde', description: 'vwx' },
    ]);
  });
});

describe('commandSorter', () => {
  const sorter = commandSorter(['name', 'search']);
  it('returns items as is if query is empty', () => {
    const items = [
      { name: 'assign', aliases: [] },
      { name: 'close', aliases: [] },
    ];
    expect(sorter(items, '')).toBe(items);
  });
  it('falls back to default sorter when no aliases match', () => {
    const items = [
      { name: 'abc', aliases: [], search: 'abc' },
      { name: 'bcd', aliases: [], search: 'bcd' },
    ];
    expect(sorter(items, 'b')[0].name).toBe('bcd');
  });
  it('ranks name prefix above alias prefix above substring', () => {
    const items = [
      { name: 'close', aliases: [] },
      { name: 'request_review', aliases: ['assign_reviewer', 'reviewer'] },
      { name: 'assign', aliases: [] },
    ];
    expect(sorter(items, 'assign').map((i) => i.name)).toEqual([
      'assign', // name starts with 'assign'
      'request_review', // alias 'assign_reviewer' starts with 'assign'
      'close', // no match
    ]);
  });
});

describe('customSorter', () => {
  it('sorts items based on custom sorter function', () => {
    const items = [3, 1, 2];
    const sorter = customSorter((a, b) => a - b);
    expect(sorter(items)).toEqual([1, 2, 3]);
  });
});

describe('createDataSource', () => {
  let mock;

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  describe('on fetch success', () => {
    const dataSourceParams = {
      source: '/source',
      searchFields: ['name', 'description'],
    };

    beforeEach(() => {
      const data = [
        { name: 'abc', description: 'xyz' },
        { name: 'bcd', description: 'wxy' },
        { name: 'cde', description: 'vwx' },
      ];
      mock.onGet('/source').reply(HTTP_STATUS_OK, data);
    });

    it('fetches data from source and filters based on query', async () => {
      const dataSource = createDataSource(dataSourceParams);

      const results = await dataSource.search('', 'b');
      expect(results).toEqual([
        { name: 'bcd', description: 'wxy' },
        { name: 'abc', description: 'xyz' },
      ]);
    });
  });

  it('handles source fetch errors', async () => {
    mock.onGet('/source').reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

    const dataSource = createDataSource({
      source: '/source',
      searchFields: ['name', 'description'],
      sorter: (items) => items,
    });

    const results = await dataSource.search('', 'b');
    expect(results).toEqual([]);
  });

  it('memoizes fetch across different prefixCommand and query values', async () => {
    mock.onGet('/source').reply(HTTP_STATUS_OK, [{ name: 'rebase' }]);

    const dataSource = createDataSource({
      source: '/source',
      searchFields: ['name'],
    });

    await dataSource.search('/r', 'r');
    await dataSource.search('/re', 're');
    await dataSource.search('/rel', 'rel');

    expect(mock.history.get).toHaveLength(1);
  });

  it('floats mentioned usernames to the top before applying the limit', async () => {
    mock
      .onGet('/source')
      .reply(HTTP_STATUS_OK, [{ username: 'aaa' }, { username: 'bbb' }, { username: 'ccc' }]);

    const dataSource = createDataSource({
      source: '/source',
      searchFields: ['username'],
      limit: 2,
    });

    const results = await dataSource.search('/assign', '', { prioritizeUsernames: ['ccc'] });

    expect(results).toEqual([{ username: 'ccc' }, { username: 'aaa' }]);
  });

  it('sends mentioned usernames to the backend when provided', async () => {
    mock.onGet('/source').reply(HTTP_STATUS_OK, []);

    const dataSource = createDataSource({
      source: '/source',
      searchFields: ['username'],
      filterOnBackend: true,
    });

    await dataSource.search('/assign', 'foo', { prioritizeUsernames: ['deloras', 'arlie'] });

    expect(mock.history.get[0].params).toEqual({ search: 'foo', mentioned: ['deloras', 'arlie'] });
  });

  it('omits the mentioned param when no users are mentioned', async () => {
    mock.onGet('/source').reply(HTTP_STATUS_OK, []);

    const dataSource = createDataSource({
      source: '/source',
      searchFields: ['username'],
      filterOnBackend: true,
    });

    await dataSource.search('/assign', 'foo');

    expect(mock.history.get[0].params).toEqual({ search: 'foo' });
  });

  describe('when filtering on the backend', () => {
    const MEMBERS = [{ username: 'mkaplan' }, { username: 'mkozono' }, { username: 'root' }];
    const MKO_MEMBERS = [{ username: 'mkozono' }, { username: 'mkozonek' }];
    const pending = () => new Promise(() => {});
    const searchParams = () => mock.history.get.map(({ params }) => params.search);

    let dataSource;
    let onRefine;

    const search = (query) => dataSource.search('', query, { onRefine });

    beforeEach(() => {
      // Make the lodash-es debounce mock wait, so bursts of keystrokes collapse.
      global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = DEFAULT_DEBOUNCE_AND_THROTTLE_MS;
      onRefine = jest.fn();
      dataSource = createDataSource({
        source: '/source',
        searchFields: ['username'],
        filterOnBackend: true,
      });
      mock.onGet('/source', { params: { search: '' } }).reply(HTTP_STATUS_OK, MEMBERS);
    });

    afterEach(() => {
      global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = undefined;
    });

    it('waits for the backend when nothing has loaded yet', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(HTTP_STATUS_OK, MKO_MEMBERS);

      expect(await search('mko')).toEqual(MKO_MEMBERS);
      expect(searchParams()).toEqual(['mko']);
    });

    it('narrows the results of a shorter search without waiting for the backend', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(pending);
      await search('');

      expect(await search('mko')).toEqual([{ username: 'mkozono' }]);
    });

    it('passes the backend results to onRefine once they arrive', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(HTTP_STATUS_OK, MKO_MEMBERS);
      await search('');

      await search('mko');
      expect(onRefine).not.toHaveBeenCalled();

      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(onRefine).toHaveBeenCalledTimes(1);
      expect(onRefine).toHaveBeenCalledWith(MKO_MEMBERS);
    });

    it('waits for typing to pause before searching the backend', async () => {
      await search('');

      await search('mko');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS - 1);
      await waitForPromises();

      expect(searchParams()).toEqual(['']);
    });

    it('does not search for a query the user has since deleted', async () => {
      await search('');

      await search('mko');
      await search('');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['']);
    });

    it('does not search the backend again without an onRefine callback', async () => {
      await dataSource.search('', '');

      await dataSource.search('', 'mko');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['']);
    });

    it('does not call onRefine when the backend search fails', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      await search('');

      await search('mko');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['', 'mko']);
      expect(onRefine).not.toHaveBeenCalled();
    });

    it('does not call onRefine when the backend results match the narrowed results', async () => {
      mock
        .onGet('/source', { params: { search: 'mkoz' } })
        .reply(HTTP_STATUS_OK, [{ username: 'mkozono' }]);
      await search('');

      await search('mkoz');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['', 'mkoz']);
      expect(onRefine).not.toHaveBeenCalled();
    });

    it('sends one backend search for a burst of keystrokes', async () => {
      mock.onGet('/source').reply(HTTP_STATUS_OK, MKO_MEMBERS);
      await search('');

      await search('m');
      await search('mk');
      await search('mko');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['', 'mko']);
      expect(onRefine).toHaveBeenCalledTimes(1);
    });

    it('reuses the backend results for a query it already searched', async () => {
      await search('');
      await search('');

      expect(searchParams()).toEqual(['']);
    });

    it('narrows a shorter search that is still in flight instead of sending another', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(pending);

      const results = Promise.all([search(''), search('mko')]);

      expect(await results).toEqual([MEMBERS, [{ username: 'mkozono' }]]);
      expect(searchParams()).toEqual(['']);
    });

    it('narrows loaded results instead of waiting for a longer query in flight', async () => {
      mock.onGet('/source', { params: { search: 'mko' } }).reply(pending);
      await search('');
      await search('mko');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(await search('mkoz')).toEqual([{ username: 'mkozono' }]);
      expect(searchParams()).toEqual(['', 'mko']);
    });

    it('keeps backend searches that found nothing', async () => {
      mock.onGet('/source', { params: { search: 'zzz' } }).reply(HTTP_STATUS_OK, []);
      await search('');
      await search('zzz');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      await search('zzz');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
      await waitForPromises();

      expect(searchParams()).toEqual(['', 'zzz']);
    });

    describe('when 50 searches are already kept', () => {
      const first50 = Array.from({ length: 50 }, (_, i) => `q${String(i).padStart(2, '0')}`);
      const searchInOrder = (queries) =>
        queries.reduce(
          (previous, query) => previous.then(() => dataSource.search('', query)),
          Promise.resolve(),
        );
      const requestsFor = (query) => searchParams().filter((param) => param === query).length;

      beforeEach(() => {
        mock.onGet('/source').reply(HTTP_STATUS_OK, []);
      });

      it('forgets the least recently used search', async () => {
        await searchInOrder([...first50, 'q50', 'q00']);

        expect(requestsFor('q00')).toBe(2);
      });

      it('keeps a search that was used again recently', async () => {
        await searchInOrder([...first50, 'q00', 'q50', 'q00', 'q01']);

        expect(requestsFor('q00')).toBe(1);
        expect(requestsFor('q01')).toBe(2);
      });
    });

    it('searches again after a failed request', async () => {
      mock.resetHandlers();
      mock.onGet('/source').replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      mock.onGet('/source').replyOnce(HTTP_STATUS_OK, MEMBERS);

      expect(await search('')).toEqual([]);
      expect(await search('')).toEqual(MEMBERS);
    });
  });
});

describe('AutocompleteHelper', () => {
  let mock;
  let autocompleteHelper;
  let dateNowOld;
  let dataSourceUrls;

  beforeEach(() => {
    mock = new MockAdapter(axios);
    dataSourceUrls = {
      members: '/members',
      issues: '/issues',
      snippets: '/snippets',
      labels: '/labels',
      epics: '/epics',
      milestones: '/milestones',
      iterations: '/iterations',
      mergeRequests: '/mergeRequests',
      vulnerabilities: '/vulnerabilities',
      commands: '/commands',
      wikis: '/wikis',
    };

    mock.onGet('/members').reply(HTTP_STATUS_OK, MOCK_MEMBERS);
    mock.onGet('/issues').reply(HTTP_STATUS_OK, MOCK_ISSUES);
    mock.onGet('/snippets').reply(HTTP_STATUS_OK, MOCK_SNIPPETS);
    mock.onGet('/labels').reply(HTTP_STATUS_OK, MOCK_LABELS);
    mock.onGet('/epics').reply(HTTP_STATUS_OK, MOCK_EPICS);
    mock.onGet('/milestones').reply(HTTP_STATUS_OK, MOCK_MILESTONES);
    mock.onGet('/iterations').reply(HTTP_STATUS_OK, MOCK_ITERATIONS);
    mock.onGet('/mergeRequests').reply(HTTP_STATUS_OK, MOCK_MERGE_REQUESTS);
    mock.onGet('/vulnerabilities').reply(HTTP_STATUS_OK, MOCK_VULNERABILITIES);
    mock.onGet('/commands').reply(HTTP_STATUS_OK, MOCK_COMMANDS);
    mock.onGet('/wikis').reply(HTTP_STATUS_OK, MOCK_WIKIS);

    mock.onGet('/new/members').reply(HTTP_STATUS_OK, MOCK_NEW_MEMBERS);

    const sidebarMediator = {
      store: {
        assignees: MOCK_ASSIGNEES,
        reviewers: MOCK_REVIEWERS,
      },
    };

    autocompleteHelper = new AutocompleteHelper({
      dataSourceUrls,
      sidebarMediator,
    });

    dateNowOld = Date.now();

    jest.spyOn(Date, 'now').mockImplementation(() => new Date('2023-11-14').getTime());
  });

  afterEach(() => {
    mock.restore();

    delete gl.GfmAutoComplete;

    jest.spyOn(Date, 'now').mockImplementation(() => dateNowOld);
  });

  it.each`
    referenceType      | query
    ${'user'}          | ${'r'}
    ${'issue'}         | ${'q'}
    ${'snippet'}       | ${'s'}
    ${'label'}         | ${'bc'}
    ${'epic'}          | ${'n'}
    ${'milestone'}     | ${'16'}
    ${'iteration'}     | ${'27'}
    ${'merge_request'} | ${'n'}
    ${'vulnerability'} | ${'cross'}
    ${'command'}       | ${'re'}
    ${'wiki'}          | ${'ho'}
  `(
    'for reference type "$referenceType", searches for "$query" correctly',
    async ({ referenceType, query }) => {
      const dataSource = autocompleteHelper.getDataSource(referenceType);
      const results = await dataSource.search('', query);

      expect(
        results.map(({ title, name, username }) => username || name || title),
      ).toMatchSnapshot();
    },
  );

  it.each`
    referenceType | command
    ${'label'}    | ${'/label'}
    ${'label'}    | ${'/unlabel'}
    ${'label'}    | ${'/relabel'}
    ${'user'}     | ${'/assign'}
    ${'user'}     | ${'/reassign'}
    ${'user'}     | ${'/unassign'}
    ${'user'}     | ${'/assign_reviewer'}
    ${'user'}     | ${'/unassign_reviewer'}
    ${'user'}     | ${'/reassign_reviewer'}
  `(
    'filters items based on command "$command" for reference type "$referenceType" and command',
    async ({ referenceType, command }) => {
      const dataSource = autocompleteHelper.getDataSource(referenceType, { command });
      const results = await dataSource.search();

      expect(
        results.map(({ username, name, title }) => username || name || title),
      ).toMatchSnapshot();
    },
  );

  describe('when the form excludes commands', () => {
    beforeEach(() => {
      setHTMLFixture('<div data-exclude-commands="shrug, confidential"><div></div></div>');
      autocompleteHelper.tiptapEditor = { view: { dom: document.querySelector('div > div') } };
    });

    afterEach(() => {
      resetHTMLFixture();
    });

    it.each(['shrug', 'confidential'])('leaves /%s out of the results', async (name) => {
      const results = await autocompleteHelper.getDataSource('command').search('', name);

      expect(results).toEqual([]);
    });

    it('keeps the other commands', async () => {
      const results = await autocompleteHelper.getDataSource('command').search('', 'tableflip');

      expect(results.map(({ name }) => name)).toEqual(['tableflip']);
    });
  });

  describe('for work items', () => {
    beforeEach(() => {
      document.body.dataset.page = 'projects:work_items:show';

      autocompleteHelper = new AutocompleteHelper({
        dataSourceUrls,
        sidebarMediator: {
          store: { assignees: [], reviewers: [] },
        },
      });

      autocompleteHelper.tiptapEditor = {
        view: {
          dom: {
            closest: () => ({
              dataset: {
                workItemFullPath: 'gitlab-org/gitlab-test',
                workItemTypeId: 'gid://gitlab/WorkItems::Type/1',
                workItemId: '1',
                workItemIid: '1',
              },
            }),
          },
        },
      };
    });

    afterEach(() => {
      delete document.body.dataset.page;
    });

    it('for /unassign, returns only assigned users from apollo cache', async () => {
      const dataSource = autocompleteHelper.getDataSource('user', { command: '/unassign' });
      const results = await dataSource.search('/unassign');

      expect(results.map(({ username }) => username)).toMatchSnapshot();
    });

    it('for /assign, filters out assigned users using apollo cache', async () => {
      const dataSource = autocompleteHelper.getDataSource('user', { command: '/assign' });
      const results = await dataSource.search('/assign');

      expect(results.map(({ username }) => username)).toMatchSnapshot();
    });

    it.each`
      command
      ${'/unlink'}
    `('filters work items using apollo cache for command "$command"', async ({ command }) => {
      const dataSource = autocompleteHelper.getDataSource('issue', { command });
      const results = await dataSource.search(command);

      expect(results.map(({ iid }) => iid)).toMatchSnapshot();
    });

    it.each`
      command
      ${'/unlabel'}
    `('filters labels using apollo cache for command "$command"', async ({ command }) => {
      const dataSource = autocompleteHelper.getDataSource('label', { command });
      const results = await dataSource.search(command);

      expect(results.map(({ title }) => title)).toMatchSnapshot();
    });

    it.each`
      command      | query
      ${'/status'} | ${''}
      ${'/status'} | ${'pro'}
    `(
      'filters statuses using apollo cache for command "$command "$query"',
      async ({ command, query }) => {
        const dataSource = autocompleteHelper.getDataSource('status', { command });
        const results = await dataSource.search(command, query);
        expect(results.map(({ name }) => name)).toMatchSnapshot();
      },
    );

    it.each`
      command    | query
      ${'/type'} | ${''}
      ${'/type'} | ${'ta'}
    `(
      'filters types using apollo cache for command "$command "$query"',
      async ({ command, query }) => {
        const dataSource = autocompleteHelper.getDataSource('type', { command });
        const results = await dataSource.search(command, query);
        expect(results.map(({ name }) => name)).toMatchSnapshot();
      },
    );
  });

  it('filters labels using fuzzy search', async () => {
    const filterSpy = jest.spyOn(fuzzaldrinPlus, 'filter');
    const dataSource = autocompleteHelper.getDataSource('label', { command: '/label' });
    await dataSource.search('', 'bc');

    expect(filterSpy).toHaveBeenCalledWith(
      expect.any(Array),
      'bc',
      expect.objectContaining({
        key: ['title'],
      }),
    );
  });

  it('filters items correctly for the second time, when the first command was different', async () => {
    let dataSource = autocompleteHelper.getDataSource('label', { command: '/label' });
    let results = await dataSource.search();

    // all labels listed for the first command
    expect(results.map(({ title }) => title)).toEqual([
      'Bronce',
      'Contour',
      'Corolla',
      'Cygsync',
      'Frontier',
      'Grand Am',
      'Onesync',
      'Phone',
      'Pynefunc',
      'Trinix',
      'Trounswood',
      'group::planner intelligence',
      'scoped label',
      'type::one',
      'type::two',
    ]);

    dataSource = autocompleteHelper.getDataSource('label', { command: '/unlabel' });
    results = await dataSource.search();

    // only set labels listed for the second command
    expect(results.map(({ title }) => title)).toEqual(['Amsche', 'Brioffe', 'Bryncefunc', 'Ghost']);
  });

  it('loads default datasources if not passed', () => {
    gl.GfmAutoComplete = {
      dataSources: {
        members: '/gitlab-org/gitlab-test/-/autocomplete_sources/members',
      },
    };
    autocompleteHelper = new AutocompleteHelper({});

    expect(autocompleteHelper.dataSourceUrls.members).toBe(
      '/gitlab-org/gitlab-test/-/autocomplete_sources/members',
    );
  });

  it("loads emoji if dataSources doesn't exist", async () => {
    autocompleteHelper = new AutocompleteHelper({});

    const dataSource = autocompleteHelper.getDataSource('emoji');
    const results = await dataSource.search('', '');

    expect(results).toEqual([{ emoji: { name: EMOJI_THUMBS_UP }, fieldValue: EMOJI_THUMBS_UP }]);
  });

  it('updates dataSourcesUrl correctly', () => {
    const newDataSources = {
      members: '/new/members',
      issues: '/new/issues',
      snippets: '/new/snippets',
      labels: '/new/labels',
      epics: '/new/epics',
      milestones: '/new/milestones',
      iterations: '/new/iterations',
      mergeRequests: '/new/mergeRequests',
      vulnerabilities: '/new/vulnerabilities',
      commands: '/new/commands',
      wikis: '/new/wikis',
    };

    autocompleteHelper.updateDataSources(newDataSources);
    expect(autocompleteHelper.dataSourceUrls).toEqual(newDataSources);
  });

  it('returns expected results before and after updating data sources', async () => {
    // Retrieve the initial data source and search for 'user'
    let dataSource = autocompleteHelper.getDataSource('user');
    let results = await dataSource.search('', '');

    expect(results.map(({ username }) => username)).toMatchSnapshot();

    // Update the data sources
    const newDataSources = {
      members: '/new/members',
    };
    autocompleteHelper.updateDataSources(newDataSources);

    // Retrieve the updated data source and search for 'user'
    dataSource = autocompleteHelper.getDataSource('user');
    results = await dataSource.search('', '');

    expect(results.map(({ username }) => username)).toMatchSnapshot();
  });

  describe('if filterOnBackend: true', () => {
    it('fetches data passing a `search` param', async () => {
      const dataSource = autocompleteHelper.getDataSource('user', { filterOnBackend: true });

      await dataSource.search('', 'bcd');

      expect(mock.history.get[0].params).toEqual({ search: 'bcd' });
    });
  });
});
