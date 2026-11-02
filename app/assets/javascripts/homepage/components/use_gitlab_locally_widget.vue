<script>
import {
  GlAccordion,
  GlAccordionItem,
  GlButton,
  GlLink,
  GlToastMixin,
  GlTooltipDirective,
} from '@gitlab/ui';
import deleteUserCalloutMutation from '~/graphql_shared/mutations/delete_user_callout.mutation.graphql';
import { helpPagePath } from '~/helpers/help_page_helper';
import { logError } from '~/lib/logger';
import { __, s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { InternalEvents } from '~/tracking';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';
import {
  EVENT_CLICK_USE_GITLAB_LOCALLY_WIDGET_LINK,
  EVENT_DISMISS_USE_GITLAB_LOCALLY_WIDGET,
  EVENT_EXPAND_USE_GITLAB_LOCALLY_WIDGET_ITEM,
  EVENT_UNDO_DISMISS_USE_GITLAB_LOCALLY_WIDGET,
  EVENT_VIEW_USE_GITLAB_LOCALLY_WIDGET,
} from '../tracking_constants';
import BaseWidget from './base_widget.vue';

const FEATURE_NAME = 'use_gitlab_locally_homepage_widget';

export default {
  name: 'UseGitlabLocallyWidget',
  components: {
    GlAccordion,
    GlAccordionItem,
    GlButton,
    GlLink,
    BaseWidget,
    UserCalloutDismisser,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin, InternalEvents.mixin()],
  data() {
    return {
      isRemoved: false,
    };
  },
  created() {
    this.pendingRequest = Promise.resolve();
  },
  mounted() {
    this.trackEvent(EVENT_VIEW_USE_GITLAB_LOCALLY_WIDGET);
  },
  methods: {
    onItemToggle(item, visible) {
      if (!visible) return;

      this.trackEvent(EVENT_EXPAND_USE_GITLAB_LOCALLY_WIDGET_ITEM, { label: item.id });
    },
    onLinkClick(item, link) {
      this.trackEvent(EVENT_CLICK_USE_GITLAB_LOCALLY_WIDGET_LINK, {
        label: item.id,
        property: link.id,
      });
    },
    remove(dismiss) {
      this.isRemoved = true;
      this.trackEvent(EVENT_DISMISS_USE_GITLAB_LOCALLY_WIDGET);
      this.enqueueRequest(() => dismiss());

      this.$toast.show(s__('Homepage|Use GitLab locally widget was removed.'), {
        action: {
          text: __('Undo'),
          onClick: (_, toast) => {
            this.trackEvent(EVENT_UNDO_DISMISS_USE_GITLAB_LOCALLY_WIDGET);
            toast.hide();
            this.undoRemove();
          },
        },
      });
    },
    undoRemove() {
      this.isRemoved = false;
      this.enqueueRequest(() => this.deleteCallout());
    },
    // Dismiss and Undo can be clicked in quick succession, so run the requests in order
    // to keep the last action's state.
    enqueueRequest(request) {
      // A rejected request would skip every later one, so catch it to keep the queue going.
      this.pendingRequest = this.pendingRequest
        .then(request)
        .catch((error) => Sentry.captureException(error));
    },
    async deleteCallout() {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: deleteUserCalloutMutation,
          variables: { input: { featureName: FEATURE_NAME } },
        });

        const errors = data?.userCalloutDelete?.errors;
        if (errors?.length > 0) {
          Sentry.captureException(new Error(`User callout delete failed: ${errors.join(', ')}`));
        }
      } catch (error) {
        logError(error);
        Sentry.captureException(error);
      }
    },
  },
  FEATURE_NAME,
  ITEMS: [
    {
      id: 'ide_extension',
      title: s__('Homepage|Install a GitLab extension in your IDE'),
      description: s__('Homepage|Manage your projects and use GitLab Duo directly in your editor.'),
      links: [
        {
          id: 'vs_code',
          text: __('VS Code'),
          href: helpPagePath('editor_extensions/visual_studio_code/setup.md'),
        },
        {
          id: 'jetbrains',
          text: __('JetBrains'),
          href: helpPagePath('editor_extensions/jetbrains_ide/setup.md'),
        },
      ],
    },
    {
      id: 'cli',
      title: s__('Homepage|Install the GitLab CLI'),
      description: s__('Homepage|Manage your projects and use GitLab Duo in your terminal.'),
      links: [
        {
          id: 'gitlab_cli',
          text: __('GitLab CLI'),
          href: 'https://gitlab.com/gitlab-org/cli#installation',
        },
      ],
    },
  ],
};
</script>

<template>
  <user-callout-dismisser :feature-name="$options.FEATURE_NAME" skip-query>
    <template #default="{ dismiss }">
      <base-widget v-if="!isRemoved" data-testid="homepage-use-gitlab-locally-widget">
        <div class="gl-mb-5 gl-flex gl-items-center gl-justify-between">
          <h2 class="gl-heading-4 gl-m-0">{{ s__('Homepage|Use GitLab locally') }}</h2>
          <gl-button
            v-gl-tooltip
            :title="__('Remove')"
            :aria-label="s__('Homepage|Remove Use GitLab locally widget')"
            icon="close"
            category="tertiary"
            size="small"
            data-testid="remove-button"
            @click="remove(dismiss)"
          />
        </div>
        <gl-accordion :header-level="3">
          <gl-accordion-item
            v-for="item in $options.ITEMS"
            :key="item.id"
            :title="item.title"
            @input="onItemToggle(item, $event)"
          >
            <p class="gl-mb-3">{{ item.description }}</p>
            <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
              <li v-for="link in item.links" :key="link.id">
                <gl-link
                  :href="link.href"
                  target="_blank"
                  show-external-icon
                  :data-testid="`link-${link.id}`"
                  @click="onLinkClick(item, link)"
                >
                  {{ link.text }}
                </gl-link>
              </li>
            </ul>
          </gl-accordion-item>
        </gl-accordion>
      </base-widget>
    </template>
  </user-callout-dismisser>
</template>
