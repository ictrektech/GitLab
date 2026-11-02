import { GlTab, GlTabs } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CombinedDiagnostics from '~/admin/database_diagnostics/components/combined_diagnostics.vue';
import VacuumInformationApp from '~/admin/database_diagnostics/components/vacuum_information_app.vue';
import AutovacuumConfigApp from '~/admin/database_diagnostics/components/autovacuum_config_app.vue';
import CollationCheckerApp from '~/admin/database_diagnostics/components/collation_checker_app.vue';
import DatabaseInformationApp from '~/admin/database_diagnostics/components/database_information_app.vue';
import SchemaCheckerApp from '~/admin/database_diagnostics/components/schema_checker_app.vue';
import LooseForeignKeysBacklogCheckerApp from '~/admin/database_diagnostics/components/loose_foreign_keys_backlog_checker_app.vue';
import ActiveSessionHistoryApp from '~/admin/database_diagnostics/components/active_session_history_app.vue';

describe('CombinedDiagnostics component', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(CombinedDiagnostics, { stubs: { GlTab } });
  };

  const findTabs = () => wrapper.findAllComponents(GlTab);

  beforeEach(() => {
    createComponent();
  });

  it('splits the page into Checks and Active session history tabs, kept in the URL', () => {
    expect(wrapper.findComponent(GlTabs).props('syncActiveTabWithQueryParams')).toBe(true);
    expect(findTabs().wrappers.map((tab) => tab.attributes('title'))).toEqual([
      'Checks',
      'Active session history',
    ]);
    expect(findTabs().wrappers.map((tab) => tab.props('queryParamValue'))).toEqual([
      'checks',
      'active-session-history',
    ]);
  });

  it('puts every check in the Checks tab, in order', () => {
    const checksTab = findTabs().at(0);
    const allElements = checksTab.findAll('*').wrappers.map((element) => element.element);
    const positions = [
      DatabaseInformationApp,
      VacuumInformationApp,
      AutovacuumConfigApp,
      CollationCheckerApp,
      SchemaCheckerApp,
      LooseForeignKeysBacklogCheckerApp,
    ].map((component) => allElements.indexOf(checksTab.findComponent(component).element));

    expect(positions.every((position) => position >= 0)).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(checksTab.findComponent(ActiveSessionHistoryApp).exists()).toBe(false);
  });

  it('marks the Active session history tab lazy, so it renders only while open', () => {
    const ashTab = findTabs().at(1);

    expect(ashTab.attributes('lazy')).toBe('true');
    expect(ashTab.findComponent(ActiveSessionHistoryApp).exists()).toBe(true);
  });
});
