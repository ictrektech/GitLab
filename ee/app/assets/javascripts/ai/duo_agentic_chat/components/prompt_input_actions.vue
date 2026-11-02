<script>
import {
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlIcon,
  GlToggle,
  GlTooltipDirective,
} from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import { s__, sprintf } from '~/locale';
import { PROMPT_COMPOSER_ACTIONS } from '../constants';
import { MAX_ATTACHMENT_BYTES } from '../utils/attachment_utils';
import { isWebSearchAvailable } from '../utils/web_search_preference';

export default {
  name: 'PromptInputActions',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlIcon,
    GlToggle,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    // Defaults to false so a mount that does not provide it hides the control
    // rather than granting a capability no group opted into.
    webSearchAllowedForGroup: {
      default: false,
    },
  },
  props: {
    webSearchEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    // Answered by the composer, which is also what runs the action. Defaults to false
    // for the same reason `webSearchAllowedForGroup` does: a mount that does not supply
    // it hides the row rather than offering one that cannot work.
    goalAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['update:web-search-enabled', 'attach-files', 'dispatch-action'],
  data() {
    return {
      isDropdownOpen: false,
    };
  },
  computed: {
    hasWebSearch() {
      return isWebSearchAvailable(this.glFeatures, this.webSearchAllowedForGroup);
    },
    hasFileAttachments() {
      return Boolean(this.glFeatures?.dapWebChatFileAttachments);
    },
    hasActions() {
      return this.hasWebSearch || this.hasFileAttachments || this.goalAvailable;
    },
  },
  methods: {
    toggleWebSearch() {
      this.$emit('update:web-search-enabled', !this.webSearchEnabled);
    },
    // The menu stays open on activation, which is what the web search toggle wants.
    // This item does not: closing it keeps it from sitting behind the file dialog.
    attachFiles() {
      this.$emit('attach-files');
      // Optional call: the dropdown is stubbed without its methods in some tests.
      this.$refs.dropdown?.close?.();
    },
    startGoalMode() {
      // Names the same action the `/goal` command names, so this row and the suggestion
      // menu reach goal mode by one path rather than two. Only the name travels: the
      // command is the plugin's, and nothing here needs it.
      this.$emit('dispatch-action', PROMPT_COMPOSER_ACTIONS.START_GOAL);
      // A one-shot action like attaching files, so it closes the menu too.
      this.$refs.dropdown?.closeAndFocus?.();
    },
  },
  goalItem: { text: s__('DuoAgenticChat|Goal'), icon: 'work-item-objective' },
  attachImageItem: { text: s__('DuoAgenticChat|Attach image'), icon: 'paperclip' },
  // Two lines separated by a blank one; `gl-whitespace-pre-line` keeps the break.
  // The formats list spells out `ALLOWED_IMAGE_MIME_TYPES` as extensions.
  attachImageTooltip: {
    title: [
      s__('DuoAgenticChat|Supported formats: .png, .jpg, .jpeg, .webp'),
      sprintf(s__('DuoAgenticChat|File limit: %{limit}'), {
        limit: numberToHumanSize(MAX_ATTACHMENT_BYTES),
      }),
    ].join('\n\n'),
    placement: 'left',
    boundary: 'viewport',
    customClass: 'gl-whitespace-pre-line',
  },
  i18n: {
    ADD_OR_ENABLE: s__('DuoAgenticChat|Add or enable'),
    WEB_SEARCH: s__('DuoAgenticChat|Web search'),
  },
};
</script>
<template>
  <gl-disclosure-dropdown
    v-if="hasActions"
    ref="dropdown"
    v-gl-tooltip="isDropdownOpen ? '' : $options.i18n.ADD_OR_ENABLE"
    icon="plus"
    category="tertiary"
    positioning-strategy="fixed"
    no-caret
    :auto-close="false"
    :disabled="disabled"
    :toggle-text="$options.i18n.ADD_OR_ENABLE"
    text-sr-only
    @shown="isDropdownOpen = true"
    @hidden="isDropdownOpen = false"
  >
    <gl-disclosure-dropdown-item
      v-if="goalAvailable"
      :item="$options.goalItem"
      data-testid="goal-item"
      @action="startGoalMode"
    />
    <gl-disclosure-dropdown-item
      v-if="hasFileAttachments"
      v-gl-tooltip="$options.attachImageTooltip"
      :item="$options.attachImageItem"
      data-testid="attach-image-item"
      @action="attachFiles"
    />
    <gl-disclosure-dropdown-item
      v-if="hasWebSearch"
      data-testid="web-search-item"
      @action="toggleWebSearch"
    >
      <template #list-item>
        <gl-toggle
          :value="webSearchEnabled"
          :label="$options.i18n.WEB_SEARCH"
          label-position="left"
          class="gl-w-full gl-justify-between"
          data-testid="web-search-toggle"
        >
          <template #label>
            <!-- `.gl-toggle-label` styles the label as a form label (bold, text-strong).
                 In a menu it is just the item's name, so it matches the sibling item. -->
            <span class="gl-flex gl-items-center gl-gap-3 gl-font-normal gl-text-default">
              <gl-icon name="earth" variant="current" />
              {{ $options.i18n.WEB_SEARCH }}
            </span>
          </template>
        </gl-toggle>
      </template>
    </gl-disclosure-dropdown-item>
  </gl-disclosure-dropdown>
</template>
