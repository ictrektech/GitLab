<script>
import { GlFormCheckbox, GlFormGroup, GlLink, GlSprintf, GlTooltipDirective } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__ } from '~/locale';

export default {
  name: 'DuoWebSearchForm',
  i18n: {
    sectionTitle: s__('DuoWorkflowSettings|Web search'),
    checkboxLabel: s__('DuoWorkflowSettings|Allow web search'),
    checkboxHelpText: s__(
      'DuoWorkflowSettings|Make web search available in GitLab Duo Chat for this group and its subgroups and projects. Users can then turn it on in a conversation. %{linkStart}Learn more about web search%{linkEnd}.',
    ),
    disabledTooltip: s__('AiPowered|This setting only applies when GitLab Duo is available.'),
  },
  components: {
    GlFormCheckbox,
    GlFormGroup,
    GlLink,
    GlSprintf,
  },
  directives: {
    tooltip: GlTooltipDirective,
  },
  webSearchHelpPath: helpPagePath('user/gitlab_duo_chat/agentic_chat', {
    anchor: 'allow-web-search-for-a-group',
  }),
  props: {
    webSearchEnabled: {
      type: Boolean,
      required: true,
    },
    disabledCheckbox: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  methods: {
    checkboxChanged(value) {
      this.$emit('change', value);
    },
  },
};
</script>
<template>
  <gl-form-group :label="$options.i18n.sectionTitle">
    <gl-form-checkbox
      :checked="webSearchEnabled"
      :disabled="disabledCheckbox"
      data-testid="web-search-enabled-checkbox"
      name="namespace[ai_settings_attributes][web_search_enabled]"
      @change="checkboxChanged"
    >
      <span v-tooltip="disabledCheckbox ? $options.i18n.disabledTooltip : ''">{{
        $options.i18n.checkboxLabel
      }}</span>
      <template #help>
        <gl-sprintf :message="$options.i18n.checkboxHelpText">
          <template #link="{ content }">
            <gl-link :href="$options.webSearchHelpPath" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </template>
    </gl-form-checkbox>
  </gl-form-group>
</template>
