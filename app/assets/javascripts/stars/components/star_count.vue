<script>
import { GlButton, GlButtonGroup, GlTooltipDirective, GlToastMixin } from '@gitlab/ui';
import { s__ } from '~/locale';
import { reportToSentry } from '~/ci/utils';
import { isLoggedIn } from '~/lib/utils/common_utils';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_PROJECT } from '~/graphql_shared/constants';
import setStarStatusMutation from './graphql/mutations/star.mutation.graphql';

export default {
  name: 'StarCount',
  components: {
    GlButton,
    GlButtonGroup,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin],
  inject: {
    projectId: {
      default: null,
    },
    signInPath: {
      default: '',
    },
    starCount: {
      default: 0,
    },
    starred: {
      default: false,
    },
    starrersPath: {
      default: '',
    },
  },
  data() {
    return {
      isLoading: false,
      count: this.starCount,
      isStarred: this.starred,
    };
  },
  computed: {
    starIcon() {
      return this.isStarred ? 'star' : 'star-o';
    },
    starText() {
      return this.isStarred ? s__('ProjectOverview|Unstar') : s__('ProjectOverview|Star');
    },
    starHref() {
      return isLoggedIn() ? null : this.signInPath;
    },
    tooltip() {
      if (isLoggedIn()) {
        return '';
      }

      return s__('ProjectOverview|You must sign in to star a project');
    },
  },
  methods: {
    showToastMessage() {
      const toastProps = {
        text: s__('ProjectOverview|Star toggle failed. Try again later.'),
        variant: 'danger',
      };

      this.$toast.show(toastProps.text, {
        variant: toastProps.variant,
      });
    },
    async setStarStatus() {
      if (!isLoggedIn()) {
        return;
      }

      try {
        this.isLoading = true;
        const { data } = await this.$apollo.mutate({
          mutation: setStarStatusMutation,
          variables: {
            projectId: convertToGraphQLId(TYPENAME_PROJECT, this.projectId),
            starred: !this.isStarred,
          },
        });

        if (data.errors?.length > 0) {
          reportToSentry(this.$options.name, new Error(data.errors.join(', ')));
          this.showToastMessage();
        } else {
          this.count = data.starProject.count;
          this.isStarred = !this.isStarred;
        }
      } catch (failure) {
        reportToSentry(this.$options.name, failure);
        this.showToastMessage();
      } finally {
        this.isLoading = false;
      }
    },
  },
  modalId: 'custom-notifications-modal',
};
</script>

<template>
  <gl-button-group>
    <gl-button
      v-gl-tooltip
      class="star-btn @max-sm:!gl-pr-1"
      button-text-classes="gl-sr-only @sm:gl-not-sr-only"
      size="small"
      data-testid="star-button"
      :icon="starIcon"
      :title="tooltip"
      :href="starHref"
      :disabled="isLoading"
      @click="setStarStatus()"
    >
      {{ starText }}
    </gl-button>
    <gl-button
      v-gl-tooltip
      class="star-count"
      button-text-classes="gl-text-sm gl-font-semibold"
      data-testid="star-count"
      size="small"
      :href="starrersPath"
      :title="s__('ProjectOverview|Starrers')"
    >
      {{ count }}
    </gl-button>
  </gl-button-group>
</template>
