<script>
import {
  GlAlert,
  GlAvatarLabeled,
  GlButton,
  GlFormInputGroup,
  GlInputGroupText,
  GlKeysetPagination,
  GlTableLite,
  GlToggle,
} from '@gitlab/ui';
import { n__, s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import getUserOverridesQuery from '../graphql/get_user_overrides.query.graphql';
import upsertUserOverridesMutation from '../graphql/upsert_user_overrides.mutation.graphql';
import { PAGE_SIZE } from '../../../usage_billing/constants';
import AddUserOverrideModal from './add_user_override_modal.vue';
import BulkUpdateOverridesModal from './bulk_update_overrides_modal.vue';

export default {
  name: 'CreditCapsUserOverridesList',
  components: {
    AddUserOverrideModal,
    BulkUpdateOverridesModal,
    GlAlert,
    GlAvatarLabeled,
    GlButton,
    GlFormInputGroup,
    GlInputGroupText,
    GlKeysetPagination,
    GlTableLite,
    GlToggle,
    CrudComponent,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  data() {
    return {
      userOverrides: null,
      userOverridesDrafts: [],
      savingUserIds: {},
      saveErrors: {},
      isSavingAll: false,
      hasError: false,
      isAddModalVisible: false,
      isBulkUpdateModalVisible: false,
      pageInfo: {
        first: PAGE_SIZE,
        after: null,
        last: null,
        before: null,
      },
    };
  },
  apollo: {
    userOverrides: {
      query: getUserOverridesQuery,
      variables() {
        return { namespacePath: this.namespacePath, ...this.pageInfo };
      },
      fetchPolicy: 'network-only',
      update({ subscriptionUsage }) {
        const { nodes = [], pageInfo = {} } = subscriptionUsage?.budgetCaps?.userOverrides ?? {};

        // Drop overrides without a user: the CDot record may lack an entity_id,
        // or the GitLab user may have been hard-deleted.
        return {
          nodes: nodes.filter((node) => node.user?.id),
          pageInfo,
        };
      },
      result({ data, error }) {
        const userOverrides = data?.subscriptionUsage?.budgetCaps?.userOverrides;
        if (error) return;
        if (!userOverrides) {
          // eslint-disable-next-line @gitlab/require-i18n-strings
          const nullDataError = new Error('User overrides data unavailable');
          this.hasError = true;
          logError(nullDataError);
          captureException(nullDataError);
          return;
        }
        this.hasError = false;

        // userOverridesDrafts decouples v-model bindings from the Apollo cache.
        // `original` holds the last persisted values so we can detect unsaved row changes.
        this.userOverridesDrafts = this.userOverrides.nodes.map((node) => ({
          cap: node.cap,
          enabled: node.capEnabled,
          user: node.user,
          original: { cap: node.cap, enabled: node.capEnabled },
          _showDetails: false,
        }));
      },
      error(error) {
        this.hasError = true;
        logError(error);
        captureException(error);
      },
    },
  },
  computed: {
    isBulkUpdateEnabled() {
      return Boolean(window.gon?.features?.creditCapsBulkUpdate);
    },
    isLoading() {
      return this.$apollo.queries.userOverrides.loading;
    },
    changedDrafts() {
      return this.userOverridesDrafts.filter((draft) => this.isRowChanged(draft));
    },
    showSaveAll() {
      return this.isSavingAll || this.changedDrafts.length > 1;
    },
    hasPagination() {
      return this.currentPageInfo.hasNextPage || this.currentPageInfo.hasPreviousPage;
    },
    currentPageInfo() {
      if (this.userOverrides?.pageInfo) return this.userOverrides.pageInfo;

      return {
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: null,
      };
    },
    tableFields() {
      // Remove bottom border on rows that have on-save error
      const tdClass = (value, key, item) =>
        this.saveErrors[item.user?.id] ? '!gl-border-b-0' : '';

      return [
        { key: 'user', label: s__('UsageBilling|User'), thClass: '!gl-border-t-0', tdClass },
        {
          key: 'cap',
          label: s__('UsageBilling|Override cap'),
          thClass: '!gl-border-t-0',
          tdClass,
        },
        {
          key: 'capEnabled',
          label: s__('UsageBilling|Status'),
          thClass: '!gl-border-t-0',
          tdClass: (...args) => `${tdClass(...args)} !gl-align-middle`.trim(),
        },
        {
          key: 'actions',
          label: s__('UsageBilling|Actions'),
          thClass: '!gl-border-t-0 gl-sr-only',
          tdClass: (...args) => `${tdClass(...args)} !gl-align-middle gl-text-right`.trim(),
        },
      ];
    },
  },
  methods: {
    getIdFromGraphQLId,
    isRowChanged(draft) {
      return draft.cap !== draft.original.cap || draft.enabled !== draft.original.enabled;
    },
    rowClass(item) {
      if (this.isRowChanged(item)) return 'gl-bg-feedback-info';
      return '';
    },
    openAddModal() {
      this.isAddModalVisible = true;
    },
    closeAddModal() {
      this.isAddModalVisible = false;
    },
    openBulkUpdateModal() {
      this.isBulkUpdateModalVisible = true;
    },
    closeBulkUpdateModal() {
      this.isBulkUpdateModalVisible = false;
    },
    resetAndReload() {
      this.pageInfo = { first: PAGE_SIZE, after: null, last: null, before: null };
      return this.$apollo.queries.userOverrides.refetch();
    },
    onOverrideSaved() {
      this.closeAddModal();
      this.resetAndReload();
    },
    onNextPage(cursor) {
      this.userOverridesDrafts = [];
      this.savingUserIds = {};
      this.saveErrors = {};
      this.pageInfo = { first: PAGE_SIZE, after: cursor, last: null, before: null };
    },
    onPrevPage(cursor) {
      this.userOverridesDrafts = [];
      this.savingUserIds = {};
      this.saveErrors = {};
      this.pageInfo = { first: null, after: null, last: PAGE_SIZE, before: cursor };
    },
    async saveAllUserOverrides() {
      const drafts = this.changedDrafts.filter((draft) => !this.savingUserIds[draft.user.id]);
      if (!drafts.length) return;

      this.isSavingAll = true;

      const results = await Promise.all(drafts.map((draft) => this.updateUserOverride(draft)));
      const savedCount = results.filter(Boolean).length;
      const failedCount = results.length - savedCount;

      const toastMessages = [];

      if (failedCount) {
        toastMessages.push(
          n__(
            'UsageBilling|%d override failed to save.',
            'UsageBilling|%d overrides failed to save.',
            failedCount,
          ),
        );
      }

      if (savedCount) {
        toastMessages.push(
          n__('UsageBilling|%d override saved.', 'UsageBilling|%d overrides saved.', savedCount),
        );
      }

      toast(toastMessages.join(' '));

      this.isSavingAll = false;
    },
    async saveUserOverride(draft) {
      const saveSucceeded = await this.updateUserOverride(draft);
      if (saveSucceeded) toast(s__('UsageBilling|Override saved.'));
    },
    async updateUserOverride(draft) {
      const userId = draft.user?.id;
      if (!userId) return false;

      this.savingUserIds = { ...this.savingUserIds, [userId]: true };
      const { [userId]: _, ...restErrors } = this.saveErrors;
      this.saveErrors = restErrors;
      // `_showDetails` is a built-in <gl-table> property to display details row.
      // We utilize details row to display row edits errors in-line
      // eslint-disable-next-line no-underscore-dangle
      draft._showDetails = false;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: upsertUserOverridesMutation,
          variables: {
            namespacePath: this.namespacePath,
            overrides: [
              {
                userId,
                cap: Number(draft.cap),
                enabled: draft.enabled,
              },
            ],
          },
        });

        const errorMessages = data?.upsertUserBudgetCapOverrides?.errors ?? [];
        const errors = errorMessages.map((msg) => new Error(msg));
        if (errors.length === 1) throw errors[0];
        if (errors.length) {
          throw new AggregateError(
            errors,
            s__('UsageBilling|An error occurred while saving user cap override.'),
          );
        }

        const [saved] = data?.upsertUserBudgetCapOverrides?.userOverrides ?? [];
        if (saved) {
          draft.cap = saved.cap;
          draft.enabled = saved.capEnabled;
        }
        draft.original = { cap: draft.cap, enabled: draft.enabled };

        return true;
      } catch (error) {
        this.saveErrors = { ...this.saveErrors, [userId]: error.message };
        // eslint-disable-next-line no-underscore-dangle
        draft._showDetails = true;
        logError(error);
        captureException(error);

        return false;
      } finally {
        const { [userId]: _done, ...restSaving } = this.savingUserIds;
        this.savingUserIds = restSaving;
      }
    },
  },
};
</script>

<template>
  <crud-component
    :title="s__('UsageBilling|Per-user cap overrides')"
    :description="s__('UsageBilling|Individual overrides take precedence over the flat cap.')"
    :is-loading="isLoading"
    data-testid="user-credit-caps-overrides-card"
  >
    <template #actions>
      <gl-button
        v-if="isBulkUpdateEnabled"
        category="tertiary"
        size="small"
        data-testid="user-credit-caps-bulk-update-button"
        @click="openBulkUpdateModal"
      >
        {{ s__('UsageBilling|Bulk update') }}
      </gl-button>
      <gl-button
        size="small"
        data-testid="user-credit-caps-add-override-button"
        @click="openAddModal"
      >
        {{ s__('UsageBilling|Add override') }}
      </gl-button>
      <gl-button
        v-if="showSaveAll"
        size="small"
        variant="confirm"
        :loading="isSavingAll"
        data-testid="user-credit-caps-save-all-button"
        @click="saveAllUserOverrides"
      >
        {{ s__('UsageBilling|Save all') }}
      </gl-button>
    </template>

    <template #default>
      <gl-alert
        v-if="hasError"
        variant="danger"
        :dismissible="false"
        data-testid="user-credit-caps-overrides-error-alert"
      >
        {{ s__('UsageBilling|An error occurred while fetching user overrides.') }}
      </gl-alert>

      <template v-else>
        <p
          v-if="!userOverridesDrafts.length"
          class="gl-text-subtle"
          data-testid="user-credit-caps-overrides-empty-state"
        >
          {{ s__('UsageBilling|No per-user overrides set.') }}
        </p>

        <template v-else>
          <!-- Forms are rendered outside GlTableLite because the HTML spec forbids
               <form> elements inside <table>. Each input and button references its
               form via the form= attribute using the user's ID as a key. -->
          <form
            v-for="draft in userOverridesDrafts"
            :id="`override-form-${draft.user.id}`"
            :key="draft.user.id"
            data-testid="user-credit-caps-overrides-form"
            @submit.prevent="saveUserOverride(draft)"
          ></form>

          <gl-table-lite
            :items="userOverridesDrafts"
            :fields="tableFields"
            stacked="sm"
            :tbody-tr-class="rowClass"
            data-testid="user-credit-caps-overrides-table"
          >
            <template #cell(user)="{ item: { user } }">
              <gl-avatar-labeled
                :src="user.avatarUrl"
                :alt="user.name"
                :entity-name="user.name"
                :entity-id="getIdFromGraphQLId(user.id)"
                :size="24"
                :label="user.name"
                :sub-label="`@${user.username}`"
              />
            </template>

            <template #cell(cap)="{ item }">
              <label :for="`cap-input-${item.user.id}`" class="gl-sr-only">{{
                s__('UsageBilling|Override cap')
              }}</label>
              <gl-form-input-group
                :id="`cap-input-${item.user.id}`"
                v-model.number="item.cap"
                :form="`override-form-${item.user.id}`"
                type="number"
                min="0"
                step="1"
                :disabled="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-cap-input"
                class="gl-w-36"
              >
                <template #append>
                  <gl-input-group-text>{{ s__('UsageBilling|credits') }}</gl-input-group-text>
                </template>
              </gl-form-input-group>
            </template>

            <template #cell(capEnabled)="{ item }">
              <gl-toggle
                v-model="item.enabled"
                :label="s__('UsageBilling|Enabled')"
                label-position="left"
                :disabled="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-enabled-toggle"
              />
            </template>

            <template #cell(actions)="{ item }">
              <gl-button
                :class="{
                  'gl-invisible': !isRowChanged(item),
                  'gl-ml-6': !savingUserIds[item.user.id],
                }"
                type="submit"
                size="small"
                variant="confirm"
                :form="`override-form-${item.user.id}`"
                :loading="savingUserIds[item.user.id]"
                data-testid="user-credit-caps-overrides-save-button"
              >
                {{ s__('UsageBilling|Save') }}
              </gl-button>
            </template>

            <template #row-details="{ item }">
              <gl-alert
                variant="danger"
                :dismissible="false"
                data-testid="user-credit-caps-overrides-save-error-alert"
              >
                {{ saveErrors[item.user.id] }}
              </gl-alert>
            </template>
          </gl-table-lite>
        </template>
      </template>

      <add-user-override-modal
        :visible="isAddModalVisible"
        @hidden="closeAddModal"
        @saved="onOverrideSaved"
      />

      <bulk-update-overrides-modal
        v-if="isBulkUpdateEnabled"
        :visible="isBulkUpdateModalVisible"
        @hidden="closeBulkUpdateModal"
        @saved="resetAndReload"
      />
    </template>

    <template v-if="hasPagination" #pagination>
      <gl-keyset-pagination
        :disabled="isLoading || isSavingAll"
        v-bind="currentPageInfo"
        data-testid="user-credit-caps-overrides-pagination"
        @prev="onPrevPage"
        @next="onNextPage"
      />
    </template>
  </crud-component>
</template>
