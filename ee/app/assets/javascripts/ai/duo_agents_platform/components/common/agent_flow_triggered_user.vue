<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlLink,
  GlSprintf,
  GlTruncate,
  GlTooltipDirective,
} from '@gitlab/ui';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { fetchPolicies } from '~/lib/graphql';
import getAgentFlowSource from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow_source.query.graphql';
import { isValidURL } from '~/lib/utils/url_utility';
import { s__ } from '~/locale';
import { getNumericId } from 'ee/ai/duo_agents_platform/utils';
import { SOURCE_TYPE_LABELS } from 'ee/ai/duo_agents_platform/constants';

export default {
  name: 'AgentFlowTriggeredUser',
  components: {
    GlAvatar,
    GlAvatarLink,
    GlLink,
    GlSprintf,
    GlTruncate,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    user: {
      required: true,
      type: Object,
    },
    avatarClass: {
      required: false,
      type: [String, Array, Object],
      default: null,
    },
    compact: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      agentFlowSource: {},
    };
  },
  apollo: {
    agentFlowSource: {
      query: getAgentFlowSource,
      fetchPolicy: fetchPolicies.CACHE_ONLY,
      skip() {
        return !this.workflowId;
      },
      variables() {
        return {
          workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.workflowId),
        };
      },
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.[0]?.node || {};
      },
    },
  },
  computed: {
    workflowId() {
      return this.$route?.params?.id?.toString() || '';
    },
    sourceType() {
      return this.agentFlowSource?.sourceType || null;
    },
    sourceLink() {
      return this.agentFlowSource?.sourceLink || '';
    },
    userId() {
      return getNumericId(this.user?.id);
    },
    userUsername() {
      return this.user?.username || '';
    },
    userWebUrl() {
      return this.user?.webUrl || '';
    },
    userName() {
      return this.user?.name || '';
    },
    userAvatarUrl() {
      return this.user?.avatarUrl || '';
    },
    sourceLabel() {
      return SOURCE_TYPE_LABELS[this.sourceType] || '';
    },
    sourceText() {
      return this.sourceLabel || this.sourceLink || '';
    },
    hasValidSourceLink() {
      return isValidURL(this.sourceLink);
    },
    hasSource() {
      return Boolean(this.sourceType) && Boolean(this.sourceText);
    },
    showUsername() {
      return !(this.compact && this.hasSource);
    },
    triggeredByMessage() {
      return this.hasSource ? s__('DuoAgentPlatform|%{user} via %{source}') : '%{user}';
    },
  },
};
</script>
<template>
  <span class="gl-inline-flex gl-min-w-0 gl-items-center gl-gap-2">
    <gl-sprintf :message="triggeredByMessage">
      <template #user>
        <gl-avatar-link
          v-gl-tooltip.bottom
          :href="userWebUrl"
          :data-user-id="userId"
          :data-username="userUsername"
          :title="userName"
          class="js-user-link gl-inline-flex gl-min-w-0 gl-items-center gl-gap-2 gl-text-inherit gl-no-underline hover:gl-text-link hover:gl-underline"
        >
          <gl-avatar
            :src="userAvatarUrl"
            :alt="userName"
            :label="userName"
            :size="16"
            class="gl-shrink-0"
            :class="avatarClass"
          />
          <span
            v-if="showUsername"
            class="gl-min-w-0 gl-truncate"
            data-testid="triggered-user-username"
          >
            @{{ userUsername }}
          </span>
        </gl-avatar-link>
      </template>
      <template #source>
        <gl-link
          v-if="hasValidSourceLink"
          :href="sourceLink"
          target="_blank"
          class="gl-min-w-0 gl-text-inherit gl-no-underline hover:gl-text-link hover:gl-underline"
        >
          <gl-truncate :text="sourceText" position="end" class="hover:gl-underline" with-tooltip />
        </gl-link>
        <gl-truncate v-else :text="sourceText" position="end" with-tooltip class="gl-min-w-0" />
      </template>
    </gl-sprintf>
  </span>
</template>
