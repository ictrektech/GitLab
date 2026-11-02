import Vue from 'vue';
import VueApollo from 'vue-apollo';
import setWindowLocation from 'helpers/set_window_location_helper';
import { fullMount, getText, screen } from 'ee_jest/integration/helpers/test_helpers';
import { getPipelineTabMetadata } from 'ee/usage_quotas/pipelines/namespace/tab_metadata';

Vue.use(VueApollo);

const USAGE_QUOTAS_PATH = '/-/profile/usage_quotas#pipelines-quota-tab';

const PIPELINE_DATASET = {
  namespaceActualPlanName: 'Free',
  namespaceId: '1',
  userNamespace: 'true',
  pageSize: '20',
  ciMinutesAnyProjectEnabled: 'true',
  ciMinutesLastResetDate: '2015-07-01',
  ciMinutesDisplayMinutesAvailableData: 'true',
  ciMinutesMonthlyMinutesUsed: '300',
  ciMinutesMonthlyMinutesUsedPercentage: '60',
  ciMinutesMonthlyMinutesLimit: '500',
};

export function mountPipelinesTab(datasetOverrides = {}) {
  setWindowLocation(USAGE_QUOTAS_PATH);

  const el = document.createElement('div');
  el.id = 'js-pipeline-usage-app';
  Object.assign(el.dataset, PIPELINE_DATASET, datasetOverrides);
  document.body.appendChild(el);

  const { component } = getPipelineTabMetadata();
  el.remove();

  return fullMount(component, { apolloProvider: component.apolloProvider });
}

export const findUsageSummary = () => screen.queryByTestId('plan-compute-minutes');

export const findProjectTable = () => screen.queryByTestId('pipelines-quota-tab-project-table');

export const findProjectNames = () =>
  screen.queryAllByTestId('pipelines-quota-tab-project-name').map(getText);

export const findPrevButton = () => screen.queryByTestId('prevButton');

export const findNextButton = () => screen.queryByTestId('nextButton');
