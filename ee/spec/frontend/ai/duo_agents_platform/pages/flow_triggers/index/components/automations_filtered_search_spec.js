import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import { FILTERED_SEARCH_TERM } from '~/vue_shared/components/filtered_search_bar/constants';
import AutomationsFilteredSearch from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automations_filtered_search.vue';

describe('AutomationsFilteredSearch', () => {
  let wrapper;

  const findScheduledButton = () => wrapper.findComponentByTestId('kind-scheduled');
  const findEventButton = () => wrapper.findComponentByTestId('kind-event');
  const findFilteredSearchBar = () => wrapper.findComponent(FilteredSearchBar);
  const findTokenTypes = () =>
    findFilteredSearchBar()
      .props('tokens')
      .map(({ type }) => type);

  const routerPush = jest.fn();

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AutomationsFilteredSearch, {
      propsData: { kind: 'scheduled', filters: {}, sort: 'CREATED_DESC', ...props },
      mocks: {
        $route: { query: { kind: 'event', status: 'on', event: 'mention' } },
        $router: { push: routerPush },
      },
    });
  };

  it('renders an icon button for each kind', () => {
    createComponent();

    expect(findScheduledButton().attributes()).toMatchObject({
      'aria-label': 'Scheduled (beta)',
      'aria-pressed': 'true',
    });
    expect(findEventButton().props('icon')).toBe('trigger-source');
    expect(findEventButton().attributes()).toMatchObject({
      'aria-label': 'Event based',
      'aria-pressed': 'false',
    });
  });

  it.each`
    kind           | tokenTypes
    ${'scheduled'} | ${['status', 'last-run']}
    ${'event'}     | ${['status', 'event', 'last-run']}
  `('shows the $tokenTypes tokens for the $kind kind', ({ kind, tokenTypes }) => {
    createComponent({ kind });

    expect(findTokenTypes()).toEqual(tokenTypes);
  });

  it('passes the filters and sort to the filtered search bar', () => {
    createComponent({
      kind: 'event',
      filters: { status: 'on', event: 'mention', last_run: 'failed', search: 'weekly' },
      sort: 'NAME_ASC',
    });

    expect(findFilteredSearchBar().props()).toMatchObject({
      initialSortBy: 'NAME_ASC',
      initialFilterValue: [
        { type: 'status', value: { data: 'on', operator: '=' } },
        { type: 'event', value: { data: 'mention', operator: '=' } },
        { type: 'last-run', value: { data: 'failed', operator: '=' } },
        { type: FILTERED_SEARCH_TERM, value: { data: 'weekly' } },
      ],
    });
  });

  describe('route updates', () => {
    const searchTokens = [
      { type: 'status', value: { data: 'off', operator: '=' } },
      { type: 'last-run', value: { data: 'never', operator: '=' } },
      { type: FILTERED_SEARCH_TERM, value: { data: 'weekly' } },
      { type: FILTERED_SEARCH_TERM, value: { data: 'risk' } },
    ];

    it.each`
      action                                                               | query
      ${() => findScheduledButton().vm.$emit('click')}                     | ${{ kind: 'scheduled', status: 'on' }}
      ${() => findFilteredSearchBar().vm.$emit('on-filter', searchTokens)} | ${{ kind: 'event', status: 'off', last_run: 'never', search: 'weekly risk' }}
      ${() => findFilteredSearchBar().vm.$emit('on-filter', [])}           | ${{ kind: 'event' }}
      ${() => findFilteredSearchBar().vm.$emit('on-sort', 'NAME_DESC')}    | ${{ kind: 'event', status: 'on', event: 'mention', sort: 'NAME_DESC' }}
    `('pushes $query to the route', ({ action, query }) => {
      createComponent({ kind: 'event' });
      action();

      expect(routerPush).toHaveBeenCalledWith({ query });
    });

    it('does not push when the query does not change', () => {
      createComponent({ kind: 'event' });
      findEventButton().vm.$emit('click');

      expect(routerPush).not.toHaveBeenCalled();
    });
  });
});
