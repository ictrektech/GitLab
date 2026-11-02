import { GlButton } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ExpandButton from '~/releases/components/expand_button.vue';

const text = {
  expanded: 'Expanded!',
  short: 'Short',
};

describe('Expand button', () => {
  let wrapper;

  const findButton = () => wrapper.findComponent(GlButton);

  const factory = ({ propsData, slots } = {}) => {
    wrapper = mount(ExpandButton, {
      propsData: {
        expandLabel: 'Expand it',
        collapseLabel: 'Collapse it',
        ...propsData,
      },
      slots,
    });
  };

  const toggle = async () => {
    findButton().trigger('click');
    await nextTick();
  };

  beforeEach(() => {
    factory({
      slots: {
        expanded: `<p>${text.expanded}</p>`,
      },
    });
  });

  it('renders a single toggle button', () => {
    expect(wrapper.findAll('button')).toHaveLength(1);
    expect(findButton().isVisible()).toBe(true);
  });

  it('renders no text when short text is not provided', () => {
    expect(wrapper.findComponent(ExpandButton).text()).toBe('');
  });

  it('does not render expanded text', () => {
    expect(wrapper.findComponent(ExpandButton).text().trim()).not.toBe(text.expanded);
  });

  describe('accessible name', () => {
    it('toggles the collapse/expand label on click', async () => {
      expect(findButton().attributes('aria-label')).toBe('Expand it');

      await toggle();

      expect(findButton().attributes('aria-label')).toBe('Collapse it');

      await toggle();

      expect(findButton().attributes('aria-label')).toBe('Expand it');
    });

    describe('with labels provided by the parent', () => {
      beforeEach(() => {
        factory({
          propsData: { expandLabel: 'Expand foo', collapseLabel: 'Collapse foo' },
          slots: { expanded: `<p>${text.expanded}</p>` },
        });
      });

      it('uses the labels provided by the parent', async () => {
        expect(findButton().attributes('aria-label')).toBe('Expand foo');

        await toggle();

        expect(findButton().attributes('aria-label')).toBe('Collapse foo');
      });
    });
  });

  describe('when short text is provided', () => {
    beforeEach(() => {
      factory({
        slots: {
          expanded: `<p>${text.expanded}</p>`,
          short: `<p>${text.short}</p>`,
        },
      });
    });

    it('renders short text', () => {
      expect(wrapper.findComponent(ExpandButton).text().trim()).toBe(text.short);
    });

    it('renders the expand button before the text', () => {
      expect(wrapper.findComponent(ExpandButton).element).toMatchSnapshot();
    });
  });

  describe('when toggled', () => {
    beforeEach(() => toggle());

    it('renders the expanded text', () => {
      expect(wrapper.findComponent(ExpandButton).text()).toContain(text.expanded);
    });

    describe('when short text is provided', () => {
      beforeEach(async () => {
        factory({
          slots: {
            expanded: `<p>${text.expanded}</p>`,
            short: `<p>${text.short}</p>`,
          },
        });

        await toggle();
      });

      it('only renders expanded text', () => {
        expect(wrapper.findComponent(ExpandButton).text().trim()).toBe(text.expanded);
      });

      it('renders the collapse button before the text', () => {
        expect(wrapper.findComponent(ExpandButton).element).toMatchSnapshot();
      });
    });
  });

  describe('when toggled twice', () => {
    beforeEach(async () => {
      await toggle();
      await toggle();
    });

    it('hides the expanded text', () => {
      expect(wrapper.findComponent(ExpandButton).text().trim()).not.toBe(text.expanded);
    });

    describe('when short text is provided', () => {
      beforeEach(async () => {
        factory({
          slots: {
            expanded: `<p>${text.expanded}</p>`,
            short: `<p>${text.short}</p>`,
          },
        });

        await toggle();
        await toggle();
      });

      it('reveals the short text again', () => {
        expect(wrapper.findComponent(ExpandButton).text().trim()).toBe(text.short);
      });
    });
  });
});
