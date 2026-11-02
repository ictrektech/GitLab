<script>
import { GlBadge, GlIcon, GlLink, GlLoadingIcon } from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { s__, sprintf } from '~/locale';
import { verdictLabel, verdictVariant } from '../../evaluations';
import { modeLabel, modeVariant } from '../list/utils';
import SummarySection from './summary_section.vue';

export default {
  name: 'PolicyEvaluationsSection',
  components: {
    GlBadge,
    GlIcon,
    GlLink,
    GlLoadingIcon,
    SummarySection,
    TimeAgoTooltip,
  },
  props: {
    // Null is "we could not read the evaluations", which is not the same as the
    // empty array's "this policy has never run". The caller passes the connection
    // through toEvaluations, which draws that line.
    evaluations: {
      type: Array,
      required: false,
      default: null,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    unreadable() {
      return this.evaluations === null;
    },
  },
  methods: {
    modeLabel,
    modeVariant,
    verdictLabel,
    verdictVariant,
    // A null project is two different facts. Only a null projectId means the
    // evaluation had no project scope; an id with no project means the viewer
    // cannot see it, and saying "No project" there would claim the policy ran
    // org-wide when it did not.
    projectText({ projectId }) {
      return projectId === null ? this.$options.i18n.noProject : this.$options.i18n.hiddenProject;
    },
    // Engine output with no fixed shape, so it is shown verbatim rather than
    // guessed at. See GovernPolicyViolation.details.
    violationText(violation) {
      return JSON.stringify(violation.details ?? {}, null, 2);
    },
    // A page holds one region per violation across every evaluation, and a policy
    // usually fires on one trigger, so the trigger alone leaves 20 identically named
    // regions. Position in the list is the only part of a row guaranteed to differ.
    violationLabel(evaluation, position, index) {
      return sprintf(this.$options.i18n.violation, {
        trigger: evaluation.trigger.label,
        position: position + 1,
        number: index + 1,
      });
    },
  },
  i18n: {
    label: s__('PolicyStore|Recent evaluations'),
    help: s__(
      'PolicyStore|The 20 most recent times the policy engine ran this policy, newest first.',
    ),
    unreadable: s__('PolicyStore|The evaluations of this policy could not be loaded.'),
    empty: s__('PolicyStore|This policy has not been evaluated yet.'),
    noProject: s__('PolicyStore|No project'),
    hiddenProject: s__('PolicyStore|A project you do not have access to'),
    violation: s__('PolicyStore|Violation %{number} of evaluation %{position}, %{trigger}'),
  },
};
</script>

<template>
  <summary-section :label="$options.i18n.label" testid="evaluations">
    <p class="gl-mb-3 gl-text-sm gl-text-subtle">{{ $options.i18n.help }}</p>

    <gl-loading-icon v-if="loading" size="md" data-testid="evaluations-loading" />

    <p v-else-if="unreadable" class="gl-mb-0 gl-text-subtle" data-testid="evaluations-unreadable">
      {{ $options.i18n.unreadable }}
    </p>

    <p
      v-else-if="!evaluations.length"
      class="gl-mb-0 gl-text-subtle"
      data-testid="evaluations-empty"
    >
      {{ $options.i18n.empty }}
    </p>

    <ul v-else class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-4 gl-p-0">
      <li
        v-for="(evaluation, position) in evaluations"
        :key="evaluation.id"
        class="gl-flex gl-items-start gl-gap-3"
        data-testid="evaluation-entry"
      >
        <span
          class="gl-flex gl-h-6 gl-w-6 gl-flex-shrink-0 gl-items-center gl-justify-center gl-rounded-base gl-bg-subtle gl-text-subtle"
        >
          <gl-icon :name="evaluation.trigger.icon" :size="14" />
        </span>
        <span class="gl-min-w-0 gl-grow">
          <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
            <span class="gl-font-semibold" data-testid="evaluation-trigger">
              {{ evaluation.trigger.label }}
            </span>
            <gl-badge
              :variant="verdictVariant(evaluation.verdict)"
              data-testid="evaluation-verdict"
            >
              {{ verdictLabel(evaluation.verdict) }}
            </gl-badge>
            <gl-badge :variant="modeVariant(evaluation.mode)" data-testid="evaluation-mode">
              {{ modeLabel(evaluation.mode) }}
            </gl-badge>
          </span>
          <span class="gl-mt-1 gl-flex gl-flex-wrap gl-gap-x-3 gl-text-sm gl-text-subtle">
            <gl-link
              v-if="evaluation.project"
              :href="evaluation.project.webPath"
              data-testid="evaluation-project"
            >
              {{ evaluation.project.nameWithNamespace }}
            </gl-link>
            <span v-else data-testid="evaluation-project">{{ projectText(evaluation) }}</span>
            <time-ago-tooltip :time="evaluation.evaluatedAt" data-testid="evaluation-time" />
          </span>
          <pre
            v-for="(violation, index) in evaluation.violations"
            :key="violation.id"
            class="gl-mb-0 gl-mt-2 gl-max-h-48 gl-overflow-y-auto gl-whitespace-pre-wrap gl-rounded-base gl-bg-subtle gl-p-3 gl-text-sm"
            tabindex="0"
            role="region"
            :aria-label="violationLabel(evaluation, position, index)"
            data-testid="evaluation-violation"
          ><code>{{ violationText(violation) }}</code></pre>
        </span>
      </li>
    </ul>
  </summary-section>
</template>
