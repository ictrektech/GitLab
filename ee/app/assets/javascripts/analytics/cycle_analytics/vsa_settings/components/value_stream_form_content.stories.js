import { mockLabelsResponse } from 'ee_jest/analytics/cycle_analytics/vsa_settings/mock_data';
import createMockApollo from 'helpers/mock_apollo_helper';
import { generateInitialStageData } from '../utils';
import getCustomStageLabels from '../graphql/get_custom_stage_labels.query.graphql';
import createValueStream from '../graphql/create_value_stream.mutation.graphql';
import updateValueStream from '../graphql/update_value_stream.mutation.graphql';
import {
  defaultStages,
  stageEvents,
  valueStream,
  valueStreamGid,
  valueStreamStages,
} from './stories_constants';
import ValueStreamFormContent from './value_stream_form_content.vue';

export default {
  component: ValueStreamFormContent,
  title: 'ee/analytics/cycle_analytics/vsa_settings/components/value_stream_form_content',
};

const generateInitialData = (stages) => ({
  ...valueStream,
  stages: generateInitialStageData(defaultStages, stages),
});

const mockApolloProvider = () =>
  createMockApollo([
    [getCustomStageLabels, () => Promise.resolve(mockLabelsResponse)],
    [createValueStream, () => Promise.reject(new Error('Some network error'))],
    [updateValueStream, () => Promise.reject(new Error('Some network error'))],
  ]);

const Template = (args, { argTypes }) => ({
  components: { ValueStreamFormContent },
  apolloProvider: mockApolloProvider(),
  provide: {
    vsaPath: '',
    groupPath: 'group',
    fullPath: 'fullPath',
    valueStreamGid: args.valueStreamGid ?? valueStreamGid,
    stageEvents,
    defaultStages,
  },
  props: Object.keys(argTypes),
  template: '<value-stream-form-content v-bind="$props" />',
});

// Returns after the timeout even when the condition is still false.
// Do not throw: the accessibility check that runs next fails then.
const waitUntil = async (condition, timeout = 5000) => {
  const deadline = Date.now() + timeout;
  while (!condition() && Date.now() < deadline) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => {
      setTimeout(resolve, 50);
    });
  }
};

const hasEmptyToggle = (canvasElement) =>
  [...canvasElement.querySelectorAll('[data-testid="listbox-toggle-btn"]')].some(
    (toggle) => !toggle.innerText.trim(),
  );

// The custom stage label dropdowns have no text until the mocked labels query resolves.
// Wait for it, so the accessibility check sees the loaded form.
const waitForStageLabels = ({ canvasElement }) => waitUntil(() => !hasEmptyToggle(canvasElement));

export const NewValueStream = Template.bind({});
NewValueStream.args = { valueStreamGid: '' };

export const EditValueStream = Template.bind({});
EditValueStream.args = {
  initialData: generateInitialData(valueStreamStages()),
};

export const EditValueStreamWithCustomStages = Template.bind({});
EditValueStreamWithCustomStages.args = {
  initialData: generateInitialData(valueStreamStages({ addCustomStage: true })),
};
EditValueStreamWithCustomStages.play = waitForStageLabels;

export const EditValueStreamWithHiddenStages = Template.bind({});
EditValueStreamWithHiddenStages.args = {
  initialData: generateInitialData(valueStreamStages({ addCustomStage: true, hideStages: true })),
};
EditValueStreamWithHiddenStages.play = waitForStageLabels;
