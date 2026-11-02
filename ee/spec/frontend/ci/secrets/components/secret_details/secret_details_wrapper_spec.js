import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import {
  GlAlert,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlModal,
} from '@gitlab/ui';
import { createAlert } from '~/alert';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  EDIT_ROUTE_NAME,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  ENTITY_GROUP,
  ENTITY_PROJECT,
  INDEX_ROUTE_NAME,
  SECRET_ROTATION_STATUS,
} from 'ee/ci/secrets/constants';
import { SECRETS_MANAGER_CONTEXT_CONFIG } from 'ee/ci/secrets/context_config';
import SecretDeleteModal from 'ee/ci/secrets/components/secret_delete_modal.vue';
import SecretDetailsWrapper from 'ee/ci/secrets/components/secret_details/secret_details_wrapper.vue';
import { mockGroupSecretQueryResponse, mockProjectSecretQueryResponse } from '../../mock_data';

jest.mock('~/alert');
Vue.use(VueApollo);
const { bindInternalEventDocument } = useMockInternalEventsTracking();

describe('SecretDetailsWrapper component', () => {
  let wrapper;
  let mockApollo;
  let mockSecretQuery;

  const mockRouter = {
    push: jest.fn(),
    replace: jest.fn(),
  };

  const defaultProps = {
    secretName: 'SECRET_KEY',
  };

  const createComponent = async ({
    context = ENTITY_PROJECT,
    provide = {},
    stubs = { GlDisclosureDropdown, GlDisclosureDropdownItem, SecretDeleteModal },
    isLoading = false,
    mountFn = shallowMountExtended,
  } = {}) => {
    const contextConfig = SECRETS_MANAGER_CONTEXT_CONFIG[context];
    mockApollo = createMockApollo([[contextConfig.getSecretDetails.query, mockSecretQuery]]);

    wrapper = mountFn(SecretDetailsWrapper, {
      apolloProvider: mockApollo,
      provide: {
        canDeleteSecret: true,
        canUpdateSecret: true,
        contextConfig,
        entitlement: null,
        fullPath: '/path/to/entity',
        hasNoReadAccess: false,
        isBetaUser: false,
        ...provide,
      },
      propsData: {
        ...defaultProps,
      },
      stubs: {
        RouterView: true,
        ...stubs,
      },
      mocks: {
        $router: mockRouter,
      },
    });

    if (!isLoading) {
      await waitForPromises();
    }
  };

  const findDisclosureDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findDeleteButton = () =>
    findDisclosureDropdown().findAllComponents(GlDisclosureDropdownItem).at(0).find('button');
  const findDeleteModal = () => wrapper.findComponent(GlModal);
  const findSecretDeleteModalComponent = () => wrapper.findComponent(SecretDeleteModal);
  const findEditButton = () => wrapper.findComponentByTestId('secret-edit-button');
  const findKey = () => wrapper.find('h1');
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findRotationAlert = () => wrapper.findComponent(GlAlert);

  beforeEach(() => {
    mockSecretQuery = jest.fn();
  });

  describe.each`
    context           | secretName          | mockResponse                      | visitEvent
    ${ENTITY_PROJECT} | ${'PROJECT_SECRET'} | ${mockProjectSecretQueryResponse} | ${'visit_project_secrets_manager'}
    ${ENTITY_GROUP}   | ${'GROUP_SECRET'}   | ${mockGroupSecretQueryResponse}   | ${'visit_group_secrets_manager'}
  `(
    'viewing the secret details in $context context',
    ({ context, secretName, mockResponse, visitEvent }) => {
      describe('when query is loading', () => {
        it('renders loading icon', () => {
          createComponent({ context, isLoading: true });

          expect(findLoadingIcon().exists()).toBe(true);
          expect(createAlert).not.toHaveBeenCalled();
        });
      });

      describe('when query fails', () => {
        const error = new Error('GraphQL error: API error');

        beforeEach(async () => {
          mockSecretQuery.mockRejectedValue(error);
          await createComponent({ context });
        });

        it('does not render secret details', () => {
          expect(findKey().exists()).toBe(false);
        });

        it('renders alert message', () => {
          expect(findLoadingIcon().exists()).toBe(false);
          expect(createAlert).toHaveBeenCalledWith({
            message: 'API error',
            captureError: true,
            error,
          });
        });
      });

      describe('when query succeeds', () => {
        beforeEach(async () => {
          mockSecretQuery.mockResolvedValue(mockResponse());
          await createComponent({ context });
        });

        it('does not render loading icon', () => {
          expect(findLoadingIcon().exists()).toBe(false);
        });

        it('renders secret details', () => {
          expect(findKey().text()).toBe(secretName);
        });

        it('shows a link to the edit secret page', async () => {
          createComponent({ context });
          await waitForPromises();

          findEditButton().vm.$emit('click');
          expect(mockRouter.push).toHaveBeenCalledWith({
            name: EDIT_ROUTE_NAME,
            params: { secretName: defaultProps.secretName },
          });
        });
      });

      describe('event tracking', () => {
        it('tracks page visit', async () => {
          await createComponent({ context });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          expect(trackEventSpy).toHaveBeenCalledTimes(1);
          expect(trackEventSpy).toHaveBeenCalledWith(
            visitEvent,
            { label: 'secret_details_page' },
            undefined,
          );
        });
      });
    },
  );

  describe('delete secrets modal', () => {
    beforeEach(async () => {
      mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse());
      await createComponent();
    });

    it('renders modal when clicking on the delete button', async () => {
      expect(findDeleteModal().props('visible')).toBe(false);

      findDeleteButton().trigger('click');
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(true);
    });

    it('can reopen modal after it is hidden', async () => {
      findDeleteButton().trigger('click');
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(true);

      findSecretDeleteModalComponent().vm.$emit('hide');
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(false);

      findDeleteButton().trigger('click');
      await nextTick();

      expect(findDeleteModal().props('visible')).toBe(true);
    });
  });

  // the following tests work for project context only
  describe('rotation alert banner', () => {
    describe('when secret has no rotation info', () => {
      beforeEach(async () => {
        await createComponent();
        mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse());
      });

      it('does not render rotation alert', () => {
        expect(findRotationAlert().exists()).toBe(false);
      });
    });

    describe('when secret rotation status is approaching', () => {
      const nextReminderAt = '2026-01-15T10:30:00Z';

      beforeEach(async () => {
        const customSecret = {
          rotationInfo: {
            rotationIntervalDays: 7,
            status: SECRET_ROTATION_STATUS.approaching,
            nextReminderAt,
            __typename: 'SecretRotationInfo',
          },
        };

        mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse({ customSecret }));
        await createComponent();
      });

      it('renders rotation alert with approaching status and message', () => {
        const alert = findRotationAlert();
        expect(alert.props('variant')).toBe('warning');
        expect(alert.props('title')).toBe('Rotation reminder');
        expect(alert.text()).toBe('Update this secret by Jan 15, 2026 to maintain security.');
      });

      it('displays formatted date in alert message', () => {
        const alert = findRotationAlert();
        expect(alert.text()).toContain('Update this secret by Jan 15, 2026 to maintain security.');
      });
    });

    describe('when secret rotation status is overdue', () => {
      beforeEach(async () => {
        const customSecret = {
          rotationInfo: {
            rotationIntervalDays: 7,
            status: SECRET_ROTATION_STATUS.overdue,
            nextReminderAt: '2026-01-15T10:30:00Z',
            __typename: 'SecretRotationInfo',
          },
        };

        mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse({ customSecret }));
        await createComponent();
      });

      it('renders rotation alert with overdue status and message', () => {
        const alert = findRotationAlert();
        expect(alert.props('variant')).toBe('warning');
        expect(alert.props('title')).toBe('Secret overdue for rotation');
        expect(alert.text()).toBe(
          'This secret has not been rotated after the configured rotation reminder interval.',
        );
      });
    });

    describe('when secret has OK rotation status', () => {
      beforeEach(async () => {
        const customSecret = {
          rotationInfo: {
            status: 'OK',
            nextReminderAt: '2024-01-15T10:30:00Z',
            __typename: 'SecretRotationInfo',
          },
        };
        mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse({ customSecret }));
        await createComponent();
      });

      it('does not render rotation alert', () => {
        expect(findRotationAlert().exists()).toBe(false);
      });
    });
  });

  describe('when entitlement state is trial eligible', () => {
    beforeEach(() => {
      mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse());
    });

    it('redirects to the index route', async () => {
      await createComponent({
        provide: {
          entitlement: { state: ENTITLEMENT_STATE_TRIAL_ELIGIBLE },
        },
      });

      expect(mockRouter.replace).toHaveBeenCalledWith({ name: INDEX_ROUTE_NAME });
    });

    it('does not redirect a beta cohort user', async () => {
      await createComponent({
        provide: {
          entitlement: { state: ENTITLEMENT_STATE_TRIAL_ELIGIBLE },
          isBetaUser: true,
        },
      });

      expect(mockRouter.replace).not.toHaveBeenCalled();
    });
  });

  describe('when the user has no read access', () => {
    beforeEach(async () => {
      await createComponent({ provide: { hasNoReadAccess: true } });
    });

    it('redirects to the index route without fetching the secret', () => {
      expect(mockRouter.replace).toHaveBeenCalledWith({ name: INDEX_ROUTE_NAME });
      expect(mockSecretQuery).not.toHaveBeenCalled();
    });
  });

  describe('when the user cannot update secrets', () => {
    beforeEach(async () => {
      mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse());
      await createComponent({ provide: { canUpdateSecret: false } });
    });

    it('hides edit button', () => {
      expect(findEditButton().exists()).toBe(false);
    });

    it('shows actions dropdown', () => {
      expect(findDisclosureDropdown().exists()).toBe(true);
    });
  });

  describe('when the user cannot delete secrets', () => {
    beforeEach(async () => {
      mockSecretQuery.mockResolvedValue(mockProjectSecretQueryResponse());
      await createComponent({ provide: { canDeleteSecret: false } });
    });

    it('shows edit button', () => {
      expect(findEditButton().exists()).toBe(true);
    });

    it('hides actions dropdown', () => {
      expect(findDisclosureDropdown().exists()).toBe(false);
    });
  });
});
