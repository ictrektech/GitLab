<script>
import { GlButton, GlIcon, GlLink, GlPopover, GlToggle, GlToastMixin } from '@gitlab/ui';
import { DOCS_URL } from '~/constants';
import getOrbitUserPreference from 'ee/ai/graphql/get_orbit_user_preference.query.graphql';
import updateOrbitUserPreference from 'ee/ai/graphql/update_orbit_user_preference.mutation.graphql';
import { s__ } from '~/locale';
import { withCaptureErrors } from '../observability/with_capture_errors';

// Matches any version of the standalone Orbit foundational agent
// (orbit_agent/v1, orbit_agent/v2, ...). Used to override the foundational-agent
// subsetting mapping, since Orbit-agent sessions are gated upstream by
// `orbit_agent_enabled` and are always-on locally.
const ORBIT_AGENT_REFERENCE_PREFIX = 'orbit_agent/';

// The default "GitLab Duo" agent is marked `foundational: true` in the data
// model but represents the regular agentic chat experience — it should map to
// the chat subsetting, not the foundational-agents one.
const DUO_DEFAULT_AGENT_REFERENCE = 'chat';

const ORBIT_FEEDBACK_URL = 'https://gitlab.com/groups/gitlab-org/-/work_items/22266';
const ORBIT_TOGGLE_BUTTON_ID = 'orbit-toggle-button';

// Subsetting keys stored inside the `orbit_settings` JSONB preference.
const SUBSETTING_CHAT = 'orbit_agentic_chat_enabled';
const SUBSETTING_FOUNDATIONAL = 'orbit_other_foundational_agents_enabled';
const SUBSETTING_CUSTOM_AGENTS = 'orbit_custom_agents_enabled';

const SUBSETTING_TOGGLES = [
  {
    key: SUBSETTING_CHAT,
    label: s__('DuoChat|Agentic chat'),
    testId: 'orbit-toggle-agentic-chat',
  },
  {
    key: SUBSETTING_FOUNDATIONAL,
    label: s__('DuoChat|Foundational agents'),
    testId: 'orbit-toggle-foundational-agents',
  },
  {
    key: SUBSETTING_CUSTOM_AGENTS,
    label: s__('DuoChat|Custom agents'),
    testId: 'orbit-toggle-custom-agents',
  },
];

export default {
  name: 'OrbitToggle',
  components: {
    GlButton,
    GlIcon,
    GlLink,
    GlPopover,
    GlToggle,
  },
  mixins: [GlToastMixin],
  model: {
    prop: 'value',
    event: 'change',
  },
  props: {
    value: {
      type: Boolean,
      required: true,
    },
    currentAgent: {
      type: Object,
      required: false,
      default: null,
    },
    // Renders the trigger as an icon + status dot without the "Orbit" text,
    // for the compact single-header layout. Popover behavior is unchanged.
    iconOnly: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  apollo: {
    orbitSettings: {
      query: getOrbitUserPreference,
      skip() {
        return !this.orbitAvailable;
      },
      update(data) {
        return data?.currentUser?.userPreferences?.orbitSettings ?? {};
      },
      result() {
        this.$emit('change', this.activeEnabled);
      },
    },
  },
  data() {
    return {
      orbitSettings: {},
      savingKey: null,
    };
  },
  computed: {
    orbitAvailable() {
      return Boolean(window.gon?.orbit_available);
    },
    masterEnabled() {
      return this.orbitSettings?.enabled === true;
    },
    showOrbitToggle() {
      return this.orbitAvailable && this.masterEnabled;
    },
    isOrbitAgentActive() {
      return Boolean(
        this.currentAgent?.referenceWithVersion?.startsWith(ORBIT_AGENT_REFERENCE_PREFIX),
      );
    },
    // Derived from the `currentAgent` prop (canonical source of truth, updated
    // by agent pickers and slash commands) rather than local fields which only
    // get re-assigned on workflow load and so leak the previous agent's identity
    // into a fresh "default Duo" chat.
    //
    // The standalone Orbit agent is gated by `orbit_agent_enabled` upstream and
    // isn't user-configurable here, so it returns null — OrbitToggle interprets
    // that as always-on.
    activeOrbitSubsettingKey() {
      if (this.isOrbitAgentActive) return null;
      if (this.currentAgent?.referenceWithVersion === DUO_DEFAULT_AGENT_REFERENCE) {
        return SUBSETTING_CHAT;
      }
      if (this.currentAgent?.foundational) return SUBSETTING_FOUNDATIONAL;
      if (this.currentAgent?.pinnedItemVersionId) return SUBSETTING_CUSTOM_AGENTS;
      return SUBSETTING_CHAT;
    },
    // `null` activeOrbitSubsettingKey signals the standalone Orbit agent, which
    // is gated upstream — always-on regardless of orbit_settings contents.
    activeEnabled() {
      if (this.activeOrbitSubsettingKey === null) return true;
      return this.orbitSettings?.[this.activeOrbitSubsettingKey] === true;
    },
    isSaving() {
      return Boolean(this.savingKey);
    },
  },
  watch: {
    // When the user switches between agent types mid-session, the governing
    // subsetting changes — re-emit so the parent's v-model (and the next
    // buildStartRequest payload) reflects the new key without a refetch.
    activeOrbitSubsettingKey() {
      this.$emit('change', this.activeEnabled);
    },
  },
  methods: {
    async onSubsettingChange(key, newValue) {
      if (this.savingKey) return;
      this.savingKey = key;

      const nextSettings = { ...this.orbitSettings, [key]: newValue };

      try {
        await this.$apollo.mutate({
          mutation: updateOrbitUserPreference,
          variables: {
            input: {
              orbitSettings: nextSettings,
            },
          },
          optimisticResponse: {
            userPreferencesUpdate: {
              __typename: 'UserPreferencesUpdatePayload',
              userPreferences: {
                __typename: 'UserPreferences',
                orbitSettings: nextSettings,
              },
              errors: [],
            },
          },
          update: (store, { data }) => {
            const updatedPreferences = data?.userPreferencesUpdate?.userPreferences;
            if (!updatedPreferences) return;

            // Cache miss is fine; the next query will refetch. This is a local
            // cache read/write, not a network call, so it needs its own
            // reporting -- the Apollo error link only sees network/GraphQL errors.
            withCaptureErrors(
              () => {
                const cacheData = store.readQuery({ query: getOrbitUserPreference });
                if (!cacheData?.currentUser) return;
                store.writeQuery({
                  query: getOrbitUserPreference,
                  data: {
                    currentUser: {
                      ...cacheData.currentUser,
                      userPreferences: {
                        ...cacheData.currentUser.userPreferences,
                        orbitSettings: updatedPreferences.orbitSettings,
                      },
                    },
                  },
                });
              },
              { rethrow: false },
            )();
          },
        });

        // Keep parent in sync whenever the toggle that just changed is the one
        // governing the current chat. For the Orbit-agent (null) case the
        // emitted value is fixed at `true`, so flipping any subsetting here
        // does not change what the parent sees.
        if (key === this.activeOrbitSubsettingKey) {
          this.$emit('change', newValue);
        }
        this.$toast.show(this.$options.i18n.preferenceUpdated);
      } catch {
        // Already reported by the Duo Chat Apollo error link. The cache is left
        // unchanged; the next query will reconcile.
      } finally {
        this.savingKey = null;
      }
    },
  },
  i18n: {
    orbitOn: s__('DuoChat|Orbit: On'),
    orbitOff: s__('DuoChat|Orbit: Off'),
    popoverTitle: s__('DuoChat|Orbit'),
    description: s__(
      'DuoChat|Empower agents to provide deeper insights in less time with a knowledge graph of your GitLab data.',
    ),
    learnAbout: s__('DuoChat|Learn about Orbit'),
    leaveFeedback: s__('DuoChat|Leave feedback'),
    preferenceUpdated: s__('DuoChat|Preference updated.'),
  },
  orbitToggleButtonId: ORBIT_TOGGLE_BUTTON_ID,
  orbitDocsPath: `${DOCS_URL}/orbit/`,
  orbitFeedbackUrl: ORBIT_FEEDBACK_URL,
  subsettingToggles: SUBSETTING_TOGGLES,
};
</script>

<template>
  <span v-if="showOrbitToggle">
    <!-- Trigger button shown in the chat header -->
    <gl-button
      :id="$options.orbitToggleButtonId"
      category="tertiary"
      size="small"
      data-testid="orbit-toggle-button"
      icon="orbit"
      :aria-label="value ? $options.i18n.orbitOn : $options.i18n.orbitOff"
    >
      <span class="gl-flex gl-items-center gl-gap-3">
        <template v-if="!iconOnly">{{ $options.i18n.popoverTitle }}</template>
        <span
          class="gl-border gl-inline-block gl-h-3 gl-w-3 gl-rounded-full"
          :class="
            value
              ? 'gl-border-green-400 gl-bg-green-400'
              : 'gl-border-neutral-400 gl-bg-transparent'
          "
          data-testid="orbit-status-dot"
          aria-hidden="true"
        ></span>
      </span>
    </gl-button>

    <!-- Popover panel -->
    <gl-popover
      :target="$options.orbitToggleButtonId"
      triggers="click blur"
      placement="bottomleft"
      data-testid="orbit-toggle-popover"
    >
      <!-- Wrapper prevents inner controls from stealing focus from the trigger,
           which would otherwise fire `blur` and close the popover. Click events
           still propagate normally. -->
      <div @mousedown.prevent>
        <span class="gl-font-bold" data-testid="orbit-popover-title">{{
          $options.i18n.popoverTitle
        }}</span>

        <p
          class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle"
          data-testid="orbit-popover-description"
        >
          {{ $options.i18n.description }}
        </p>
        <p class="gl-mb-0 gl-mt-3 gl-text-sm gl-font-bold gl-text-subtle">{{ __('Use Orbit') }}</p>
        <div class="gl-flex gl-flex-col gl-gap-3 gl-pb-3">
          <div
            v-for="toggle in $options.subsettingToggles"
            :key="toggle.key"
            class="gl-flex gl-items-center gl-justify-between gl-gap-2"
          >
            <span>{{ toggle.label }}</span>
            <gl-toggle
              :value="orbitSettings[toggle.key] === true"
              :disabled="isSaving"
              :label="toggle.label"
              label-position="hidden"
              :data-testid="toggle.testId"
              @change="(newValue) => onSubsettingChange(toggle.key, newValue)"
            />
          </div>
        </div>

        <!-- Links -->
        <div class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-3">
          <gl-link
            :href="$options.orbitDocsPath"
            class="gl-flex gl-items-center gl-gap-2"
            target="_blank"
            rel="noopener noreferrer"
            data-testid="orbit-learn-about-link"
          >
            <gl-icon name="information-o" :size="12" />
            {{ $options.i18n.learnAbout }}
          </gl-link>

          <gl-link
            :href="$options.orbitFeedbackUrl"
            class="gl-flex gl-items-center gl-gap-2"
            target="_blank"
            rel="noopener noreferrer"
            data-testid="orbit-feedback-link"
          >
            <gl-icon name="comment" :size="12" />
            {{ $options.i18n.leaveFeedback }}
          </gl-link>
        </div>
      </div>
    </gl-popover>
  </span>
</template>
