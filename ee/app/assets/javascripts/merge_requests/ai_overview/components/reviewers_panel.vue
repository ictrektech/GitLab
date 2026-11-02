<script>
import { GlAvatar, GlIcon, GlLink } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { __, sprintf } from '~/locale';
import SuggestedReviewers from 'ee/merge_requests/components/reviewers/suggested_reviewers.vue';
import { buildReviewers } from '../utils';

export default {
  name: 'ReviewersPanel',
  components: {
    GlAvatar,
    GlIcon,
    GlLink,
    SuggestedReviewers,
  },
  inject: ['iid', 'aiSuggestedReviewersAvailable'],
  // The sidebar's recommended reviewers component reads the merge request from these.
  provide() {
    return {
      issuableId: getIdFromGraphQLId(this.mergeRequest.id),
      issuableIid: this.iid,
    };
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  computed: {
    reviewers() {
      return buildReviewers(this.mergeRequest);
    },
    canUpdate() {
      return Boolean(this.mergeRequest.userPermissions?.updateMergeRequest);
    },
    approvedText() {
      return sprintf(__('%{approved} of %{total} approved'), {
        approved: this.reviewers.filter((reviewer) => reviewer.mergeRequestInteraction?.approved)
          .length,
        total: this.reviewers.length,
      });
    },
  },
  methods: {
    userId(user) {
      return getIdFromGraphQLId(user.id);
    },
  },
  i18n: {
    reviewers: __('Reviewers'),
    noReviewers: __('No reviewers yet'),
  },
  userLinkClasses:
    'js-user-link gl-mr-auto gl-flex gl-min-w-0 gl-items-center gl-gap-3 !gl-text-inherit hover:!gl-text-link',
};
</script>

<template>
  <section class="gl-flex gl-flex-col gl-gap-2">
    <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ $options.i18n.reviewers }}</h3>
      <span v-if="reviewers.length" class="gl-text-subtle">{{ approvedText }}</span>
    </div>
    <ul v-if="reviewers.length" class="gl-m-0 gl-list-none gl-p-0">
      <li
        v-for="reviewer in reviewers"
        :key="reviewer.id"
        data-testid="reviewer-row"
        class="gl-flex gl-items-center gl-gap-3 gl-py-2"
      >
        <gl-link
          :href="reviewer.webPath"
          :data-user-id="userId(reviewer)"
          :data-username="reviewer.username"
          :class="$options.userLinkClasses"
        >
          <gl-avatar :src="reviewer.avatarUrl" :entity-name="reviewer.name" :size="24" />
          <span>{{ reviewer.name }}</span>
        </gl-link>
        <span
          class="gl-inline-flex gl-items-center gl-gap-2 gl-font-bold"
          :class="reviewer.textClass"
        >
          <gl-icon :name="reviewer.icon" :size="14" :variant="reviewer.variant" />
          {{ reviewer.stateLabel }}
        </span>
      </li>
    </ul>
    <p v-else class="gl-m-0 gl-text-subtle">
      {{ $options.i18n.noReviewers }}
    </p>

    <suggested-reviewers
      v-if="aiSuggestedReviewersAvailable"
      :can-update="canUpdate"
      class="!gl-mt-3"
    />
  </section>
</template>
