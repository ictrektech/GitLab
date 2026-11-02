import { http, HttpResponse } from 'msw';
import { captureMissingOperation, captureRequest } from './core/operation_helpers';
import { handleWorkItemOperation, workItemRestEndpoints } from './work_items/handlers';
import { handleAiCatalogOperation, aiCatalogRestEndpoints } from './ai_catalog/handlers';
import { handleCdEnvironmentOperation, cdEnvironmentRestEndpoints } from './cd/handlers';
import { handleCommitListOperation, commitListRestEndpoints } from './commits/handlers';
import {
  handleSecurityPolicyOperation,
  securityPolicyRestEndpoints,
} from './security_policies/handlers';
import { handlePipelineEditorOperation, pipelineEditorRestEndpoints } from './ci/handlers';
import { handleCiCatalogOperation, ciCatalogRestEndpoints } from './ci/catalog/handlers';
import { handleRepositoryOperation, repositoryRestEndpoints } from './repository/handlers';
import {
  handlePipelineSecurityOperation,
  pipelineSecurityRestEndpoints,
} from './ci/pipelines/handlers';
import {
  handleVulnerabilityManagementOperation,
  vulnerabilityManagementRestEndpoints,
} from './vulnerability_management/handlers';
import {
  handleAnalyticsDashboardOperation,
  analyticsDashboardRestEndpoints,
} from './analytics_dashboards/handlers';
import { handleAdminJobsOperation, adminJobsRestEndpoints } from './ci/admin_jobs/handlers';
import { handleJobDetailsOperation, jobDetailsRestEndpoints } from './ci/job_details/handlers';
import { handleUsageQuotasOperation, usageQuotasRestEndpoints } from './usage_quotas/handlers';
import { handleHomePanelOperation, homePanelRestEndpoints } from './home_panel/handlers';
import {
  handlePipelineSubscriptionsOperation,
  pipelineSubscriptionsRestEndpoints,
} from './ci/pipeline_subscriptions/handlers';
import {
  handlePipelineTriggersOperation,
  pipelineTriggersRestEndpoints,
} from './ci/pipeline_triggers/handlers';
import {
  handlePackageRegistryOperation,
  packageRegistryRestEndpoints,
} from './package_registry/handlers';
import {
  handleContainerRegistryOperation,
  containerRegistryRestEndpoints,
} from './container_registry/handlers';
import { richTextEditorRestEndpoints } from './rich_text_editor/rest_endpoints';

export { buildHandlers } from '@gitlab/frontend-tests/integration';

// Keyed on the GraphQL operation name alone, so the first handler to claim an operation wins
// and a domain missing its own fixture silently gets an earlier domain's payload.
export const featureHandlers = [
  handleWorkItemOperation,
  handleAiCatalogOperation,
  handleCdEnvironmentOperation,
  handleCommitListOperation,
  handleSecurityPolicyOperation,
  handlePipelineEditorOperation,
  handleCiCatalogOperation,
  handleRepositoryOperation,
  handlePipelineSecurityOperation,
  handleVulnerabilityManagementOperation,
  handleAnalyticsDashboardOperation,
  handleAdminJobsOperation,
  handleJobDetailsOperation,
  handleUsageQuotasOperation,
  handleHomePanelOperation,
  handlePipelineSubscriptionsOperation,
  handlePipelineTriggersOperation,
  handlePackageRegistryOperation,
  handleContainerRegistryOperation,
];
export const restEndpoints = [
  ...workItemRestEndpoints,
  ...aiCatalogRestEndpoints,
  ...cdEnvironmentRestEndpoints,
  ...commitListRestEndpoints,
  ...securityPolicyRestEndpoints,
  ...pipelineEditorRestEndpoints,
  ...ciCatalogRestEndpoints,
  ...repositoryRestEndpoints,
  ...pipelineSecurityRestEndpoints,
  ...vulnerabilityManagementRestEndpoints,
  ...analyticsDashboardRestEndpoints,
  ...adminJobsRestEndpoints,
  ...jobDetailsRestEndpoints,
  ...usageQuotasRestEndpoints,
  ...homePanelRestEndpoints,
  ...pipelineSubscriptionsRestEndpoints,
  ...pipelineTriggersRestEndpoints,
  ...packageRegistryRestEndpoints,
  ...containerRegistryRestEndpoints,
  ...richTextEditorRestEndpoints,
];

// BatchHttpLink posts an array of operations, which the `buildHandlers` GraphQL handler
// doesn't match, so each one is resolved through the same feature handlers here.
export const buildBatchedOperationsHandler = (allFeatureHandlers) =>
  http.post('*/api/graphql', async ({ request }) => {
    const operations = await request
      .clone()
      .json()
      .catch(() => null);

    if (!Array.isArray(operations)) return undefined;

    const responses = operations.map(({ operationName, variables }) => {
      const result = allFeatureHandlers.reduce(
        (found, handler) => found ?? handler({ operationName, variables }),
        null,
      );

      if (result) captureRequest(operationName, request, variables);
      else captureMissingOperation(operationName);

      return result;
    });

    if (responses.includes(null)) return new HttpResponse(null, { status: 400 });

    return HttpResponse.json(await Promise.all(responses.map((response) => response.json())));
  });
