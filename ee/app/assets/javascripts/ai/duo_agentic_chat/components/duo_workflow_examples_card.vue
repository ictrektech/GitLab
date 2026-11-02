<script>
import { GlButton, GlCard, GlIcon } from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { InternalEvents } from '~/tracking';
import {
  DUO_PANEL_EVENT_CLICK_LEARN_MORE,
  DUO_PANEL_EVENT_CLICK_LEARN_MORE_REQUEST,
} from '../../constants';

export default {
  name: 'DuoWorkflowExamplesCard',
  components: {
    GlButton,
    GlCard,
    GlIcon,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    // Set only when the request CTA is shown.
    requestState: {
      type: String,
      required: false,
      default: null,
    },
    requestGroupId: {
      type: Number,
      required: false,
      default: null,
    },
  },
  dapDocs: helpPagePath('/user/duo_agent_platform/_index.md'),
  clickLearnMoreEvent: DUO_PANEL_EVENT_CLICK_LEARN_MORE,
  workflowExamples: [
    {
      icon: 'merge-request',
      title: s__('DuoAgentsPlatform|Review a merge request'),
      subtitle: s__('DuoAgentsPlatform|Identify code improvements'),
    },
    {
      icon: 'pipeline',
      title: s__('DuoAgentsPlatform|Fix a failing pipeline'),
      subtitle: s__('DuoAgentsPlatform|Analyze pipeline failures and get fix suggestions'),
    },
  ],
  methods: {
    handleLearnMoreClick() {
      if (!this.requestState) return;

      this.trackEvent(DUO_PANEL_EVENT_CLICK_LEARN_MORE_REQUEST, {
        label: this.requestState,
        property: String(this.requestGroupId),
      });
    },
  },
};
</script>

<template>
  <gl-card class="gl-w-full">
    <div class="gl-flex gl-flex-col gl-gap-4">
      <div class="gl-font-bold gl-text-strong">
        {{ s__('DuoAgentsPlatform|Get things done with GitLab Duo') }}
      </div>
      <div
        v-for="(example, i) in $options.workflowExamples"
        :key="i"
        class="gl-flex gl-gap-x-2"
        data-testid="workflow-example"
      >
        <div><gl-icon :name="example.icon" /></div>
        <div>
          <div class="gl-font-bold gl-text-strong">
            {{ example.title }}
          </div>
          <div class="gl-text-subtle">{{ example.subtitle }}</div>
        </div>
      </div>
      <gl-button
        variant="default"
        class="gl-self-start"
        :href="$options.dapDocs"
        target="_blank"
        :data-event-tracking="$options.clickLearnMoreEvent"
        data-testid="learn-more-link"
        @click="handleLearnMoreClick"
      >
        {{ s__('DuoAgentsPlatform|Learn more about GitLab Duo') }}
      </gl-button>
    </div>
  </gl-card>
</template>
