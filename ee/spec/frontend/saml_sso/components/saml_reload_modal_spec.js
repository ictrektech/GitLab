import { shallowMount } from '@vue/test-utils';
import SamlReloadModal from 'ee/saml_sso/components/saml_reload_modal.vue';
import { getExpiringSamlSession } from 'ee/saml_sso/saml_sessions';
import SessionExpireModal from '~/authentication/sessions/components/session_expire_modal.vue';
import {
  BROADCAST_CHANNEL_SAML_SESSION_EXPIRY,
  BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN,
} from '~/authentication/sessions/constants';
import waitForPromises from 'helpers/wait_for_promises';

jest.useFakeTimers();

jest.mock('ee/saml_sso/saml_sessions', () => ({
  getExpiringSamlSession: jest.fn(),
}));

describe('SamlReloadModal', () => {
  let wrapper;

  const samlSessionsUrl = '/test.json';

  const createComponent = () => {
    wrapper = shallowMount(SamlReloadModal, {
      propsData: { samlProviderId: 1, samlSessionsUrl },
    });
  };

  const findModal = () => wrapper.findComponent(SessionExpireModal);

  describe('when there is no expiring SAML session', () => {
    it('does not show the modal', () => {
      createComponent();

      expect(findModal().exists()).toBe(false);
    });
  });

  describe('when there is an expired SAML sessions', () => {
    it('shows the modal', async () => {
      getExpiringSamlSession.mockResolvedValue({ timeRemainingMs: 0 });
      createComponent();
      await waitForPromises();

      expect(findModal().props()).toMatchObject({
        broadcastChannel: BROADCAST_CHANNEL_SAML_SESSION_EXPIRY,
        message:
          'Please, reload the page and sign in again, if necessary. To avoid data loss, if you have unsaved edits, dismiss the modal and copy the unsaved text before refreshing the page.',
        sessionTimeout: Date.now(),
        title: 'Your SAML session has expired',
      });
    });
  });

  describe('when the general session-expiry modal announces its visibility', () => {
    const announceGeneralModalState = (shown) => {
      const shownChannel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN);
      shownChannel.postMessage(shown);
      shownChannel.close();
    };

    it('hides the SAML modal that was already showing', async () => {
      getExpiringSamlSession.mockResolvedValue({ timeRemainingMs: 0 });
      createComponent();
      await waitForPromises();
      expect(findModal().exists()).toBe(true);

      announceGeneralModalState(true);
      await waitForPromises();

      expect(findModal().exists()).toBe(false);
    });

    it('keeps the SAML modal hidden even if a session becomes expiring afterwards', async () => {
      getExpiringSamlSession.mockResolvedValue({ timeRemainingMs: 0 });
      createComponent();

      announceGeneralModalState(true);
      await waitForPromises();

      expect(findModal().exists()).toBe(false);
    });

    it('resumes the SAML modal when the general modal announces it is hidden', async () => {
      getExpiringSamlSession.mockResolvedValue({ timeRemainingMs: 0 });
      createComponent();
      await waitForPromises();

      announceGeneralModalState(true);
      await waitForPromises();
      expect(findModal().exists()).toBe(false);

      announceGeneralModalState(false);
      await waitForPromises();
      expect(findModal().exists()).toBe(true);
    });
  });
});
