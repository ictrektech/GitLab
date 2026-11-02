import { HTTP_STATUS_FORBIDDEN } from '~/lib/utils/http_status';
import { s__ } from '~/locale';
import {
  aggregationRowsToTable,
  graphNodesToRows,
  transformGraphResponse,
} from 'ee/orbit/utils/graph_transform';
import { orbitApiMessage } from 'ee/orbit/utils/orbit_errors';
import {
  BILLING_NAMESPACE_REQUIRED_CODE,
  INVALID_QUERY_STATUSES,
  QUERY_ERROR_KIND,
} from './constants';

// Orbit sends node properties in no fixed order, so the columns would change between runs.
function withSortedProperties({ type, id, ...properties }) {
  const sortedProperties = Object.entries(properties).sort(([a], [b]) => a.localeCompare(b));
  return { type, id, ...Object.fromEntries(sortedProperties) };
}

export function queryResultRows(result) {
  const aggregationRows = aggregationRowsToTable(result.rows);
  if (aggregationRows.length) return aggregationRows;

  return graphNodesToRows(transformGraphResponse(result).nodes).map(withSortedProperties);
}

export function queryErrorFor(error) {
  const status = error.response?.status;
  const data = error.response?.data ?? {};

  if (data.code === BILLING_NAMESPACE_REQUIRED_CODE) {
    return {
      kind: QUERY_ERROR_KIND.BILLING_GROUP_REQUIRED,
      message: data.message,
      preferencesUrl: data.deep_link,
    };
  }

  if (status === HTTP_STATUS_FORBIDDEN) {
    return { kind: QUERY_ERROR_KIND.NO_ACCESS, message: orbitApiMessage(data) };
  }

  if (INVALID_QUERY_STATUSES.includes(status)) {
    return {
      kind: QUERY_ERROR_KIND.INVALID_QUERY,
      message:
        orbitApiMessage(data) || s__('Orbit|Invalid query. Check query parameters and try again.'),
    };
  }

  if (status >= 400 && status < 500) {
    return {
      kind: QUERY_ERROR_KIND.REQUEST_REJECTED,
      message: orbitApiMessage(data) || s__('Orbit|Could not run the query. Try again.'),
    };
  }

  return {
    kind: QUERY_ERROR_KIND.SERVER,
    message: s__('Orbit|Could not run the query. Try again.'),
  };
}
