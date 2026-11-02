<script>
import { GlCard, GlFormGroup, GlIcon, GlLink, GlModal, GlSprintf } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import MembersTokenSelect from '~/invite_members/components/members_token_select.vue';
import { __, s__ } from '~/locale';
import RoleSelector from '~/members/components/role_selector.vue';

export const INVITE_MEMBERS_MODAL_ID = 'organization-access-invite-members-modal';

export default {
  name: 'OrganizationAccessInviteMembersModal',
  components: {
    GlCard,
    GlFormGroup,
    GlIcon,
    GlLink,
    GlModal,
    GlSprintf,
    MembersTokenSelect,
    RoleSelector,
  },
  props: {
    resource: {
      type: Object,
      required: true,
    },
  },
  emits: ['invite'],
  data() {
    return {
      selectedUsers: [],
      hasPendingInput: false,
      roleValue: this.resource.defaultRole,
    };
  },
  computed: {
    roleItems() {
      return this.resource.roles.map(({ value, text, description }) => ({
        value,
        text,
        description,
      }));
    },
    roles() {
      return { formatted: this.roleItems, flatten: this.roleItems };
    },
    selectedRole() {
      return this.resource.roles.find(({ value }) => value === this.roleValue);
    },
    actionPrimary() {
      return {
        text: s__('OrganizationAccess|Invite'),
        attributes: {
          variant: 'confirm',
          disabled: !this.selectedUsers.length || this.hasPendingInput,
        },
      };
    },
  },
  methods: {
    onRoleInput({ value }) {
      this.roleValue = value;
    },
    onPrimary() {
      this.$emit('invite', { users: this.selectedUsers, role: this.roleValue });
    },
    reset() {
      this.selectedUsers = [];
      this.hasPendingInput = false;
      this.roleValue = this.resource.defaultRole;
    },
  },
  i18n: {
    allowed: s__('OrganizationAccess|Allowed'),
    notAllowed: s__('OrganizationAccess|Not allowed'),
  },
  modalId: INVITE_MEMBERS_MODAL_ID,
  invalidMembers: {},
  usersInputId: 'organization-access-invite-members-input',
  roleToggleId: 'organization-access-invite-members-role',
  actionCancel: { text: __('Cancel') },
  rolesHelpPath: helpPagePath('user/permissions'),
};
</script>

<template>
  <gl-modal
    :modal-id="$options.modalId"
    :title="s__('OrganizationAccess|Invite members')"
    :action-primary="actionPrimary"
    :action-cancel="$options.actionCancel"
    @primary="onPrimary"
    @hidden="reset"
  >
    <p>
      <gl-sprintf :message="s__('OrganizationAccess|You\'re inviting members to %{resource}.')">
        <template #resource>
          <strong>{{ resource.label }}</strong>
        </template>
      </gl-sprintf>
    </p>
    <gl-form-group
      :label="s__('OrganizationAccess|GitLab usernames')"
      :label-for="$options.usersInputId"
    >
      <members-token-select
        :input-id="$options.usersInputId"
        :invalid-members="$options.invalidMembers"
        :exception-state="null"
        :allow-emails="false"
        :no-matches-text="s__('OrganizationAccess|No matching organization members.')"
        @input="selectedUsers = $event"
        @clear="selectedUsers = []"
        @tokenization-state-change="hasPendingInput = $event"
      />
    </gl-form-group>
    <gl-form-group :label="s__('OrganizationAccess|Role')" :label-for="$options.roleToggleId">
      <template #description>
        <gl-link :href="$options.rolesHelpPath" target="_blank">
          {{ s__('OrganizationAccess|What are roles?') }}
        </gl-link>
      </template>
      <role-selector
        :roles="roles"
        :value="selectedRole"
        :toggle-id="$options.roleToggleId"
        :header-text="s__('OrganizationAccess|Select a role')"
        @input="onRoleInput"
      />
    </gl-form-group>
    <gl-card data-testid="access-summary">
      <template #header>
        <h3 class="gl-m-0 gl-text-base">{{ s__('OrganizationAccess|Access summary') }}</h3>
      </template>
      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="{ text, allowed } in selectedRole.accessSummary"
          :key="text"
          class="gl-mb-3 gl-flex gl-gap-3 last:gl-mb-0"
        >
          <gl-icon
            :name="allowed ? 'check' : 'close'"
            :aria-label="allowed ? $options.i18n.allowed : $options.i18n.notAllowed"
            class="gl-shrink-0"
          />
          <span>{{ text }}</span>
        </li>
      </ul>
    </gl-card>
  </gl-modal>
</template>
