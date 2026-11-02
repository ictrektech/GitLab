<script>
import {
  GlAnimatedChevronRightDownIcon,
  GlBadge,
  GlButton,
  GlCollapse,
  GlIcon,
  GlLink,
  GlTooltipDirective,
} from '@gitlab/ui';
import { mapState } from 'pinia';
import { n__, s__, sprintf } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { useDiscussions } from '~/notes/store/discussions';
import { DUO_CODE_REVIEW_DEPTH_LABELS } from '../constants';

const SEVERITY_LABELS = {
  critical: s__('DuoCodeReview|Critical'),
  major: s__('DuoCodeReview|Major'),
  minor: s__('DuoCodeReview|Minor'),
};

// Same icons as the thread's resolve button, so the state reads the same in both places.
const RESOLVED_STATUS = {
  icon: 'check-circle-filled',
  variant: 'success',
  text: s__('DuoCodeReview|Resolved'),
};
const UNRESOLVED_STATUS = {
  icon: 'check-circle',
  variant: 'default',
  text: s__('DuoCodeReview|Unresolved'),
};

export default {
  name: 'DuoCodeReviewSummaryCard',
  components: {
    GlAnimatedChevronRightDownIcon,
    GlBadge,
    GlButton,
    GlCollapse,
    GlIcon,
    GlLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    noteId: {
      type: String,
      required: true,
    },
    findingNoteIds: {
      type: Array,
      required: true,
    },
    depth: {
      type: String,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      isExpanded: false,
    };
  },
  computed: {
    ...mapState(useDiscussions, ['discussions']),
    findings() {
      return this.discussions
        .map((discussion) => ({ discussion, note: discussion.notes?.[0] }))
        .filter(
          ({ note }) => note?.duo_code_review_finding && this.findingNoteIds.includes(note.id),
        )
        .map(({ discussion, note }) => {
          const position = discussion.position || note.position || {};

          return {
            ...note.duo_code_review_finding,
            noteId: note.id,
            path: position.new_path || position.old_path,
            line: position.new_line ?? position.old_line,
            resolved: Boolean(discussion.resolved),
          };
        })
        .sort((a, b) => a.path.localeCompare(b.path) || (a.line ?? 0) - (b.line ?? 0));
    },
    groups() {
      return Object.keys(SEVERITY_LABELS)
        .map((severity) => ({
          severity,
          label: SEVERITY_LABELS[severity],
          findings: this.findings.filter((finding) => finding.severity === severity),
        }))
        .filter(({ findings }) => findings.length);
    },
    heading() {
      const fileCount = new Set(this.findings.map(({ path }) => path)).size;
      const resolvedCount = this.findings.filter(({ resolved }) => resolved).length;
      const message = resolvedCount
        ? s__('DuoCodeReview|%{findings} across %{files} · %{resolved}')
        : s__('DuoCodeReview|%{findings} across %{files}');

      return sprintf(message, {
        findings: n__(
          'DuoCodeReview|%d finding',
          'DuoCodeReview|%d findings',
          this.findings.length,
        ),
        files: n__('DuoCodeReview|%d file', 'DuoCodeReview|%d files', fileCount),
        resolved: n__('DuoCodeReview|%d resolved', 'DuoCodeReview|%d resolved', resolvedCount),
      });
    },
    depthLabel() {
      return DUO_CODE_REVIEW_DEPTH_LABELS[this.depth];
    },
    bodyId() {
      return `duo-code-review-summary-findings-${this.noteId}`;
    },
  },
  methods: {
    categoryLabel(category) {
      return humanize(category, '[-_]');
    },
    status(finding) {
      return finding.resolved ? RESOLVED_STATUS : UNRESOLVED_STATUS;
    },
  },
};
</script>

<template>
  <div
    v-if="findings.length"
    class="gl-border-b gl-border-section"
    data-testid="duo-code-review-summary-card"
  >
    <!-- eslint-disable tailwindcss/no-arbitrary-value -- inner radius of the 1px-bordered note box -->
    <gl-button
      category="tertiary"
      block
      class="!gl-justify-start !gl-rounded-b-none !gl-rounded-t-[calc(var(--gl-border-radius-lg)-1px)]"
      button-text-classes="gl-flex gl-items-center gl-gap-2 gl-font-bold gl-w-full"
      :aria-expanded="String(isExpanded)"
      :aria-controls="bodyId"
      data-testid="duo-code-review-summary-toggle"
      @click="isExpanded = !isExpanded"
    >
      <!-- eslint-enable tailwindcss/no-arbitrary-value -->
      <gl-animated-chevron-right-down-icon :is-on="isExpanded" />
      {{ heading }}
      <gl-badge
        v-if="depthLabel"
        variant="neutral"
        data-testid="duo-code-review-depth-badge"
        class="gl-ml-auto"
      >
        {{ depthLabel }}
      </gl-badge>
    </gl-button>

    <gl-collapse :id="bodyId" :visible="isExpanded">
      <div class="gl-border-t gl-flex gl-flex-col gl-gap-4 gl-border-section gl-p-4">
        <section
          v-for="group in groups"
          :key="group.severity"
          data-testid="duo-code-review-summary-group"
        >
          <h4 class="gl-m-0 gl-mb-3 gl-text-base gl-font-bold">{{ group.label }}</h4>
          <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
            <li
              v-for="finding in group.findings"
              :key="finding.noteId"
              class="gl-flex gl-items-start gl-gap-3"
              data-testid="duo-code-review-summary-finding"
            >
              <gl-icon
                v-gl-tooltip
                :name="status(finding).icon"
                :variant="status(finding).variant"
                :title="status(finding).text"
                :aria-label="status(finding).text"
                class="gl-mt-1 gl-shrink-0"
                data-testid="duo-code-review-summary-status"
              />
              <div class="gl-min-w-0">
                <gl-link :href="`#note_${finding.noteId}`">{{
                  categoryLabel(finding.category)
                }}</gl-link>
                <div
                  class="gl-break-all gl-font-monospace gl-text-sm"
                  data-testid="duo-code-review-summary-location"
                >
                  {{ finding.path }}:{{ finding.line }}
                </div>
              </div>
            </li>
          </ul>
        </section>
      </div>
    </gl-collapse>
  </div>
</template>
