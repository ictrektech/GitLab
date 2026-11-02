import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  within,
  screen,
} from 'ee_jest/integration/helpers/test_helpers';
import { activateVariant, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getWorkItemsCountOnly,
  getWorkItemsSlim,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  expectTokensToShow,
  mountListWithQuery,
  useFilterSpec,
} from './filter_shared_test_helpers';

const idOf = (gid) => gid.split('/').pop();
const nodesOf = (variant) => getWorkItemsSlim[variant].data.namespace.workItems.nodes;
const idsOf = (variant) => nodesOf(variant).map(({ id }) => idOf(id));

// Read from the recorded epics so the URL filter and the fixture agree on the Epic type id.
const EPIC_TYPE_ID = idOf(nodesOf('MANY_PAGES_EPICS')[0].workItemType.id);

// Each MANY_PAGES* variant holds 51 work items: pages of 20, 20 and 11, or 50 and 1.
// The epics list is the group list filtered to the Epic type, the URL group_epics_path
// redirects to.
const LISTS = [
  {
    list: 'project',
    variant: 'MANY_PAGES',
    isGroup: false,
    query: '',
    requestVariables: { fullPath: 'gitlab-org/gitlab' },
  },
  {
    list: 'group',
    variant: 'MANY_PAGES_GROUP',
    isGroup: true,
    query: '',
    requestVariables: { fullPath: 'gitlab-org' },
  },
  {
    list: 'epics',
    variant: 'MANY_PAGES_EPICS',
    isGroup: true,
    query: `type[]=${EPIC_TYPE_ID}`,
    requestVariables: {
      fullPath: 'gitlab-org',
      // The list sends a single type id as a scalar, which GraphQL coerces to a list.
      workItemTypeIds: `gid://gitlab/WorkItems::Type/${EPIC_TYPE_ID}`,
    },
  },
];

const searchOf = (...params) => {
  const search = params.filter(Boolean).join('&');
  return search ? `?${search}` : '';
};

const findPagination = () => screen.queryByTestId('list-footer');
const findPrevButton = () => within(findPagination()).queryByTestId('prevButton');
const findNextButton = () => within(findPagination()).queryByTestId('nextButton');
// GlButton renders disabled pagination buttons with aria-disabled, not the disabled attribute.
const isDisabled = (button) => button.getAttribute('aria-disabled') === 'true';
// GlCollapsibleListbox toggles use the ARIA select-only combobox pattern, not the button role.
const findPageSizeToggle = (text) =>
  within(findPagination()).queryAllByRole('combobox', { name: text })[0] ?? null;

const findRowIds = () =>
  [...document.querySelectorAll('[data-testid="issuable-container"]')].map((row) =>
    row.id.replace('issuable_', ''),
  );

const expectRows = (ids) =>
  waitForAssertion(() => {
    expect(findRowIds()).toEqual(ids);
  });

describe('Work items list - pagination', () => {
  useFilterSpec();

  describe('when the URL filters by the Epic type', () => {
    beforeEach(() => {
      activateVariant('getWorkItemsSlimEE', 'MANY_PAGES_EPICS');
      activateVariant('getWorkItemsFullEE', 'MANY_PAGES_EPICS');
      setQueryVariant(getWorkItemsCountOnly).manyPages();
      mountListWithQuery(searchOf(`type[]=${EPIC_TYPE_ID}`), { isGroup: true });
    });

    it('shows the Type token', async () => {
      await expectTokensToShow(['Type is Epic']);
    });
  });

  describe.each(LISTS)('on the $list list', ({ variant, isGroup, query, requestVariables }) => {
    const allIds = idsOf(variant);

    beforeEach(() => {
      activateVariant('getWorkItemsSlimEE', variant);
      activateVariant('getWorkItemsFullEE', variant);
      setQueryVariant(getWorkItemsCountOnly).manyPages();
    });

    describe('with the default page size', () => {
      beforeEach(async () => {
        mountListWithQuery(searchOf(query), { isGroup });
        await expectRows(allIds.slice(0, 20));
      });

      it('requests that list', () => {
        expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject(requestVariables);
      });

      it('shows the first page with Previous disabled', () => {
        expect(isDisabled(findPrevButton())).toBe(true);
        expect(isDisabled(findNextButton())).toBe(false);
        expect(findPageSizeToggle('Show 20 items')).not.toBe(null);
      });

      it('shows the total count', () => {
        expect(getText(document.body)).toContain('51 items');
      });

      describe('when paginating to the next page', () => {
        beforeEach(async () => {
          await waitAndClick(findNextButton);
          await expectRows(allIds.slice(20, 40));
        });

        it('requests the page after the first one', () => {
          expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
            afterCursor: expect.any(String),
            firstPageSize: 20,
          });
        });

        it('enables both buttons', () => {
          expect(isDisabled(findPrevButton())).toBe(false);
          expect(isDisabled(findNextButton())).toBe(false);
        });

        describe('when paginating to the last page', () => {
          beforeEach(async () => {
            await waitAndClick(findNextButton);
          });

          it('shows the remaining items with Next disabled', async () => {
            await expectRows(allIds.slice(40));

            expect(isDisabled(findNextButton())).toBe(true);
          });
        });

        describe('when going back', () => {
          beforeEach(async () => {
            await waitAndClick(findPrevButton);
          });

          it('shows the first page again', async () => {
            await expectRows(allIds.slice(0, 20));

            expect(isDisabled(findPrevButton())).toBe(true);
            expect(isDisabled(findNextButton())).toBe(false);
            expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
              beforeCursor: expect.any(String),
              lastPageSize: 20,
            });
          });
        });
      });

      describe('when choosing a larger page size', () => {
        beforeEach(async () => {
          await waitAndClick(() => findPageSizeToggle('Show 20 items'));
          await waitAndClick(() => screen.queryByRole('option', { name: 'Show 50 items' }));
        });

        // The chosen page size is persisted by local-storage-sync.
        afterEach(() => {
          localStorage.clear();
        });

        it('shows 50 items with Next enabled', async () => {
          await expectRows(allIds.slice(0, 50));

          expect(findRowIds()).toHaveLength(50);
          expect(isDisabled(findNextButton())).toBe(false);
          expect(isDisabled(findPrevButton())).toBe(true);
        });
      });
    });

    describe('when the URL sets first_page_size', () => {
      beforeEach(() => {
        mountListWithQuery(searchOf(query, 'first_page_size=50'), { isGroup });
      });

      it('shows that many items per page', async () => {
        await expectRows(allIds.slice(0, 50));

        expect(findRowIds()).toHaveLength(50);
        expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ firstPageSize: 50 });
      });
    });
  });
});
