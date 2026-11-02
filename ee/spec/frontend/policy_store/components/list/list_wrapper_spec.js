import { GlEmptyState, GlLink, GlTable } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import ConfigInfo from 'ee/policy_store/components/list/config_info.vue';
import ListWrapper from 'ee/policy_store/components/list/list_wrapper.vue';
import StatsBar from 'ee/policy_store/components/list/stats_bar.vue';

const mockPolicies = [
  {
    id: 1,
    name: 'Production Deployment Approval',
    type: 'Deployment',
    mode: 'enforce',
    status: 'active',
    scopedProjectsCount: 3,
    updated_at: '2024-01-01T00:00:00Z',
    detailPath: 'policy_store/1',
  },
  {
    id: 2,
    name: 'Staging Before Production',
    type: 'Deployment',
    mode: 'warn',
    status: 'active',
    scopedProjectsCount: 1,
    updated_at: '2024-01-02T00:00:00Z',
    detailPath: 'policy_store/2',
  },
  {
    id: 3,
    name: 'Disabled policy',
    type: 'Merge Request',
    mode: 'audit',
    status: 'disabled',
    scopedProjectsCount: 5,
    updated_at: '2024-01-03T00:00:00Z',
    detailPath: 'policy_store/3',
  },
];

describe('ListWrapper', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(ListWrapper, {
      propsData: {
        policies: mockPolicies,
        recentEvaluations: 1233,
        canCreatePolicy: true,
        ...propsData,
      },
      provide: { emptyListSvgPath: '/empty.svg' },
      stubs: {
        GlTable: stubComponent(GlTable, { template: '<div><slot name="empty"></slot></div>' }),
        GlEmptyState: stubComponent(GlEmptyState, {
          template: '<div><slot name="actions"></slot></div>',
        }),
      },
    });
  };

  const findTable = () => wrapper.findComponent(GlTable);
  const findStatsBar = () => wrapper.findComponent(StatsBar);
  const findHeading = () => wrapper.findByTestId('policies-heading');
  const findCreateButton = () => wrapper.findComponentByTestId('create-policy');
  const findLoadMoreButton = () => wrapper.findComponentByTestId('load-more-policies');

  it('marks the table busy while the policies load', () => {
    createComponent({ loading: true });

    expect(findTable().attributes('busy')).toBe('true');
  });

  it('renders the "Policies" heading', () => {
    createComponent();

    expect(findHeading().text()).toBe('Policies');
  });

  it('links the create button to the new policy path', () => {
    createComponent({ newPolicyPath: 'policy_store/new' });

    expect(findCreateButton().attributes('href')).toBe('policy_store/new');
  });

  it('offers no way to create a policy without the permission to create one', () => {
    createComponent({ canCreatePolicy: false, policies: [] });

    expect(findCreateButton().exists()).toBe(false);
    expect(wrapper.findByTestId('empty-state-create-button').exists()).toBe(false);
  });

  it('hides the create button when there is no new policy path', () => {
    createComponent();

    expect(findCreateButton().exists()).toBe(false);
  });

  it('hides the evaluations stat when the container reports none', () => {
    createComponent({ showRecentEvaluations: false });

    expect(findStatsBar().props('showRecentEvaluations')).toBe(false);
  });

  it('links each policy name to its detail path', () => {
    wrapper = mountExtended(ListWrapper, {
      propsData: { policies: mockPolicies, recentEvaluations: 1233, canCreatePolicy: true },
      provide: { emptyListSvgPath: '/empty.svg' },
    });

    const table = wrapper.findComponent(GlTable);
    const links = table.findAllComponents(GlLink).wrappers;

    expect(links.map((link) => link.attributes('href'))).toEqual(
      mockPolicies.map((policy) => policy.detailPath),
    );
  });

  it('renders policy names as plain text when they have no detail path', () => {
    wrapper = mountExtended(ListWrapper, {
      propsData: { policies: mockPolicies.map((policy) => ({ ...policy, detailPath: '' })) },
      provide: { emptyListSvgPath: '/empty.svg' },
    });

    expect(wrapper.findComponent(GlTable).findAllComponents(GlLink)).toHaveLength(0);
    expect(wrapper.text()).toContain(mockPolicies[0].name);
  });

  describe('the source column', () => {
    const group = { id: 'gid://gitlab/Group/11', name: 'Flight', fullPath: 'flightjs' };

    const mountWith = (policy) => {
      wrapper = mountExtended(ListWrapper, {
        propsData: {
          policies: [{ ...mockPolicies[0], ...policy }],
          recentEvaluations: 1233,
        },
        provide: { emptyListSvgPath: '/empty.svg' },
      });

      return wrapper.findComponent(GlTable).find('tbody tr').findAll('td').at(2);
    };

    it.each`
      description                      | policy                               | text
      ${'a policy from an ancestor'}   | ${{ inherited: true, group }}        | ${'Inherited from Flight'}
      ${'a policy from the org'}       | ${{ inherited: true, group: null }}  | ${'Inherited from the organization'}
      ${'a policy this group owns'}    | ${{ inherited: false, group }}       | ${'Flight'}
      ${'an organization-wide policy'} | ${{ inherited: false, group: null }} | ${'Organization'}
    `('names $description as $text', ({ policy, text }) => {
      expect(mountWith(policy).text().replace(/\s+/g, ' ')).toBe(text);
    });

    it("links a named group to that group's policy store", () => {
      const cell = mountWith({ inherited: true, group });

      expect(cell.findComponent(GlLink).attributes('href')).toBe(
        '/groups/flightjs/-/security/policy_store',
      );
    });
  });

  it('passes the active policy count and the recent evaluations to the stats bar', () => {
    createComponent({ recentEvaluationsLoading: true });

    expect(findStatsBar().props()).toMatchObject({
      activePolicies: 2,
      recentEvaluations: 1233,
      recentEvaluationsLoading: true,
    });
  });

  it('excludes non-active policies from the active count', () => {
    createComponent({
      policies: mockPolicies.map((policy) => ({ ...policy, status: 'disabled' })),
    });

    expect(findStatsBar().props('activePolicies')).toBe(0);
  });

  it('renders the policies as table rows without transforming them', () => {
    createComponent();

    expect(findTable().props('items')).toBe(mockPolicies);
  });

  it('makes every data column sortable', () => {
    createComponent();

    const dataFields = findTable()
      .props('fields')
      .filter(({ key }) => key !== 'configInfo');

    expect(dataFields.every((field) => field.sortable)).toBe(true);
  });

  describe('config info', () => {
    it('renders a details toggle for each row', () => {
      wrapper = mountExtended(ListWrapper, {
        propsData: { policies: mockPolicies, recentEvaluations: 1233, canCreatePolicy: true },
        provide: { emptyListSvgPath: '/empty.svg' },
      });

      expect(wrapper.findAllByTestId('config-info-toggle')).toHaveLength(mockPolicies.length);
    });

    it('shows the config info for a row only once its toggle is clicked', async () => {
      wrapper = mountExtended(ListWrapper, {
        propsData: { policies: mockPolicies, recentEvaluations: 1233, canCreatePolicy: true },
        provide: { emptyListSvgPath: '/empty.svg' },
      });

      expect(wrapper.findAllComponents(ConfigInfo)).toHaveLength(0);

      await wrapper.findAllByTestId('config-info-toggle').at(0).trigger('click');

      const details = wrapper.findAllComponents(ConfigInfo);
      expect(details).toHaveLength(1);
      expect(details.at(0).props('policy')).toMatchObject({ id: mockPolicies[0].id });
    });
  });

  describe('load more', () => {
    it('is hidden when no further page exists', () => {
      createComponent();

      expect(findLoadMoreButton().exists()).toBe(false);
    });

    // A real button, so that a disabled one swallows the click like it does for users.
    const mountComponent = (propsData) => {
      wrapper = mountExtended(ListWrapper, {
        propsData: {
          policies: mockPolicies,
          recentEvaluations: 1233,
          canCreatePolicy: true,
          ...propsData,
        },
        provide: { emptyListSvgPath: '/empty.svg' },
      });
    };

    it('emits load-more when clicked', () => {
      mountComponent({ hasNextPage: true });

      expect(findLoadMoreButton().text()).toBe('Load more');

      findLoadMoreButton().trigger('click');

      expect(wrapper.emitted('load-more')).toHaveLength(1);
    });

    it('is disabled with a spinner while the next page is in flight', () => {
      mountComponent({ hasNextPage: true, loadingMore: true });

      expect(findLoadMoreButton().props('loading')).toBe(true);
      expect(findLoadMoreButton().attributes('aria-disabled')).toBe('true');

      findLoadMoreButton().trigger('click');

      expect(wrapper.emitted('load-more')).toBeUndefined();
    });

    it('is hidden alongside the table when the fetch failed', () => {
      createComponent({ hasNextPage: true, error: true });

      expect(findLoadMoreButton().exists()).toBe(false);
    });

    // A retry refetch and a load-more would otherwise race for the same cache entry.
    it('is hidden while the first page is loading', () => {
      createComponent({ hasNextPage: true, loading: true });

      expect(findLoadMoreButton().exists()).toBe(false);
    });
  });

  describe('empty state', () => {
    const findEmptyState = () => wrapper.findComponent(GlEmptyState);

    it('renders the placeholder when there are no policies', () => {
      createComponent({ policies: [] });

      expect(findEmptyState().props()).toMatchObject({
        title: 'No policies found',
        svgPath: '/empty.svg',
      });
    });

    it('links the placeholder button to the new policy path', () => {
      createComponent({ policies: [], newPolicyPath: 'policy_store/new' });

      expect(wrapper.findByTestId('empty-state-create-button').attributes('href')).toBe(
        'policy_store/new',
      );
    });

    it('invites the reader to create a policy when they can', () => {
      createComponent({ policies: [], newPolicyPath: 'policy_store/new' });

      expect(findEmptyState().props('description')).toBe(
        'Create a policy to enforce rules for deployments across your organization.',
      );
    });

    it('invites nothing when the container allows authoring but the reader cannot', () => {
      createComponent({ policies: [], canCreatePolicy: false, newPolicyPath: 'policy_store/new' });

      expect(wrapper.findByTestId('empty-state-create-button').exists()).toBe(false);
      expect(findEmptyState().props('description')).toBe('');
    });

    it('hides the placeholder button and invites nothing when the container is read-only', () => {
      createComponent({ policies: [], canCreatePolicy: false });

      expect(wrapper.findByTestId('empty-state-create-button').exists()).toBe(false);
      expect(findEmptyState().props('description')).toBe(
        'Policies that apply here are created in the parent group or organization.',
      );
    });

    it('hides the table entirely when the fetch failed', () => {
      createComponent({ policies: [], error: true });

      expect(findTable().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });
  });
});
