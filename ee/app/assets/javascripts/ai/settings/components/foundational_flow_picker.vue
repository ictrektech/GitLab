<script>
import { GlFormCheckbox } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { CODE_REVIEW_FLOW_REFERENCE } from '../constants';
import DuoCodeReviewConsentMessage from './duo_code_review_consent_message.vue';
import FoundationalFlowSelector from './foundational_flow_selector.vue';

const sameSelection = (left, right) =>
  left.length === right.length && left.every((reference) => right.includes(reference));

export default {
  name: 'FoundationalFlowPicker',
  i18n: {
    codeReviewConfirmationMessage: s__(
      "DuoCodeReview|When you enable Code Review Flow for this namespace, all reviews will consume GitLab Credits, regardless of the user's seat. You can disable Code Review Flow at any time.",
    ),
    codeReviewConfirmationTitle: s__('DuoCodeReview|Enable Code Review Flow for this namespace?'),
    codeReviewConfirmationButton: s__('DuoCodeReview|Enable Code Review Flow'),
    selectAll: s__('DuoAgentPlatform|Select all flows'),
  },
  components: {
    GlFormCheckbox,
    DuoCodeReviewConsentMessage,
    FoundationalFlowSelector,
  },
  inject: {
    duoEnterpriseActive: {},
    initialCodeReviewFlowConsentGiven: {},
    availableFoundationalFlows: { default: () => [] },
  },
  props: {
    value: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    selectAll: {
      type: Boolean,
      required: false,
      default: false,
    },
    // id of the note that says why the checkboxes are disabled.
    describedBy: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input', 'consent-given'],
  data() {
    return {
      codeReviewFlowConsentGiven: this.initialCodeReviewFlowConsentGiven,
      selectorKey: 0,
    };
  },
  computed: {
    codeReviewFlowSelected() {
      return this.value.includes(CODE_REVIEW_FLOW_REFERENCE);
    },
    allFlowReferences() {
      return this.availableFoundationalFlows.map((flow) => flow.reference);
    },
    allFlowsSelected() {
      return (
        this.allFlowReferences.length > 0 &&
        this.allFlowReferences.every((reference) => this.value.includes(reference))
      );
    },
    someFlowsSelected() {
      return (
        !this.allFlowsSelected &&
        this.allFlowReferences.some((reference) => this.value.includes(reference))
      );
    },
    showSelectAll() {
      return this.selectAll && this.allFlowReferences.length > 0;
    },
  },
  methods: {
    onSelectAllChanged(checked) {
      this.onFlowSelectionChanged(checked ? this.allFlowReferences : []);
    },
    async onFlowSelectionChanged(flowIds) {
      const addingCodeReview =
        flowIds.includes(CODE_REVIEW_FLOW_REFERENCE) && !this.codeReviewFlowSelected;

      if (addingCodeReview && this.duoEnterpriseActive && !this.codeReviewFlowConsentGiven) {
        const confirmed = await confirmAction(this.$options.i18n.codeReviewConfirmationMessage, {
          title: this.$options.i18n.codeReviewConfirmationTitle,
          primaryBtnText: this.$options.i18n.codeReviewConfirmationButton,
          primaryBtnVariant: 'confirm',
          cancelBtnText: __('Cancel'),
        });

        if (!confirmed) {
          // Increment the key to remount the checkboxes with fresh native DOM state.
          // Vue would otherwise skip the DOM update because :checked on
          // GlFormCheckbox was never seen as false→true→false.
          this.selectorKey += 1;

          // Declining keeps the rest of the change, so "Select all" still selects the other flows.
          const withoutCodeReview = flowIds.filter(
            (reference) => reference !== CODE_REVIEW_FLOW_REFERENCE,
          );
          if (!sameSelection(withoutCodeReview, this.value)) this.$emit('input', withoutCodeReview);

          return;
        }

        this.codeReviewFlowConsentGiven = true;
        this.$emit('consent-given');
      }

      this.$emit('input', flowIds);
    },
  },
  codeReviewFlowReference: CODE_REVIEW_FLOW_REFERENCE,
};
</script>
<template>
  <div :key="selectorKey">
    <gl-form-checkbox
      v-if="showSelectAll"
      :checked="allFlowsSelected"
      :indeterminate="someFlowsSelected"
      :disabled="disabled"
      :aria-describedby="describedBy"
      class="gl-ml-6 gl-mt-3"
      data-testid="foundational-flow-select-all"
      @change="onSelectAllChanged"
    >
      {{ $options.i18n.selectAll }}
    </gl-form-checkbox>
    <foundational-flow-selector
      :class="{ 'gl-pl-5': showSelectAll }"
      :value="value"
      :disabled="disabled"
      :described-by="describedBy"
      @input="onFlowSelectionChanged"
    >
      <template #after-flow="{ reference }">
        <duo-code-review-consent-message
          v-if="reference === $options.codeReviewFlowReference"
          :code-review-flow-selected="codeReviewFlowSelected"
          :code-review-flow-consent-given="codeReviewFlowConsentGiven"
        />
      </template>
    </foundational-flow-selector>
  </div>
</template>
