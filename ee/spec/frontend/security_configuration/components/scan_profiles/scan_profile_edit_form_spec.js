import { nextTick } from 'vue';
import { GlForm, GlFormInput, GlFormTextarea, GlToggle } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ScanProfileEditForm from 'ee/security_configuration/components/scan_profiles/scan_profile_edit_form.vue';
import AdvancedConfigurationEditor from 'ee/security_configuration/components/scan_profiles/advanced_configuration_editor.vue';
import TriggerInfoPopover from 'ee/security_configuration/components/scan_profiles/trigger_info_popover.vue';
import TriggerVariableTable from 'ee/security_configuration/components/scan_profiles/trigger_variable_table.vue';
import {
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

describe('ScanProfileEditForm', () => {
  let wrapper;

  const baseProfile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Nightly secret detection',
    description: 'Scans the default branch overnight',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
    triggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
  };

  const createComponent = ({ profile = baseProfile, isSaving = false } = {}) => {
    wrapper = shallowMountExtended(ScanProfileEditForm, {
      propsData: { profile, isSaving },
      stubs: {
        CrudComponent: stubComponent(CrudComponent, {
          template: '<div><slot name="title" /><slot name="actions" /><slot /></div>',
        }),
      },
    });
  };

  const findNameInput = () => wrapper.findComponent(GlFormInput);
  const findDescriptionInput = () => wrapper.findComponent(GlFormTextarea);
  const findTriggerToggles = () => wrapper.findAllComponents(GlToggle);
  const findSaveButton = () => wrapper.findComponentByTestId('scan-profile-edit-save');
  const findCancelButton = () => wrapper.findComponentByTestId('scan-profile-edit-cancel');
  const submitForm = () => wrapper.findComponent(GlForm).vm.$emit('submit', new Event('submit'));
  const findAdvancedConfigurationEditor = () => wrapper.findComponent(AdvancedConfigurationEditor);
  const findVariableTables = () => wrapper.findAllComponents(TriggerVariableTable);
  const findInfoPopovers = () => wrapper.findAllComponents(TriggerInfoPopover);

  it('prefills name and description from the profile', () => {
    createComponent();

    expect(findNameInput().attributes('value')).toBe('Nightly secret detection');
    expect(findDescriptionInput().attributes('value')).toBe('Scans the default branch overnight');
  });

  it('renders a toggle per allowed trigger for the scan type, with initial state from the profile', () => {
    createComponent();

    const toggles = findTriggerToggles();
    expect(toggles).toHaveLength(3); // MR, default, git push
    expect(toggles.at(0).props('value')).toBe(true); // MERGE_REQUEST_PIPELINE (enabled)
    expect(toggles.at(1).props('value')).toBe(true); // DEFAULT_BRANCH_PIPELINE (enabled)
    expect(toggles.at(2).props('value')).toBe(false); // GIT_PUSH_EVENT (not in profile.triggers)
  });

  it('narrows the toggle set for SAST', () => {
    createComponent({ profile: { ...baseProfile, scanType: SCAN_PROFILE_TYPE_SAST } });

    expect(findTriggerToggles()).toHaveLength(2);
  });

  it('flips a trigger off when its toggle emits false', async () => {
    createComponent();

    findTriggerToggles().at(0).vm.$emit('change', false);
    submitForm();
    await nextTick();

    expect(wrapper.emitted('save')[0][0].enabledTriggers).toEqual(['DEFAULT_BRANCH_PIPELINE']);
    expect(wrapper.emitted('save')[0][0].triggersChanged).toBe(true);
  });

  it('flips a trigger on when its toggle emits true', async () => {
    createComponent({ profile: { ...baseProfile, triggers: ['MERGE_REQUEST_PIPELINE'] } });

    findTriggerToggles().at(2).vm.$emit('change', true); // enable GIT_PUSH_EVENT
    submitForm();
    await nextTick();

    expect(wrapper.emitted('save')[0][0].enabledTriggers).toEqual([
      'MERGE_REQUEST_PIPELINE',
      'GIT_PUSH_EVENT',
    ]);
    expect(wrapper.emitted('save')[0][0].triggersChanged).toBe(true);
  });

  it('gives a newly enabled trigger the configuration already shared by the other enabled triggers', async () => {
    createComponent({
      profile: {
        ...baseProfile,
        triggers: ['DEFAULT_BRANCH_PIPELINE'],
        triggerSettings: [
          { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { historicScan: true } },
        ],
      },
    });

    findTriggerToggles().at(0).vm.$emit('change', true); // enable MERGE_REQUEST_PIPELINE
    submitForm();
    await nextTick();

    expect(wrapper.emitted('save')[0][0].triggerConfigurations).toEqual({
      DEFAULT_BRANCH_PIPELINE: { historicScan: true },
      MERGE_REQUEST_PIPELINE: { historicScan: true },
    });
  });

  it('does not propagate configuration to a trigger that cannot be configured', async () => {
    createComponent({
      profile: {
        ...baseProfile,
        triggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
        triggerSettings: [
          { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { historicScan: true } },
          { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { historicScan: true } },
        ],
      },
    });

    findTriggerToggles().at(2).vm.$emit('change', true); // enable GIT_PUSH_EVENT (unconfigurable)
    submitForm();
    await nextTick();

    expect(wrapper.emitted('save')[0][0].triggerConfigurations).toEqual({
      MERGE_REQUEST_PIPELINE: { historicScan: true },
      DEFAULT_BRANCH_PIPELINE: { historicScan: true },
    });
  });

  it('emits cancel when the Cancel button is clicked', () => {
    createComponent();

    findCancelButton().vm.$emit('click');

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  it('disables Cancel while saving', () => {
    createComponent({ isSaving: true });

    expect(findCancelButton().props('disabled')).toBe(true);
    expect(findSaveButton().props('loading')).toBe(true);
  });

  describe('save button enabled state', () => {
    it('is enabled when name and at least one trigger are present', () => {
      createComponent();

      expect(findSaveButton().props('disabled')).toBe(false);
    });

    it('is disabled when the name is empty', () => {
      createComponent({ profile: { ...baseProfile, name: '' } });

      expect(findSaveButton().props('disabled')).toBe(true);
    });

    it('is disabled when no triggers are enabled', () => {
      createComponent({ profile: { ...baseProfile, triggers: [] } });

      expect(findSaveButton().props('disabled')).toBe(true);
    });

    describe('with a dependency scanning apiTimeout', () => {
      const setApiTimeout = async (value) => {
        findAdvancedConfigurationEditor().vm.$emit('set-value', {
          setting: 'apiTimeout',
          triggerType: 'MERGE_REQUEST_PIPELINE',
          value,
        });
        await nextTick();
      };

      beforeEach(() => {
        createComponent({
          profile: { ...baseProfile, scanType: SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING },
        });
      });

      it.each(['500', '1.5'])('disables Save given %s', async (value) => {
        await setApiTimeout(value);

        expect(findSaveButton().props('disabled')).toBe(true);
      });

      it('enables Save given a valid value', async () => {
        await setApiTimeout('500');
        await setApiTimeout('30');

        expect(findSaveButton().props('disabled')).toBe(false);
      });
    });
  });

  describe('save button label', () => {
    it('reads "Save changes" when editing an existing profile', () => {
      createComponent();

      expect(findSaveButton().text()).toBe('Save changes');
    });

    it('reads "Create profile" when creating a new profile', () => {
      createComponent({ profile: { ...baseProfile, id: '' } });

      expect(findSaveButton().text()).toBe('Create profile');
    });
  });

  describe('on valid submit', () => {
    beforeEach(() => {
      createComponent();
      submitForm();
    });

    it('emits save with the trimmed name, description, and current trigger set', () => {
      expect(wrapper.emitted('save')).toEqual([
        [
          {
            profileId: baseProfile.id,
            scanType: baseProfile.scanType,
            name: 'Nightly secret detection',
            description: 'Scans the default branch overnight',
            enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
            triggerConfigurations: {},
            triggersChanged: false,
          },
        ],
      ]);
    });
  });

  describe('triggersChanged flag', () => {
    it('is false when the enabled set matches the initial set regardless of order', () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggers: ['DEFAULT_BRANCH_PIPELINE', 'MERGE_REQUEST_PIPELINE'],
        },
      });

      submitForm();

      expect(wrapper.emitted('save')[0][0].triggersChanged).toBe(false);
    });

    it('is true when only an advanced configuration value changes, with the enabled set unchanged', () => {
      createComponent();

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: true,
      });
      submitForm();

      expect(wrapper.emitted('save')[0][0].triggersChanged).toBe(true);
    });
  });

  describe('trigger cards', () => {
    it('renders an info popover per trigger, with the docs link', () => {
      createComponent();

      expect(findInfoPopovers()).toHaveLength(3);
      expect(findInfoPopovers().at(0).props()).toMatchObject({
        anchor: 'merge-request-pipeline',
        description: expect.stringContaining('GitLab scans'),
        helpLink: expect.any(String),
      });
    });

    it('does not render a description line or a documentation button', () => {
      createComponent();

      expect(wrapper.text()).not.toContain('View documentation');
      expect(wrapper.text()).not.toContain('Scans commits to the default branch');
    });

    it('uses the plain toggle on every card', () => {
      createComponent();

      expect(
        wrapper.findAllComponents(CrudComponent).wrappers.every((c) => c.props('plainToggle')),
      ).toBe(true);
    });
  });

  describe('per-trigger variable table', () => {
    it('renders a table of the variables an enabled trigger sets', () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
          ],
        },
      });

      expect(findVariableTables()).toHaveLength(1);
      expect(findVariableTables().at(0).props()).toMatchObject({
        triggerTitle: 'Merge Request Pipelines',
        rows: [
          { setting: 'historicScan', value: true },
          { setting: 'excludedPaths', value: ['spec/'] },
        ],
        variableDefinitions: expect.objectContaining({
          historicScan: expect.objectContaining({ valueType: 'boolean' }),
        }),
      });
    });

    describe('push protection message', () => {
      const heading = 'Advanced configuration for this trigger';
      const message = "Push protection can't carry analyzer configuration.";

      it('explains that push protection cannot carry analyzer configuration', () => {
        createComponent({ profile: { ...baseProfile, triggerSettings: [] } });

        expect(wrapper.text()).toContain(message);
        expect(wrapper.text()).toContain(heading);
      });

      it('renders the heading with the table, and no message, for a trigger with variables', () => {
        createComponent({
          profile: {
            ...baseProfile,
            triggers: ['MERGE_REQUEST_PIPELINE'],
            scanType: SCAN_PROFILE_TYPE_SAST,
            triggerSettings: [
              {
                triggerType: 'MERGE_REQUEST_PIPELINE',
                configuration: { excludedPaths: ['spec/'] },
              },
            ],
          },
        });

        expect(findVariableTables()).toHaveLength(1);
        expect(wrapper.text()).toContain(heading);
        expect(wrapper.text()).not.toContain(message);
      });
    });

    it('renders no table for an enabled trigger with no variables set', () => {
      createComponent({ profile: { ...baseProfile, triggerSettings: [] } });

      expect(findVariableTables()).toHaveLength(0);
    });

    it('renders no table for a disabled trigger', () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggers: ['MERGE_REQUEST_PIPELINE'],
          triggerSettings: [
            { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { historicScan: true } },
          ],
        },
      });

      expect(findVariableTables()).toHaveLength(0);
    });

    it('updates once a value is set through the advanced configuration editor', async () => {
      createComponent();

      expect(findVariableTables()).toHaveLength(0);

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: true,
      });
      await nextTick();

      expect(findVariableTables()).toHaveLength(1);
      expect(findVariableTables().at(0).props('rows')).toEqual([
        { setting: 'historicScan', value: true },
      ]);
    });
  });

  describe('advanced configuration', () => {
    it('renders the editor when a configurable trigger is enabled', () => {
      createComponent();

      expect(findAdvancedConfigurationEditor().exists()).toBe(true);
      expect(findAdvancedConfigurationEditor().props('hasConfigurableTriggers')).toBe(true);
    });

    it('renders the editor with adding disabled when only the unconfigurable trigger is enabled', () => {
      createComponent({ profile: { ...baseProfile, triggers: ['GIT_PUSH_EVENT'] } });

      expect(findAdvancedConfigurationEditor().exists()).toBe(true);
      expect(findAdvancedConfigurationEditor().props('hasConfigurableTriggers')).toBe(false);
    });

    it('hides the editor when there are no enabled triggers', () => {
      createComponent({ profile: { ...baseProfile, triggers: [] } });

      expect(findAdvancedConfigurationEditor().exists()).toBe(false);
    });

    it('passes only the configurable enabled triggers to the editor', () => {
      createComponent({
        profile: { ...baseProfile, triggers: ['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT'] },
      });

      expect(findAdvancedConfigurationEditor().props('configurableTriggers')).toEqual([
        'MERGE_REQUEST_PIPELINE',
      ]);
    });

    it('includes a value set through the editor in the save payload', () => {
      createComponent();

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: true,
      });
      submitForm();

      expect(wrapper.emitted('save')[0][0].triggerConfigurations).toEqual({
        MERGE_REQUEST_PIPELINE: { historicScan: true },
      });
    });

    it('drops the key entirely when the editor removes a value, rather than sending it as null', () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
          ],
        },
      });

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: null,
      });
      submitForm();

      const { triggerConfigurations } = wrapper.emitted('save')[0][0];
      expect(triggerConfigurations).toEqual({
        MERGE_REQUEST_PIPELINE: { excludedPaths: ['spec/'] },
      });
      expect(triggerConfigurations.MERGE_REQUEST_PIPELINE).not.toHaveProperty('historicScan');
    });

    it('treats a value cleared to an empty string through the input the same as removing it', async () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: { secureAnalyzersPrefix: 'registry.example.com', historicScan: true },
            },
            {
              triggerType: 'DEFAULT_BRANCH_PIPELINE',
              configuration: { secureAnalyzersPrefix: 'registry.example.com', historicScan: true },
            },
          ],
        },
      });

      // Clear it through the input (an empty string) rather than the remove button (null), on
      // every trigger, until it's fully unset.
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'secureAnalyzersPrefix',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: '',
      });
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'secureAnalyzersPrefix',
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        value: '',
      });
      await nextTick();

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['historicScan']);

      // Re-add it, sorted back into its catalog position ahead of historicScan.
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'secureAnalyzersPrefix',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: 'registry2.example.com',
      });
      await nextTick();

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['secureAnalyzersPrefix', 'historicScan']);
    });

    it('keeps a row in place when its value is removed from just one trigger, rather than moving it to the end', async () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
            {
              triggerType: 'DEFAULT_BRANCH_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
          ],
        },
      });

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['historicScan', 'excludedPaths']);

      // Remove the first setting's value from just the first trigger; it's still configured
      // on DEFAULT_BRANCH_PIPELINE, so the row should stay where it was.
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: null,
      });
      await nextTick();

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['historicScan', 'excludedPaths']);
    });

    it('drops a row from the order once its value is removed from every trigger', async () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
            {
              triggerType: 'DEFAULT_BRANCH_PIPELINE',
              configuration: { historicScan: true, excludedPaths: ['spec/'] },
            },
          ],
        },
      });

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: null,
      });
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        value: null,
      });
      await nextTick();

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['excludedPaths']);

      // Re-adding it afterwards sorts it back into its catalog position, ahead of excludedPaths.
      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: true,
      });
      await nextTick();

      expect(
        findAdvancedConfigurationEditor()
          .props('rows')
          .map((row) => row.setting),
      ).toEqual(['historicScan', 'excludedPaths']);
    });

    it('sends no configuration at all once every value on a trigger is removed', () => {
      createComponent({
        profile: {
          ...baseProfile,
          triggerSettings: [
            { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { historicScan: true } },
          ],
        },
      });

      findAdvancedConfigurationEditor().vm.$emit('set-value', {
        setting: 'historicScan',
        triggerType: 'MERGE_REQUEST_PIPELINE',
        value: null,
      });
      submitForm();

      expect(wrapper.emitted('save')[0][0].triggerConfigurations).toEqual({
        MERGE_REQUEST_PIPELINE: {},
      });
    });
  });
});
