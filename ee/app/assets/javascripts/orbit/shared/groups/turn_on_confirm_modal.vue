<script>
import { defineComponent } from 'vue';
import { GlModal } from '@gitlab/ui';
import { __, n__, s__, sprintf } from '~/locale';
import { daysText, freeCreditsText, trialDateText } from 'ee/orbit/utils/trial_offer_text';

export default defineComponent({
  name: 'OrbitTurnOnConfirmModal',
  components: { GlModal },
  props: {
    visible: { type: Boolean, required: true },
    groups: { type: Array, required: true },
    loading: { type: Boolean, required: true },
    instanceTrialEndsOn: { type: String, required: false, default: null },
  },
  emits: ['confirm', 'hide'],
  computed: {
    isSingle() {
      return this.groups.length === 1;
    },
    title() {
      if (this.isSingle) {
        return sprintf(s__('Orbit|Turn on GitLab Orbit for %{name}?'), {
          name: this.groups[0].name,
        });
      }

      return n__(
        'Orbit|Turn on GitLab Orbit for %d group?',
        'Orbit|Turn on GitLab Orbit for %d groups?',
        this.groups.length,
      );
    },
    startsTrial() {
      return this.groups.some((group) => group.startsTrial);
    },
    showsTrialText() {
      return this.startsTrial || Boolean(this.instanceTrialEndsOn);
    },
    instanceTrialText() {
      const message = this.isSingle
        ? s__(
            'Orbit|The group uses the trial of this instance until %{date}. All groups on this instance share its credits.',
          )
        : s__(
            'Orbit|These groups use the trial of this instance until %{date}. All groups on this instance share its credits.',
          );

      return sprintf(message, { date: trialDateText(this.instanceTrialEndsOn) });
    },
    singleTrialText() {
      const { offer } = this.groups[0];
      if (!offer) return s__('Orbit|The group starts a GitLab Orbit trial.');

      return sprintf(s__('Orbit|The group gets %{credits} for GitLab Orbit, valid for %{days}.'), {
        credits: freeCreditsText(offer.initialCredits),
        days: daysText(offer.durationDays),
      });
    },
    listedGroups() {
      return this.groups.map((group) => ({
        fullPath: group.fullPath,
        name: group.name,
        trialLabel: this.trialLabel(group),
      }));
    },
    actionPrimary() {
      return {
        text: s__('Orbit|Turn on GitLab Orbit'),
        attributes: { variant: 'confirm', loading: this.loading },
      };
    },
    actionCancel() {
      return { text: __('Cancel'), attributes: { disabled: this.loading } };
    },
  },
  methods: {
    trialLabel({ startsTrial, offer }) {
      if (!startsTrial) return '';
      if (!offer) return s__('Orbit|Trial');

      return sprintf(s__('Orbit|%{days}-day trial, %{credits}'), {
        days: offer.durationDays,
        credits: freeCreditsText(offer.initialCredits),
      });
    },
  },
});
</script>

<template>
  <gl-modal
    modal-id="orbit-turn-on-confirm-modal"
    :visible="visible"
    :title="title"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    @primary.prevent="$emit('confirm')"
    @hidden="$emit('hide')"
  >
    <div class="gl-flex gl-flex-col gl-gap-3">
      <p v-if="isSingle" class="gl-mb-0">
        {{
          s__(
            'Orbit|GitLab Orbit indexes the group, its subgroups, and projects. Indexing can take up to a few hours.',
          )
        }}
      </p>
      <template v-else>
        <p class="gl-mb-0">
          {{
            s__(
              'Orbit|GitLab Orbit indexes each group, its subgroups, and projects. Groups become ready one at a time. Indexing can take up to a few hours.',
            )
          }}
        </p>
        <ul class="gl-mb-0 gl-pl-5" data-testid="turn-on-group-list">
          <li v-for="group in listedGroups" :key="group.fullPath">
            <span class="gl-font-bold">{{ group.name }}</span>
            <span v-if="group.trialLabel" class="gl-text-subtle">· {{ group.trialLabel }}</span>
          </li>
        </ul>
      </template>
      <p v-if="showsTrialText" class="gl-mb-0" data-testid="turn-on-trial-text">
        <template v-if="instanceTrialEndsOn">{{ instanceTrialText }}</template>
        <template v-else-if="isSingle">{{ singleTrialText }}</template>
        {{
          s__(
            'Orbit|When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
          )
        }}
      </p>
    </div>
  </gl-modal>
</template>
