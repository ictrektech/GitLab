import { GlButton, GlIcon, GlLoadingIcon, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupAreasPopover from 'ee/orbit/shared/groups/group_areas_popover.vue';

describe('GroupAreasPopover', () => {
  let wrapper;

  const areas = [
    {
      key: 'core',
      label: 'Core',
      stateLabel: 'Indexed',
      isIndexing: false,
      icon: 'status-success',
      iconVariant: 'success',
    },
    {
      key: 'ci',
      label: 'CI/CD',
      stateLabel: 'Indexing',
      isIndexing: true,
      icon: null,
      iconVariant: null,
    },
  ];

  const findToggle = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findAreaItems = () => wrapper.findAll('li');

  beforeEach(() => {
    wrapper = shallowMountExtended(GroupAreasPopover, {
      propsData: { toggleId: 'orbit-group-areas-0', groupName: 'acme', areas },
      stubs: { GlPopover },
    });
  });

  it('labels the toggle with the group name', () => {
    expect(findToggle().attributes()).toMatchObject({
      id: 'orbit-group-areas-0',
      'aria-label': 'Index status by area for acme',
    });
  });

  it('targets the toggle and titles the popover with the group name', () => {
    expect(findPopover().props()).toMatchObject({ target: 'orbit-group-areas-0', title: 'acme' });
  });

  it('lists each area with its state', () => {
    expect(findAreaItems().wrappers.map((item) => item.text().replace(/\s+/g, ' '))).toEqual([
      'Core Indexed',
      'CI/CD Indexing',
    ]);
  });

  it('shows a spinner for the area that indexes and an icon for the others', () => {
    expect(findAreaItems().at(0).findComponent(GlIcon).props('name')).toBe('status-success');
    expect(findAreaItems().at(1).findComponent(GlLoadingIcon).exists()).toBe(true);
  });
});
