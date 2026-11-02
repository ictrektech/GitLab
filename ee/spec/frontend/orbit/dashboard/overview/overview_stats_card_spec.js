import { GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import OverviewStatsCard from 'ee/orbit/dashboard/overview/overview_stats_card.vue';

const AREA_TOTALS = {
  core: 2140,
  plan: 4380,
  code_review: 3912,
  ci: 5206,
  source_code: 1894,
  security: 242,
};

const buildStats = ({ indexedProjects = 3, domains = AREA_TOTALS } = {}) => ({
  domains,
  indexedProjects,
});

const RouterLinkStub = { name: 'RouterLink', props: ['to'], template: '<a><slot /></a>' };

describe('OverviewStatsCard', () => {
  let wrapper;

  const createComponent = ({
    groupCount = 4,
    graphStats = buildStats(),
    status = 'ready',
  } = {}) => {
    wrapper = shallowMountExtended(OverviewStatsCard, {
      propsData: { groupCount, graphStats, status },
      stubs: { GlSprintf, RouterLink: RouterLinkStub },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findScope = () => wrapper.findByTestId('overview-stats-scope');
  const findTotal = () => wrapper.findByTestId('overview-stats-total');
  const findTotalCount = () => wrapper.findByTestId('overview-stats-total-count');
  const areaRowTexts = () =>
    wrapper.findAll('ul li').wrappers.map((row) => row.text().replace(/\s+/g, ' ').trim());

  describe('when the counts loaded', () => {
    beforeEach(() => createComponent());

    it('shows the title and the compact total, with the exact total in a tooltip', () => {
      expect(wrapper.text()).toContain('On your map');
      expect(findTotal().text().replace(/\s+/g, ' ')).toBe('17.8K items');
      expect(findTotalCount().attributes('title')).toBe('17,774');
      expect(getBinding(findTotalCount().element, 'gl-tooltip')).toBeDefined();
    });

    it('shows the areas with their counts in order', () => {
      expect(areaRowTexts()).toEqual([
        'Core 2,140',
        'Planning 4,380',
        'Code review 3,912',
        'CI/CD 5,206',
        'Source code 1,894',
        'Security 242',
      ]);
    });

    it('links to the schema', () => {
      expect(wrapper.text()).toContain('View the schema of each area');
      expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({ name: 'schema' });
    });

    it('summarizes the groups and projects', () => {
      expect(findScope().text()).toBe('in 4 groups and 3 projects');
    });
  });

  describe('with large counts', () => {
    beforeEach(() =>
      createComponent({
        groupCount: 10,
        graphStats: buildStats({ domains: { core: 1269871870 }, indexedProjects: 29754 }),
      }),
    );

    it('shows the total in compact form and formats the project count', () => {
      expect(findTotal().text().replace(/\s+/g, ' ')).toBe('1.3B items');
      expect(findTotalCount().attributes('title')).toBe('1,269,871,870');
      expect(findScope().text()).toBe('in 10 groups and 29,754 projects');
    });
  });

  describe('with one item', () => {
    beforeEach(() => createComponent({ graphStats: buildStats({ domains: { core: 1 } }) }));

    it('uses the singular', () => {
      expect(wrapper.text()).toMatch(/1\s+item\b/);
      expect(wrapper.text()).not.toContain('items');
    });
  });

  describe('when one group and one project', () => {
    beforeEach(() =>
      createComponent({ groupCount: 1, graphStats: buildStats({ indexedProjects: 1 }) }),
    );

    it('uses singular forms', () => {
      expect(findScope().text()).toBe('in 1 group and 1 project');
    });
  });

  describe('when the counts are loading', () => {
    beforeEach(() => createComponent({ graphStats: null, status: 'loading' }));

    it('shows a loading icon and no counts', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(wrapper.text()).not.toContain('items');
    });
  });

  describe('when the counts did not load', () => {
    beforeEach(() => createComponent({ graphStats: null, status: 'failed' }));

    it('says the counts are not available, with no zero and the schema link', () => {
      expect(wrapper.findByTestId('overview-stats-failed').text()).toBe(
        'Counts are not available right now. Try again later.',
      );
      expect(wrapper.text()).not.toMatch(/0\s+items/);
      expect(wrapper.text()).toContain('View the schema of each area');
    });
  });
});
