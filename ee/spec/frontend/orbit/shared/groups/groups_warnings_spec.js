import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupsWarnings from 'ee/orbit/shared/groups/groups_warnings.vue';

describe('GroupsWarnings', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GroupsWarnings, { propsData: props });
  };

  const findIndexStatusError = () => wrapper.findByTestId('orbit-index-status-error');
  const findExcludedError = () => wrapper.findByTestId('orbit-excluded-error');

  describe('with no errors', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders no warning', () => {
      expect(findIndexStatusError().exists()).toBe(false);
      expect(findExcludedError().exists()).toBe(false);
    });
  });

  describe('with an index status error', () => {
    beforeEach(() => {
      createComponent({ indexStatusError: 'Knowledge graph request failed' });
    });

    it('shows the server message and the hint to turn Orbit on or off', () => {
      expect(findIndexStatusError().text()).toContain('Knowledge graph request failed');
      expect(findIndexStatusError().text()).toContain('You can still turn GitLab Orbit on or off.');
      expect(findExcludedError().exists()).toBe(false);
    });
  });

  describe('with an index status error for a user who cannot change the groups', () => {
    beforeEach(() => {
      createComponent({
        indexStatusError: 'Knowledge graph request failed',
        canChangeGroups: false,
      });
    });

    it('shows the server message with no hint to turn Orbit on or off', () => {
      expect(findIndexStatusError().text()).toContain('Knowledge graph request failed');
      expect(findIndexStatusError().text()).not.toContain(
        'You can still turn GitLab Orbit on or off.',
      );
    });
  });

  describe('with an excluded groups error', () => {
    beforeEach(() => {
      createComponent({ excludedGroupsError: 'GitLab could not complete the request. Try again.' });
    });

    it('shows the excluded groups warning only, with why bulk actions wait', () => {
      expect(findExcludedError().text()).toContain(
        'GitLab could not complete the request. Try again.',
      );
      expect(findExcludedError().text()).toContain(
        'Bulk actions are available after the excluded groups load.',
      );
      expect(findIndexStatusError().exists()).toBe(false);
    });
  });
});
