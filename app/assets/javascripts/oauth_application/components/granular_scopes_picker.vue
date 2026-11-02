<script>
import { GlFormGroup } from '@gitlab/ui';
import { s__ } from '~/locale';
import { scrollToElement } from '~/lib/utils/scroll_utils';
import GranularPermissionsSelector from '~/vue_shared/access_tokens/components/granular_permissions_selector.vue';
import {
  ACCESS_SCOPES,
  ACCESS_SELECTED_MEMBERSHIPS_ENUM,
} from '~/vue_shared/access_tokens/constants';
import { emptyByScope } from '~/vue_shared/access_tokens/utils';
import { GRANULAR_SCOPES_INPUT_PREFIX, SCOPE_KEY_BY_ACCESS_LEVEL } from '../constants';
import GroupHierarchyNamespaceSelector from './group_hierarchy_namespace_selector.vue';

export default {
  name: 'GranularScopesPicker',
  components: {
    GlFormGroup,
    GranularPermissionsSelector,
    GroupHierarchyNamespaceSelector,
  },
  props: {
    allowedAccessLevels: {
      type: Array,
      required: true,
    },
    initialScopes: {
      type: Array,
      required: false,
      default: () => [],
    },
    groupFullPath: {
      type: String,
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
  },
  data() {
    const selectedPermissions = emptyByScope();

    this.initialScopes.forEach(({ access, permissions = [] }) => {
      const key = SCOPE_KEY_BY_ACCESS_LEVEL[access];
      if (key) selectedPermissions[key] = [...permissions];
    });

    const selectedMemberships = this.initialScopes.find(
      ({ access }) => access === ACCESS_SELECTED_MEMBERSHIPS_ENUM,
    );

    return {
      selectedPermissions,
      selectedNamespaces: [...(selectedMemberships?.namespaces ?? [])],
      formEl: null,
      submitAttempted: false,
    };
  },
  computed: {
    scopes() {
      const keys = this.allowedAccessLevels.map((level) => SCOPE_KEY_BY_ACCESS_LEVEL[level]);

      return ACCESS_SCOPES.filter(({ key }) => keys.includes(key));
    },
    showNamespaceSelector() {
      return this.allowedAccessLevels.includes(ACCESS_SELECTED_MEMBERSHIPS_ENUM);
    },
    namespacePermissions() {
      return this.selectedPermissions[SCOPE_KEY_BY_ACCESS_LEVEL[ACCESS_SELECTED_MEMBERSHIPS_ENUM]];
    },
    missingNamespaces() {
      return (
        this.showNamespaceSelector &&
        this.namespacePermissions?.length > 0 &&
        !this.selectedNamespaces.length
      );
    },
    // scopeInputs drops a scope without permissions, so its groups and projects would be lost
    missingNamespacePermissions() {
      return (
        this.showNamespaceSelector &&
        this.selectedNamespaces.length > 0 &&
        !this.namespacePermissions?.length
      );
    },
    namespaceError() {
      return this.submitAttempted && this.missingNamespaces
        ? this.$options.i18n.namespaceError
        : '';
    },
    permissionsError() {
      return this.submitAttempted && this.missingNamespacePermissions
        ? this.$options.i18n.permissionsError
        : '';
    },
    scopeInputs() {
      return this.allowedAccessLevels.flatMap((access) => {
        const permissions = this.selectedPermissions[SCOPE_KEY_BY_ACCESS_LEVEL[access]] || [];

        if (!permissions.length) return [];

        const scope = { access, permissions };

        if (access === ACCESS_SELECTED_MEMBERSHIPS_ENUM) {
          scope.resourceIds = this.selectedNamespaces.map(({ id }) => id);
        }

        return [scope];
      });
    },
  },
  mounted() {
    this.formEl = this.$el.closest('form');
    this.formEl?.addEventListener('submit', this.validateBeforeSubmit);
  },
  beforeDestroy() {
    this.formEl?.removeEventListener('submit', this.validateBeforeSubmit);
  },
  methods: {
    validateBeforeSubmit(event) {
      this.submitAttempted = true;

      const invalidSelector = this.invalidSelector();
      if (!invalidSelector) return;

      event.preventDefault();
      // Keeps rails-ujs from disabling the submit button for a submission that never happens
      event.stopPropagation();

      scrollToElement(invalidSelector.$el, { behavior: 'smooth', offset: -100 });
      // Focus would otherwise stay on the submit button, away from the field to fix
      invalidSelector.$el.querySelector('button')?.focus({ preventScroll: true });
    },
    invalidSelector() {
      if (this.missingNamespaces) return this.$refs.namespaceSelector;
      if (this.missingNamespacePermissions) return this.$refs.permissionsSelector;

      return null;
    },
    inputName(index, field) {
      return `${GRANULAR_SCOPES_INPUT_PREFIX}[${index}][${field}]`;
    },
    listInputName(index, field) {
      return `${this.inputName(index, field)}[]`;
    },
  },
  i18n: {
    label: s__('OAuthApplication|Fine-grained permissions'),
    help: s__(
      'OAuthApplication|Tokens for this application can use only the permissions you select here, and only within what each user can already access. Leave everything cleared to keep a legacy application.',
    ),
    mcpHint: s__(
      'OAuthApplication|Tokens can use the GitLab MCP server only when the set grants execute_mcp_tool.',
    ),
    namespaceError: s__('AccessTokens|At least one group or project is required.'),
    permissionsError: s__(
      'OAuthApplication|Selected groups and projects require at least one group and project permission.',
    ),
  },
};
</script>

<template>
  <gl-form-group :label="$options.i18n.label" :label-description="$options.i18n.help">
    <group-hierarchy-namespace-selector
      v-if="showNamespaceSelector"
      ref="namespaceSelector"
      :value="selectedNamespaces"
      :group-full-path="groupFullPath"
      :group-name="groupName"
      :error="namespaceError"
      class="gl-mb-5"
      @input="selectedNamespaces = $event"
    />

    <granular-permissions-selector
      ref="permissionsSelector"
      :scopes="scopes"
      :value="selectedPermissions"
      :error="permissionsError"
      @input="selectedPermissions = $event"
    />

    <p class="gl-mb-0 gl-mt-3 gl-text-sm gl-text-subtle">{{ $options.i18n.mcpHint }}</p>

    <div v-for="(scope, index) in scopeInputs" :key="scope.access">
      <!-- authn_oauth_application[granular_scopes][0][access] -->
      <input type="hidden" :name="inputName(index, 'access')" :value="scope.access" />
      <!-- authn_oauth_application[granular_scopes][0][permissions][] -->
      <input
        v-for="name in scope.permissions"
        :key="name"
        type="hidden"
        :name="listInputName(index, 'permissions')"
        :value="name"
      />
      <!-- authn_oauth_application[granular_scopes][0][resource_ids][] -->
      <input
        v-for="id in scope.resourceIds"
        :key="id"
        type="hidden"
        :name="listInputName(index, 'resource_ids')"
        :value="id"
      />
    </div>
  </gl-form-group>
</template>
