import { GlButton, GlCard, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsEmptyState from 'ee/ci/secrets/components/secrets_empty_state.vue';
import {
  ENTITY_GROUP,
  ENTITY_PROJECT,
  NEW_ROUTE_NAME,
  SECRET_MANAGER_STATUS_ACTIVE,
} from 'ee/ci/secrets/constants';

describe('SecretsEmptyState component', () => {
  let wrapper;
  let mockRouterPush;

  const createComponent = ({
    props = {},
    context = ENTITY_PROJECT,
    provide = {},
    isProvisioning = false,
    isEnablingAddOn = false,
    secretManagerStatus = SECRET_MANAGER_STATUS_ACTIVE,
  } = {}) => {
    wrapper = shallowMountExtended(SecretsEmptyState, {
      propsData: props,
      provide: {
        contextConfig: { type: context },
        isEnablingAddOn,
        isProvisioning,
        secretManagerStatus,
        ...provide,
      },
      stubs: { GlCard },
      mocks: {
        $router: { push: mockRouterPush },
      },
    });
  };

  const findNewSecretButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findGroupSubheader = () => wrapper.findByTestId('group-subheader');
  const findContactOwnerAlert = () => wrapper.findByTestId('contact-owner-alert');
  const findNoReadAccessAlert = () => wrapper.findByTestId('no-read-access-alert');

  beforeEach(() => {
    mockRouterPush = jest.fn();
  });

  describe('subheader', () => {
    it('renders the subheader in group context', () => {
      createComponent({ context: ENTITY_GROUP });

      expect(findGroupSubheader().exists()).toBe(true);
      expect(findGroupSubheader().text()).toBe(
        'By default, all subgroups and projects can use stored secrets in their pipelines.',
      );
    });

    it('does not render the subheader in project context', () => {
      createComponent({ context: ENTITY_PROJECT });

      expect(findGroupSubheader().exists()).toBe(false);
    });
  });

  describe('"New secret" button visibility', () => {
    // The button either fires the Owner-only provisioning mutation
    // (unprovisioned) or opens the Reporter+ secret form (provisioned), so
    // it is gated on the ability matching the current status. actionsAllowed
    // (OpenBao health, read-only entitlement states) always wins.
    it.each`
      status                          | actionsAllowed | canProvision | canCreateSecret | rendered
      ${null}                         | ${true}        | ${true}      | ${false}        | ${true}
      ${null}                         | ${true}        | ${false}     | ${true}         | ${false}
      ${null}                         | ${false}       | ${true}      | ${true}         | ${false}
      ${SECRET_MANAGER_STATUS_ACTIVE} | ${true}        | ${false}     | ${true}         | ${true}
      ${SECRET_MANAGER_STATUS_ACTIVE} | ${true}        | ${true}      | ${false}        | ${false}
      ${SECRET_MANAGER_STATUS_ACTIVE} | ${false}       | ${true}      | ${true}         | ${false}
    `(
      'when status=$status, actionsAllowed=$actionsAllowed, canProvision=$canProvision, canCreateSecret=$canCreateSecret renders=$rendered',
      ({ status, actionsAllowed, canProvision, canCreateSecret, rendered }) => {
        createComponent({
          props: { actionsAllowed },
          provide: { canProvision, canCreateSecret },
          secretManagerStatus: status,
        });

        expect(findNewSecretButton().exists()).toBe(rendered);
      },
    );

    // A missing injection means the backend did not send the ability, so the
    // button must fail closed.
    it('does not render the button when abilities are not provided', () => {
      createComponent({ props: { actionsAllowed: true } });

      expect(findNewSecretButton().exists()).toBe(false);
    });
  });

  describe('contact owner alert', () => {
    // Only the unprovisioned page misses an Owner-only action; a blocked or
    // read-only entitlement is not a permissions problem, so no alert there.
    it.each`
      status                          | actionsAllowed | canProvision | shown
      ${null}                         | ${true}        | ${false}     | ${true}
      ${null}                         | ${true}        | ${true}      | ${false}
      ${null}                         | ${false}       | ${false}     | ${false}
      ${SECRET_MANAGER_STATUS_ACTIVE} | ${true}        | ${false}     | ${false}
    `(
      'when status=$status, actionsAllowed=$actionsAllowed, canProvision=$canProvision shown=$shown',
      ({ status, actionsAllowed, canProvision, shown }) => {
        createComponent({
          props: { actionsAllowed },
          provide: { canProvision },
          secretManagerStatus: status,
        });

        expect(findContactOwnerAlert().exists()).toBe(shown);
      },
    );

    it('names who can enable the secrets manager', () => {
      createComponent({
        props: { actionsAllowed: true },
        provide: { canProvision: false },
        secretManagerStatus: null,
      });

      expect(findContactOwnerAlert().text()).toBe(
        'Contact your group owner or instance administrator to enable GitLab Secrets Manager.',
      );
    });
  });

  describe('no read access alert', () => {
    it.each`
      context           | message
      ${ENTITY_GROUP}   | ${"You don't have permissions to read or create secrets in this group. Contact your group owner to request permissions."}
      ${ENTITY_PROJECT} | ${"You don't have permissions to read or create secrets in this project. Contact your project owner to request permissions."}
    `('renders the $context message when enabled', ({ context, message }) => {
      createComponent({ context, provide: { showNoReadAccessAlert: true } });

      expect(findNoReadAccessAlert().text()).toBe(message);
    });
  });

  describe('when the user can create secrets', () => {
    describe('when secrets manager is already provisioned', () => {
      beforeEach(() => {
        createComponent({
          props: { actionsAllowed: true },
          provide: { canCreateSecret: true },
          secretManagerStatus: SECRET_MANAGER_STATUS_ACTIVE,
        });
      });

      it('redirects to the new secret route when clicked', () => {
        findNewSecretButton().vm.$emit('click');

        expect(mockRouterPush).toHaveBeenCalledWith({ name: NEW_ROUTE_NAME });
      });

      it('does not emit provision-secrets-manager', () => {
        findNewSecretButton().vm.$emit('click');

        expect(wrapper.emitted('provision-secrets-manager')).toBeUndefined();
      });

      it('does not show the popover', () => {
        expect(findPopover().props('show')).toBe(false);
      });
    });

    describe('when secrets manager needs provisioning', () => {
      beforeEach(() => {
        createComponent({
          props: { actionsAllowed: true },
          provide: { canProvision: true },
          secretManagerStatus: null,
        });
      });

      it('emits provision-secrets-manager when clicked', () => {
        findNewSecretButton().vm.$emit('click');

        expect(wrapper.emitted('provision-secrets-manager')).toHaveLength(1);
      });

      it('does not redirect when clicked', () => {
        findNewSecretButton().vm.$emit('click');

        expect(mockRouterPush).not.toHaveBeenCalled();
      });
    });

    describe('when provisioning is in progress', () => {
      beforeEach(() => {
        createComponent({
          props: { actionsAllowed: true },
          provide: { canProvision: true },
          isProvisioning: true,
          secretManagerStatus: null,
        });
      });

      it('shows the loading state on the button', () => {
        expect(findNewSecretButton().props('loading')).toBe(true);
      });

      it('shows the popover', () => {
        expect(findPopover().props('show')).toBe(true);
      });
    });

    // isProvisioning also flips during the add-on enable flow, whose waiting
    // UI lives on the banner button -- so this button must stay quiet.
    describe('when the add-on enable is driving provisioning', () => {
      beforeEach(() => {
        createComponent({
          props: { actionsAllowed: true },
          provide: { canProvision: true },
          isProvisioning: true,
          isEnablingAddOn: true,
          secretManagerStatus: null,
        });
      });

      it('does not show the loading state on the button', () => {
        expect(findNewSecretButton().props('loading')).toBe(false);
      });

      it('does not show the popover', () => {
        expect(findPopover().props('show')).toBe(false);
      });
    });
  });
});
