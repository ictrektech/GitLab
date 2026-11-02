<script>
import { GlDisclosureDropdown, GlKeysetPagination } from '@gitlab/ui';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { createAlert } from '~/alert';
import { InternalEvents } from '~/tracking';
import branchRulesQuery from 'ee_else_ce/projects/settings/repository/branch_rules/graphql/queries/branch_rules.query.graphql';
import BranchRule from 'ee_else_ce/projects/settings/repository/branch_rules/components/branch_rule.vue';
import { visitUrl } from '~/lib/utils/url_utility';
import {
  BRANCH_RULE_DETAILS_LABEL,
  PROTECTED_BRANCH,
} from '~/projects/settings/branch_rules/tracking/constants';
import BranchRuleModal from '../../components/branch_rule_modal.vue';
import createBranchRuleMutation from './graphql/mutations/create_branch_rule.mutation.graphql';
import { I18N, PROTECTED_BRANCHES_ANCHOR, BRANCH_PROTECTION_MODAL_ID } from './constants';

const PAGE_SIZE = 20;

export default {
  name: 'BranchRules',
  i18n: I18N,
  components: {
    BranchRule,
    BranchRuleModal,
    GlDisclosureDropdown,
    CrudComponent,
    GlKeysetPagination,
  },
  apollo: {
    branchRules: {
      query: branchRulesQuery,
      variables() {
        return {
          projectPath: this.projectPath,
          first: PAGE_SIZE,
          after: this.currentCursor,
        };
      },
      update(data) {
        const branchRulesData = data.project?.branchRules;
        this.pageInfo = branchRulesData?.pageInfo || {};
        return branchRulesData?.nodes || [];
      },
      error() {
        createAlert({ message: this.$options.i18n.queryError });
      },
    },
  },
  inject: {
    projectPath: { default: '' },
    branchRulesPath: { default: '' },
    canCreateBranchRule: { default: false },
    canCreateApprovalRule: { default: false },
    canCreateExternalStatusCheck: { default: false },
  },
  data() {
    return {
      branchRules: [],
      pageInfo: {},
      pageHistory: [null],
      currentPageIndex: 0,
    };
  },
  computed: {
    currentCursor() {
      return this.pageHistory[this.currentPageIndex] || null;
    },
    canGoBack() {
      return this.currentPageIndex > 0;
    },
    canAddBranchRule() {
      return this.getAddRuleItems.length > 0;
    },
    getAddRuleItems() {
      const items = [];

      if (this.canCreateBranchRule) {
        items.push({
          text: this.$options.i18n.branchName,
          action: () => this.openCreateRuleModal(),
        });
      }

      // Predefined rules exist only through their approval rules and status checks.
      // Status checks cannot target all protected branches.
      const predefinedBranches = [];
      if (this.canCreateApprovalRule || this.canCreateExternalStatusCheck) {
        predefinedBranches.push(this.$options.i18n.allBranches);
      }
      if (this.canCreateApprovalRule) {
        predefinedBranches.push(this.$options.i18n.allProtectedBranches);
      }

      return items.concat(
        predefinedBranches
          .filter((branch) => !this.hasPredefinedBranchRule(branch))
          .map((branch) => this.createPredefinedBrachRulesItem(branch)),
      );
    },
  },
  methods: {
    createPredefinedBrachRulesItem(branchRuleName) {
      return {
        text: branchRuleName,
        action: () => this.redirectToEdit(branchRuleName),
      };
    },
    redirectToEdit(branch) {
      visitUrl(`${this.branchRulesPath}?branch=${encodeURIComponent(branch)}`);
    },
    hasPredefinedBranchRule(branchName) {
      return Boolean(this.branchRules.filter((rule) => rule.name === branchName).length);
    },
    openCreateRuleModal() {
      this.$refs[this.$options.modalId].show();
    },
    addBranchRule({ name }) {
      this.$apollo
        .mutate({
          mutation: createBranchRuleMutation,
          variables: {
            projectPath: this.projectPath,
            name,
          },
        })
        .then(() => {
          InternalEvents.trackEvent(PROTECTED_BRANCH, {
            label: BRANCH_RULE_DETAILS_LABEL,
          });
          visitUrl(this.getBranchRuleEditPath(name));
        })
        .catch(() => {
          createAlert({ message: this.$options.i18n.createBranchRuleError });
        });
    },
    getBranchRuleEditPath(name) {
      return `${this.branchRulesPath}?branch=${encodeURIComponent(name)}`;
    },
    handleNextPage() {
      this.pageHistory.push(this.pageInfo.endCursor);
      this.currentPageIndex += 1;
    },
    handlePreviousPage() {
      if (this.currentPageIndex > 0) {
        this.currentPageIndex -= 1;
      }
    },
  },
  modalId: BRANCH_PROTECTION_MODAL_ID,
  protectedBranchesAnchor: PROTECTED_BRANCHES_ANCHOR,
};
</script>

<template>
  <crud-component
    :title="__('Branch rules')"
    icon="branch"
    :count="branchRules.length"
    class="gl-mb-5"
    :is-loading="$apollo.queries.branchRules.loading"
  >
    <template v-if="canAddBranchRule" #actions>
      <gl-disclosure-dropdown
        :toggle-text="$options.i18n.addBranchRule"
        :items="getAddRuleItems"
        size="small"
      />
    </template>

    <template v-if="!branchRules.length" #empty>
      {{ $options.i18n.emptyState }}
    </template>

    <template v-else #default>
      <ul class="content-list">
        <branch-rule
          v-for="(rule, index) in branchRules"
          :key="`${rule.name}-${index}`"
          :rule-id="rule.id"
          :name="rule.name"
          :is-default="rule.isDefault"
          :branch-protection="rule.branchProtection"
          :status-checks-total="
            rule.externalStatusChecks ? rule.externalStatusChecks.nodes.length : 0
          "
          :approval-rules-total="rule.approvalRules ? rule.approvalRules.nodes.length : 0"
          :matching-branches-count="rule.matchingBranchesCount"
          :project-path="projectPath"
        />
      </ul>

      <branch-rule-modal
        :id="$options.modalId"
        :ref="$options.modalId"
        :title="$options.i18n.createBranchRule"
        :action-primary-text="$options.i18n.createBranchRule"
        @primary="addBranchRule({ name: $event })"
      />
    </template>

    <template #pagination>
      <gl-keyset-pagination
        v-bind="pageInfo"
        :prev-text="__('Prev')"
        :next-text="__('Next')"
        :disabled="$apollo.queries.branchRules.loading"
        :has-previous-page="canGoBack"
        @prev="handlePreviousPage"
        @next="handleNextPage"
      />
    </template>
  </crud-component>
</template>
