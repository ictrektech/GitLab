import { GlButton, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GeoSiteReplicableTitle from 'ee/geo_sites/components/details/geo_site_replicable_title.vue';

describe('GeoSiteReplicableTitle', () => {
  let wrapper;

  const createComponent = (props) => {
    wrapper = shallowMountExtended(GeoSiteReplicableTitle, {
      propsData: {
        item: { titlePlural: 'Uploads' },
        ...props,
      },
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findLink = () => wrapper.findComponent(GlLink);

  describe('when the item is a group', () => {
    const item = { titlePlural: 'Uploads', children: [] };

    describe('when collapsed', () => {
      beforeEach(() => {
        createComponent({ item });
      });

      it('renders a toggle button with the title and a right chevron', () => {
        expect(findButton().text()).toBe('Uploads');
        expect(findButton().props('icon')).toBe('chevron-right');
        expect(findButton().attributes('aria-expanded')).toBe('false');
        expect(findLink().exists()).toBe(false);
      });

      it('emits toggle when clicked', () => {
        findButton().vm.$emit('click');

        expect(wrapper.emitted('toggle')).toHaveLength(1);
      });
    });

    describe('when expanded', () => {
      beforeEach(() => {
        createComponent({ item, expanded: true });
      });

      it('renders a down chevron', () => {
        expect(findButton().props('icon')).toBe('chevron-down');
        expect(findButton().attributes('aria-expanded')).toBe('true');
      });
    });
  });

  describe('when the item has a replication view', () => {
    beforeEach(() => {
      createComponent({ item: { titlePlural: 'Wikis', replicationView: '/replication/wikis' } });
    });

    it('renders a link to the replication view', () => {
      expect(findLink().text()).toBe('Wikis');
      expect(findLink().attributes('href')).toBe('/replication/wikis');
      expect(findButton().exists()).toBe(false);
    });
  });

  describe('when the item has no replication view', () => {
    beforeEach(() => {
      createComponent({ item: { titlePlural: 'Wikis', replicationView: null } });
    });

    it('renders the plain title', () => {
      expect(wrapper.text()).toBe('Wikis');
      expect(findLink().exists()).toBe(false);
      expect(findButton().exists()).toBe(false);
    });
  });
});
