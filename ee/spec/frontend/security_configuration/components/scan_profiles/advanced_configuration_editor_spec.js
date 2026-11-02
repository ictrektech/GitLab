import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import AdvancedConfigurationEditor from 'ee/security_configuration/components/scan_profiles/advanced_configuration_editor.vue';
import AddScanProfileVariableModal from 'ee/security_configuration/components/scan_profiles/add_scan_profile_variable_modal.vue';
import AdvancedConfigurationTable from 'ee/security_configuration/components/scan_profiles/advanced_configuration_table.vue';
import {
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

describe('AdvancedConfigurationEditor', () => {
  let wrapper;

  const configurableTriggers = ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'];

  const createComponent = ({ rows = [], props = {} } = {}) => {
    wrapper = mountExtended(AdvancedConfigurationEditor, {
      propsData: {
        scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
        rows,
        hasConfigurableTriggers: true,
        configurableTriggers,
        ...props,
      },
      stubs: {
        AddScanProfileVariableModal: stubComponent(AddScanProfileVariableModal, {
          props: [
            'visible',
            'title',
            'variableDefinitions',
            'existingSettings',
            'configurableTriggers',
          ],
        }),
      },
    });
  };

  const findAddButton = () => wrapper.findByTestId('scan-profile-add-variable-button');
  const findAddButtonWrapper = () => wrapper.findByTestId('scan-profile-add-variable-wrapper');
  const findModal = () => wrapper.findComponent(AddScanProfileVariableModal);
  const findTable = () => wrapper.findComponent(AdvancedConfigurationTable);

  it('renders the heading and subheading', () => {
    createComponent();

    expect(wrapper.text()).toContain('Advanced configuration');
    expect(wrapper.text()).toContain(
      'Variables passed to the analyzer that override its default behavior.',
    );
  });

  it('opens the add-variable modal from the Add variable button', async () => {
    createComponent();

    expect(findModal().props('visible')).toBe(false);

    await findAddButton().trigger('click');

    expect(findModal().props('visible')).toBe(true);
  });

  it('titles the modal with the sentence-cased scan type name', () => {
    createComponent();

    expect(findModal().props('title')).toBe('Add secret detection variable');
  });

  it('keeps an all-caps acronym scan type name as-is in the modal title', () => {
    createComponent({ props: { scanType: SCAN_PROFILE_TYPE_SAST } });

    expect(findModal().props('title')).toBe('Add SAST variable');
  });

  it('closes the modal and emits set-value for each trigger the modal returns', async () => {
    createComponent();
    await findAddButton().trigger('click');

    findModal().vm.$emit('add', {
      setting: 'historicScan',
      values: { MERGE_REQUEST_PIPELINE: true, DEFAULT_BRANCH_PIPELINE: true },
    });
    await nextTick();

    expect(findModal().props('visible')).toBe(false);
    expect(wrapper.emitted('set-value')).toEqual([
      [{ setting: 'historicScan', triggerType: 'MERGE_REQUEST_PIPELINE', value: true }],
      [{ setting: 'historicScan', triggerType: 'DEFAULT_BRANCH_PIPELINE', value: true }],
    ]);
  });

  it('closes the modal on cancel without emitting anything', async () => {
    createComponent();
    await findAddButton().trigger('click');

    findModal().vm.$emit('cancel');
    await nextTick();

    expect(findModal().props('visible')).toBe(false);
    expect(wrapper.emitted('set-value')).toBeUndefined();
  });

  it('passes existing settings to the modal so they cannot be added twice', () => {
    createComponent({
      rows: [{ setting: 'historicScan', value: true, triggerValues: [] }],
    });

    expect(findModal().props('existingSettings')).toEqual(['historicScan']);
  });

  describe('when no configurable trigger is enabled', () => {
    it('disables the Add variable button with an explanatory tooltip', () => {
      createComponent({ props: { hasConfigurableTriggers: false } });

      expect(findAddButton().attributes('aria-disabled')).toBe('true');
      expect(findAddButtonWrapper().attributes('title')).toBe(
        'Enable a trigger that supports configuration to add a variable.',
      );
    });

    it('does not open the modal when clicked', async () => {
      createComponent({ props: { hasConfigurableTriggers: false } });

      await findAddButton().trigger('click');

      expect(findModal().props('visible')).toBe(false);
    });
  });

  it('has no tooltip and an enabled button when a configurable trigger is enabled', () => {
    createComponent();

    expect(findAddButton().attributes('aria-disabled')).toBeUndefined();
    expect(findAddButtonWrapper().attributes('title')).toBe('');
  });

  describe('advanced configuration table', () => {
    it('does not render the table when there are no configured rows', () => {
      createComponent();

      expect(findTable().exists()).toBe(false);
    });

    it('renders the table with the currently configured rows, editable, and the variable definitions', () => {
      const rows = [{ setting: 'historicScan', value: true, triggerValues: [] }];
      createComponent({ rows });

      expect(findTable().props()).toMatchObject({
        caption: 'Advanced configuration',
        rows,
        editable: true,
        variableDefinitions: findModal().props('variableDefinitions'),
      });
    });

    it('forwards the table update-value event as set-value', () => {
      const rows = [
        {
          setting: 'historicScan',
          value: true,
          triggerValues: [{ triggerType: 'MERGE_REQUEST_PIPELINE', value: true }],
        },
      ];
      createComponent({ rows });

      findTable().vm.$emit('update-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: false,
      });

      expect(wrapper.emitted('set-value')).toEqual([
        [{ setting: 'historicScan', triggerType: 'MERGE_REQUEST_PIPELINE', value: false }],
      ]);
    });
  });
});
