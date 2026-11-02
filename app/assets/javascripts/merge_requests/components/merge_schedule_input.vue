<script>
import { GlCollapsibleListbox, GlFormInput } from '@gitlab/ui';
import { s__ } from '~/locale';
import { formatDate } from '~/lib/utils/datetime_utility';

const ANYTIME = 'anytime';
const AFTER = 'after';
const BETWEEN = 'between';

export default {
  name: 'MergeScheduleInput',
  components: {
    GlCollapsibleListbox,
    GlFormInput,
  },
  props: {
    mergeAfter: {
      type: String,
      required: false,
      default: undefined,
    },
    mergeBefore: {
      type: String,
      required: false,
      default: undefined,
    },
    paramKey: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      selectedMode: this.initialMode(),
      localMergeAfter: formatDate(this.mergeAfter, "yyyy-mm-dd'T'HH:MM"),
      localMergeBefore: formatDate(this.mergeBefore, "yyyy-mm-dd'T'HH:MM"),
    };
  },
  computed: {
    actualMergeAfter() {
      if (this.selectedMode === ANYTIME) {
        return '';
      }

      return new Date(this.localMergeAfter).toJSON();
    },
    actualMergeBefore() {
      if (this.selectedMode !== BETWEEN) {
        return '';
      }

      return new Date(this.localMergeBefore).toJSON();
    },
    dropdownValues() {
      return [
        {
          text: s__('MergeSchedule|Anytime'),
          value: ANYTIME,
        },
        {
          text: s__('MergeSchedule|After'),
          value: AFTER,
        },
        {
          text: s__('MergeSchedule|Between'),
          value: BETWEEN,
        },
      ];
    },
    shouldDisplayAfterInput() {
      return this.selectedMode !== ANYTIME;
    },
    shouldDisplayBeforeInput() {
      return this.selectedMode === BETWEEN;
    },
  },
  methods: {
    initialMode() {
      if (this.mergeAfter === undefined) return ANYTIME;
      if (this.mergeBefore === undefined) return AFTER;
      return BETWEEN;
    },
  },
};
</script>

<template>
  <div class="gl-col-12">
    <gl-collapsible-listbox v-model="selectedMode" :items="dropdownValues" />
    <div v-if="shouldDisplayAfterInput" class="issuable-form-select-holder">
      <gl-form-input v-model="localMergeAfter" type="datetime-local" />
    </div>
    <template v-if="shouldDisplayBeforeInput">
      <span>-</span>
      <div class="issuable-form-select-holder">
        <gl-form-input v-model="localMergeBefore" type="datetime-local" />
      </div>
    </template>
    <input type="hidden" :name="`${paramKey}[merge_after]`" :value="actualMergeAfter" />
    <input type="hidden" :name="`${paramKey}[merge_before]`" :value="actualMergeBefore" />
  </div>
</template>
