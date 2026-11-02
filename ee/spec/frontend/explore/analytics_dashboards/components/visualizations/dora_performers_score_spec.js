import { GlLoadingIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DoraPerformersScore from 'ee/explore/analytics_dashboards/components/visualizations/dora_performers_score.vue';
import DoraChart from 'ee/explore/analytics_dashboards/metrics/dora_performers_score/components/dora_performers_score_chart.vue';
import GroupOrProjectProvider from 'ee/explore/analytics_dashboards/metrics/components/group_or_project_provider.vue';
import GetGroupOrProjectQuery from 'ee_else_ce/explore/analytics_dashboards/metrics/graphql/get_group_or_project.query.graphql';
import {
  mockGroupWithAbilities,
  mockProjectWithAbilities,
} from 'ee_jest/explore/analytics_dashboards/metrics/mock_data';

Vue.use(VueApollo);

describe('DoraPerformersScore Visualization', () => {
  let wrapper;
  let mockGroupOrProjectRequestHandler;

  const namespace = 'some/fake/path';

  const createWrapper = ({ group = null, project = null, stubs } = {}) => {
    mockGroupOrProjectRequestHandler = jest.fn().mockReturnValueOnce({ data: { group, project } });

    wrapper = shallowMountExtended(DoraPerformersScore, {
      apolloProvider: createMockApollo([
        [GetGroupOrProjectQuery, mockGroupOrProjectRequestHandler],
      ]),
      propsData: {
        data: { namespace },
        options: {},
      },
      stubs: {
        GroupOrProjectProvider,
        ...stubs,
      },
    });
  };

  const findChart = () => wrapper.findComponent(DoraChart);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);

  describe('isLoadingNamespace = true', () => {
    it('displays a loading state', () => {
      createWrapper({
        group: mockGroupWithAbilities,
      });

      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('for groups', () => {
    beforeEach(() => {
      createWrapper({ group: mockGroupWithAbilities });
    });

    it('does not display a loading state', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('resolves the namespace', () => {
      expect(mockGroupOrProjectRequestHandler).toHaveBeenCalled();
    });

    it('renders the panel', () => {
      expect(findChart().props().data).toMatchObject({
        namespace,
      });
    });

    it('emits `set-alerts` event when chart emits `error`', () => {
      const payload = { errors: ['error message'] };
      findChart().vm.$emit('error', payload.errors[0]);

      expect(wrapper.emitted('set-alerts')).toHaveLength(1);
      expect(wrapper.emitted('set-alerts')[0][0]).toEqual(payload);
    });
  });

  describe('for projects', () => {
    beforeEach(() => {
      createWrapper({ project: mockProjectWithAbilities });
    });

    it('does not render the panel', () => {
      expect(findChart().exists()).toBe(false);
    });

    it('emits `set-alerts` event', () => {
      const emitted = wrapper.emitted('set-alerts');
      expect(emitted).toHaveLength(1);
      expect(emitted[0]).toEqual([
        {
          errors: ['This visualization is not supported for project namespaces.'],
          canRetry: false,
        },
      ]);
    });
  });
});
