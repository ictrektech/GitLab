import { GlIcon, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FreeVsPremiumComparisonTable from 'ee/vue_shared/subscription/components/free_vs_premium_comparison_table.vue';

describe('FreeVsPremiumComparisonTable', () => {
  let wrapper;

  const rows = [
    { id: 'sourceCodeManagement', title: 'Source Code Management & CI/CD', freeIncluded: true },
    {
      id: 'epics',
      title: 'Epics',
      freeIncluded: false,
      description: 'Track groups of related issues.',
      docsLink: '/help/epics',
    },
  ];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(FreeVsPremiumComparisonTable, {
      propsData: { rows, ...props },
    });
  };

  const findFreeColumnIcons = () => wrapper.findByTestId('free-column').findAllComponents(GlIcon);
  const findPremiumColumnIcons = () =>
    wrapper.findByTestId('premium-column').findAllComponents(GlIcon);

  it('renders the Free and Premium column headers', () => {
    createComponent();

    expect(wrapper.text()).toContain('Free');
    expect(wrapper.text()).toContain('Premium');
  });

  it('renders every row title', () => {
    createComponent();

    expect(wrapper.text()).toContain('Source Code Management & CI/CD');
    expect(wrapper.text()).toContain('Epics');
  });

  it('renders a check or close icon per row in the Free column, matching freeIncluded', () => {
    createComponent();

    const icons = findFreeColumnIcons();
    expect(icons.at(0).props('name')).toBe('check');
    expect(icons.at(1).props('name')).toBe('close');
  });

  it('renders a check icon for every row in the Premium column', () => {
    createComponent();

    const icons = findPremiumColumnIcons();
    expect(icons).toHaveLength(rows.length);
    icons.wrappers.forEach((icon) => expect(icon.props('name')).toBe('check'));
  });

  it('gives each icon sr-only "Included" / "Not included" text', () => {
    createComponent();

    const freeSrText = wrapper.findByTestId('free-column').findAll('.gl-sr-only');
    expect(freeSrText.at(0).text()).toBe('Included');
    expect(freeSrText.at(1).text()).toBe('Not included');

    const premiumSrText = wrapper.findByTestId('premium-column').findAll('.gl-sr-only');
    premiumSrText.wrappers.forEach((text) => expect(text.text()).toBe('Included'));
  });

  describe('when showFeaturePopovers is false (default)', () => {
    it('renders row titles as plain text, with no popover', () => {
      createComponent();

      expect(wrapper.findAllComponents(GlPopover)).toHaveLength(0);
      expect(wrapper.text()).toContain('Epics');
    });
  });

  describe('when showFeaturePopovers is true', () => {
    beforeEach(() => createComponent({ showFeaturePopovers: true }));

    it('renders a row with a docsLink as underlined with a popover', () => {
      const popover = wrapper.findComponent(GlPopover);

      expect(popover.exists()).toBe(true);
      expect(popover.props('title')).toBe('Epics');
      expect(wrapper.find(`#${popover.props('target')}`).text()).toBe('Epics');
    });

    it('renders a row with no docsLink as plain text, with no popover', () => {
      expect(wrapper.findAllComponents(GlPopover)).toHaveLength(1);
      expect(wrapper.text()).toContain('Source Code Management & CI/CD');
    });
  });
});
