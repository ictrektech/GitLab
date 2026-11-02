import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ScanTriggersDetail from 'ee/security_configuration/components/scan_profiles/scan_triggers_detail.vue';
import TriggerInfoPopover from 'ee/security_configuration/components/scan_profiles/trigger_info_popover.vue';
import TriggerVariableTable from 'ee/security_configuration/components/scan_profiles/trigger_variable_table.vue';
import { SCAN_TRIGGER_DEFINITIONS } from '~/security_configuration/constants';

const ALL_TRIGGERS = Object.entries(SCAN_TRIGGER_DEFINITIONS).map(([triggerType, definition]) => ({
  triggerType,
  ...definition,
}));

describe('ScanTriggersDetail', () => {
  let wrapper;

  const findAllCruds = () => wrapper.findAllComponents(CrudComponent);
  const findCrudAt = (index) => findAllCruds().at(index);
  const findInfoPopoverAt = (index) => wrapper.findAllComponents(TriggerInfoPopover).at(index);
  const findVariableTables = () => wrapper.findAllComponents(TriggerVariableTable);

  const mountWithRows = (variableRows) => {
    wrapper = shallowMountExtended(ScanTriggersDetail, {
      stubs: { CrudComponent },
      propsData: {
        triggers: [{ ...SCAN_TRIGGER_DEFINITIONS.MERGE_REQUEST_PIPELINE, variableRows }],
        variableDefinitions: {},
      },
    });
  };

  describe('Secret detection', () => {
    beforeEach(() => {
      wrapper = shallowMountExtended(ScanTriggersDetail, {
        stubs: { CrudComponent },
        propsData: { triggers: ALL_TRIGGERS, variableDefinitions: {} },
      });
    });

    it('renders all 3 triggers', () => {
      expect(findAllCruds()).toHaveLength(3);
    });

    it('does not render an "On" badge', () => {
      expect(wrapper.text()).not.toContain('On');
    });

    it('uses the plain toggle, without a divider and with right and down chevrons', () => {
      expect(findAllCruds().wrappers.every((crud) => crud.props('plainToggle'))).toBe(true);
    });

    describe('Secret push protection trigger', () => {
      it('renders CrudComponent with correct props and no description line', () => {
        expect(findCrudAt(0).props()).toMatchObject({
          isCollapsible: true,
          collapsed: true,
          description: null,
          anchorId: 'secret-push-protection',
        });
      });

      it('does not pass icon prop to CrudComponent', () => {
        expect(findCrudAt(0).props('icon')).toBeNull();
      });

      it('renders the info popover with its own docs link', () => {
        expect(findInfoPopoverAt(0).props()).toMatchObject({
          anchor: 'secret-push-protection',
          title: 'Secret push protection',
          description: 'GitLab checks each push for secrets and blocks the push if it finds any.',
          helpLink:
            '/help/user/application_security/secret_detection/secret_push_protection/_index.md',
        });
      });

      it('renders the push protection message instead of a variables table', () => {
        expect(findCrudAt(0).text()).toContain('Advanced configuration for this trigger');
        expect(findCrudAt(0).text()).toContain(
          "Push protection can't carry analyzer configuration.",
        );
      });
    });

    describe.each`
      index | anchor                       | targetBranch | results
      ${1}  | ${'merge-request-pipeline'}  | ${'All'}     | ${'New vulnerabilities only'}
      ${2}  | ${'default-branch-pipeline'} | ${'Default'} | ${'All vulnerabilities'}
    `('pipeline trigger $anchor', ({ index, anchor, targetBranch, results }) => {
      it('renders CrudComponent with no description line', () => {
        expect(findCrudAt(index).props()).toMatchObject({ description: null, anchorId: anchor });
      });

      it('renders target branch and results, but no scope', () => {
        const text = findCrudAt(index).text();

        expect(text).toContain('Target branch');
        expect(text).toContain(targetBranch);
        expect(text).toContain('Results');
        expect(text).toContain(results);
        expect(text).not.toContain('Scope');
      });

      it('renders neither a variables heading nor the push protection message without variables', () => {
        expect(findCrudAt(index).text()).not.toContain('Advanced configuration for this trigger');
      });

      it('renders the info popover with the profile link as the docs link fallback', () => {
        wrapper = shallowMountExtended(ScanTriggersDetail, {
          stubs: { CrudComponent },
          propsData: {
            triggers: ALL_TRIGGERS,
            variableDefinitions: {},
            profileHelpLink: '/profile-help',
          },
        });

        expect(findInfoPopoverAt(index).props()).toMatchObject({
          anchor,
          description: expect.stringContaining('GitLab scans'),
          helpLink: '/profile-help',
        });
      });
    });
  });

  describe('analyzer settings', () => {
    it('renders a table of the variables a trigger sets', () => {
      mountWithRows([
        { setting: 'historicScan', value: true },
        { setting: 'excludedPaths', value: ['spec/'] },
      ]);

      expect(findVariableTables()).toHaveLength(1);
      expect(findVariableTables().at(0).props('rows')).toEqual([
        { setting: 'historicScan', value: true },
        { setting: 'excludedPaths', value: ['spec/'] },
      ]);
    });

    it('renders the variables heading when the trigger sets variables', () => {
      mountWithRows([{ setting: 'historicScan', value: true }]);

      expect(wrapper.text()).toContain('Advanced configuration for this trigger');
    });

    it('renders no table for a trigger with no variables', () => {
      mountWithRows([]);

      expect(findVariableTables()).toHaveLength(0);
    });

    it('forwards variableDefinitions to the variable table, so it can show display labels instead of raw values', () => {
      const variableDefinitions = { historicScan: { valueType: 'boolean' } };
      wrapper = shallowMountExtended(ScanTriggersDetail, {
        stubs: { CrudComponent },
        propsData: {
          triggers: [
            {
              ...SCAN_TRIGGER_DEFINITIONS.MERGE_REQUEST_PIPELINE,
              variableRows: [{ setting: 'historicScan', value: true }],
            },
          ],
          variableDefinitions,
        },
      });

      expect(findVariableTables().at(0).props('variableDefinitions')).toBe(variableDefinitions);
    });
  });
});
