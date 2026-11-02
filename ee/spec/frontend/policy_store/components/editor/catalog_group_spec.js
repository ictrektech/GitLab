import { GlButton, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import CatalogGroup from 'ee/policy_store/components/editor/catalog_group.vue';

describe('CatalogGroup', () => {
  let wrapper;

  const group = {
    label: 'Deployment',
    items: [
      {
        id: 'environment_state',
        label: 'Environment State',
        icon: 'environment',
        description: 'When an environment is not in the required state',
      },
      { id: 'soak_time', label: 'Soak Time', icon: 'timer' },
    ],
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(CatalogGroup, {
      propsData: { group, optionTestid: 'rules-option', ...props },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      // The item label and state icons live in GlButton's default slot; the default stub
      // would swallow them.
      stubs: { GlButton: stubComponent(GlButton, { template: RENDER_ALL_SLOTS_TEMPLATE }) },
    });
  };

  const findOptions = () => wrapper.findAllComponentsByTestId('rules-option');
  const findOption = (label) =>
    findOptions().wrappers.find((option) => option.text().includes(label));
  const findStateIcon = (label) =>
    findOption(label)
      .findAllComponents(GlIcon)
      .wrappers.find((icon) =>
        ['information-o', 'check-circle-filled'].includes(icon.props('name')),
      );

  it('renders the group label', () => {
    createComponent();

    expect(wrapper.text()).toContain('Deployment');
  });

  it('renders a button per item', () => {
    createComponent();

    expect(findOptions().wrappers.map((option) => option.text())).toEqual([
      expect.stringContaining('Environment State'),
      expect.stringContaining('Soak Time'),
    ]);
  });

  it('marks selected items as pressed without the Pajamas selected background', () => {
    createComponent({ selectedIds: ['soak_time'] });

    expect(findOption('Soak Time').attributes('aria-pressed')).toBe('true');
    expect(findOption('Environment State').attributes('aria-pressed')).toBe('false');
    expect(
      wrapper.findAllComponents(GlButton).wrappers.map((button) => button.props('selected')),
    ).toEqual([false, false]);
  });

  it('emits select with the item id when an option is clicked', () => {
    createComponent();

    findOption('Soak Time').vm.$emit('click');

    expect(wrapper.emitted('select')).toEqual([['soak_time']]);
  });

  it('shows a check on a selected item when it is not hovered', () => {
    createComponent({ selectedIds: ['environment_state'] });

    expect(findStateIcon('Environment State').props('name')).toBe('check-circle-filled');
  });

  it('puts the description tooltip on the button, where hover and focus can reach it', () => {
    createComponent();

    expect(getBinding(findOption('Environment State').element, 'gl-tooltip')).toBeDefined();
    expect(findOption('Environment State').attributes('title')).toBe(
      'When an environment is not in the required state',
    );
    expect(findOption('Soak Time').attributes('title')).toBeUndefined();
  });

  describe('a disabled item', () => {
    const disabledItems = { soak_time: 'Not available with Project created' };

    it('stays visible, carrying the reason as its tooltip', () => {
      createComponent({ disabledItems });

      expect(findOption('Soak Time').attributes('title')).toBe(
        'Not available with Project created',
      );
      expect(findOption('Environment State').attributes('title')).toBe(
        'When an environment is not in the required state',
      );
    });

    // aria-disabled rather than disabled, so the button still takes the hover and focus
    // the tooltip carrying the reason needs.
    it('is marked aria-disabled rather than disabled', () => {
      createComponent({ disabledItems });

      expect(findOption('Soak Time').attributes('aria-disabled')).toBe('true');
      expect(findOption('Soak Time').props('disabled')).toBe(false);
      expect(findOption('Environment State').attributes('aria-disabled')).toBeUndefined();
    });

    it('emits no select when clicked', () => {
      createComponent({ disabledItems });

      findOption('Soak Time').vm.$emit('click');

      expect(wrapper.emitted('select')).toBeUndefined();
    });

    // A loaded policy can arrive already holding a pairing the rule refuses, and
    // deselecting it in the picker is the way out of it.
    it('can still be deselected while it is selected', () => {
      createComponent({ disabledItems, selectedIds: ['soak_time'] });

      findOption('Soak Time').vm.$emit('click');

      expect(wrapper.emitted('select')).toEqual([['soak_time']]);
    });

    // Since that click is the way out of the pairing, announcing the item as disabled would
    // tell a screen-reader user the one control that still works is unavailable.
    it('is not marked aria-disabled while it is selected', () => {
      createComponent({ disabledItems, selectedIds: ['soak_time'] });

      expect(findOption('Soak Time').attributes('aria-disabled')).toBeUndefined();
      expect(findOption('Soak Time').classes()).not.toContain('gl-cursor-not-allowed');
    });

    // The reason says the item cannot be picked, which would contradict the only control
    // that still works, so a selected item goes back to carrying its own description.
    it('drops the reason from its tooltip while it is selected', () => {
      createComponent({ disabledItems, selectedIds: ['soak_time', 'environment_state'] });

      expect(findOption('Soak Time').attributes('title')).toBeUndefined();
      expect(findOption('Environment State').attributes('title')).toBe(
        'When an environment is not in the required state',
      );
    });
  });

  it.each(['mouseenter', 'focusin'])(
    'shows the info cue on %s of an item with a description',
    async (event) => {
      createComponent({ selectedIds: ['environment_state'] });

      await findOption('Environment State').vm.$emit(event);

      expect(findStateIcon('Environment State').props('name')).toBe('information-o');
    },
  );

  it.each([
    ['mouseenter', 'mouseleave'],
    ['focusin', 'focusout'],
  ])('hides the info cue again after %s ends', async (enter, leave) => {
    createComponent({ selectedIds: ['environment_state'] });

    await findOption('Environment State').vm.$emit(enter);
    await findOption('Environment State').vm.$emit(leave);

    expect(findStateIcon('Environment State').props('name')).toBe('check-circle-filled');
  });

  it('shows no info cue when the highlighted item has no description', async () => {
    createComponent();

    await findOption('Soak Time').vm.$emit('focusin');

    expect(findStateIcon('Soak Time')).toBeUndefined();
  });
});
