import { createAlert } from '~/alert';
import { HTTP_STATUS_FORBIDDEN, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import { groupLabelsPath, groupMilestonesPath } from '~/lib/utils/path_helpers/group';
import { projectLabelsPath, projectMilestonesPath } from '~/lib/utils/path_helpers/project';
import { __ } from '~/locale';
import * as types from './mutation_types';

export * from './actions/filters';
export * from './actions/stages';
export * from './actions/value_streams';

export const setPaths = ({
  dispatch,
  state: { namespace, groupPath },
  getters: { isProjectNamespace },
}) => {
  const projectPaths = isProjectNamespace
    ? {
        projectEndpoint: namespace.restApiRequestPath,
      }
    : {};
  const labelsPath = isProjectNamespace ? projectLabelsPath : groupLabelsPath;
  const milestonesPath = isProjectNamespace ? projectMilestonesPath : groupMilestonesPath;

  return dispatch('filters/setEndpoints', {
    labelsEndpoint: labelsPath(namespace.path, { format: 'json' }),
    milestonesEndpoint: milestonesPath(namespace.path, { format: 'json' }),
    groupEndpoint: groupPath,
    ...projectPaths,
  });
};

export const requestCycleAnalyticsData = ({ commit }) => commit(types.REQUEST_VALUE_STREAM_DATA);

export const receiveCycleAnalyticsDataSuccess = ({ commit }) => {
  commit(types.RECEIVE_VALUE_STREAM_DATA_SUCCESS);
};

export const receiveCycleAnalyticsDataError = ({ commit }, { response = {} }) => {
  const { status = HTTP_STATUS_INTERNAL_SERVER_ERROR } = response;

  commit(types.RECEIVE_VALUE_STREAM_DATA_ERROR, status);
  if (status !== HTTP_STATUS_FORBIDDEN) {
    createAlert({
      message: __('There was an error while fetching value stream analytics data.'),
    });
  }
};

export const fetchCycleAnalyticsData = ({ dispatch }) => {
  return Promise.resolve()
    .then(() => dispatch('requestCycleAnalyticsData'))
    .then(() => dispatch('fetchValueStreams'))
    .then(() => dispatch('receiveCycleAnalyticsDataSuccess'))
    .catch((error) => dispatch('receiveCycleAnalyticsDataError', error));
};

export const initializeCycleAnalyticsSuccess = ({ commit }) =>
  commit(types.INITIALIZE_VALUE_STREAM_SUCCESS);

export const initializeCycleAnalytics = ({ dispatch, commit }, initialData = {}) => {
  commit(types.INITIALIZE_VSA, initialData);

  const {
    selectedAuthor,
    selectedMilestone,
    selectedAssigneeList,
    selectedLabelList,
    stage: selectedStage,
    namespace,
  } = initialData;

  if (namespace?.restApiRequestPath) {
    let promises = [
      dispatch('setPaths', { namespacePath: namespace.restApiRequestPath }),
      dispatch('filters/initialize', {
        selectedAuthor,
        selectedMilestone,
        selectedAssigneeList,
        selectedLabelList,
      }),
    ];

    if (selectedStage) {
      promises = [dispatch('setSelectedStage', selectedStage), ...promises];
    } else {
      promises = [dispatch('setDefaultSelectedStage'), ...promises];
    }

    return Promise.all(promises)
      .then(() =>
        Promise.all([
          selectedStage?.id ? dispatch('fetchStageData', selectedStage.id) : Promise.resolve(),
          dispatch('fetchCycleAnalyticsData'),
        ]),
      )
      .then(() => dispatch('initializeCycleAnalyticsSuccess'));
  }

  return dispatch('initializeCycleAnalyticsSuccess');
};
