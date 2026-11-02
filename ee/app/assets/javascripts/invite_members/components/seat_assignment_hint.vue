<script>
import { GlSprintf, GlLink } from '@gitlab/ui';
import { groupUsageQuotasPath } from 'ee/lib/utils/path_helpers/group';

export default {
  name: 'SeatAssignmentHint',
  components: { GlSprintf, GlLink },
  props: {
    rootGroupPath: {
      type: String,
      required: true,
    },
  },
  computed: {
    seatsPath() {
      return groupUsageQuotasPath(this.rootGroupPath, { anchor: 'seats-quota-tab' });
    },
  },
};
</script>

<template>
  <span>
    <gl-sprintf
      :message="
        s__(
          'InviteMembersModal|You can invite only users who already have a seat. %{linkStart}Assign seats%{linkEnd}.',
        )
      "
    >
      <template #link="{ content }">
        <gl-link :href="seatsPath" target="_blank">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
  </span>
</template>
