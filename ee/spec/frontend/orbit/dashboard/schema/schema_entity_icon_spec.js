import { GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SchemaEntityIcon from 'ee/orbit/dashboard/schema/schema_entity_icon.vue';

describe('SchemaEntityIcon', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SchemaEntityIcon, {
      propsData: { icon: 'pipeline', color: '#3B82F6', ...props },
    });
  };

  it.each`
    color        | rgb                    | iconClass
    ${'#3B82F6'} | ${'rgb(59, 130, 246)'} | ${'gl-text-neutral-0'}
    ${'#22D3EE'} | ${'rgb(34, 211, 238)'} | ${'gl-text-neutral-950'}
    ${'#FCD34D'} | ${'rgb(252, 211, 77)'} | ${'gl-text-neutral-950'}
    ${'#06B6D4'} | ${'rgb(6, 182, 212)'}  | ${'gl-text-neutral-950'}
  `('uses $iconClass on a $color circle', ({ color, rgb, iconClass }) => {
    createComponent({ color });

    expect(wrapper.classes()).toContain(iconClass);
    expect(wrapper.attributes('style')).toBe(`background-color: ${rgb};`);
  });

  describe('with the xl size', () => {
    beforeEach(() => {
      createComponent({ size: 'xl' });
    });

    it('sizes the circle and the icon together', () => {
      expect(wrapper.classes()).toEqual(expect.arrayContaining(['gl-h-13', 'gl-w-13']));
      expect(wrapper.findComponent(GlIcon).props()).toMatchObject({ name: 'pipeline', size: 32 });
    });
  });

  describe('with no icon', () => {
    beforeEach(() => {
      createComponent({ icon: null });
    });

    it('shows only the colored circle', () => {
      expect(wrapper.findComponent(GlIcon).exists()).toBe(false);
    });
  });
});
