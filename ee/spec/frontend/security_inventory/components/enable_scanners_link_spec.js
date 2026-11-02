import { GlLink } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersLink from 'ee/security_inventory/components/enable_scanners_link.vue';

describe('EnableScannersLink', () => {
  let wrapper;

  const findLink = () => wrapper.findComponent(GlLink);

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(EnableScannersLink, { propsData });
  };

  describe('when a web path is given', () => {
    beforeEach(() => {
      createComponent({ webPath: '/groups/gitlab-org' });
    });

    it('links to the enable scanners wizard', () => {
      expect(findLink().text()).toBe('Enable scanners');
      expect(findLink().attributes('href')).toBe(
        '/groups/gitlab-org/-/security/configuration#/enable_scanners',
      );
    });

    it('is hidden at rest and revealed on hover or keyboard focus', () => {
      expect(findLink().classes()).toEqual(
        expect.arrayContaining([
          'gl-opacity-0',
          'group-hover:gl-opacity-10',
          'focus:gl-opacity-10',
        ]),
      );
    });
  });

  describe('when rendered inside a clickable parent', () => {
    it('does not bubble the click to the parent', async () => {
      const onParentClick = jest.fn();
      wrapper = mountExtended({
        components: { EnableScannersLink },
        // Capture-phase preventDefault stops jsdom from attempting a real navigation
        template:
          '<div @click.capture.prevent><button @click="onParentClick"><enable-scanners-link web-path="/g" /></button></div>',
        methods: { onParentClick },
      });

      await wrapper.findByTestId('enable-scanners-link').trigger('click');

      expect(onParentClick).not.toHaveBeenCalled();
    });
  });

  describe('when no web path is given', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders nothing', () => {
      expect(findLink().exists()).toBe(false);
    });
  });
});
