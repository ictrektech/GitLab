<script>
import { GlAlert, GlButton, GlCard, GlPopover } from '@gitlab/ui';
import EmptySecretsSvg from '@gitlab/svgs/dist/illustrations/empty-state/empty-secrets-md.svg?url';
import { s__ } from '~/locale';
import { ENTITY_GROUP, I18N_SECRETS_EMPTY_STATE, NEW_ROUTE_NAME } from 'ee/ci/secrets/constants';

export default {
  name: 'SecretsEmptyState',
  components: {
    GlAlert,
    GlButton,
    GlCard,
    GlPopover,
  },
  inject: {
    canCreateSecret: { default: false },
    canProvision: { default: false },
    contextConfig: {},
    isProvisioning: {},
    secretManagerStatus: {},
    isEnablingAddOn: { default: false },
    showNoReadAccessAlert: { default: false },
  },
  props: {
    actionsAllowed: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['provision-secrets-manager'],
  computed: {
    isGroupContext() {
      return this.contextConfig.type === ENTITY_GROUP;
    },
    // Unprovisioned, the button fires the Owner-only provisioning mutation;
    // provisioned, it opens the Reporter+ secret form. Gate on the matching
    // ability, failing closed when the value is missing.
    showNewSecretButton() {
      if (!this.actionsAllowed) {
        return false;
      }

      return this.secretManagerStatus === null ? this.canProvision : this.canCreateSecret;
    },
    showContactOwnerAlert() {
      return this.actionsAllowed && this.secretManagerStatus === null && !this.canProvision;
    },
    noReadAccessMessage() {
      return this.isGroupContext
        ? s__(
            "SecretsManager|You don't have permissions to read or create secrets in this group. Contact your group owner to request permissions.",
          )
        : s__(
            "SecretsManager|You don't have permissions to read or create secrets in this project. Contact your project owner to request permissions.",
          );
    },
    showProvisioningState() {
      return this.isProvisioning && !this.isEnablingAddOn;
    },
  },
  methods: {
    onNewSecretClick() {
      if (this.secretManagerStatus === null) {
        this.$emit('provision-secrets-manager');
      } else {
        this.$router.push({ name: NEW_ROUTE_NAME });
      }
    },
  },
  EmptySecretsSvg,
  i18n: {
    ...I18N_SECRETS_EMPTY_STATE,
    contactOwnerMessage: s__(
      'SecretsManager|Contact your group owner or instance administrator to enable GitLab Secrets Manager.',
    ),
    provisioningTitle: s__('SecretsManager|Enabling GitLab Secrets Manager'),
    provisioningDescription: s__(
      'SecretsManager|Please wait while the secrets manager is enabled.',
    ),
  },
};
</script>
<template>
  <div>
    <gl-alert
      v-if="showContactOwnerAlert"
      variant="warning"
      :dismissible="false"
      data-testid="contact-owner-alert"
      class="gl-mb-5"
    >
      {{ $options.i18n.contactOwnerMessage }}
    </gl-alert>
    <gl-alert
      v-if="showNoReadAccessAlert"
      variant="warning"
      :dismissible="false"
      data-testid="no-read-access-alert"
      class="gl-mb-5"
    >
      {{ noReadAccessMessage }}
    </gl-alert>
    <gl-card
      data-testid="secrets-list-empty-state"
      body-class="gl-flex gl-flex-col gl-items-center gl-text-center gl-py-8"
    >
      <template #header>
        <strong>{{ s__('SecretsManager|Secrets') }}</strong>
        <p v-if="isGroupContext" data-testid="group-subheader" class="gl-mb-0 gl-text-subtle">
          {{ $options.i18n.groupSubheader }}
        </p>
      </template>
      <!-- eslint-disable-next-line @gitlab/vue-require-i18n-attribute-strings -->
      <img :src="$options.EmptySecretsSvg" alt="" class="gl-mb-4" />
      <h2 class="gl-mb-3 gl-mt-0 gl-text-size-h2">
        {{ $options.i18n.title }}
      </h2>
      <p class="gl-mb-5">
        {{ $options.i18n.description }}
      </p>
      <gl-button
        v-if="showNewSecretButton"
        ref="newSecretButton"
        variant="confirm"
        category="primary"
        :loading="showProvisioningState"
        data-testid="empty-state-new-secret-button"
        @click="onNewSecretClick"
      >
        {{ s__('SecretsManager|New secret') }}
      </gl-button>
      <gl-popover
        :target="() => $refs.newSecretButton"
        :show="showProvisioningState"
        :title="$options.i18n.provisioningTitle"
        placement="bottom"
        triggers="manual"
      >
        {{ $options.i18n.provisioningDescription }}
      </gl-popover>
    </gl-card>
  </div>
</template>
