import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlDatepicker, GlModal } from '@gitlab/ui';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createAlert } from '~/alert';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { ALERT_CONTAINER_SELECTOR } from 'ee/pages/projects/shared/permissions/secrets_manager/constants';
import PermissionsModal from 'ee/pages/projects/shared/permissions/secrets_manager/components/secrets_manager_permissions_modal.vue';
import createSecretsPermissionMutation from 'ee/pages/projects/shared/permissions/secrets_manager/graphql/create_secrets_permission.mutation.graphql';
import createGroupSecretsPermissionMutation from 'ee/pages/projects/shared/permissions/secrets_manager/graphql/create_group_secrets_permission.mutation.graphql';
import searchProjectMembersQuery from '~/graphql_shared/queries/project_user_members_search.query.graphql';
import groupUsersSearchQuery from '~/graphql_shared/queries/group_users_search.query.graphql';
import { SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG } from 'ee/pages/projects/shared/permissions/secrets_manager/context_config';
import { ENTITY_PROJECT, ENTITY_GROUP } from 'ee/ci/secrets/constants';
import {
  mockCreatePermissionResponse,
  mockCreatePermissionErrorResponse,
  mockCreateGroupPermissionResponse,
  mockCreateGroupPermissionErrorResponse,
  mockGroupMembersQueryResponse,
  mockProjectMembersQueryResponse,
} from '../mock_data';

jest.mock('~/alert');

const mockToastShow = jest.fn();
Vue.use(VueApollo);

describe('SecretsManagerPermissionsModal', () => {
  let wrapper;
  let mockApollo;
  let mockCreatePermission;
  let mockMemberSearchQuery;

  const contextConfigs = [
    {
      context: 'project',
      fullPath: '/path/to/project',
      mutation: createSecretsPermissionMutation,
      memberSearchQuery: searchProjectMembersQuery,
      mockSuccessResponse: mockCreatePermissionResponse,
      mockErrorResponse: mockCreatePermissionErrorResponse,
      mockMemberSearchQueryResponse: mockProjectMembersQueryResponse,
      relations: SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG[ENTITY_PROJECT].searchMembers.relations,
    },
    {
      context: 'group',
      fullPath: '/path/to/group',
      mutation: createGroupSecretsPermissionMutation,
      memberSearchQuery: groupUsersSearchQuery,
      mockSuccessResponse: mockCreateGroupPermissionResponse,
      mockErrorResponse: mockCreateGroupPermissionErrorResponse,
      mockMemberSearchQueryResponse: mockGroupMembersQueryResponse,
      relations: SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG[ENTITY_GROUP].searchMembers.relations,
    },
  ];

  const createComponent = ({ permissionCategory = null, context = 'project' } = {}) => {
    const config = contextConfigs.find((c) => c.context === context);

    mockApollo = createMockApollo([
      [config.mutation, mockCreatePermission],
      [config.memberSearchQuery, mockMemberSearchQuery],
    ]);

    wrapper = shallowMountExtended(PermissionsModal, {
      apolloProvider: mockApollo,
      propsData: {
        permissionCategory,
        fullPath: config.fullPath,
        projectId: 123,
        context,
      },
      mocks: {
        $toast: { show: mockToastShow },
      },
    });
  };

  const findDatepicker = () => wrapper.findComponent(GlDatepicker);
  const findReadMetadataCheckbox = () => wrapper.findComponentByTestId('read-metadata-checkbox');
  const findReadValueCheckbox = () => wrapper.findComponentByTestId('read-value-checkbox');
  const findDeleteCheckbox = () => wrapper.findComponentByTestId('delete-checkbox');
  const findCreateCheckbox = () => wrapper.findComponentByTestId('create-checkbox');
  const findUpdateCheckbox = () => wrapper.findComponentByTestId('update-checkbox');
  const findModal = () => wrapper.findComponent(GlModal);
  const findPrincipalField = () => wrapper.findComponent(GlCollapsibleListbox);

  const inputRequiredFields = async (selectedItem = 'MAINTAINER') => {
    // expiredAt is optional
    findReadMetadataCheckbox().vm.$emit('input', true);
    findReadValueCheckbox().vm.$emit('input', true);
    findDeleteCheckbox().vm.$emit('input', true);

    findPrincipalField().vm.$emit('select', selectedItem);

    await nextTick();
  };

  const submitPermission = async ({
    includeOptionalFields = false,
    selectedItem = 'MAINTAINER',
  } = {}) => {
    if (includeOptionalFields) {
      findDatepicker().vm.$emit('input', new Date('2055-08-12'));
    }

    await inputRequiredFields(selectedItem);
    findModal().vm.$emit('primary', { preventDefault: jest.fn() });
    await waitForPromises();
  };

  const waitForDebounce = () => {
    jest.runOnlyPendingTimers();
    return waitForPromises();
  };

  beforeEach(() => {
    mockCreatePermission = jest.fn().mockResolvedValue(mockCreatePermissionResponse);
    mockMemberSearchQuery = jest.fn().mockResolvedValue(mockProjectMembersQueryResponse);
  });

  describe('template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('hides modal when permission category is not provided', () => {
      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('modal behavior', () => {
    beforeEach(() => {
      createComponent({ permissionCategory: 'ROLE' });
    });

    it('disables all checkboxes except Read metadata', () => {
      expect(findReadMetadataCheckbox().attributes('disabled')).toBeUndefined();
      expect(findReadValueCheckbox().attributes('disabled')).toBeDefined();
      expect(findDeleteCheckbox().attributes('disabled')).toBeDefined();
      expect(findCreateCheckbox().attributes('disabled')).toBeDefined();
      expect(findUpdateCheckbox().attributes('disabled')).toBeDefined();
    });

    describe('when Read metadata is selected', () => {
      beforeEach(async () => {
        findReadMetadataCheckbox().vm.$emit('input', true);
        await nextTick();
      });

      it('enables all checkboxes except Update', () => {
        expect(findReadValueCheckbox().attributes('disabled')).toBeUndefined();
        expect(findDeleteCheckbox().attributes('disabled')).toBeUndefined();
        expect(findCreateCheckbox().attributes('disabled')).toBeUndefined();
        expect(findUpdateCheckbox().attributes('disabled')).toBeDefined();
      });

      describe('when Create is selected', () => {
        beforeEach(async () => {
          findCreateCheckbox().vm.$emit('input', true);
          await nextTick();
        });

        it('enables Update', () => {
          expect(findUpdateCheckbox().attributes('disabled')).toBeUndefined();
        });
      });
    });

    it.each`
      modalEvent     | emittedEvent
      ${'canceled'}  | ${'hide'}
      ${'hidden'}    | ${'hide'}
      ${'secondary'} | ${'hide'}
    `(
      'emits the $emittedEvent event when $modalEvent event is triggered',
      ({ modalEvent, emittedEvent }) => {
        expect(wrapper.emitted(emittedEvent)).toBeUndefined();

        findModal().vm.$emit(modalEvent);

        expect(wrapper.emitted(emittedEvent)).toHaveLength(1);
      },
    );
  });

  const USER_ITEMS = ['Administrator', 'John Doe'];
  const ROLE_ITEMS = ['Reporter', 'Security Manager', 'Developer', 'Maintainer'];

  describe.each([
    {
      contextName: 'project',
      contextConfig: contextConfigs[0],
    },
    {
      contextName: 'group',
      contextConfig: contextConfigs[1],
    },
  ])('$contextName context', ({ contextName, contextConfig }) => {
    describe.each`
      category  | title         | fieldItems    | selectedItem    | principalId
      ${'USER'} | ${'Add user'} | ${USER_ITEMS} | ${'john.doe'}   | ${2}
      ${'ROLE'} | ${'Add role'} | ${ROLE_ITEMS} | ${'MAINTAINER'} | ${40}
    `(
      '$category permissions form',
      ({ category, title, fieldItems, selectedItem, principalId }) => {
        beforeEach(async () => {
          mockCreatePermission = jest.fn().mockResolvedValue(contextConfig.mockSuccessResponse);
          mockMemberSearchQuery = jest
            .fn()
            .mockResolvedValue(contextConfig.mockMemberSearchQueryResponse);
          createComponent({ permissionCategory: category, context: contextName });
          if (category === 'USER') {
            findPrincipalField().vm.$emit('shown');
            await waitForPromises();
          }
        });

        it('renders modal', () => {
          expect(findModal().props('visible')).toBe(true);
        });

        it('renders template correctly', () => {
          expect(findModal().props('title')).toBe(title);
          expect(findDatepicker().exists()).toBe(true);
          expect(findReadMetadataCheckbox().text()).toContain('Read metadata');
          expect(findReadValueCheckbox().text()).toContain('Read value');
          expect(findDeleteCheckbox().text()).toContain('Delete');
          expect(findCreateCheckbox().text()).toContain('Create');
          expect(findUpdateCheckbox().text()).toContain('Update');
        });

        it('sets expiration date in the future', () => {
          const today = new Date();
          const expirationMinDate = findDatepicker().props('minDate').getTime();
          expect(expirationMinDate).toBeGreaterThan(today.getTime());
        });

        it('fills listbox with correct items', () => {
          const actualFieldItems = findPrincipalField()
            .props('items')
            .map((item) => item.text);

          expect(actualFieldItems).toEqual(fieldItems);
        });

        it('calls the create mutation with the correct variables', async () => {
          await submitPermission({ includeOptionalFields: true, selectedItem });

          expect(mockCreatePermission).toHaveBeenCalledWith({
            fullPath: contextConfig.fullPath,
            principal: {
              id: principalId,
              type: category,
            },
            actions: ['READ', 'READ_VALUE', 'DELETE'],
            expiredAt: '2055-08-12',
          });
        });

        describe('when only Create is selected', () => {
          beforeEach(async () => {
            findReadMetadataCheckbox().vm.$emit('input', true);
            findCreateCheckbox().vm.$emit('input', true);
            findPrincipalField().vm.$emit('select', selectedItem);
            await nextTick();

            findModal().vm.$emit('primary', { preventDefault: jest.fn() });
            await waitForPromises();
          });

          it('calls the create mutation with the CREATE action', () => {
            expect(mockCreatePermission).toHaveBeenCalledWith(
              expect.objectContaining({ actions: ['READ', 'CREATE'] }),
            );
          });
        });

        describe('when Create and Update are selected', () => {
          beforeEach(async () => {
            findReadMetadataCheckbox().vm.$emit('input', true);
            findCreateCheckbox().vm.$emit('input', true);
            await nextTick();
            findUpdateCheckbox().vm.$emit('input', true);
            findPrincipalField().vm.$emit('select', selectedItem);
            await nextTick();

            findModal().vm.$emit('primary', { preventDefault: jest.fn() });
            await waitForPromises();
          });

          it('calls the create mutation with the WRITE action', () => {
            expect(mockCreatePermission).toHaveBeenCalledWith(
              expect.objectContaining({ actions: ['READ', 'CREATE', 'WRITE'] }),
            );
          });
        });

        describe('when Create is cleared after Update is selected', () => {
          beforeEach(async () => {
            findReadMetadataCheckbox().vm.$emit('input', true);
            findCreateCheckbox().vm.$emit('input', true);
            await nextTick();
            findUpdateCheckbox().vm.$emit('input', true);
            await nextTick();

            findCreateCheckbox().vm.$emit('input', false);
            await nextTick();
            findCreateCheckbox().vm.$emit('input', true);
            findPrincipalField().vm.$emit('select', selectedItem);
            await nextTick();

            findModal().vm.$emit('primary', { preventDefault: jest.fn() });
            await waitForPromises();
          });

          it('clears Update', () => {
            expect(mockCreatePermission).toHaveBeenCalledWith(
              expect.objectContaining({ actions: ['READ', 'CREATE'] }),
            );
          });
        });
      },
    );

    describe('when submission is successful', () => {
      beforeEach(() => {
        mockCreatePermission = jest.fn().mockResolvedValue(contextConfig.mockSuccessResponse);
        mockMemberSearchQuery = jest
          .fn()
          .mockResolvedValue(contextConfig.mockMemberSearchQueryResponse);
        createComponent({ permissionCategory: 'ROLE', context: contextName });
      });

      it('disables submission button by default', () => {
        expect(findModal().props('actionPrimary').attributes.disabled).toBe(true);
      });

      it('enables submission button when required fields are provided', async () => {
        await inputRequiredFields();

        expect(findModal().props('actionPrimary').attributes.disabled).toBe(false);
      });

      it('emits the refetch event', async () => {
        expect(wrapper.emitted('refetch')).toBeUndefined();

        await submitPermission();

        expect(wrapper.emitted('refetch')).toHaveLength(1);
      });

      it('hides modal and shows toast message on successful submission', async () => {
        expect(mockCreatePermission).toHaveBeenCalledTimes(0);

        await submitPermission();

        expect(mockCreatePermission).toHaveBeenCalledTimes(1);
        expect(wrapper.emitted('hide')).toHaveLength(1);
        expect(mockToastShow).toHaveBeenCalledWith(
          'Secrets manager permissions were successfully updated.',
        );
      });
    });

    describe('when submission returns errors', () => {
      beforeEach(() => {
        mockCreatePermission = jest
          .fn()
          .mockResolvedValue(contextConfig.mockErrorResponse('This permission is invalid.'));
        mockMemberSearchQuery = jest
          .fn()
          .mockResolvedValue(contextConfig.mockMemberSearchQueryResponse);
        createComponent({ permissionCategory: 'ROLE', context: contextName });
      });

      it('renders error message from API', async () => {
        await submitPermission();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'This permission is invalid.',
          containerSelector: ALERT_CONTAINER_SELECTOR,
        });
      });
    });

    describe('when submission fails', () => {
      const error = new Error('GraphQL error: API error');
      beforeEach(() => {
        mockCreatePermission = jest.fn().mockRejectedValue(error);
        mockMemberSearchQuery = jest
          .fn()
          .mockResolvedValue(contextConfig.mockMemberSearchQueryResponse);
        createComponent({ permissionCategory: 'ROLE', context: contextName });
      });

      it('renders error message with GraphQL prefix stripped', async () => {
        await submitPermission();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'API error',
          captureError: true,
          error,
          containerSelector: ALERT_CONTAINER_SELECTOR,
        });
      });
    });

    describe('debounced search', () => {
      beforeEach(() => {
        mockCreatePermission = jest.fn().mockResolvedValue(contextConfig.mockSuccessResponse);
        mockMemberSearchQuery = jest
          .fn()
          .mockResolvedValue(contextConfig.mockMemberSearchQueryResponse);
        createComponent({ permissionCategory: 'USER', context: contextName });
      });

      it('uses debounced search for user listbox with correct relations from context_config', async () => {
        findPrincipalField().vm.$emit('shown');
        await waitForPromises();

        expect(mockMemberSearchQuery).toHaveBeenCalledTimes(1);
        expect(mockMemberSearchQuery).toHaveBeenCalledWith({
          fullPath: contextConfig.fullPath,
          search: '',
          accessLevels: ['REPORTER', 'DEVELOPER', 'MAINTAINER'],
          relations: contextConfig.relations,
        });

        findPrincipalField().vm.$emit('search', 'Foo');
        await waitForDebounce();

        expect(mockMemberSearchQuery).toHaveBeenCalledTimes(2);
        expect(mockMemberSearchQuery).toHaveBeenCalledWith({
          fullPath: contextConfig.fullPath,
          search: 'Foo',
          accessLevels: ['REPORTER', 'DEVELOPER', 'MAINTAINER'],
          relations: contextConfig.relations,
        });
      });
    });
  });
});
