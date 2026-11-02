import { GlDisclosureDropdownItem } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective } from 'helpers/vue_mock_directive';
import CsvImportExportButtons from '~/merge_requests/list/components/csv_import_export_buttons.vue';
import MoreActionsDropdown from '~/merge_requests/list/components/more_actions_dropdown.vue';

describe('MoreActionsDropdown', () => {
  let wrapper;

  const exportVariables = { fullPath: 'gitlab-org/gitlab-test', state: 'opened' };

  const createComponent = ({ isProject = true, isSignedIn = true } = {}) => {
    wrapper = shallowMountExtended(MoreActionsDropdown, {
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      provide: { isProject, isSignedIn, rssUrl: '/rss' },
      propsData: { count: 3, exportVariables },
    });
  };

  const findCsvButtons = () => wrapper.findComponent(CsvImportExportButtons);
  const findRssItem = () => wrapper.findComponent(GlDisclosureDropdownItem);

  it('passes the export variables to the CSV buttons in a project', () => {
    createComponent();

    expect(findCsvButtons().props()).toMatchObject({ issuableCount: 3, exportVariables });
  });

  it.each`
    description                      | options
    ${'in a group'}                  | ${{ isProject: false }}
    ${'when the user is signed out'} | ${{ isSignedIn: false }}
  `('does not show the CSV buttons $description', ({ options }) => {
    createComponent(options);

    expect(findCsvButtons().exists()).toBe(false);
    expect(findRssItem().props('item')).toEqual({ text: 'Subscribe to RSS feed', href: '/rss' });
  });
});
