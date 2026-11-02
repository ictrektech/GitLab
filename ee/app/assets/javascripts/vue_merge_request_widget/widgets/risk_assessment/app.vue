<script>
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { buildApiUrl } from '~/api/api_utils';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__ } from '~/locale';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import RiskAssessmentWidget from './index.vue';
import riskAssessmentQuery from './graphql/risk_assessment.query.graphql';
import { RISK_CLASSIFICATION_FLOW_REFERENCE } from './constants';

export default normalizeRender({
  name: 'WidgetRiskAssessmentApp',
  components: {
    RiskAssessmentWidget,
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  apollo: {
    riskAssessment: {
      query: riskAssessmentQuery,
      variables() {
        return {
          projectPath:
            this.mergeRequest.targetProjectFullPath || this.mergeRequest.sourceProjectFullPath,
          iid: String(this.mergeRequest.iid),
        };
      },
      update(data) {
        this.project = data?.project ?? null;

        return data?.project?.mergeRequest?.riskAssessment ?? null;
      },
      error() {
        this.hasError = true;
      },
    },
    flowConsumerId: {
      query: getConfiguredFlows,
      variables() {
        return {
          projectId: this.project.id,
          foundationalFlowReference: RISK_CLASSIFICATION_FLOW_REFERENCE,
        };
      },
      skip() {
        return !this.project?.id;
      },
      update(data) {
        return data?.aiCatalogConfiguredItems?.nodes?.[0]?.id ?? null;
      },
    },
  },
  data() {
    return {
      riskAssessment: null,
      project: null,
      flowConsumerId: null,
      hasError: false,
      isSubmitting: false,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.riskAssessment.loading;
    },
    shouldRender() {
      return Boolean(this.hasError || this.riskAssessment);
    },
    canRefresh() {
      return Boolean(
        this.flowConsumerId && this.project?.duoWorkflowStatusCheck?.createDuoWorkflowForCiAllowed,
      );
    },
  },
  methods: {
    async refresh() {
      const { id: projectGid, mergeRequest } = this.project;
      this.isSubmitting = true;

      try {
        await axios.post(buildApiUrl('/api/:version/ai/duo_workflows/workflows'), {
          project_id: getIdFromGraphQLId(projectGid),
          ai_catalog_item_consumer_id: getIdFromGraphQLId(this.flowConsumerId),
          start_workflow: true,
          source_branch: mergeRequest.sourceBranch,
          merge_request_id: this.mergeRequest.iid,
        });
      } catch (error) {
        createAlert({
          message: s__('RiskAssessment|Could not start a new risk assessment.'),
          error,
          captureError: true,
        });
        this.isSubmitting = false;
        return;
      }

      try {
        await this.$apollo.queries.riskAssessment.refetch();
      } catch {
        // The query's error handler already puts the widget in its error state.
      } finally {
        this.isSubmitting = false;
      }
    },
  },
  // The default scoped slot lets another surface, like the merge request overview, draw the
  // assessment its own way while sharing this data and refresh flow with the widget.
  render(h) {
    if (!this.shouldRender) return null;

    const slotProps = {
      riskAssessment: this.riskAssessment,
      isLoading: this.isLoading,
      hasError: this.hasError,
      canRefresh: this.canRefresh,
      isSubmitting: this.isSubmitting,
      refresh: this.refresh,
    };

    const slot = getSlotFunction(this);
    if (slot) return slot(slotProps);

    const { refresh, ...props } = slotProps;
    return h(RiskAssessmentWidget, { props, on: { refresh } });
  },
});
</script>
