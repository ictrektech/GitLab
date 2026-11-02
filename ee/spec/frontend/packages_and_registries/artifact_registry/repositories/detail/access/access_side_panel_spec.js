import { GlDisclosureDropdown, GlDrawer, GlTableLite } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { nextTick } from 'vue';
import { stubComponent } from 'helpers/stub_component';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import AccessSidePanel from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/access_side_panel.vue';
import DirectMembersCard from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/direct_members_card.vue';
import InheritedMembersCard from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/inherited_members_card.vue';
import { REPOSITORY_ID } from '../../../mock_data';

describe('ArtifactRegistryAccessSidePanel', () => {
  let wrapper;

  const findPanel = () => wrapper.findByTestId('access-side-panel');
  const findHeading = () => wrapper.findByTestId('access-heading');
  const findCloseButton = () => wrapper.findByTestId('panel-close-button');
  const findDirectCard = () => wrapper.findComponent(DirectMembersCard);
  const findInheritedCard = () => wrapper.findComponent(InheritedMembersCard);
  const findInheritedTable = () => findInheritedCard().findComponent(GlTableLite);
  const findInheritedRows = () => findInheritedTable().findAll('tbody tr');

  const createComponent = ({ open = true, repositoryName = 'payment-core' } = {}) => {
    wrapper = mountExtended(AccessSidePanel, {
      propsData: { open, repositoryId: REPOSITORY_ID, repositoryName },
      stubs: {
        DirectMembersCard: true,
        MountingPortal: stubComponent(MountingPortal, { name: 'MountingPortal' }),
      },
      attachTo: document.body,
    });
  };

  const pressEscape = () =>
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

  describe('when closed', () => {
    beforeEach(() => {
      createComponent({ open: false });
    });

    it('renders no panel', () => {
      expect(wrapper.findComponent(DynamicPanel).exists()).toBe(false);
    });

    it('ignores Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });
  });

  describe('when open', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the repository in its heading', () => {
      expect(findHeading().text()).toBe('Access for payment-core');
    });

    it('renders the heading at the level the panel reserves for its title', () => {
      expect(findHeading().element.tagName).toBe('H2');
    });

    it('is a region named by its heading', () => {
      expect(findPanel().attributes('role')).toBe('region');
      expect(findHeading().attributes('id')).toEqual(expect.any(String));
      expect(findPanel().attributes('aria-labelledby')).toBe(findHeading().attributes('id'));
    });

    it('does not escape the repository name, which renders as text', () => {
      createComponent({ repositoryName: 'a&b' });

      expect(findHeading().text()).toBe('Access for a&b');
    });

    it('emits close when its Close button is pressed', async () => {
      await findCloseButton().trigger('click');

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('emits close on Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('leaves other keys alone', () => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('leaves Escape to an open modal', () => {
      document.body.classList.add('modal-open');

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      document.body.classList.remove('modal-open');
    });

    it.each(['input', 'textarea'])('leaves Escape to a focused %s', (tag) => {
      const field = document.createElement(tag);
      document.body.appendChild(field);
      field.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      field.remove();
    });

    it('leaves Escape to a focused rich text editor', () => {
      const editor = document.createElement('div');
      editor.setAttribute('contenteditable', 'true');
      document.body.appendChild(editor);
      editor.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      editor.remove();
    });

    it('leaves Escape to an open drawer', async () => {
      mountExtended(GlDrawer, { propsData: { open: true }, attachTo: document.body });
      await nextTick();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('closes on Escape while a closed dropdown toggle has focus', () => {
      const dropdown = mountExtended(GlDisclosureDropdown, {
        propsData: { toggleText: 'More actions', items: [{ text: 'Copy', action: jest.fn() }] },
        attachTo: document.body,
      });
      dropdown.find('button').element.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('still closes from its Close button while a drawer is open', async () => {
      mountExtended(GlDrawer, { propsData: { open: true }, attachTo: document.body });
      await nextTick();

      await findCloseButton().trigger('click');

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('lists the direct members of the repository, above the inherited members', () => {
      expect(findDirectCard().props('repositoryId')).toBe(REPOSITORY_ID);
      expect(findDirectCard().element.nextElementSibling).toBe(findInheritedCard().element);
    });

    describe('the Inherited members card', () => {
      it('is titled Inherited members, one level below the panel heading', () => {
        const crud = findInheritedCard().findComponent(CrudComponent);

        expect(crud.props()).toMatchObject({ title: 'Inherited members', titleTag: 'h3' });
      });

      it('has Role and Permission columns and no Members column', () => {
        const headers = findInheritedTable()
          .findAll('thead th')
          .wrappers.map((th) => th.text());

        expect(headers).toEqual(['Role', 'Permission']);
      });

      it('lists the four roles, most access first, with what each permits', () => {
        const rows = findInheritedRows().wrappers.map((row) =>
          row.findAll('td').wrappers.map((td) => td.text()),
        );

        expect(rows).toEqual([
          [
            'Artifact Admin',
            'View, create, and delete repositories. Manage member access to the registry.',
          ],
          [
            'Artifact Manager',
            'Publish and delete artifacts. Update settings for repositories and virtual repository upstreams. Cannot create or delete repositories, or manage access to the registry.',
          ],
          [
            'Artifact Contributor',
            'Browse, pull, and publish artifacts (for example, from CI/CD jobs). Cannot delete artifacts or change repository settings.',
          ],
          ['Artifact Viewer', 'Browse repositories and pull artifacts. Cannot publish or delete.'],
        ]);
      });

      it('shows no count', () => {
        expect(wrapper.findByTestId('crud-count').exists()).toBe(false);
      });
    });
  });

  describe('when it opens', () => {
    beforeEach(async () => {
      createComponent({ open: false });

      await wrapper.setProps({ open: true });
      await nextTick();
    });

    it('moves focus to the panel', () => {
      expect(document.activeElement).toBe(findPanel().element);
    });
  });
});
