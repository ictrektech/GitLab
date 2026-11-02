<script>
import SessionExpireModal from '~/authentication/sessions/components/session_expire_modal.vue';
import {
  BROADCAST_CHANNEL_SAML_SESSION_EXPIRY,
  BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN,
} from '~/authentication/sessions/constants';
import { getExpiringSamlSession } from '../saml_sessions';

export default {
  name: 'SamlReloadModal',
  components: {
    SessionExpireModal,
  },
  broadcastChannel: BROADCAST_CHANNEL_SAML_SESSION_EXPIRY,
  props: {
    samlProviderId: {
      type: Number,
      required: true,
    },
    samlSessionsUrl: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      sessionTimeout: null,
      shownChannelInstance: null,
      suppressed: false,
    };
  },
  async created() {
    // Mirror the general session-expiry modal's visibility: while it is shown this modal
    // yields (the general sign-in flow re-establishes SSO, so it must not stack on top);
    // when the general modal is later hidden - e.g. activity extends the session - this
    // modal resumes. Set up the listener before the async fetch so an early signal applies.
    this.shownChannelInstance = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN);
    this.shownChannelInstance.addEventListener('message', this.onGeneralModalShown);

    const session = await getExpiringSamlSession({
      samlProviderId: this.samlProviderId,
      url: this.samlSessionsUrl,
    });

    if (session) {
      this.sessionTimeout = Date.now() + session.timeRemainingMs;
    }
  },
  beforeDestroy() {
    this.shownChannelInstance.removeEventListener('message', this.onGeneralModalShown);
    this.shownChannelInstance.close();
  },
  methods: {
    /** @param {MessageEvent} event */
    onGeneralModalShown(event) {
      this.suppressed = event.data === true;
    },
  },
};
</script>

<template>
  <session-expire-modal
    v-if="sessionTimeout && !suppressed"
    :broadcast-channel="$options.broadcastChannel"
    :message="
      s__(
        'SAML|Please, reload the page and sign in again, if necessary. To avoid data loss, if you have unsaved edits, dismiss the modal and copy the unsaved text before refreshing the page.',
      )
    "
    :session-timeout="sessionTimeout"
    :title="s__('SAML|Your SAML session has expired')"
  />
</template>
