import { GlTable, GlAvatarLabeled } from '@gitlab/ui';
import { nextTick } from 'vue';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ComparisonTable from 'ee/explore/analytics_dashboards/metrics/dora_projects_comparison/components/comparison_table.vue';
import MetricTableCell from 'ee/explore/analytics_dashboards/metrics/dora_projects_comparison/components/metric_table_cell.vue';
import { mockProjectsDoraMetrics } from '../mock_data';

describe('Comparison table', () => {
  let wrapper;

  const createWrapper = (propsData = {}) => {
    wrapper = mountExtended(ComparisonTable, {
      provide: { namespaceFullPath: 'goo' },
      propsData,
    });
  };

  const findTable = () => wrapper.findComponent(GlTable);

  describe('without data', () => {
    beforeEach(() => {
      createWrapper({ projects: [] });
    });

    it('does not render the table', () => {
      expect(findTable().exists()).toBe(false);
    });

    it('shows a no data message', () => {
      expect(wrapper.text()).toBe('No data available for Group: goo');
    });
  });

  describe('with data', () => {
    beforeEach(() => {
      createWrapper({ projects: mockProjectsDoraMetrics });
    });

    it('renders a row for each project', () => {
      expect(findTable().props('items')).toHaveLength(mockProjectsDoraMetrics.length);
    });

    it('passes the new sort column and direction back to the table', async () => {
      findTable().vm.$emit('sort-changed', { sortBy: 'name', sortDesc: false });
      await nextTick();

      expect(findTable().props()).toMatchObject({ sortBy: 'name', sortDesc: false });
    });

    describe.each(mockProjectsDoraMetrics)(
      'for each table row',
      ({ id, name, webUrl, avatarUrl }) => {
        const findTableRow = () => wrapper.findByTestId(`project-${getIdFromGraphQLId(id)}`);
        const findAvatar = () => findTableRow().findComponent(GlAvatarLabeled);
        const findAllMetricTableCells = () => findTableRow().findAllComponents(MetricTableCell);

        it('renders the project avatar', () => {
          expect(findAvatar().props().label).toBe(name);
          expect(findAvatar().props().labelLink).toBe(webUrl);
          expect(findAvatar().props('entityId')).toBe(getIdFromGraphQLId(id));
          expect(findAvatar().props('entityName')).toBe(name);
          expect(findAvatar().props('src')).toBe(avatarUrl);
        });

        it('renders each metric value', () => {
          const metricProps = findAllMetricTableCells().wrappers.map((metric) => metric.props());
          expect(metricProps).toMatchSnapshot();
        });
      },
    );
  });
});
