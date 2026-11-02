<script>
import { defineComponent } from 'vue';
import { GlButton, GlIcon, GlIntersperse, GlLink, GlSprintf } from '@gitlab/ui';
import { DUO_CHAT_AGENT_GITLAB_DUO } from 'ee/ai/constants';
import { sendDuoChatCommand, setAgenticMode } from 'ee/ai/utils';
import { DOCS_URL } from '~/constants';
import { s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import { ORBIT_CLI_SETUP_COMMAND, ORBIT_VALUE_PROMPT } from './constants';
import QuickstartOption from './quickstart_option.vue';

export default defineComponent({
  name: 'OverviewQuickstart',
  components: {
    GlButton,
    GlIcon,
    GlIntersperse,
    GlLink,
    GlSprintf,
    ClipboardButton,
    QuickstartOption,
  },
  mixins: [InternalEvents.mixin()],
  inject: ['preferencesPath'],
  props: {
    duoAccessible: {
      type: Boolean,
      required: true,
    },
    orbitSettingsEnabled: {
      type: Boolean,
      required: true,
    },
    indexing: {
      type: Boolean,
      required: true,
    },
  },
  computed: {
    tryDuoText() {
      return this.indexing
        ? s__('Orbit|When indexing finishes, ask GitLab Duo a question that spans projects.')
        : s__('Orbit|Ask GitLab Duo a question that spans projects.');
    },
  },
  methods: {
    trackCliCopy() {
      this.trackEvent('click_orbit_copy_to_clipboard', { label: 'CLI' });
    },
    askDuo() {
      this.trackEvent('click_orbit_open_duo_chat');
      // sendDuoChatCommand keeps the current chat mode, and the agent runs only in agentic mode.
      setAgenticMode();
      sendDuoChatCommand({
        question: ORBIT_VALUE_PROMPT,
        agenticPrompt: ORBIT_VALUE_PROMPT,
        resourceId: 'orbit-quickstart',
        agent: { name: DUO_CHAT_AGENT_GITLAB_DUO },
      });
    },
  },
  cliCommand: ORBIT_CLI_SETUP_COMMAND,
  docsHref: `${DOCS_URL}/orbit/`,
  mcpDocsHref: `${DOCS_URL}/orbit/remote/access/mcp/`,
});
</script>

<template>
  <section
    id="orbit-quickstart"
    class="gl-border gl-rounded-xl gl-border-default gl-bg-default gl-p-5"
    aria-labelledby="orbit-quickstart-title"
    data-testid="orbit-quickstart"
  >
    <div class="gl-flex gl-flex-wrap gl-items-baseline gl-gap-x-3">
      <h2 id="orbit-quickstart-title" class="gl-heading-4 gl-m-0">
        {{ s__('Orbit|Quickstart') }}
      </h2>
      <span v-if="duoAccessible" class="gl-text-subtle" data-testid="orbit-quickstart-subtitle">
        {{ s__('Orbit|Use GitLab Orbit in GitLab Duo, in your own agents, or both.') }}
      </span>
    </div>

    <hr class="gl-my-4" />

    <ul
      class="gl-m-0 gl-grid gl-list-none gl-grid-cols-1 gl-gap-5 gl-p-0"
      :class="{ 'md:gl-grid-cols-2': duoAccessible }"
    >
      <quickstart-option
        v-if="duoAccessible"
        icon="tanuki-ai"
        :title="s__('Orbit|Use GitLab Orbit in GitLab Duo')"
        :description="tryDuoText"
        data-testid="orbit-quickstart-duo"
      >
        <gl-button
          v-if="orbitSettingsEnabled"
          class="gl-self-start"
          category="secondary"
          size="small"
          icon="tanuki-ai"
          data-testid="orbit-quickstart-ask-duo"
          @click="askDuo"
        >
          {{ s__('Orbit|Ask GitLab Duo') }}
        </gl-button>
        <span v-else data-testid="orbit-quickstart-turn-on">
          <gl-sprintf
            :message="
              s__(
                'Orbit|To use GitLab Orbit in GitLab Duo, turn it on in your %{linkStart}preferences%{linkEnd}.',
              )
            "
          >
            <template #link="{ content }">
              <gl-link :href="preferencesPath" data-testid="orbit-quickstart-preferences">{{
                content
              }}</gl-link>
            </template>
          </gl-sprintf>
        </span>
      </quickstart-option>

      <quickstart-option
        icon="terminal"
        :class="{ 'md:gl-border-l md:gl-border-l-default md:gl-pl-5': duoAccessible }"
        :title="s__('Orbit|Use GitLab Orbit with your own agents')"
        :description="
          s__(
            'Orbit|Connect your AI coding agents to GitLab Orbit and query it from your terminal with one command.',
          )
        "
      >
        <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
          <div
            class="gl-flex gl-items-center gl-justify-between gl-gap-2 gl-rounded-md gl-bg-strong gl-px-3 gl-py-2"
          >
            <code class="gl-bg-transparent gl-text-sm gl-text-default">{{
              $options.cliCommand
            }}</code>
            <clipboard-button
              :text="$options.cliCommand"
              :title="s__('Orbit|Copy command')"
              category="tertiary"
              size="small"
              @click="trackCliCopy"
            />
          </div>
          <gl-intersperse separator=" · ">
            <gl-link :href="$options.docsHref" target="_blank" data-testid="orbit-quickstart-docs">
              {{ s__('Orbit|Documentation') }} <gl-icon name="external-link" :size="12" />
            </gl-link>
            <gl-link
              :href="$options.mcpDocsHref"
              target="_blank"
              data-testid="orbit-quickstart-mcp-docs"
            >
              {{ s__('Orbit|Connect an MCP client') }} <gl-icon name="external-link" :size="12" />
            </gl-link>
          </gl-intersperse>
        </div>
      </quickstart-option>
    </ul>
  </section>
</template>
