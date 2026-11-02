<script>
import { GlButton, GlDisclosureDropdownItem } from '@gitlab/ui';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import duoChatAvailableQuery from '../../graphql/duo_chat_available.query.graphql';

export default {
  name: 'ViewSessionButton',
  components: {
    GlButton,
    GlDisclosureDropdownItem,
  },
  props: {
    sessionId: {
      type: Number,
      required: true,
    },
    size: {
      type: String,
      required: false,
      default: 'medium',
    },
    /**
     * Render as an item for a parent `GlDisclosureDropdown` (e.g. an overflow menu)
     * instead of as a standalone button.
     */
    asDropdownItem: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  apollo: {
    duoChatAvailable: {
      query: duoChatAvailableQuery,
      update(data) {
        return data?.currentUser?.duoChatAvailable ?? false;
      },
      error() {
        this.duoChatAvailable = false;
      },
    },
  },
  data() {
    return {
      duoChatAvailable: false,
    };
  },
  methods: {
    openSession() {
      eventHub.$emit(SHOW_SESSION, { id: this.sessionId });
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown-item v-if="duoChatAvailable && asDropdownItem" @action="openSession">
    <template #list-item>
      {{ s__('DuoAgentsPlatform|View session') }}
    </template>
  </gl-disclosure-dropdown-item>
  <gl-button
    v-else-if="duoChatAvailable"
    category="tertiary"
    icon="session-ai"
    :size="size"
    class="!gl-text-subtle"
    @click="openSession"
  >
    {{ s__('DuoAgentsPlatform|View session') }}
  </gl-button>
</template>
