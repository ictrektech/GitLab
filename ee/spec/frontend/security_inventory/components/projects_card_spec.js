import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlPopover, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ProjectsCard from 'ee/security_inventory/components/projects_card.vue';
import SegmentedBar from 'ee/security_inventory/components/segmented_bar.vue';
import EnableScannersLink from 'ee/security_inventory/components/enable_scanners_link.vue';
import GroupSecurityPostureCountersQuery from 'ee/security_configuration/graphql/scan_profiles/group_security_posture_counters.query.graphql';
import { groupSecurityPostureCountersResponse } from '../mock_data';

Vue.use(VueApollo);

describe('ProjectsCard', () => {
  let wrapper;

  const fullPath = 'gitlab-org';

  const findCard = () => wrapper.findByTestId('projects-card');
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findRow = (status) => wrapper.findByTestId(`project-status-row-${status}`);
  const findTotalText = () => wrapper.findByTestId('total-projects');
  const rowCount = (status) => findRow(status).find('[data-testid="row-count"]').text();
  const rowPercent = (status) => findRow(status).find('[data-testid="row-percent"]').text();
  const rowBarSegments = (status) => findRow(status).findComponent(SegmentedBar).props('segments');
  const findEnableScannersLink = (status) => findRow(status).findComponent(EnableScannersLink);
  const findRowButton = (status) => wrapper.findByTestId(`project-status-button-${status}`);

  const createComponent = ({ handler, selectedStatus } = {}) => {
    const queryHandler =
      handler ?? jest.fn().mockResolvedValue(groupSecurityPostureCountersResponse);

    wrapper = shallowMountExtended(ProjectsCard, {
      apolloProvider: createMockApollo([[GroupSecurityPostureCountersQuery, queryHandler]]),
      propsData: { fullPath, ...(selectedStatus ? { selectedStatus } : {}) },
    });

    return queryHandler;
  };

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a skeleton loader instead of the rows', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
      expect(findRow('NEEDS_ATTENTION').exists()).toBe(false);
    });
  });

  describe('when the card mounts', () => {
    it('fetches the counters for the given group', () => {
      const handler = createComponent();

      expect(handler).toHaveBeenCalledWith({ fullPath });
    });
  });

  describe('help popover', () => {
    beforeEach(() => {
      createComponent();
    });

    it('explains what the widget shows', () => {
      expect(findPopover().props('title')).toBe('Projects');
      expect(findPopover().text()).toContain(
        'Counts of projects that need attention, have stale scans, or are unprotected, out of all projects in this group.',
      );
    });
  });

  describe('when the query succeeds', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the card and hides the skeleton loader', () => {
      expect(findCard().exists()).toBe(true);
      expect(findSkeletonLoader().exists()).toBe(false);
    });

    it.each`
      status               | count    | percent  | filled | track   | color
      ${'NEEDS_ATTENTION'} | ${'316'} | ${'21%'} | ${316} | ${1204} | ${'var(--red-500)'}
      ${'STALE_SCANS'}     | ${'215'} | ${'14%'} | ${215} | ${1305} | ${'var(--gl-color-neutral-600)'}
      ${'UNPROTECTED'}     | ${'134'} | ${'9%'}  | ${134} | ${1386} | ${'var(--gl-color-neutral-200)'}
    `('renders the $status row', ({ status, count, percent, filled, track, color }) => {
      expect(rowCount(status)).toBe(count);
      expect(rowPercent(status)).toBe(percent);
      expect(rowBarSegments(status)).toEqual([
        { key: 'filled', count: filled, color },
        { key: 'track', count: track, color: expect.any(String) },
      ]);
    });

    it('shows the total project count', () => {
      expect(findTotalText().text()).toBe('of 1,520 projects');
    });

    describe('enable scanners link', () => {
      it('passes the group web path for the unprotected row', () => {
        expect(findEnableScannersLink('UNPROTECTED').props('webPath')).toBe('/groups/gitlab-org');
      });

      it.each(['NEEDS_ATTENTION', 'STALE_SCANS'])(
        'does not render the link for the %s row',
        (status) => {
          expect(findEnableScannersLink(status).exists()).toBe(false);
        },
      );

      it('keeps the row in a hover group', () => {
        expect(findRow('UNPROTECTED').classes()).toContain('gl-group');
      });
    });
  });

  describe('click-to-filter', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('shows rows as unpressed without a selection', () => {
      expect(wrapper.findAll('[aria-pressed="true"]')).toHaveLength(0);
    });

    it('emits the clicked status on click', async () => {
      await findRowButton('STALE_SCANS').trigger('click');

      expect(wrapper.emitted('update:selected-status')).toEqual([['STALE_SCANS']]);
    });

    describe('when a status is selected', () => {
      beforeEach(async () => {
        createComponent({ selectedStatus: 'STALE_SCANS' });
        await waitForPromises();
      });

      it('marks the matching row as pressed and highlighted', () => {
        expect(findRowButton('STALE_SCANS').attributes('aria-pressed')).toBe('true');
        expect(findRow('STALE_SCANS').classes()).toContain('gl-bg-feedback-info');
      });

      it('leaves other rows unpressed', () => {
        expect(findRowButton('NEEDS_ATTENTION').attributes('aria-pressed')).toBe('false');
        expect(findRowButton('UNPROTECTED').attributes('aria-pressed')).toBe('false');
      });

      it('emits null when the selected row is clicked again', async () => {
        await findRowButton('STALE_SCANS').trigger('click');

        expect(wrapper.emitted('update:selected-status')).toEqual([[null]]);
      });

      it('emits the new status when a different row is clicked', async () => {
        await findRowButton('UNPROTECTED').trigger('click');

        expect(wrapper.emitted('update:selected-status')).toEqual([['UNPROTECTED']]);
      });
    });
  });

  describe('when the group has no projects', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue({
          data: {
            group: {
              __typename: 'Group',
              id: 'gid://gitlab/Group/1',
              webPath: '/groups/gitlab-org',
              securityPostureCounters: {
                __typename: 'SecurityPostureCounters',
                total: 0,
                withScanners: 0,
                withFailures: 0,
                withStale: 0,
              },
            },
          },
        }),
      });
      await waitForPromises();
    });

    it('renders zeroed percentages rather than hiding the card', () => {
      expect(findCard().exists()).toBe(true);
      expect(rowPercent('NEEDS_ATTENTION')).toBe('0%');
      expect(rowCount('NEEDS_ATTENTION')).toBe('0');
    });

    it('uses the plural form for zero projects', () => {
      expect(findTotalText().text()).toBe('of 0 projects');
    });
  });

  describe('when the group has exactly one project', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue({
          data: {
            group: {
              __typename: 'Group',
              id: 'gid://gitlab/Group/1',
              webPath: '/groups/gitlab-org',
              securityPostureCounters: {
                __typename: 'SecurityPostureCounters',
                total: 1,
                withScanners: 0,
                withFailures: 0,
                withStale: 0,
              },
            },
          },
        }),
      });
      await waitForPromises();
    });

    it('uses the singular form', () => {
      expect(findTotalText().text()).toBe('of 1 project');
    });
  });

  describe('when the query fails', () => {
    const error = new Error('network error');

    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException').mockImplementation();
      createComponent({ handler: jest.fn().mockRejectedValue(error) });
      await waitForPromises();
    });

    it('hides the card', () => {
      expect(findCard().exists()).toBe(false);
    });

    it('calls Sentry with the error', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });
  });
});
