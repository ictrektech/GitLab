import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import {
  DISPLAY_SETTINGS_PAGE_GROUP_BY,
  VIEW_MODE_LIST,
  VIEW_MODE_BOARD,
} from '~/work_items/constants';
import WorkItemDisplaySettingsDrawer from '~/work_items/list/components/work_item_display_settings_drawer.vue';
import WorkItemDisplaySettingsEmptyGroups from '~/work_items/list/components/work_item_display_settings_empty_groups.vue';

// Pin this to the EE view modes regardless of which alias environment the suite runs under
// — the CE/EE difference itself is covered by view_modes_spec.js.
jest.mock('ee_else_ce/work_items/view_modes', () => jest.requireActual('ee/work_items/view_modes'));

const DEFAULT_PROPS = {
  open: false,
  fullPath: 'gitlab-org/gitlab',
  workItemTypeId: 'gid://gitlab/WorkItems::Type/8',
  viewMode: VIEW_MODE_LIST,
};

describe('WorkItemDisplaySettingsDrawer (EE)', () => {
  let wrapper;

  const findGroupByRow = () => wrapper.findByTestId('group-by-row');
  const findEmptyGroups = () => wrapper.findComponent(WorkItemDisplaySettingsEmptyGroups);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(WorkItemDisplaySettingsDrawer, {
      propsData: {
        ...DEFAULT_PROPS,
        isBoardEnabled: true,
        ...props,
      },
    });
  };

  describe('group by section', () => {
    it('does not render the group by row when the board is not enabled', () => {
      createComponent({ props: { viewMode: VIEW_MODE_BOARD, isBoardEnabled: false } });

      expect(findGroupByRow().exists()).toBe(false);
    });

    it('renders the group by row with the current strategy label in board view mode', () => {
      createComponent({ props: { viewMode: VIEW_MODE_BOARD } });

      expect(findGroupByRow().text()).toContain('Status');
    });

    it('emits page-change with groupBy when the row is clicked', async () => {
      createComponent({ props: { viewMode: VIEW_MODE_BOARD } });

      await findGroupByRow().trigger('click');

      expect(wrapper.emitted('page-change')).toEqual([[DISPLAY_SETTINGS_PAGE_GROUP_BY]]);
    });
  });

  describe('empty groups section', () => {
    it('does not render the row when the board is not enabled', () => {
      createComponent({ props: { viewMode: VIEW_MODE_BOARD, isBoardEnabled: false } });

      expect(findEmptyGroups().exists()).toBe(false);
    });

    it('renders the row with respective props in board view mode', () => {
      const namespacePreferences = { showEmptyGroups: false };
      createComponent({
        props: {
          viewMode: VIEW_MODE_BOARD,
          namespacePreferences,
          isSavedView: true,
          sortKey: 'CREATED_DESC',
        },
      });

      expect(findEmptyGroups().props()).toMatchObject({
        namespacePreferences,
        fullPath: 'gitlab-org/gitlab',
        isSavedView: true,
        workItemTypeId: 'gid://gitlab/WorkItems::Type/8',
        sortKey: 'CREATED_DESC',
      });
    });

    it('re-emits update-settings when the row emits updates', () => {
      createComponent({ props: { viewMode: VIEW_MODE_BOARD } });

      const payload = { showEmptyGroups: false };
      findEmptyGroups().vm.$emit('update-settings', payload);

      expect(wrapper.emitted('update-settings')).toEqual([[payload]]);
    });
  });
});
