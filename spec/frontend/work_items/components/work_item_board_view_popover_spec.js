import { GlBadge, GlLink, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemBoardViewPopover from '~/work_items/components/work_item_board_view_popover.vue';

describe('WorkItemBoardViewPopover', () => {
  let wrapper;

  const target = () => document.body;

  const findPopover = () => wrapper.findComponent(GlPopover);

  const createComponent = () => {
    wrapper = shallowMountExtended(WorkItemBoardViewPopover, {
      propsData: { target },
      stubs: { GlPopover },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('opens on hover and focus of the target', () => {
    expect(findPopover().props('triggers')).toBe('hover focus');
    expect(findPopover().props('target')).toBe(target);
  });

  it('renders the title, badge, description and docs link', () => {
    expect(wrapper.text()).toContain('Board view');
    expect(wrapper.findComponent(GlBadge).text()).toBe('New');
    expect(wrapper.text()).toContain(
      'View your work items as a board, with the same filters and saved views as the list.',
    );
    expect(wrapper.findComponent(GlLink).text()).toBe('Learn more about board view');
    expect(wrapper.findComponent(GlLink).attributes('href')).toContain(
      'user/work_items/saved_views',
    );
  });
});
