import { GlSkeletonLoader } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import MemberStats from 'ee/organizations/access/components/member_stats.vue';

describe('OrganizationAccessMemberStats', () => {
  let wrapper;

  const adminFilter = { type: 'role', value: { data: 'ARTIFACT_ADMIN', operator: '=' } };
  const stats = [
    { title: 'Admins', value: 2, filter: adminFilter, filterLabel: 'Filter list for Admins' },
    { title: 'Total members', value: 1200 },
  ];

  const createComponent = (props = {}) => {
    wrapper = mountExtended(MemberStats, { propsData: { stats, ...props } });
  };

  const findStats = () => wrapper.findAllByTestId('member-stat');
  const findStat = (index) => findStats().at(index);

  beforeEach(() => {
    createComponent();
  });

  it('renders a card per stat with its title and value', () => {
    expect(findStats()).toHaveLength(2);
    expect(findStat(0).find('[data-testid="member-stat-title"]').text()).toBe('Admins');
    expect(findStat(0).find('[data-testid="member-stat-value"]').text()).toBe('2');
    expect(findStat(1).find('[data-testid="member-stat-title"]').text()).toBe('Total members');
    expect(findStat(1).find('[data-testid="member-stat-value"]').text()).toBe('1,200');
  });

  it('renders "Filter list" only for stats with a filter', () => {
    const button = findStat(0).find('[data-testid="member-stat-filter"]');

    expect(button.text()).toBe('Filter list');
    expect(button.attributes('aria-label')).toBe('Filter list for Admins');
    expect(findStat(1).find('[data-testid="member-stat-filter"]').exists()).toBe(false);
  });

  it('emits the stat filter when "Filter list" is clicked', async () => {
    await findStat(0).find('[data-testid="member-stat-filter"]').trigger('click');

    expect(wrapper.emitted('filter')).toEqual([[adminFilter]]);
  });

  it('renders the title as a level 5 heading', () => {
    expect(findStat(0).find('[data-testid="member-stat-title"]').classes()).toContain(
      'gl-heading-5',
    );
  });

  it('renders a skeleton loader instead of each value while loading', () => {
    createComponent({ loading: true });

    expect(wrapper.findAllComponents(GlSkeletonLoader)).toHaveLength(2);
    expect(wrapper.findByTestId('member-stat-value').exists()).toBe(false);
  });
});
