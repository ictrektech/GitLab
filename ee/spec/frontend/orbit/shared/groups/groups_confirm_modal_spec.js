import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupsConfirmModal from 'ee/orbit/shared/groups/groups_confirm_modal.vue';

describe('GroupsConfirmModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GroupsConfirmModal, {
      propsData: { kind: null, groups: [], autoIndexEnabled: false, ...props },
      stubs: { GlModal },
    });
  };

  const acme = { name: 'acme', fullPath: 'acme' };
  const beta = { name: 'beta', fullPath: 'beta' };

  const findModal = () => wrapper.findComponent(GlModal);
  const findAutoIndexNote = () => wrapper.findByTestId('auto-index-note');

  describe('with no kind', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders no modal', () => {
      expect(findModal().exists()).toBe(false);
    });
  });

  describe('when turning off groups', () => {
    beforeEach(() => {
      createComponent({ kind: 'turnOff', groups: [acme, beta] });
    });

    it('asks to turn off the listed groups with a danger action', () => {
      expect(findModal().props()).toMatchObject({
        visible: true,
        title: 'Turn off GitLab Orbit for 2 groups?',
        actionPrimary: { text: 'Turn off GitLab Orbit', attributes: { variant: 'danger' } },
      });
      expect(findModal().text()).toContain('acme');
      expect(findModal().text()).toContain('deleted 30 or more days after');
      expect(findAutoIndexNote().exists()).toBe(false);
    });

    it('emits confirm with the kind', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('confirm')).toEqual([['turnOff']]);
    });

    it('emits cancel on hidden', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('cancel')).toEqual([[]]);
    });
  });

  describe('when turning off groups with automatic indexing on', () => {
    beforeEach(() => {
      createComponent({ kind: 'turnOff', groups: [acme, beta], autoIndexEnabled: true });
    });

    it('says that Orbit turns on again and points to the exclusion', () => {
      expect(findAutoIndexNote().text()).toBe(
        'Automatic indexing is on, so GitLab Orbit turns on again for these groups within an hour. To keep GitLab Orbit off, exclude the groups from automatic indexing.',
      );
    });
  });

  describe('when two groups share a name', () => {
    beforeEach(() => {
      createComponent({
        kind: 'turnOff',
        groups: [
          { name: 'Orbit Twin', fullPath: 'orbit-twin' },
          { name: 'Orbit Twin', fullPath: 'orbit-twin-2' },
        ],
      });
    });

    it('lists each group with its full path', () => {
      const items = wrapper.findAll('li').wrappers.map((item) => item.text().replace(/\s+/g, ' '));

      expect(items).toEqual(['Orbit Twin orbit-twin', 'Orbit Twin orbit-twin-2']);
    });
  });

  describe('when turning off one group', () => {
    beforeEach(() => {
      createComponent({ kind: 'turnOff', groups: [acme] });
    });

    it('uses the singular title and body', () => {
      expect(findModal().props('title')).toBe('Turn off GitLab Orbit for 1 group?');
      expect(findModal().text()).toContain('Orbit stops indexing this group.');
    });
  });

  describe('when excluding groups', () => {
    beforeEach(() => {
      createComponent({ kind: 'exclude', groups: [acme, beta] });
    });

    it('explains that the groups that are on turn off, with a danger action', () => {
      expect(findModal().props()).toMatchObject({
        title: 'Exclude 2 groups from automatic indexing?',
        actionPrimary: { text: 'Exclude', attributes: { variant: 'danger' } },
      });
      expect(findModal().text()).toContain('Within an hour, GitLab Orbit also turns off');
      expect(findModal().text()).toContain('beta');
    });
  });

  describe('when turning on automatic indexing', () => {
    beforeEach(() => {
      createComponent({ kind: 'autoIndex' });
    });

    it('asks to turn on Orbit for all groups', () => {
      expect(findModal().props()).toMatchObject({
        title: 'Turn on GitLab Orbit for all top-level groups?',
        actionPrimary: {
          text: 'Turn on for all top-level groups',
          attributes: { variant: 'confirm' },
        },
      });
      expect(findModal().text()).toContain(
        'GitLab Orbit turns on for every top-level group now, and for each new top-level group later, except excluded groups.',
      );
    });
  });
});
