<script>
import {
  GlIcon,
  GlButton,
  GlDisclosureDropdown,
  GlPopover,
  GlAvatarsInline,
  GlSprintf,
  GlTooltipDirective,
} from '@gitlab/ui';
import { RULE_TYPE_ANY_APPROVER } from 'ee/approvals/constants';
import Api from 'ee/api';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId, convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_MERGE_REQUEST } from '~/graphql_shared/constants';
import { __, n__, sprintf } from '~/locale';
import { isUserBusy } from '~/set_status_modal/utils';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import ReviewerAvatarLink from '~/sidebar/components/reviewers/reviewer_avatar_link.vue';
import setReviewersMutation from '~/merge_requests/components/reviewers/queries/set_reviewers.mutation.graphql';
import suggestedReviewersQuery from '../../queries/suggested_reviewer.query.graphql';
import aiSuggestedReviewersSubscription from '../../queries/ai_suggested_reviewers.subscription.graphql';

const COLLAPSE_STORAGE_KEY = 'suggested_reviewers_collapsed';
const MAX_COLLAPSED_CHIPS = 3;
const CHIP_AVATAR_SIZE = 24;
const RECOMMEND_REVIEWERS_FLOW = 'recommend_reviewers/v1';
const WORKFLOW_STATUS_GROUP_ACTIVE = 'ACTIVE';
// The automatic run on merge request creation starts from a background job, so a new
// merge request can briefly have no workflow even though a run is about to start.
const NEW_MR_GRACE_PERIOD_MS = 2 * 60 * 1000;

export default {
  name: 'SuggestedReviewers',
  apollo: {
    suggestedReviewers: {
      query: suggestedReviewersQuery,
      variables() {
        return {
          projectPath: this.projectPath,
          iid: this.issuableIid,
        };
      },
      update: (d) => d.project?.mergeRequest?.aiSuggestedReviewers?.nodes || [],
      result({ data }) {
        const mergeRequest = data?.project?.mergeRequest;
        const workflows = mergeRequest?.duoWorkflows?.nodes;

        this.recommendationRuns = workflows
          ? workflows.filter(
              ({ workflowDefinition }) => workflowDefinition === RECOMMEND_REVIEWERS_FLOW,
            )
          : null;
        // Once the requested run is visible, its workflow status drives the button.
        if (this.hasRecommendationRun) this.fetchRequested = false;
        this.startGracePeriodTimer(mergeRequest?.createdAt);
      },
      subscribeToMore: {
        document: aiSuggestedReviewersSubscription,
        variables() {
          return {
            issuableId: convertToGraphQLId(TYPENAME_MERGE_REQUEST, this.issuableId),
          };
        },
        updateQuery(
          _,
          {
            subscriptionData: {
              data: { mergeRequestAiSuggestedReviewersUpdated: queryResult },
            },
          },
        ) {
          if (queryResult) {
            this.suggestedReviewers = queryResult.aiSuggestedReviewers?.nodes || [];

            // Reviewer changes also fire this subscription, so an empty update doesn't mean
            // the run finished. Refetch to read the workflow status instead.
            if (this.isFetching && !this.suggestedReviewers.length) {
              this.$apollo.queries.suggestedReviewers.refetch();
            }
          }
        },
      },
    },
  },
  components: {
    GlIcon,
    GlButton,
    GlDisclosureDropdown,
    GlPopover,
    GlAvatarsInline,
    GlSprintf,
    LocalStorageSync,
    TimeAgoTooltip,
    ReviewerAvatarLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['projectPath', 'issuableId', 'issuableIid'],
  props: {
    canUpdate: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      suggestedReviewers: [],
      loadingUserIds: [],
      collapsed: false,
      isRetrying: false,
      recommendationRuns: null,
      gracePeriodElapsed: false,
      fetchRequested: false,
    };
  },
  computed: {
    recommendationCreatedAt() {
      return this.collapsed ? null : this.suggestedReviewers[0]?.createdAt;
    },
    hasRecommendationRun() {
      return Boolean(this.recommendationRuns?.length);
    },
    isFetching() {
      return (
        this.fetchRequested ||
        !this.gracePeriodElapsed ||
        Boolean(
          this.recommendationRuns?.some(
            ({ statusGroup }) => statusGroup === WORKFLOW_STATUS_GROUP_ACTIVE,
          ),
        )
      );
    },
    showFetchPrompt() {
      return (
        this.canUpdate &&
        this.recommendationRuns !== null &&
        !this.suggestedReviewers.length &&
        (!this.hasRecommendationRun || this.isFetching)
      );
    },
    dropdownItems() {
      return [
        {
          text: __('Refresh'),
          icon: 'retry',
          action: () => this.retryRecommendation(),
        },
      ];
    },
    chipStackAriaLabel() {
      return sprintf(
        n__(
          '%{count} recommended reviewer',
          '%{count} recommended reviewers',
          this.suggestedReviewers.length,
        ),
        { count: this.suggestedReviewers.length },
      );
    },
    chipBadgeSrOnlyText() {
      const hiddenCount = Math.max(this.suggestedReviewers.length - MAX_COLLAPSED_CHIPS, 0);

      return sprintf(
        n__(
          '%{count} more recommended reviewer',
          '%{count} more recommended reviewers',
          hiddenCount,
        ),
        { count: hiddenCount },
      );
    },
    toggleAriaLabel() {
      return this.collapsed
        ? __('Expand recommended reviewers')
        : __('Collapse recommended reviewers');
    },
  },
  beforeDestroy() {
    clearTimeout(this.gracePeriodTimer);
  },
  methods: {
    ruleName({ type, name, section }) {
      if (type.toLowerCase() === RULE_TYPE_ANY_APPROVER) return __('Any eligible user');

      return section && section !== 'codeowners' ? section : name;
    },
    reviewerRole(reviewer) {
      return reviewer.approvalRule ? this.ruleName(reviewer.approvalRule) : null;
    },
    rulePatterns(rule) {
      return rule.patterns?.length && this.ruleName(rule) === rule.section ? rule.patterns : null;
    },
    reviewerPatterns(reviewer) {
      return reviewer.approvalRule ? this.rulePatterns(reviewer.approvalRule) : null;
    },
    patternsAriaLabel(rule) {
      return sprintf(__('%{section}, matching files: %{patterns}'), {
        section: this.ruleName(rule),
        patterns: this.rulePatterns(rule).join(', '),
      });
    },
    patternsTargetId(reviewerId) {
      return `suggested-reviewer-patterns-${getIdFromGraphQLId(reviewerId)}`;
    },
    reasonIconVariant(user) {
      return isUserBusy(user.status?.availability) ? 'subtle' : 'info';
    },
    reasonIconName(user) {
      return isUserBusy(user.status?.availability) ? 'status-waiting' : 'status-active';
    },
    async addSuggestedReviewer(user) {
      this.loadingUserIds = [...this.loadingUserIds, user.id];

      try {
        await this.$apollo.mutate({
          mutation: setReviewersMutation,
          variables: {
            reviewerUsernames: [user.username],
            projectPath: this.projectPath,
            iid: this.issuableIid,
            operationMode: 'APPEND',
          },
        });
      } catch (error) {
        createAlert({
          message: sprintf(__('Could not add %{name} as a reviewer. Try again later.'), {
            name: user.name,
          }),
          error,
          captureError: true,
        });
      } finally {
        this.loadingUserIds = this.loadingUserIds.filter((id) => id !== user.id);
      }
    },
    async retryRecommendation() {
      this.isRetrying = true;

      try {
        await Api.triggerDuoFlow(RECOMMEND_REVIEWERS_FLOW, {
          project_id: this.projectPath,
          merge_request_id: this.issuableIid,
          goal: this.issuableIid,
        });
        return true;
      } catch (error) {
        createAlert({
          message: __('Could not generate new reviewer recommendations. Try again later.'),
          error,
          captureError: true,
        });
        return false;
      } finally {
        this.isRetrying = false;
      }
    },
    async fetchRecommendations() {
      this.fetchRequested = true;
      this.fetchRequested = await this.retryRecommendation();
    },
    startGracePeriodTimer(createdAt) {
      if (this.gracePeriodElapsed) return;

      // A visible run ends the wait, even if a timer started before the run appeared.
      if (this.hasRecommendationRun) {
        clearTimeout(this.gracePeriodTimer);
        this.gracePeriodTimer = null;
        this.gracePeriodElapsed = true;
        return;
      }

      if (this.gracePeriodTimer) return;

      // Capped so a slow client clock can't stretch the wait past the grace period.
      const remaining = createdAt
        ? Math.min(
            new Date(createdAt).getTime() + NEW_MR_GRACE_PERIOD_MS - Date.now(),
            NEW_MR_GRACE_PERIOD_MS,
          )
        : 0;

      if (remaining <= 0) {
        this.gracePeriodElapsed = true;
        return;
      }

      this.gracePeriodTimer = setTimeout(() => {
        this.gracePeriodTimer = null;
        this.gracePeriodElapsed = true;
        this.$apollo.queries.suggestedReviewers.refetch();
      }, remaining);
    },
    addButtonAriaLabel(user) {
      return sprintf(__('Add %{name} as a reviewer'), {
        name: user.name,
      });
    },
  },
  COLLAPSE_STORAGE_KEY,
  MAX_COLLAPSED_CHIPS,
  CHIP_AVATAR_SIZE,
  rowsId: 'suggested-reviewers-rows',
};
</script>

<template>
  <div v-if="suggestedReviewers.length" class="gl-mt-5">
    <local-storage-sync
      :storage-key="$options.COLLAPSE_STORAGE_KEY"
      :value="collapsed"
      @input="collapsed = $event"
    />
    <div :class="{ 'gl-mb-3': !recommendationCreatedAt }" class="gl-flex gl-items-center gl-gap-3">
      <button
        :aria-expanded="(!collapsed).toString()"
        :aria-controls="$options.rowsId"
        :aria-label="toggleAriaLabel"
        type="button"
        class="suggested-reviewers-toggle gl-flex gl-grow gl-items-center gl-gap-3 gl-rounded-base gl-border-0 gl-bg-transparent gl-p-0 gl-text-left gl-leading-20 gl-text-subtle hover:gl-text-default focus-visible:gl-focus"
        data-testid="suggested-reviewers-toggle"
        @click="collapsed = !collapsed"
      >
        <gl-icon name="tanuki-ai" class="gl-shrink-0" />
        <span class="gl-grow">{{ __('Recommended') }}</span>
      </button>
      <gl-avatars-inline
        v-if="collapsed"
        :aria-label="chipStackAriaLabel"
        :avatars="suggestedReviewers"
        :avatar-size="$options.CHIP_AVATAR_SIZE"
        :max-visible="$options.MAX_COLLAPSED_CHIPS"
        :badge-sr-only-text="chipBadgeSrOnlyText"
        role="group"
        collapsed
        data-testid="collapsed-chips"
      >
        <template #avatar="{ avatar }">
          <reviewer-avatar-link
            :user="avatar.user"
            :data-recommendation-reason="avatar.reason || null"
            class="suggested-reviewer-avatar"
            data-testid="collapsed-chip"
          />
        </template>
      </gl-avatars-inline>
      <gl-disclosure-dropdown
        v-if="canUpdate"
        :items="dropdownItems"
        placement="bottom-end"
        class="gl-shrink-0"
      >
        <template #toggle="{ accessibilityAttributes }">
          <gl-button
            v-gl-tooltip.hover
            v-bind="accessibilityAttributes"
            :title="__('Recommended reviewer actions')"
            :aria-label="__('Recommended reviewer actions')"
            :loading="isRetrying"
            icon="ellipsis_v"
            category="tertiary"
            size="small"
            data-testid="actions-toggle"
          />
        </template>
      </gl-disclosure-dropdown>
    </div>
    <span
      v-if="recommendationCreatedAt"
      class="gl-mb-3 gl-ml-6 gl-block gl-text-sm gl-text-subtle"
      data-testid="recommendation-created-at"
    >
      <gl-sprintf :message="s__('SuggestedReviewers|Generated %{timeAgo}')">
        <template #timeAgo>
          <time-ago-tooltip :time="recommendationCreatedAt" />
        </template>
      </gl-sprintf>
    </span>
    <div v-show="!collapsed" :id="$options.rowsId" data-testid="suggested-reviewers-rows">
      <div
        v-for="(reviewer, index) in suggestedReviewers"
        :key="reviewer.user.id"
        :class="{ 'gl-mb-3': index !== suggestedReviewers.length - 1 }"
        class="reviewer-grid gl-grid gl-items-center"
        data-testid="reviewer"
      >
        <span class="gl-relative gl-break-anywhere" data-css-area="user">
          <reviewer-avatar-link
            :user="reviewer.user"
            :data-recommendation-reason="reviewer.reason || null"
            class="suggested-reviewer-avatar gl-items-center"
          >
            <span class="gl-ml-3 gl-flex gl-items-center gl-leading-normal">
              {{ reviewer.user.name }}
            </span>
          </reviewer-avatar-link>
          <template v-if="reviewerRole(reviewer)">
            <gl-button
              v-if="reviewerPatterns(reviewer)"
              :id="patternsTargetId(reviewer.user.id)"
              :aria-label="patternsAriaLabel(reviewer.approvalRule)"
              data-testid="rule-patterns"
              variant="link"
              button-text-classes="gl-text-sm gl-font-normal gl-text-subtle gl-underline gl-decoration-dotted gl-underline-offset-4"
              class="gl-ml-7 gl-block"
            >
              {{ reviewerRole(reviewer) }}
            </gl-button>
            <span
              v-else
              class="gl-ml-7 gl-block gl-text-sm gl-text-subtle"
              data-testid="reviewer-role"
            >
              {{ reviewerRole(reviewer) }}
            </span>
          </template>
          <gl-popover
            v-if="reviewerPatterns(reviewer)"
            :target="patternsTargetId(reviewer.user.id)"
            :title="__('Matching files')"
            triggers="hover focus"
          >
            <span
              v-for="pattern in reviewerPatterns(reviewer)"
              :key="pattern"
              class="gl-block gl-break-all gl-font-monospace"
              data-testid="matching-file"
            >
              {{ pattern }}
            </span>
          </gl-popover>
          <gl-icon
            v-if="reviewer.reason"
            :aria-label="__('Reason for recommended reviewer')"
            :size="8"
            :variant="reasonIconVariant(reviewer.user)"
            :name="reasonIconName(reviewer.user)"
            class="suggested-reviewer-reason-icon gl-absolute"
          />
        </span>
        <gl-button
          v-if="canUpdate"
          v-gl-tooltip.left
          :title="__('Add reviewer')"
          :aria-label="addButtonAriaLabel(reviewer.user)"
          class="gl-float-right gl-ml-auto gl-self-start !gl-text-subtle"
          data-testid="add-reviewer"
          size="small"
          icon="plus"
          category="tertiary"
          :loading="loadingUserIds.includes(reviewer.user.id)"
          @click="addSuggestedReviewer(reviewer.user)"
        />
      </div>
    </div>
  </div>
  <div
    v-else-if="showFetchPrompt"
    class="gl-mt-5 gl-flex gl-items-center gl-gap-3 gl-leading-20 gl-text-subtle"
    data-testid="fetch-recommendations-prompt"
  >
    <gl-icon name="tanuki-ai" class="gl-shrink-0" />
    <span class="gl-grow">{{ __('Recommended') }}</span>
    <gl-button
      :aria-label="__('Generate recommended reviewers')"
      :loading="isFetching"
      size="small"
      class="gl-shrink-0"
      data-testid="fetch-recommendations"
      @click="fetchRecommendations"
    >
      {{ s__('SuggestedReviewers|Generate') }}
    </gl-button>
  </div>
</template>
