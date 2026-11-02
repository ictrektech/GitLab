<script>
import { GlButton, GlCard, GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { InternalEvents } from '~/tracking';
import {
  DUO_PANEL_EVENT_CLICK_BUY_CREDITS,
  DUO_PANEL_EVENT_CLICK_LEARN_MORE_CREDITS,
  DUO_PANEL_EVENT_CLICK_START_TRIAL,
  DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE,
} from '../../constants';
import TanukiAiIcon from '../../shared/widgets/tanuki_ai_icon.vue';
import DuoWorkflowExamplesCard from './duo_workflow_examples_card.vue';

export default {
  name: 'StartTrialEmptyState',
  components: {
    GlButton,
    GlCard,
    GlLink,
    GlSprintf,
    TanukiAiIcon,
    DuoWorkflowExamplesCard,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    newTrialPath: {
      type: String,
      required: true,
    },
    trialDuration: {
      type: String,
      required: true,
    },
    buyCreditsPath: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    description() {
      return this.buyCreditsPath
        ? s__(
            'DuoAgentsPlatform|Automate tasks with AI agents, from searching projects to creating commits. Two ways to start.',
          )
        : s__(
            'DuoAgentsPlatform|Automate tasks with AI agents, from searching projects to creating commits.',
          );
    },
  },
  mounted() {
    this.trackEvent(DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE);
  },
  creditsDocs: helpPagePath('subscriptions/gitlab_credits', { anchor: 'monthly-commitment-pool' }),
  clickStartTrialEvent: DUO_PANEL_EVENT_CLICK_START_TRIAL,
  clickLearnMoreCreditsEvent: DUO_PANEL_EVENT_CLICK_LEARN_MORE_CREDITS,
  clickBuyCreditsEvent: DUO_PANEL_EVENT_CLICK_BUY_CREDITS,
};
</script>

<template>
  <div class="gl-flex gl-w-full gl-flex-col gl-items-start gl-gap-5">
    <tanuki-ai-icon />
    <h2 class="gl-my-0 gl-text-size-h2">
      {{ s__('DuoAgentsPlatform|Try GitLab Duo Agent Platform') }}
    </h2>
    <p class="gl-m-0 gl-text-subtle" data-testid="empty-state-text">
      {{ description }}
    </p>
    <gl-card class="gl-w-full" data-testid="trial-card">
      <div class="gl-flex gl-flex-col gl-gap-3">
        <div class="gl-font-bold gl-text-strong">
          {{
            sprintf(s__('DuoAgentsPlatform|Start a free %{trialDuration}-day trial'), {
              trialDuration,
            })
          }}
        </div>
        <div class="gl-text-subtle">
          {{
            s__(
              'DuoAgentsPlatform|Get full access to agentic chat, agents, and flows. No credit card required.',
            )
          }}
        </div>
        <gl-button
          variant="confirm"
          category="primary"
          class="gl-self-start"
          :href="newTrialPath"
          :data-event-tracking="$options.clickStartTrialEvent"
          data-testid="start-trial-link"
        >
          {{ s__('DuoAgentsPlatform|Start a free trial') }}
        </gl-button>
      </div>
    </gl-card>
    <gl-card v-if="buyCreditsPath" class="gl-w-full" data-testid="credits-card">
      <div class="gl-flex gl-flex-col gl-gap-3">
        <div class="gl-font-bold gl-text-strong">
          {{ s__('DuoAgentsPlatform|Buy GitLab Credits') }}
        </div>
        <div class="gl-text-subtle">
          <gl-sprintf
            :message="
              s__(
                'DuoAgentsPlatform|Buy shared %{linkStart}GitLab Credits%{linkEnd} for your group and power AI capabilities and other add-ons.',
              )
            "
          >
            <template #link="{ content }">
              <gl-link
                :href="$options.creditsDocs"
                target="_blank"
                :data-event-tracking="$options.clickLearnMoreCreditsEvent"
                data-testid="credits-docs-link"
                >{{ content }}</gl-link
              >
            </template>
          </gl-sprintf>
        </div>
        <gl-button
          variant="default"
          class="gl-self-start"
          :href="buyCreditsPath"
          :data-event-tracking="$options.clickBuyCreditsEvent"
          data-testid="buy-credits-link"
        >
          {{ s__('DuoAgentsPlatform|Buy credits') }}
        </gl-button>
      </div>
    </gl-card>
    <duo-workflow-examples-card />
  </div>
</template>
