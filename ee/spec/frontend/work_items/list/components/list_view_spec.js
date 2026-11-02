import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import ListView from '~/work_items/list/list_view.vue';
import ListViewEE from 'ee/work_items/list/list_view.vue';
import WorkItemStatusBadge from 'ee/work_items/components/shared/work_item_status_badge.vue';
import { WIDGET_TYPE_STATUS } from '~/work_items/constants';
import { CREATED_DESC } from '~/work_items/list/constants';
import { STATUS_OPEN } from '~/issues/constants';

/** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
let wrapper;

const findListView = () => wrapper.findComponent(ListView);
const findStatusBadge = () => wrapper.findComponent(WorkItemStatusBadge);

const baseProps = {
  rootPageFullPath: 'gitlab-org',
  queryVariables: { fullPath: 'gitlab-org', sort: CREATED_DESC, state: STATUS_OPEN },
  showBulkEditSidebar: false,
  sortKey: CREATED_DESC,
  isSortKeyInitialized: true,
};

const mountComponent = ({ scopedSlots = {}, listeners = {}, stubs = {} } = {}) => {
  wrapper = shallowMountExtended(ListViewEE, {
    propsData: baseProps,
    listeners,
    scopedSlots,
    stubs: {
      ListView: stubComponent(ListView, { template: RENDER_ALL_SLOTS_TEMPLATE }),
      ...stubs,
    },
  });
};

const mountComponentWithIssuable = (issuable) => {
  const ListViewStub = {
    name: 'ListView',
    data() {
      return { issuable };
    },
    template: '<div><slot name="custom-status" :issuable="issuable" /></div>',
  };

  mountComponent({ stubs: { ListView: ListViewStub } });
};

const mountComponentWithListEmptyStateSlot = (scopedSlots) => {
  const ListViewStub = {
    name: 'ListView',
    template: '<div><slot name="list-empty-state" /></div>',
  };

  mountComponent({ scopedSlots, stubs: { ListView: ListViewStub } });
};

describe('ListViewEE', () => {
  it('passes props down to the ce list_view component', () => {
    mountComponent();

    expect(findListView().props()).toMatchObject(baseProps);
  });

  it('forwards listeners to the ce list_view component', () => {
    const refetchData = jest.fn();
    mountComponent({ listeners: { 'refetch-data': refetchData } });

    findListView().vm.$emit('refetch-data');

    expect(refetchData).toHaveBeenCalled();
  });

  describe('list-empty-state slot', () => {
    it('does not render a slot when the consumer did not provide one', () => {
      mountComponentWithListEmptyStateSlot({});

      expect(wrapper.find('[data-testid="list-empty-state-slot"]').exists()).toBe(false);
    });

    it('forwards the slot and its scope when the consumer provided one', () => {
      mountComponentWithListEmptyStateSlot({
        'list-empty-state': `
          <div data-testid="list-empty-state-slot">
            empty-state
          </div>
        `,
      });

      const slot = wrapper.find('[data-testid="list-empty-state-slot"]');

      expect(slot.exists()).toBe(true);
      expect(slot.text()).toBe('empty-state');
    });
  });

  describe('custom-status slot', () => {
    it('renders the status badge when the issuable has a status widget', () => {
      const status = { name: 'To do', iconName: 'status-waiting', description: 'To do' };
      mountComponentWithIssuable({
        widgets: [{ type: WIDGET_TYPE_STATUS, status }],
      });

      expect(findStatusBadge().exists()).toBe(true);
      expect(findStatusBadge().props('item')).toEqual(status);
    });

    it('does not render the status badge when the issuable has no status widget', () => {
      mountComponentWithIssuable({ widgets: [] });

      expect(findStatusBadge().exists()).toBe(false);
    });
  });
});
