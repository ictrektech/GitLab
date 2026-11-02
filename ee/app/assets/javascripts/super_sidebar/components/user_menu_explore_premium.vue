<script>
import { GlDisclosureDropdownGroup, GlDisclosureDropdownItem, GlIcon } from '@gitlab/ui';
import { InternalEvents } from '~/tracking';
import { s__ } from '~/locale';
import {
  REQUEST_STATE,
  PAINTED_DOOR_FEATURES,
  getInitialRequestState,
  recordRequest,
} from 'ee/painted_door_request/utils';
import ExplorePremiumModal from './explore_premium_modal.vue';

export default {
  name: 'UserMenuExplorePremium',
  components: {
    GlDisclosureDropdownGroup,
    GlDisclosureDropdownItem,
    GlIcon,
    ExplorePremiumModal,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    groupId: {
      type: Number,
      required: true,
    },
    requested: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['action'],
  i18n: {
    label: s__('ExplorePremium|Explore Premium'),
  },
  data() {
    return {
      // Owned here, not by the modal, so reopening the modal keeps the Requested state.
      requestState: getInitialRequestState({
        feature: PAINTED_DOOR_FEATURES.EXPLORE_PREMIUM,
        groupId: this.groupId,
        requested: this.requested,
      }),
      showModal: false,
      requestMadeThisOpen: false,
    };
  },
  computed: {
    groupIdProperty() {
      return String(this.groupId);
    },
    item() {
      return { text: this.$options.i18n.label };
    },
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- called by the parent user menu via $refs on its dropdown @shown event
    handleMenuShown() {
      this.trackEvent('view_explore_premium_user_menu_item', {
        label: this.requestState,
        property: this.groupIdProperty,
      });
    },
    openModal() {
      this.trackEvent('click_explore_premium_user_menu_item', {
        label: this.requestState,
        property: this.groupIdProperty,
      });
      this.requestMadeThisOpen = false;
      this.showModal = true;
      this.$emit('action');
    },
    handleModalChange(visible) {
      this.showModal = visible;
    },
    handleModalHide() {
      if (!this.requestMadeThisOpen) {
        this.trackEvent('dismiss_explore_premium_modal', {
          label: this.requestState,
          property: this.groupIdProperty,
        });
      }
    },
    handleRequest() {
      if (this.requestState !== REQUEST_STATE.NOT_REQUESTED) return;

      this.requestState = REQUEST_STATE.REQUESTED;
      this.requestMadeThisOpen = true;
      this.trackEvent('click_request_premium_features_explore_premium_modal', {
        property: this.groupIdProperty,
      });
      recordRequest({ feature: PAINTED_DOOR_FEATURES.EXPLORE_PREMIUM, groupId: this.groupId });
    },
    handleLearnMoreClick() {
      this.trackEvent('click_learn_more_explore_premium_modal', {
        label: this.requestState,
        property: this.groupIdProperty,
      });
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown-group>
    <gl-disclosure-dropdown-item
      :item="item"
      data-testid="explore-premium-item"
      @action="openModal"
    >
      <template #list-item>
        <gl-icon name="license" variant="subtle" class="gl-mr-2" />
        <span>{{ $options.i18n.label }}</span>
      </template>
    </gl-disclosure-dropdown-item>

    <explore-premium-modal
      :visible="showModal"
      :state="requestState"
      @change="handleModalChange"
      @hide="handleModalHide"
      @request="handleRequest"
      @learn-more-click="handleLearnMoreClick"
    />
  </gl-disclosure-dropdown-group>
</template>
