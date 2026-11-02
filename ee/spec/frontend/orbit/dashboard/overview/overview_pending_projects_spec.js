import { GlButton, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import OverviewPendingProjects from 'ee/orbit/dashboard/overview/overview_pending_projects.vue';
import { buildGroupWithPendingProjects, buildOrbitGroup } from '../../mock_data';

describe('OverviewPendingProjects', () => {
  let wrapper;

  const createComponent = ({ groups }) => {
    wrapper = shallowMountExtended(OverviewPendingProjects, {
      propsData: { groups },
      stubs: { GlPopover },
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findGroupRows = () => wrapper.findAllByTestId('overview-pending-projects-group');

  describe('when groups have projects that wait for indexing', () => {
    beforeEach(() =>
      createComponent({
        groups: [
          buildGroupWithPendingProjects({ id: 1, name: 'gitlab-ai-hackathon', pending: 2 }),
          buildOrbitGroup({ id: 2, name: 'gitlab-org' }),
          buildGroupWithPendingProjects({ id: 3, name: 'gitlab-com', pending: 1 }),
        ],
      }),
    );

    it('shows the total on the button', () => {
      expect(findButton().text()).toBe('Indexing 3 projects');
    });

    it('opens the popover from the button', () => {
      expect(findPopover().props()).toMatchObject({
        target: findButton().attributes('id'),
        triggers: 'click blur',
        title: 'Indexing projects',
      });
    });

    it('lists only the groups with pending projects', () => {
      expect(findGroupRows().wrappers.map((row) => row.text().replace(/\s+/g, ' '))).toEqual([
        'gitlab-ai-hackathon 2 projects',
        'gitlab-com 1 project',
      ]);
    });
  });
});
