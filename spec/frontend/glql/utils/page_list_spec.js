import {
  appendPage,
  currentPage,
  emptyPageList,
  goToPage,
  hasCachedNextPage,
  hasPreviousPage,
  markCurrentPageAsLast,
  startPageList,
} from '~/glql/utils/page_list';

const page = (id, hasNextPage = true) => ({
  nodes: [{ id }],
  pageInfo: { endCursor: `cursor-${id}`, hasNextPage },
});

describe('GLQL page list', () => {
  const first = page(1);
  const second = page(2);

  it('starts empty, with no page and nothing behind it', () => {
    const list = emptyPageList();

    expect(currentPage(list)).toBeUndefined();
    expect(hasPreviousPage(list)).toBe(false);
    expect(hasCachedNextPage(list)).toBe(false);
  });

  it('starts on the first page', () => {
    const list = startPageList(first);

    expect(currentPage(list)).toBe(first);
    expect(hasPreviousPage(list)).toBe(false);
    expect(hasCachedNextPage(list)).toBe(false);
  });

  it('shows an appended page and keeps the earlier one cached', () => {
    const list = appendPage(startPageList(first), second);

    expect(currentPage(list)).toBe(second);
    expect(hasPreviousPage(list)).toBe(true);
    expect(hasCachedNextPage(goToPage(list, 0))).toBe(true);
  });

  it('returns to a cached page without changing the cache', () => {
    const list = appendPage(startPageList(first), second);
    const back = goToPage(list, 0);

    expect(currentPage(back)).toBe(first);
    expect(back.pages).toBe(list.pages);
  });

  it('marks only the page on screen as the last one', () => {
    const list = markCurrentPageAsLast(goToPage(appendPage(startPageList(first), second), 0));

    expect(currentPage(list).pageInfo).toEqual({ endCursor: 'cursor-1', hasNextPage: false });
    expect(list.pages[1]).toBe(second);
  });

  it('does not mutate the list it was given', () => {
    const list = startPageList(first);

    appendPage(list, second);
    markCurrentPageAsLast(list);

    expect(list).toEqual({ pages: [first], index: 0 });
    expect(first.pageInfo.hasNextPage).toBe(true);
  });
});
