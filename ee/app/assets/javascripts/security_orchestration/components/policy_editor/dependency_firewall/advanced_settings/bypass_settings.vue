<script>
import { GlCard } from '@gitlab/ui';
import { s__ } from '~/locale';
import UsersSelector from '../../scan_result/advanced_settings/policy_exceptions/users_selector.vue';
import TokensSelector from '../../scan_result/advanced_settings/policy_exceptions/tokens_selector.vue';

export default {
  name: 'BypassSettings',
  components: { GlCard, UsersSelector, TokensSelector },
  i18n: {
    title: s__('SecurityOrchestration|Bypass settings'),
    usersLabel: s__('SecurityOrchestration|Users'),
    usersDescription: s__(
      'SecurityOrchestration|For service accounts that must publish or download internal packages, or for emergency access during an incident.',
    ),
    tokensLabel: s__('SecurityOrchestration|Access tokens'),
    tokensDescription: s__(
      'SecurityOrchestration|A request made with one of these personal access tokens is allowed through.',
    ),
  },
  props: {
    bypassSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['changed'],
  computed: {
    selectedUsers() {
      return this.bypassSettings.users || [];
    },
    selectedTokens() {
      return this.bypassSettings.access_tokens || [];
    },
  },
  methods: {
    emitChanges(users, accessTokens) {
      const changes = {};

      if (users.length) changes.users = users;
      if (accessTokens.length) changes.access_tokens = accessTokens;

      this.$emit('changed', 'bypass_settings', changes);
    },
    updateUsers(users) {
      this.emitChanges(users, this.selectedTokens);
    },
    updateTokens(accessTokens) {
      this.emitChanges(this.selectedUsers, accessTokens);
    },
  },
};
</script>

<template>
  <gl-card>
    <template #header>
      <h4 class="gl-m-0 gl-text-base">{{ $options.i18n.title }}</h4>
    </template>

    <users-selector
      :label="$options.i18n.usersLabel"
      :description="$options.i18n.usersDescription"
      :selected-users="selectedUsers"
      @set-users="updateUsers"
    />
    <tokens-selector
      :label="$options.i18n.tokensLabel"
      :description="$options.i18n.tokensDescription"
      :selected-tokens="selectedTokens"
      @set-access-tokens="updateTokens"
    />
  </gl-card>
</template>
