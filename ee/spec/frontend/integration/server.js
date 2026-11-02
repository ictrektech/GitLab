import { setupServer } from 'msw/node';
import {
  buildBatchedOperationsHandler,
  buildHandlers,
  featureHandlers,
  restEndpoints,
} from './handlers';
import { analyticsDashboardGlqlHandlers } from './analytics_dashboards/handlers';

// Setup requests interception in Node
export const server = setupServer(
  ...analyticsDashboardGlqlHandlers,
  ...buildHandlers(featureHandlers, restEndpoints),
  buildBatchedOperationsHandler(featureHandlers),
);
