<script>
import { GlButton, GlButtonGroup, GlTooltipDirective } from '@gitlab/ui';
import { jumpToQuestion } from 'ee/work_items/utils/question_navigation';
import { QUESTION_NAVIGATION_NEXT, QUESTION_NAVIGATION_PREVIOUS } from 'ee/work_items/constants';

export default {
  name: 'WorkplanQuestionNavigator',
  components: {
    GlButton,
    GlButtonGroup,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    questions: {
      type: Array,
      required: true,
    },
  },
  computed: {
    openNoteIds() {
      return this.questions.filter(({ answered }) => !answered).map(({ noteId }) => noteId);
    },
  },
  methods: {
    jump(direction) {
      jumpToQuestion({ noteIds: this.openNoteIds, direction });
    },
  },
  QUESTION_NAVIGATION_NEXT,
  QUESTION_NAVIGATION_PREVIOUS,
};
</script>

<template>
  <gl-button-group data-testid="workplan-question-navigator">
    <gl-button
      v-gl-tooltip
      :title="s__('AgentPlan|Previous open question')"
      :aria-label="s__('AgentPlan|Previous open question')"
      icon="chevron-lg-up"
      category="tertiary"
      size="small"
      data-testid="previous-question-button"
      @click="jump($options.QUESTION_NAVIGATION_PREVIOUS)"
    />
    <gl-button
      v-gl-tooltip
      :title="s__('AgentPlan|Next open question')"
      :aria-label="s__('AgentPlan|Next open question')"
      icon="chevron-lg-down"
      category="tertiary"
      size="small"
      data-testid="next-question-button"
      @click="jump($options.QUESTION_NAVIGATION_NEXT)"
    />
  </gl-button-group>
</template>
