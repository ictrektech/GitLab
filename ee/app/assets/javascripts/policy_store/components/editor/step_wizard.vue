<script>
import { GlButton, GlModal } from '@gitlab/ui';
import { isEqual, cloneDeep } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPE_ORGANIZATION } from '~/graphql_shared/constants';
import { s__ } from '~/locale';
import { CATALOG_NAMES, EMPTY_CATALOGS, toCatalogs } from '../../utils';
import getPolicyStoreCatalogs from '../../graphql/get_policy_store_catalogs.query.graphql';
import getGroupPolicyStoreCatalogs from '../../graphql/get_group_policy_store_catalogs.query.graphql';
import { RULES } from '../../catalog/rules';
import { ACTIONS } from '../../catalog/actions';
import { TRIGGERS } from '../../catalog/triggers';
import { actionTriggerBlockers } from '../../catalog/compatibility';
import { actionRuleBlockers, ruleConfigBlockers } from '../../catalog/validation';
import {
  STEP_BUILD,
  STEP_SCOPE,
  STEP_REVIEW,
  STEP_ORDER,
  STEP_LABELS,
  STATUS_COMPLETE,
  STATUS_CURRENT,
  STATUS_UPCOMING,
  SCOPE_ALL,
  ENFORCEMENT_DEFAULT,
  NAMESPACE_TYPE_GROUP,
} from './constants';
import { deserializePolicyData, deserializeScope, emptyPolicyData } from './serializer';
import BuildPolicyStep from './steps/build_policy_step.vue';
import ScopeStep from './steps/scope_step.vue';
import ReviewStep from './steps/review_step.vue';
import PolicyNameField from './policy_name_field.vue';
import WizardControls from './wizard_controls.vue';

export default {
  name: 'StepWizard',
  components: {
    GlButton,
    GlModal,
    BuildPolicyStep,
    ScopeStep,
    ReviewStep,
    PolicyNameField,
    WizardControls,
  },
  STEP_ORDER,
  inject: {
    organizationId: { default: '' },
    namespacePath: { default: '' },
    namespaceType: {},
  },
  props: {
    policy: {
      type: Object,
      required: false,
      default: null,
    },
    saving: {
      type: Boolean,
      required: false,
      default: false,
    },
    nameError: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['cancel', 'save', 'name-update'],
  apollo: {
    catalogsResult: {
      query() {
        return this.isGroupContext ? getGroupPolicyStoreCatalogs : getPolicyStoreCatalogs;
      },
      skip() {
        return this.isGroupContext ? !this.namespacePath : !this.organizationId;
      },
      variables() {
        return this.isGroupContext
          ? { fullPath: this.namespacePath }
          : { id: convertToGraphQLId(TYPE_ORGANIZATION, this.organizationId) };
      },
      update(data) {
        const policyStore = this.isGroupContext
          ? data?.group?.policyStore
          : data?.organization?.policyStore;
        return toCatalogs(policyStore);
      },
      error(error) {
        Sentry.captureException(error, { tags: { policyStoreCatalog: 'all' } });
        this.catalogsResult = { catalogs: EMPTY_CATALOGS, failedCatalogs: [...CATALOG_NAMES] };
      },
    },
  },
  data() {
    const name = this.policy?.name || '';
    const description = this.policy?.description || '';
    const mode = this.policy?.mode || ENFORCEMENT_DEFAULT;
    const scope = this.policy
      ? deserializeScope(this.policy.policy_scope)
      : { mode: SCOPE_ALL, projects: [], exclusions: [] };
    const policyData = this.policy ? deserializePolicyData(this.policy) : emptyPolicyData();

    return {
      name,
      description,
      mode,
      scope,
      policyData,
      initialName: name,
      initialDescription: description,
      initialMode: mode,
      initialScope: cloneDeep(scope),
      initialPolicyData: cloneDeep(policyData),
      showCancelModal: false,
      leaving: false,
      currentStepIndex: 0,
      // The rules whose blank required fields now read as gaps rather than as fields the
      // author has not reached. Ids rather than a flag: a rule added after the author came
      // back from a later step has not been skipped over, so it opens neutral like any
      // other new rule. Owned here because the build step is destroyed on every step
      // change and cannot remember either the signal or which rules it applied to.
      revealedEntryIds: [],
      // Without a namespace identifier the query is skipped, so the catalogs
      // start settled and failed instead of loading forever. The predicate
      // mirrors skip(): groups need namespacePath, orgs need organizationId.
      catalogsResult: {
        catalogs: EMPTY_CATALOGS,
        failedCatalogs: this.hasNamespaceIdentifierForInit() ? [] : [...CATALOG_NAMES],
      },
    };
  },
  computed: {
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    hasNamespaceIdentifier() {
      return this.isGroupContext ? Boolean(this.namespacePath) : Boolean(this.organizationId);
    },
    catalogsLoading() {
      return this.hasNamespaceIdentifier ? this.$apollo.queries.catalogsResult.loading : false;
    },
    catalogs() {
      return this.catalogsResult.catalogs;
    },
    failedCatalogs() {
      return this.catalogsResult.failedCatalogs;
    },
    isDirty() {
      return (
        this.name !== this.initialName ||
        this.description !== this.initialDescription ||
        this.mode !== this.initialMode ||
        !isEqual(this.scope, this.initialScope) ||
        !isEqual(this.policyData, this.initialPolicyData)
      );
    },
    currentStepId() {
      return this.$options.STEP_ORDER[this.currentStepIndex];
    },
    isBuildStep() {
      return this.currentStepId === STEP_BUILD;
    },
    isScopeStep() {
      return this.currentStepId === STEP_SCOPE;
    },
    isReviewStep() {
      return this.currentStepId === STEP_REVIEW;
    },
    // Everything the review step summarises: the wizard-owned fields plus the Build
    // step's selections, flattened to id lists the catalogs can label.
    policyState() {
      const { trigger, rules, actions } = this.policyData;

      return {
        name: this.name,
        description: this.description,
        mode: this.mode,
        scope: this.scope,
        trigger,
        rules,
        actions,
      };
    },
    steps() {
      const { length } = this.$options.STEP_ORDER;
      return this.$options.STEP_ORDER.map((id, index) => ({
        id,
        number: index + 1,
        label: this.stepLabel(id),
        status: this.stepStatus(index),
        isLast: index === length - 1,
      }));
    },
    currentStepLabel() {
      return this.stepLabel(this.currentStepId);
    },
    isFirstStep() {
      return this.currentStepIndex === 0;
    },
    isLastStep() {
      return this.currentStepIndex === this.$options.STEP_ORDER.length - 1;
    },
    // The store refuses a rule whose declared-required config is blank, so
    // the review step names each gap and the Save button waits for them.
    // Validated against the static catalogs (which carry the field metadata and
    // the trigger kinds), not the fetched ones, so blockers survive a fetch failure.
    // Deduplicated because the review step keys the rendered list by the sentence itself,
    // and two catalog entries sharing a label produce the same sentence twice.
    saveBlockers() {
      return [
        ...new Set([
          ...ruleConfigBlockers(RULES, this.policyData.rules, this.policyData.ruleConfigs),
          ...actionRuleBlockers(
            { actions: ACTIONS, rules: RULES },
            this.policyData.actions,
            this.policyData.rules,
          ),
          ...actionTriggerBlockers(
            { triggers: TRIGGERS, actions: ACTIONS },
            this.policyData.trigger,
            this.policyData.actions,
          ),
        ]),
      ];
    },
    // The create endpoint requires a name, a trigger and at least one rule, so
    // the Save button waits for all three rather than submitting a known 400.
    canSave() {
      return Boolean(
        this.name.trim() &&
        this.policyData.trigger &&
        this.policyData.rules.length &&
        !this.saveBlockers.length,
      );
    },
  },
  watch: {
    // Leaving the build step is the closest thing this wizard has to a submit: the save
    // button is disabled while blockers exist, so there is no click to intercept.
    currentStepIndex(index) {
      // Every rule that exists at this moment, so one added on a later visit to the build
      // step stays neutral until the author steps past it too.
      if (index > 0) this.revealedEntryIds = this.policyData.rules ?? [];
    },
  },
  mounted() {
    window.addEventListener('beforeunload', this.confirmUnload);
  },
  beforeDestroy() {
    window.removeEventListener('beforeunload', this.confirmUnload);
  },
  methods: {
    // Called during data() init — cannot rely on computed props yet.
    hasNamespaceIdentifierForInit() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP
        ? Boolean(this.namespacePath)
        : Boolean(this.organizationId);
    },
    // A rule dropped here has to lose its revealed mark too, or removing and re-adding
    // it after stepping past the build step reopens it red.
    onBuildUpdate(policyData) {
      this.policyData = policyData;
      const rules = policyData.rules ?? [];
      this.revealedEntryIds = this.revealedEntryIds.filter((id) => rules.includes(id));
    },
    stepLabel(id) {
      return STEP_LABELS[id];
    },
    stepStatus(index) {
      if (index < this.currentStepIndex) return STATUS_COMPLETE;
      if (index === this.currentStepIndex) return STATUS_CURRENT;
      return STATUS_UPCOMING;
    },
    closeCancelModal() {
      this.showCancelModal = false;
    },
    requestCancel() {
      if (this.isDirty) {
        this.showCancelModal = true;
      } else {
        this.confirmCancel();
      }
    },
    // The user explicitly discarded (or had nothing to discard), so the
    // unload guard must not prompt a second time on the way out.
    confirmCancel() {
      this.leaving = true;
      this.$emit('cancel');
    },
    confirmUnload(event) {
      if (!this.isDirty || this.saving || this.leaving) return;

      event.preventDefault();
      // Chrome only shows the prompt when returnValue is set.
      Object.assign(event, { returnValue: '' });
    },
    onModeSelect(mode) {
      this.mode = mode;
    },
    onNameUpdate(name) {
      this.name = name;
      this.$emit('name-update');
    },
    onScopeUpdate(scope) {
      this.scope = scope;
    },
    onEditPolicy() {
      this.currentStepIndex = 0;
    },
    back() {
      if (!this.isFirstStep) this.currentStepIndex -= 1;
    },
    next() {
      if (!this.isLastStep) this.currentStepIndex += 1;
    },
    requestSave() {
      this.$emit('save', {
        name: this.name,
        description: this.description,
        mode: this.mode,
        scope: this.scope,
        // The wizard only understands project scoping, so the save handler
        // needs to know whether the scope was touched before overwriting a
        // scope authored through the API (Rego, groups, frameworks).
        scopeChanged: !isEqual(this.scope, this.initialScope),
        policyData: this.policyData,
      });
    },
  },
  cancelModalPrimary: {
    text: s__('PolicyStore|Discard changes'),
    attributes: { variant: 'danger' },
  },
  cancelModalCancel: {
    text: s__('PolicyStore|Continue editing'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5 gl-pt-6">
    <div class="gl-flex gl-flex-col gl-gap-4 md:gl-flex-row md:gl-items-center">
      <policy-name-field
        class="gl-w-full gl-flex-shrink-0 md:gl-w-1/4"
        :name="name"
        :description="description"
        :error="nameError"
        @update:name="onNameUpdate"
        @update:description="description = $event"
      />
      <div class="gl-min-w-0 gl-flex-1">
        <wizard-controls :steps="steps" :mode="mode" @select-mode="onModeSelect" />
      </div>
    </div>

    <build-policy-step
      v-if="isBuildStep"
      :policy-data="policyData"
      :revealed-entry-ids="revealedEntryIds"
      :catalogs="catalogs"
      :catalogs-loading="catalogsLoading"
      :failed-catalogs="failedCatalogs"
      data-testid="wizard-step-content"
      @update="onBuildUpdate"
    />
    <scope-step
      v-else-if="isScopeStep"
      :scope="scope"
      class="gl-my-6"
      data-testid="wizard-step-content"
      @update="onScopeUpdate"
    />
    <review-step
      v-else-if="isReviewStep"
      :policy="policyState"
      :catalogs="catalogs"
      :save-blockers="saveBlockers"
      class="gl-my-6"
      data-testid="wizard-step-content"
      @edit="onEditPolicy"
    />
    <div
      v-else
      data-testid="wizard-step-content"
      class="gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-p-6 gl-text-subtle"
    >
      <h3 class="gl-heading-3 gl-mb-2">{{ currentStepLabel }}</h3>
      <p class="gl-mb-0">{{ s__('PolicyStore|This step is coming soon.') }}</p>
    </div>

    <div
      class="gl-z-10 gl-border-t gl-sticky gl-bottom-0 gl-flex gl-flex-shrink-0 gl-items-center gl-justify-between gl-border-subtle gl-bg-default gl-px-6 gl-py-3"
    >
      <gl-button @click="requestCancel">
        {{ __('Cancel') }}
      </gl-button>
      <div class="gl-flex gl-items-center gl-gap-3">
        <gl-button v-if="!isFirstStep" @click="back">{{ __('Back') }}</gl-button>
        <gl-button v-if="!isLastStep" variant="confirm" :disabled="catalogsLoading" @click="next">
          {{ __('Next') }}
        </gl-button>
        <gl-button
          v-if="isLastStep"
          variant="confirm"
          :disabled="!canSave"
          :loading="saving"
          data-testid="save-policy-button"
          @click="requestSave"
        >
          {{ s__('PolicyStore|Save policy') }}
        </gl-button>
      </div>
    </div>

    <gl-modal
      modal-id="policy-store-cancel-modal"
      :visible="showCancelModal"
      :title="s__('PolicyStore|Discard this policy?')"
      :action-primary="$options.cancelModalPrimary"
      :action-cancel="$options.cancelModalCancel"
      @primary="confirmCancel"
      @hidden="closeCancelModal"
    >
      {{ s__('PolicyStore|Your progress will be lost if you leave without saving.') }}
    </gl-modal>
  </div>
</template>
