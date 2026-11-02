<script>
import { GlButton, GlFormRadio, GlFormRadioGroup, GlPopover } from '@gitlab/ui';
import { __, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import {
  SIDEBAR_NAV_MODE_ITEMS,
  SIDEBAR_PREFERENCES_TOGGLE_ID,
  FEATURE_LIBRARY_TRIGGER_ID,
} from '../../constants';
import { EVENT_SELECT_SIDEBAR_NAVIGATION_MODE_IN_SIDEBAR_PREFERENCES } from '../../tracking_constants';

const STEP_LAYOUT = 1;
const STEP_CATALOG = 2;
const STEP_COUNT = 2;
const AUTOFOCUSED_LANDMARK_SELECTOR =
  '[autofocus]:not(input, textarea, select, [contenteditable]:not([contenteditable="false"]))';

export default {
  name: 'TailoredNavigationOnboardingPopover',
  components: {
    GlButton,
    GlFormRadio,
    GlFormRadioGroup,
    GlPopover,
  },
  mixins: [InternalEvents.mixin()],
  STEP_LAYOUT,
  STEP_CATALOG,
  navModeOptions: SIDEBAR_NAV_MODE_ITEMS,
  inject: ['panelType'],
  props: {
    navMode: {
      type: String,
      required: true,
    },
    // Hides the popover without destroying this component, so the current step
    // survives while the sidebar is collapsed.
    visible: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['catalog-step', 'nav-mode-change', 'close'],
  data() {
    return {
      step: STEP_LAYOUT,
      // The popover remounts whenever it's hidden and shown again (sidebar collapse,
      // catalog item scrolled away), so only take focus on each step's first show.
      focusOnShow: true,
    };
  },
  computed: {
    target() {
      return this.step === STEP_CATALOG
        ? FEATURE_LIBRARY_TRIGGER_ID
        : SIDEBAR_PREFERENCES_TOGGLE_ID;
    },
    isFirstStep() {
      return this.step === STEP_LAYOUT;
    },
    isLastStep() {
      return this.step === STEP_COUNT;
    },
    stepLabel() {
      return sprintf(__('Step %{currentStep} of %{stepsTotal}'), {
        currentStep: this.step,
        stepsTotal: STEP_COUNT,
      });
    },
  },
  watch: {
    step(step) {
      this.$emit('catalog-step', step === STEP_CATALOG);
    },
  },
  beforeDestroy() {
    this.popoverElement?.removeEventListener('keydown', this.onPopoverKeydown);
  },
  methods: {
    onShown({ relatedTarget }) {
      // The popover remounts on each step, so move the listener to the new element.
      this.popoverElement?.removeEventListener('keydown', this.onPopoverKeydown);

      // Listen on the whole popover so Esc also works from the title's close button.
      this.popoverElement = relatedTarget;
      this.popoverElement?.addEventListener('keydown', this.onPopoverKeydown);

      // Focus the popover itself (it has tabindex="-1") so it is read from the top and Tab
      // starts at its first control. It opens by itself, so only take focus nobody holds.
      if (!this.focusOnShow) return;
      const autoOpened = !this.stepChanged;
      this.focusOnShow = false;
      this.stepChanged = false;
      if (autoOpened && !this.focusIsFree()) return;
      this.popoverElement?.focus();
    },
    focusIsFree() {
      const { activeElement } = document;
      if (!activeElement || activeElement === document.body) return true;

      // Pages autofocus the top bar landmark on load, which the user hasn't chosen.
      return activeElement.matches(AUTOFOCUSED_LANDMARK_SELECTOR);
    },
    close() {
      // The popover is about to be destroyed, so hand focus back to its anchor
      // instead of letting it fall to <body>.
      document.getElementById(this.target)?.focus();
      this.$emit('close');
    },
    onPopoverKeydown(event) {
      if (event.key !== 'Escape') return;

      event.stopPropagation();
      this.close();
    },
    goToStep(step) {
      this.focusOnShow = true;
      this.stepChanged = true;
      this.step = step;
    },
    onNavModeChange(mode) {
      if (mode === this.navMode) return;

      // Same event the in-sidebar dropdown fires, so the choice is counted
      // uniformly regardless of where it was made.
      this.trackEvent(EVENT_SELECT_SIDEBAR_NAVIGATION_MODE_IN_SIDEBAR_PREFERENCES, {
        label: this.panelType,
        property: mode,
      });

      // SuperSidebar owns persistence (localStorage) and live state, so it
      // stays the single writer shared with the in-sidebar dropdown.
      this.$emit('nav-mode-change', mode);
    },
  },
};
</script>

<template>
  <!-- Keyed by step so the popover re-anchors and re-positions on its new target.
       Viewport boundary: the default (scrollParent) is the sidebar's scroll area, which
       flips the catalog step to the left, over the sidebar. -->
  <gl-popover
    v-if="visible"
    :key="step"
    show
    show-close-button
    :target="target"
    :title="s__('TailoredNav|Tailor your sidebar experience')"
    placement="right"
    boundary="viewport"
    triggers=""
    data-testid="tailored-navigation-onboarding-popover"
    @close-button-clicked="close"
    @shown="onShown"
  >
    <template v-if="step === $options.STEP_LAYOUT">
      <p class="gl-mb-3 gl-text-subtle">
        {{
          s__(
            'TailoredNav|Your sidebar is built around your pins. Choose how much of the sidebar to show.',
          )
        }}
      </p>
      <fieldset>
        <legend class="gl-sr-only">{{ s__('TailoredNav|Layout') }}</legend>
        <gl-form-radio-group
          :checked="navMode"
          data-testid="onboarding-nav-mode"
          @change="onNavModeChange"
        >
          <gl-form-radio
            v-for="option in $options.navModeOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.text }}
          </gl-form-radio>
        </gl-form-radio-group>
      </fieldset>
    </template>

    <p v-else-if="step === $options.STEP_CATALOG" class="gl-mb-3 gl-text-subtle">
      {{ s__('TailoredNav|Explore and pin more features at any time from the Feature catalog.') }}
    </p>

    <div class="gl-mt-4 gl-flex gl-items-center gl-justify-between gl-gap-3">
      <span class="gl-text-subtle" aria-live="polite" data-testid="onboarding-step-label">{{
        stepLabel
      }}</span>
      <div class="gl-flex gl-gap-3">
        <gl-button v-if="!isFirstStep" data-testid="onboarding-back" @click="goToStep(step - 1)">
          {{ s__('TailoredNav|Back') }}
        </gl-button>
        <gl-button v-if="isLastStep" variant="confirm" data-testid="onboarding-done" @click="close">
          {{ s__('TailoredNav|Done') }}
        </gl-button>
        <gl-button
          v-else
          variant="confirm"
          data-testid="onboarding-next"
          @click="goToStep(step + 1)"
        >
          {{ s__('TailoredNav|Next') }}
        </gl-button>
      </div>
    </div>
  </gl-popover>
</template>
