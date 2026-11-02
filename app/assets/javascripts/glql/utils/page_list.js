// The pages a paged table has fetched, and which one is on screen. Plain objects in, new plain
// objects out, so the resolver's reactive state never holds a class instance.

export const emptyPageList = () => ({ pages: [], index: 0 });

export const startPageList = (page) => ({ pages: [page], index: 0 });

export const currentPage = ({ pages, index }) => pages[index];

export const hasPreviousPage = ({ index }) => index > 0;

export const hasCachedNextPage = ({ pages, index }) => index + 1 < pages.length;

export const goToPage = (list, index) => ({ ...list, index });

export const appendPage = ({ pages }, page) => ({ pages: [...pages, page], index: pages.length });

export const markCurrentPageAsLast = ({ pages, index }) => ({
  pages: pages.map((page, i) =>
    i === index ? { ...page, pageInfo: { ...page.pageInfo, hasNextPage: false } } : page,
  ),
  index,
});
