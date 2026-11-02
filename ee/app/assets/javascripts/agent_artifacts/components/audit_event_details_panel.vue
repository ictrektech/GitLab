<script>
import { s__, sprintf } from '~/locale';
import { formatEventName } from '../utils';
import SummarySection from './summary_section.vue';
import DetailsSection from './details_section.vue';

// The backend does not expose entity/target as stored columns, so the target
// facts are reconstructed client-side from the session. GitLab Duo events
// target the workflow; external agent events target the governance session.
const WORKFLOW_TARGET_TYPE = 'Ai::DuoWorkflows::Workflow';
const SESSION_TARGET_TYPE = 'Ai::Governance::Session';
const GITLAB_DUO_SOURCE = 'GITLAB_DUO';

export default {
  name: 'AuditEventDetailsPanel',
  components: {
    SummarySection,
    DetailsSection,
  },
  props: {
    event: {
      type: Object,
      required: true,
    },
    flowName: {
      type: String,
      required: false,
      default: '',
    },
    sessionId: {
      type: String,
      required: false,
      default: '',
    },
    // Unset when the sessions API flag is off, where every session is GitLab Duo.
    source: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    targetType() {
      return !this.source || this.source === GITLAB_DUO_SOURCE
        ? WORKFLOW_TARGET_TYPE
        : SESSION_TARGET_TYPE;
    },
    targetDetails() {
      if (!this.flowName || !this.sessionId) {
        return '';
      }

      return sprintf(this.$options.i18n.targetDetailsFormat, {
        flowName: this.flowName,
        sessionId: this.sessionId,
      });
    },
    detailsData() {
      return this.event.details || {};
    },
  },
  methods: {
    formatEventName,
  },
  i18n: {
    targetDetailsFormat: s__('AgentArtifacts|%{flowName} session %{sessionId}'),
  },
};
</script>

<template>
  <div data-testid="audit-event-details-panel">
    <div class="gl-mt-6 gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h4 class="gl-m-0" data-testid="audit-event-title">
        {{ formatEventName(event.eventName) }}
      </h4>
      <slot name="download-action"></slot>
    </div>

    <summary-section
      :event="event"
      :target-type="targetType"
      :target-details="targetDetails"
      class="gl-mt-6"
    />

    <details-section :details="detailsData" class="gl-mt-6" />
  </div>
</template>
