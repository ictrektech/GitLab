<script>
import { defineComponent } from 'vue';
import { GlModal } from '@gitlab/ui';
import { __, n__, s__ } from '~/locale';
import { CONFIRM_AUTO_INDEX, CONFIRM_EXCLUDE, CONFIRM_KINDS, CONFIRM_TURN_OFF } from './constants';

const DELETION_NOTE = s__(
  'Orbit|Its indexed data is deleted 30 or more days after you turn GitLab Orbit off.',
);

const MODAL_VIEWS = {
  [CONFIRM_TURN_OFF]: (count, autoIndexEnabled) => ({
    title: n__(
      'Orbit|Turn off GitLab Orbit for %d group?',
      'Orbit|Turn off GitLab Orbit for %d groups?',
      count,
    ),
    intro: n__(
      'Orbit|GitLab Orbit stops indexing this group. GitLab Duo and GitLab Orbit queries no longer return its data.',
      'Orbit|GitLab Orbit stops indexing these groups. GitLab Duo and GitLab Orbit queries no longer return their data.',
      count,
    ),
    autoIndexNote: autoIndexEnabled
      ? n__(
          'Orbit|Automatic indexing is on, so GitLab Orbit turns on again for this group within an hour. To keep GitLab Orbit off, exclude the group from automatic indexing.',
          'Orbit|Automatic indexing is on, so GitLab Orbit turns on again for these groups within an hour. To keep GitLab Orbit off, exclude the groups from automatic indexing.',
          count,
        )
      : null,
    outro: DELETION_NOTE,
    primary: { text: s__('Orbit|Turn off GitLab Orbit'), attributes: { variant: 'danger' } },
    listsGroups: true,
  }),
  [CONFIRM_EXCLUDE]: (count) => ({
    title: n__(
      'Orbit|Exclude %d group from automatic indexing?',
      'Orbit|Exclude %d groups from automatic indexing?',
      count,
    ),
    intro: s__(
      'Orbit|Excluded groups are never turned on automatically. Within an hour, GitLab Orbit also turns off for the excluded groups that are on.',
    ),
    outro: DELETION_NOTE,
    primary: { text: s__('Orbit|Exclude'), attributes: { variant: 'danger' } },
    listsGroups: true,
  }),
  [CONFIRM_AUTO_INDEX]: () => ({
    title: s__('Orbit|Turn on GitLab Orbit for all top-level groups?'),
    intro: s__(
      'Orbit|GitLab Orbit turns on for every top-level group now, and for each new top-level group later, except excluded groups.',
    ),
    outro: s__('Orbit|On a large instance, the first index can take several hours.'),
    primary: {
      text: s__('Orbit|Turn on for all top-level groups'),
      attributes: { variant: 'confirm' },
    },
    listsGroups: false,
  }),
};

export default defineComponent({
  name: 'OrbitGroupsConfirmModal',
  components: {
    GlModal,
  },
  props: {
    kind: {
      type: String,
      required: false,
      default: null,
      validator: (value) => CONFIRM_KINDS.includes(value),
    },
    groups: {
      type: Array,
      required: true,
    },
    autoIndexEnabled: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['confirm', 'cancel'],
  computed: {
    view() {
      return this.kind ? MODAL_VIEWS[this.kind](this.groups.length, this.autoIndexEnabled) : null;
    },
  },
  cancelAction: { text: __('Cancel') },
});
</script>

<template>
  <gl-modal
    v-if="view"
    visible
    modal-id="orbit-admin-confirm-modal"
    size="sm"
    :title="view.title"
    :action-primary="view.primary"
    :action-cancel="$options.cancelAction"
    data-testid="orbit-admin-confirm-modal"
    @primary="$emit('confirm', kind)"
    @hidden="$emit('cancel')"
  >
    <p>{{ view.intro }}</p>
    <ul v-if="view.listsGroups" class="gl-mb-4">
      <li v-for="group in groups" :key="group.fullPath">
        <span class="gl-font-bold">{{ group.name }}</span>
        <span v-if="group.fullPath !== group.name" class="gl-text-sm gl-text-subtle">{{
          group.fullPath
        }}</span>
      </li>
    </ul>
    <p v-if="view.autoIndexNote" data-testid="auto-index-note">{{ view.autoIndexNote }}</p>
    <p class="gl-mb-0">{{ view.outro }}</p>
  </gl-modal>
</template>
