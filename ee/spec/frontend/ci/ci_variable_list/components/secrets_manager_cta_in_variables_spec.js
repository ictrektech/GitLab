import { GlBadge, GlButton, GlIcon, GlLink, GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { helpPagePath } from '~/helpers/help_page_helper';
import SecretsManagerCtaInVariables from 'ee/ci/ci_variable_list/components/secrets_manager_cta_in_variables.vue';
import {
  SECRETS_MANAGER_CTA_CLICK_EVENT,
  SECRETS_MANAGER_CTA_VIEW_EVENT,
  SECRETS_MANAGER_CTA_LABEL_VIEW,
  SECRETS_MANAGER_CTA_LABEL_INFO,
  SECRETS_MANAGER_CTA_LABEL_LEARN_MORE,
  SECRETS_MANAGER_CTA_LABEL_REQUEST,
  SECRETS_MANAGER_CTA_LABEL_TRY,
  SECRETS_MANAGER_REQUEST_MODAL_ID,
  VARIANT_INFO,
  VARIANT_REQUEST,
  VARIANT_TRY,
  VARIANT_VIEW,
} from 'ee/ci/ci_variable_list/constants';

const DISABLED_BODY =
  'Use GitLab Secrets Manager to store your sensitive credentials, and then safely use them in your processes. Secrets could be access tokens, database credentials, private keys, or similar. Learn more.';
const ENABLED_BODY =
  'Store your sensitive credentials in GitLab Secrets Manager and safely use them in your processes. Unlike CI/CD variables, which are always available to jobs by default, secrets must be explicitly requested by a job. Learn more.';

describe('SecretsManagerCtaInVariables', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const ctaPath = '/path/to/cta';

  // The server sends the same facts as for the vulnerability page, and the component derives the variant.
  const ctaFor = (variant) =>
    ({
      [VARIANT_VIEW]: { secretsManagerAvailable: true, secretsPath: ctaPath },
      [VARIANT_INFO]: { secretsManagerAvailable: true },
      [VARIANT_TRY]: {
        secretsManagerAvailable: false,
        canStartTrial: true,
        secretsPath: '/other/path',
        startTrialPath: ctaPath,
      },
      [VARIANT_REQUEST]: {
        secretsManagerAvailable: false,
        canStartTrial: false,
        secretsPath: '/other/path',
      },
    })[variant];

  const createComponent = (cta, props = {}) => {
    wrapper = shallowMountExtended(SecretsManagerCtaInVariables, {
      propsData: { entity: 'project', ...props },
      provide: { secretsManagerCtaInVariables: cta },
      stubs: {
        GlSprintf,
        GlLink,
        GlModal: stubComponent(GlModal, { template: RENDER_ALL_SLOTS_TEMPLATE }),
      },
      directives: { GlModal: createMockDirective('gl-modal') },
    });
  };

  const findIcon = () => wrapper.findComponent(GlIcon);
  const findTitle = () => wrapper.findByTestId('secrets-manager-cta-title');
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findBody = () => wrapper.findByTestId('secrets-manager-cta-body');
  const findLearnMore = () => wrapper.findComponent(GlLink);
  const findButton = () => wrapper.findComponent(GlButton);
  const findModal = () => wrapper.findComponent(GlModal);

  describe('visibility', () => {
    it.each([true, false])('renders the card as visible: %s', (visible) => {
      createComponent(ctaFor(VARIANT_VIEW), { visible });

      expect(wrapper.isVisible()).toBe(visible);
    });
  });

  describe('variant', () => {
    it.each`
      secretsManagerAvailable | canStartTrial | secretsPath  | expected
      ${true}                 | ${false}      | ${ctaPath}   | ${VARIANT_VIEW}
      ${true}                 | ${true}       | ${ctaPath}   | ${VARIANT_VIEW}
      ${true}                 | ${false}      | ${undefined} | ${VARIANT_INFO}
      ${false}                | ${true}       | ${ctaPath}   | ${VARIANT_TRY}
      ${false}                | ${false}      | ${ctaPath}   | ${VARIANT_REQUEST}
    `(
      'is $expected when available: $secretsManagerAvailable, can start a trial: $canStartTrial, secrets path: $secretsPath',
      ({ secretsManagerAvailable, canStartTrial, secretsPath, expected }) => {
        const { trackEventSpy } = bindInternalEventDocument(document);
        const labels = {
          [VARIANT_VIEW]: SECRETS_MANAGER_CTA_LABEL_VIEW,
          [VARIANT_INFO]: SECRETS_MANAGER_CTA_LABEL_INFO,
          [VARIANT_TRY]: SECRETS_MANAGER_CTA_LABEL_TRY,
          [VARIANT_REQUEST]: SECRETS_MANAGER_CTA_LABEL_REQUEST,
        };

        createComponent({ secretsManagerAvailable, canStartTrial, secretsPath });

        expect(trackEventSpy).toHaveBeenCalledWith(
          SECRETS_MANAGER_CTA_VIEW_EVENT,
          { label: labels[expected], property: 'project' },
          undefined,
        );
      },
    );
  });

  describe.each`
    variant            | path       | level         | icon                       | title                               | badge    | body             | buttonText                          | label
    ${VARIANT_TRY}     | ${ctaPath} | ${'project'}  | ${'secrets-manager'}       | ${'GitLab Secrets Manager'}         | ${'New'} | ${DISABLED_BODY} | ${'Try GitLab Secrets Manager'}     | ${SECRETS_MANAGER_CTA_LABEL_TRY}
    ${VARIANT_REQUEST} | ${null}    | ${'group'}    | ${'secrets-manager'}       | ${'GitLab Secrets Manager'}         | ${'New'} | ${DISABLED_BODY} | ${'Request GitLab Secrets Manager'} | ${SECRETS_MANAGER_CTA_LABEL_REQUEST}
    ${VARIANT_VIEW}    | ${ctaPath} | ${'project'}  | ${'work-item-enhancement'} | ${'Are you creating a new secret?'} | ${null}  | ${ENABLED_BODY}  | ${'View GitLab Secrets Manager'}    | ${SECRETS_MANAGER_CTA_LABEL_VIEW}
    ${VARIANT_INFO}    | ${null}    | ${'instance'} | ${'work-item-enhancement'} | ${'Are you creating a new secret?'} | ${null}  | ${ENABLED_BODY}  | ${null}                             | ${SECRETS_MANAGER_CTA_LABEL_INFO}
  `('$variant variant', ({ variant, path, level, icon, title, badge, body, buttonText, label }) => {
    beforeEach(() => {
      createComponent(ctaFor(variant), { entity: level });
    });

    it('renders the icon', () => {
      expect(findIcon().props('name')).toBe(icon);
    });

    it('renders the title', () => {
      expect(findTitle().text()).toBe(title);
    });

    it(`${badge ? 'renders' : 'does not render'} the badge`, () => {
      expect(findBadge().exists()).toBe(Boolean(badge));
      if (badge) {
        expect(findBadge().text()).toBe(badge);
      }
    });

    it('renders the body text', () => {
      expect(findBody().text()).toBe(body);
    });

    it('renders the Learn more link, opening in a new tab so an unsaved variable is kept', () => {
      expect(findLearnMore().attributes('href')).toBe(
        helpPagePath('ci/secrets/secrets_manager/_index'),
      );
      expect(findLearnMore().attributes('target')).toBe('_blank');
    });

    it(`${buttonText ? 'renders' : 'does not render'} the button`, () => {
      expect(findButton().exists()).toBe(Boolean(buttonText));
      if (buttonText) {
        expect(findButton().text()).toBe(buttonText);
        expect(findButton().attributes('href')).toBe(path ?? undefined);
      }
    });

    if (path) {
      it('opens the button link in a new tab so an unsaved variable is kept', () => {
        expect(findButton().attributes('target')).toBe('_blank');
      });
    }

    it('tracks a click on Learn more', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findLearnMore().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        SECRETS_MANAGER_CTA_CLICK_EVENT,
        { label: SECRETS_MANAGER_CTA_LABEL_LEARN_MORE, property: level },
        undefined,
      );
    });

    if (buttonText) {
      it('tracks a click on the button', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findButton().vm.$emit('click');

        expect(trackEventSpy).toHaveBeenCalledWith(
          SECRETS_MANAGER_CTA_CLICK_EVENT,
          { label, property: level },
          undefined,
        );
      });
    }
  });

  describe('request modal', () => {
    describe('for the request variant', () => {
      beforeEach(() => {
        createComponent(ctaFor(VARIANT_REQUEST), { entity: 'group' });
      });

      it('opens from the button and tells the user to ask their owner or administrator', () => {
        expect(getBinding(findButton().element, 'gl-modal').value).toBe(
          SECRETS_MANAGER_REQUEST_MODAL_ID,
        );
        expect(findModal().props('title')).toBe('Request GitLab Secrets Manager');
        expect(findModal().text()).toBe(
          'To use GitLab Secrets Manager, request it from your group owner or instance administrator.',
        );
      });

      it('reports when the modal is open, so the drawer can ignore ESC meant for the modal', () => {
        findModal().vm.$emit('show');
        findModal().vm.$emit('hidden');

        expect(wrapper.emitted('modal-toggle')).toEqual([[true], [false]]);
      });
    });

    it.each`
      variant         | path       | level
      ${VARIANT_TRY}  | ${ctaPath} | ${'project'}
      ${VARIANT_VIEW} | ${ctaPath} | ${'project'}
      ${VARIANT_INFO} | ${null}    | ${'instance'}
    `('is not rendered for the $variant variant', ({ variant, path, level }) => {
      createComponent(ctaFor(variant), { entity: level });

      expect(findModal().exists()).toBe(false);
      if (path) expect(getBinding(findButton().element, 'gl-modal').value).toBeUndefined();
    });
  });

  describe('view tracking', () => {
    it('tracks a view event with the variant and level on mount', () => {
      const { trackEventSpy } = bindInternalEventDocument(document);

      createComponent(ctaFor(VARIANT_TRY), { entity: 'group' });

      expect(trackEventSpy).toHaveBeenCalledWith(
        SECRETS_MANAGER_CTA_VIEW_EVENT,
        { label: SECRETS_MANAGER_CTA_LABEL_TRY, property: 'group' },
        undefined,
      );
    });

    it.each`
      variant            | level         | label
      ${VARIANT_TRY}     | ${'project'}  | ${SECRETS_MANAGER_CTA_LABEL_TRY}
      ${VARIANT_REQUEST} | ${'group'}    | ${SECRETS_MANAGER_CTA_LABEL_REQUEST}
      ${VARIANT_VIEW}    | ${'project'}  | ${SECRETS_MANAGER_CTA_LABEL_VIEW}
      ${VARIANT_INFO}    | ${'instance'} | ${SECRETS_MANAGER_CTA_LABEL_INFO}
    `('reports the $label label for the $variant variant', ({ variant, level, label }) => {
      const { trackEventSpy } = bindInternalEventDocument(document);

      createComponent(ctaFor(variant), { entity: level });

      expect(trackEventSpy).toHaveBeenCalledWith(
        SECRETS_MANAGER_CTA_VIEW_EVENT,
        { label, property: level },
        undefined,
      );
    });

    describe('when the card is toggled', () => {
      const cta = ctaFor(VARIANT_TRY);

      const mountCard = (props) => {
        wrapper = shallowMountExtended(SecretsManagerCtaInVariables, {
          propsData: { entity: 'project', ...props },
          provide: { secretsManagerCtaInVariables: cta },
        });
      };

      it('does not track a view event while the card is hidden', () => {
        const { trackEventSpy } = bindInternalEventDocument(document);

        mountCard({ visible: false });

        expect(trackEventSpy).not.toHaveBeenCalled();
      });

      it('tracks a view event the first time the card is shown', async () => {
        const { trackEventSpy } = bindInternalEventDocument(document);

        mountCard({ visible: false });
        await wrapper.setProps({ visible: true });

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith(
          SECRETS_MANAGER_CTA_VIEW_EVENT,
          { label: SECRETS_MANAGER_CTA_LABEL_TRY, property: 'project' },
          undefined,
        );
      });

      it('does not track another view event when the card is hidden and shown again', async () => {
        const { trackEventSpy } = bindInternalEventDocument(document);

        mountCard({});
        await wrapper.setProps({ visible: false });
        await wrapper.setProps({ visible: true });

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });
  });
});
