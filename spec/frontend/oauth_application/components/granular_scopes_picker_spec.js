import { GlFormGroup } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import { scrollToElement } from '~/lib/utils/scroll_utils';
import GranularScopesPicker from '~/oauth_application/components/granular_scopes_picker.vue';
import GroupHierarchyNamespaceSelector from '~/oauth_application/components/group_hierarchy_namespace_selector.vue';
import groupHierarchySearchQuery from '~/oauth_application/graphql/group_hierarchy_search.query.graphql';
import GranularPermissionsSelector from '~/vue_shared/access_tokens/components/granular_permissions_selector.vue';
import {
  ACCESS_SELECTED_MEMBERSHIPS_ENUM,
  ACCESS_USER_ENUM,
} from '~/vue_shared/access_tokens/constants';
import getAccessTokenPermissions from '~/vue_shared/access_tokens/graphql/get_access_token_permissions.query.graphql';
import { mockAccessTokenPermissionsQueryResponse } from '../../vue_shared/access_tokens/mock_data';

Vue.use(VueApollo);

jest.mock('~/lib/utils/scroll_utils');

const PREFIX = 'authn_oauth_application[granular_scopes]';

const subgroup = {
  id: 'gid://gitlab/Group/2',
  name: 'Widgets',
  fullPath: 'acme/widgets',
  __typename: 'Group',
};
const project = {
  id: 'gid://gitlab/Project/3',
  name: 'Site',
  fullPath: 'acme/widgets/site',
  __typename: 'Project',
};

describe('GranularScopesPicker', () => {
  let wrapper;

  const defaultProps = {
    allowedAccessLevels: [ACCESS_USER_ENUM, ACCESS_SELECTED_MEMBERSHIPS_ENUM],
    groupFullPath: 'acme',
    groupName: 'Acme',
  };

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(GranularScopesPicker, {
      propsData: { ...defaultProps, ...props },
    });
  };

  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findPermissionsSelector = () => wrapper.findComponent(GranularPermissionsSelector);
  const findNamespaceSelector = () => wrapper.findComponent(GroupHierarchyNamespaceSelector);
  const hiddenInputs = () =>
    wrapper
      .findAll('input[type="hidden"]')
      .wrappers.map((input) => [input.attributes('name'), input.attributes('value')]);

  const selectPermissions = (value) => findPermissionsSelector().vm.$emit('input', value);
  const selectNamespaces = (value) => findNamespaceSelector().vm.$emit('input', value);

  beforeEach(() => {
    createComponent();
  });

  describe('rendering', () => {
    it('labels the form group and explains the set', () => {
      expect(findFormGroup().attributes('label')).toBe('Fine-grained permissions');
      expect(findFormGroup().props('labelDescription')).toContain(
        'Leave everything cleared to keep a legacy application.',
      );
    });

    it('renders the permissions selector with the scopes for the allowed access levels', () => {
      expect(findPermissionsSelector().props('scopes')).toEqual([
        { key: 'namespace', boundaries: ['GROUP', 'PROJECT'] },
        { key: 'user', boundaries: ['USER'] },
      ]);
      expect(findPermissionsSelector().props('value')).toEqual({
        namespace: [],
        user: [],
        instance: [],
      });
    });

    it('renders the namespace selector for the group', () => {
      expect(findNamespaceSelector().props()).toMatchObject({
        value: [],
        groupFullPath: 'acme',
        groupName: 'Acme',
      });
    });

    it('explains that the MCP server needs execute_mcp_tool', () => {
      expect(wrapper.text()).toContain(
        'Tokens can use the GitLab MCP server only when the set grants execute_mcp_tool.',
      );
    });

    it('posts nothing while nothing is selected', () => {
      expect(hiddenInputs()).toEqual([]);
    });

    describe('when only the user level is allowed', () => {
      beforeEach(() => {
        createComponent({ props: { allowedAccessLevels: [ACCESS_USER_ENUM] } });
      });

      it('renders only the user scope and no namespace selector', () => {
        expect(findPermissionsSelector().props('scopes')).toEqual([
          { key: 'user', boundaries: ['USER'] },
        ]);
        expect(findNamespaceSelector().exists()).toBe(false);
      });
    });
  });

  describe('hidden inputs', () => {
    it('posts a user scope when user permissions are selected', async () => {
      await selectPermissions({ namespace: [], user: ['execute_mcp_tool'], instance: [] });

      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'USER'],
        [`${PREFIX}[0][permissions][]`, 'execute_mcp_tool'],
      ]);
    });

    it('posts a selected memberships scope with the global IDs of the chosen groups and projects', async () => {
      await selectNamespaces([subgroup, project]);
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });

      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'SELECTED_MEMBERSHIPS'],
        [`${PREFIX}[0][permissions][]`, 'read_project'],
        [`${PREFIX}[0][resource_ids][]`, subgroup.id],
        [`${PREFIX}[0][resource_ids][]`, project.id],
      ]);
    });

    it('keeps namespace permissions without namespaces instead of dropping them', async () => {
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });

      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'SELECTED_MEMBERSHIPS'],
        [`${PREFIX}[0][permissions][]`, 'read_project'],
      ]);
    });

    it('indexes the scopes compactly when both levels are filled', async () => {
      await selectNamespaces([subgroup]);
      await selectPermissions({
        namespace: ['read_project'],
        user: ['execute_mcp_tool'],
        instance: [],
      });

      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'USER'],
        [`${PREFIX}[0][permissions][]`, 'execute_mcp_tool'],
        [`${PREFIX}[1][access]`, 'SELECTED_MEMBERSHIPS'],
        [`${PREFIX}[1][permissions][]`, 'read_project'],
        [`${PREFIX}[1][resource_ids][]`, subgroup.id],
      ]);
    });

    it('drops a namespace from the inputs when it is removed', async () => {
      await selectNamespaces([subgroup, project]);
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });
      await selectNamespaces([project]);

      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'SELECTED_MEMBERSHIPS'],
        [`${PREFIX}[0][permissions][]`, 'read_project'],
        [`${PREFIX}[0][resource_ids][]`, project.id],
      ]);
    });

    it('posts nothing again when the permissions are cleared', async () => {
      await selectPermissions({ namespace: [], user: ['execute_mcp_tool'], instance: [] });
      await selectPermissions({ namespace: [], user: [], instance: [] });

      expect(hiddenInputs()).toEqual([]);
    });
  });

  describe('with initial scopes', () => {
    beforeEach(() => {
      createComponent({
        props: {
          initialScopes: [
            { access: ACCESS_USER_ENUM, permissions: ['execute_mcp_tool'], namespaces: [] },
            {
              access: ACCESS_SELECTED_MEMBERSHIPS_ENUM,
              permissions: ['read_project'],
              namespaces: [subgroup],
            },
          ],
        },
      });
    });

    it('pre-fills the permissions and namespaces', () => {
      expect(findPermissionsSelector().props('value')).toEqual({
        namespace: ['read_project'],
        user: ['execute_mcp_tool'],
        instance: [],
      });
      expect(findNamespaceSelector().props('value')).toEqual([subgroup]);
    });

    it('posts the pre-filled scopes', () => {
      expect(hiddenInputs()).toEqual([
        [`${PREFIX}[0][access]`, 'USER'],
        [`${PREFIX}[0][permissions][]`, 'execute_mcp_tool'],
        [`${PREFIX}[1][access]`, 'SELECTED_MEMBERSHIPS'],
        [`${PREFIX}[1][permissions][]`, 'read_project'],
        [`${PREFIX}[1][resource_ids][]`, subgroup.id],
      ]);
    });
  });

  describe('inside a form', () => {
    let form;

    beforeEach(async () => {
      form = document.createElement('form');
      const mountPoint = document.createElement('div');
      form.appendChild(mountPoint);
      document.body.appendChild(form);

      wrapper = mountExtended(GranularScopesPicker, {
        attachTo: mountPoint,
        apolloProvider: createMockApollo([
          [
            getAccessTokenPermissions,
            jest.fn().mockResolvedValue(mockAccessTokenPermissionsQueryResponse),
          ],
          [groupHierarchySearchQuery, jest.fn().mockResolvedValue({ data: { group: null } })],
        ]),
        propsData: {
          ...defaultProps,
          initialScopes: [
            { access: ACCESS_USER_ENUM, permissions: ['read_user'], namespaces: [] },
            {
              access: ACCESS_SELECTED_MEMBERSHIPS_ENUM,
              permissions: ['read_project'],
              namespaces: [project],
            },
          ],
        },
      });

      await waitForPromises();
    });

    afterEach(() => {
      form.remove();
    });

    it('submits the scopes as form data', () => {
      const formData = new FormData(form);

      expect(formData.getAll(`${PREFIX}[0][access]`)).toEqual(['USER']);
      expect(formData.getAll(`${PREFIX}[0][permissions][]`)).toEqual(['read_user']);
      expect(formData.getAll(`${PREFIX}[1][access]`)).toEqual(['SELECTED_MEMBERSHIPS']);
      expect(formData.getAll(`${PREFIX}[1][permissions][]`)).toEqual(['read_project']);
      expect(formData.getAll(`${PREFIX}[1][resource_ids][]`)).toEqual(['gid://gitlab/Project/3']);
    });
  });

  describe('submit validation', () => {
    const NAMESPACE_ERROR = 'At least one group or project is required.';
    const PERMISSIONS_ERROR =
      'Selected groups and projects require at least one group and project permission.';
    let form;

    const submitForm = () => {
      const event = new Event('submit', { bubbles: true, cancelable: true });
      form.dispatchEvent(event);
      return event;
    };

    beforeEach(() => {
      form = document.createElement('form');
      const mountPoint = document.createElement('div');
      form.appendChild(mountPoint);
      document.body.appendChild(form);

      wrapper = shallowMountExtended(GranularScopesPicker, {
        attachTo: mountPoint,
        propsData: defaultProps,
        stubs: {
          GroupHierarchyNamespaceSelector: stubComponent(GroupHierarchyNamespaceSelector, {
            template: '<div><button>Add group or project</button></div>',
          }),
          GranularPermissionsSelector: stubComponent(GranularPermissionsSelector, {
            template: '<div><button>Group and project</button></div>',
          }),
        },
      });
    });

    afterEach(() => {
      form.remove();
    });

    const focusedElement = () => document.activeElement;

    it('shows no error before the form is submitted', async () => {
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });

      expect(findNamespaceSelector().props('error')).toBe('');
    });

    describe('when namespace permissions are selected without a group or project', () => {
      let event;

      beforeEach(async () => {
        await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });
        event = submitForm();
        await nextTick();
      });

      it('blocks the submission', () => {
        expect(event.defaultPrevented).toBe(true);
      });

      it('shows the error on the namespace selector', () => {
        expect(findNamespaceSelector().props('error')).toBe(NAMESPACE_ERROR);
      });

      it('clears the error once a group or project is selected', async () => {
        await selectNamespaces([subgroup]);

        expect(findNamespaceSelector().props('error')).toBe('');
      });

      it('scrolls to the namespace selector', () => {
        expect(scrollToElement).toHaveBeenCalledWith(findNamespaceSelector().element, {
          behavior: 'smooth',
          offset: -100,
        });
      });

      it('moves focus to the namespace selector', () => {
        expect(focusedElement()).toBe(findNamespaceSelector().find('button').element);
      });
    });

    describe('when a group or project is selected without namespace permissions', () => {
      let event;

      beforeEach(async () => {
        await selectNamespaces([subgroup]);
        await selectPermissions({ namespace: [], user: ['execute_mcp_tool'], instance: [] });
        event = submitForm();
        await nextTick();
      });

      it('blocks the submission', () => {
        expect(event.defaultPrevented).toBe(true);
      });

      it('shows the error on the permissions selector', () => {
        expect(findPermissionsSelector().props('error')).toBe(PERMISSIONS_ERROR);
        expect(findNamespaceSelector().props('error')).toBe('');
      });

      it('clears the error once a namespace permission is selected', async () => {
        await selectPermissions({
          namespace: ['read_project'],
          user: ['execute_mcp_tool'],
          instance: [],
        });

        expect(findPermissionsSelector().props('error')).toBe('');
      });

      it('clears the error once the groups and projects are removed', async () => {
        await selectNamespaces([]);

        expect(findPermissionsSelector().props('error')).toBe('');
      });

      it('scrolls to the permissions selector', () => {
        expect(scrollToElement).toHaveBeenCalledWith(findPermissionsSelector().element, {
          behavior: 'smooth',
          offset: -100,
        });
      });

      it('moves focus to the permissions selector', () => {
        expect(focusedElement()).toBe(findPermissionsSelector().find('button').element);
      });
    });

    it('blocks the submission when only a group or project is selected', async () => {
      await selectNamespaces([subgroup]);

      expect(submitForm().defaultPrevented).toBe(true);
    });

    it('allows the submission when a group or project is selected', async () => {
      await selectNamespaces([subgroup]);
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });

      expect(submitForm().defaultPrevented).toBe(false);
      await nextTick();
      expect(findNamespaceSelector().props('error')).toBe('');
    });

    it('allows the submission with only user permissions', async () => {
      await selectPermissions({ namespace: [], user: ['execute_mcp_tool'], instance: [] });

      expect(submitForm().defaultPrevented).toBe(false);
    });

    it('allows the submission when nothing is selected', () => {
      expect(submitForm().defaultPrevented).toBe(false);
    });

    it('stops validating the form once destroyed', async () => {
      await selectPermissions({ namespace: ['read_project'], user: [], instance: [] });
      wrapper.destroy();

      expect(submitForm().defaultPrevented).toBe(false);
    });
  });
});
