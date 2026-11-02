import { GlBadge, GlButton, GlDisclosureDropdown } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ScanProfileDetail from 'ee/security_configuration/components/scan_profiles/scan_profile_detail.vue';
import InsufficientPermissionsPopover from 'ee/security_configuration/components/scan_profiles/insufficient_permissions_popover.vue';
import ScanTriggersDetail from 'ee/security_configuration/components/scan_profiles/scan_triggers_detail.vue';
import AdvancedConfigurationTable from 'ee/security_configuration/components/scan_profiles/advanced_configuration_table.vue';
import {
  SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

const buildConfiguration = (values) => ({
  __typename: 'SecretDetectionConfiguration',
  secureAnalyzersPrefix: null,
  imageSuffix: null,
  historicScan: null,
  logOptions: null,
  excludedPaths: null,
  rulesetGitReference: null,
  ...values,
});

describe('ScanProfileDetail', () => {
  let wrapper;

  const profile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection (default)',
    description: 'Protect your repository from leaked secrets',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
    gitlabRecommended: true,
    triggers: ['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT'],
  };

  const createComponent = (overrides = {}, provide = {}, props = {}) => {
    wrapper = shallowMountExtended(ScanProfileDetail, {
      propsData: { profile: { ...profile, ...overrides }, ...props },
      provide: { rootGroupName: 'Acme Corp', ...provide },
      stubs: { CrudComponent },
    });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);
  const findTriggersDetail = () => wrapper.findComponent(ScanTriggersDetail);
  const findActionsWrapper = () => wrapper.findByTestId('scan-profile-actions-wrapper');
  const findActionsDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findActionByText = (text) =>
    findActionsDropdown()
      .props('items')
      .find((item) => item.text === text);
  const findActionTexts = () =>
    findActionsDropdown()
      .props('items')
      .map((item) => item.text);
  const findDuplicateButton = () => wrapper.findComponent(GlButton);
  const findValues = () => wrapper.findAll('dd').wrappers.map((cell) => cell.text());
  const findTriggers = () => findTriggersDetail().props('triggers');
  const findTriggerAnchors = () => findTriggers().map(({ anchor }) => anchor);
  const findAdvancedConfigurationTable = () => wrapper.findComponent(AdvancedConfigurationTable);
  const findAdvancedConfigurationEmpty = () =>
    wrapper.findByTestId('scan-profile-advanced-configuration-empty');
  const findNothingToConfigure = () =>
    wrapper.findByTestId('scan-profile-advanced-configuration-nothing-to-configure');

  it('renders the profile name as the heading', () => {
    createComponent();

    expect(wrapper.find('h3').text()).toBe(profile.name);
  });

  it('renders the general details', () => {
    createComponent();

    expect(findValues()).toEqual([
      'Secret Detection (default)',
      'Protect your repository from leaked secrets',
      'Secret detection',
      'GitLab',
    ]);
  });

  it.each([
    [true, 'GitLab'],
    [false, 'Acme Corp'],
  ])('badges gitlabRecommended %s as managed by %s', (gitlabRecommended, label) => {
    createComponent({ gitlabRecommended });

    expect(findBadge().text()).toBe(label);
  });

  it('shows Custom without a group name', () => {
    createComponent({ gitlabRecommended: false }, { rootGroupName: '' });

    expect(findBadge().text()).toBe('Custom');
  });

  it('falls back to the raw scan type when it is not a known category', () => {
    createComponent({ scanType: 'NOT_A_SCANNER' });

    expect(findValues()).toContain('NOT_A_SCANNER');
  });

  it('passes the resolved trigger definitions down', () => {
    createComponent();

    expect(findTriggerAnchors()).toEqual(['merge-request-pipeline', 'secret-push-protection']);
    expect(findTriggers()[0].title).toBe('Merge Request Pipelines');
  });

  it('passes the business logic trigger text for a business logic profile', () => {
    createComponent({
      scanType: SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
      triggers: ['MERGE_REQUEST_PIPELINE'],
    });

    expect(findTriggers()[0]).toMatchObject({
      infoDescription:
        "GitLab scans the files a merge request changes after the merge request's head pipeline succeeds.",
    });
  });

  it('passes the help link for the scan type down', () => {
    createComponent();

    expect(findTriggersDetail().props('profileHelpLink')).toBe(
      '/help/user/application_security/configuration/security_configuration_profiles',
    );
  });

  it('passes the scan type variable definitions down, so the triggers table can show display labels instead of raw values', () => {
    createComponent();

    expect(findTriggersDetail().props('variableDefinitions')).toMatchObject({
      historicScan: { valueType: 'boolean' },
      imageSuffix: { valueType: 'enum' },
    });
  });

  it('drops trigger types with no definition rather than rendering blanks', () => {
    createComponent({ triggers: ['MERGE_REQUEST_PIPELINE', 'NOT_A_TRIGGER'] });

    expect(findTriggerAnchors()).toEqual(['merge-request-pipeline']);
  });

  it('handles a profile with no triggers', () => {
    createComponent({ triggers: [] });

    expect(findTriggerAnchors()).toEqual([]);
  });

  it('passes each trigger its own variable rows', () => {
    createComponent({
      triggerSettings: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: buildConfiguration({ historicScan: true, excludedPaths: ['spec/'] }),
        },
        { triggerType: 'GIT_PUSH_EVENT', configuration: null },
      ],
    });

    const rowsPerTrigger = findTriggers().map(({ anchor, variableRows }) => [anchor, variableRows]);

    expect(rowsPerTrigger).toEqual([
      [
        'merge-request-pipeline',
        [
          { setting: 'historicScan', value: true },
          { setting: 'excludedPaths', value: ['spec/'] },
        ],
      ],
      ['secret-push-protection', []],
    ]);
  });

  describe('advanced configuration heading', () => {
    it('renders when a configurable trigger is enabled', () => {
      createComponent({ gitlabRecommended: false });

      expect(wrapper.text()).toContain('Advanced configuration');
      expect(wrapper.text()).toContain(
        'Variables passed to the analyzer that override its default behavior.',
      );
    });

    it('shows the nothing-to-configure state', () => {
      createComponent({ gitlabRecommended: false, triggers: ['GIT_PUSH_EVENT'] });

      expect(findNothingToConfigure().text()).toBe(
        "None of this profile's triggers use analyzer settings, so there is nothing to configure.",
      );
      expect(findAdvancedConfigurationTable().exists()).toBe(false);
      expect(findAdvancedConfigurationEmpty().exists()).toBe(false);
    });

    it('is hidden when there are no triggers', () => {
      createComponent({ gitlabRecommended: false, triggers: [] });

      expect(wrapper.text()).not.toContain('Advanced configuration');
    });

    it('hides the section for a GitLab-recommended profile', () => {
      createComponent({
        gitlabRecommended: true,
        triggerSettings: [
          {
            triggerType: 'MERGE_REQUEST_PIPELINE',
            configuration: {
              __typename: 'SecretDetectionConfiguration',
              excludedPaths: 'spec',
            },
          },
        ],
      });

      expect(wrapper.text()).not.toContain('Advanced configuration');
      expect(findAdvancedConfigurationTable().exists()).toBe(false);
      expect(findAdvancedConfigurationEmpty().exists()).toBe(false);
    });

    it('shows an empty state with no settings set', () => {
      createComponent({ gitlabRecommended: false });

      expect(findAdvancedConfigurationEmpty().text()).toBe(
        'No advanced configuration is set for this profile.',
      );
    });

    describe('with a setting set', () => {
      beforeEach(() => {
        createComponent({
          gitlabRecommended: false,
          triggerSettings: [
            {
              triggerType: 'MERGE_REQUEST_PIPELINE',
              configuration: {
                __typename: 'SecretDetectionConfiguration',
                excludedPaths: 'spec',
              },
            },
          ],
        });
      });

      it('passes the profile rows to the table', () => {
        expect(findAdvancedConfigurationTable().props('rows')).toEqual([
          {
            setting: 'excludedPaths',
            triggerValues: [{ triggerType: 'MERGE_REQUEST_PIPELINE', value: 'spec' }],
            value: 'spec',
          },
        ]);
      });

      it('passes the scan type variable definitions, so raw values render with their display label', () => {
        expect(findAdvancedConfigurationTable().props('variableDefinitions')).toMatchObject({
          historicScan: { valueType: 'boolean' },
          imageSuffix: { valueType: 'enum' },
        });
      });

      it('hides the empty state', () => {
        expect(findAdvancedConfigurationEmpty().exists()).toBe(false);
      });
    });

    it('translates a GraphQL enum value (e.g. imageSuffix DEFAULT) to the backend value its variable definition maps to a display label', () => {
      createComponent({
        gitlabRecommended: false,
        triggerSettings: [
          {
            triggerType: 'MERGE_REQUEST_PIPELINE',
            configuration: buildConfiguration({ imageSuffix: 'DEFAULT' }),
          },
        ],
      });

      expect(findAdvancedConfigurationTable().props('rows')).toEqual([
        expect.objectContaining({ setting: 'imageSuffix', value: '' }),
      ]);
    });
  });

  describe('actions dropdown', () => {
    it('is always rendered', () => {
      createComponent();

      expect(findActionsDropdown().exists()).toBe(true);
    });

    it('holds Edit and Delete, leaving Duplicate to its own button', () => {
      createComponent({ gitlabRecommended: false });

      expect(findActionTexts()).toEqual(['Edit', 'Delete']);
    });

    it('is disabled for a GitLab-managed profile with an explanatory tooltip on the wrapper', () => {
      createComponent({ gitlabRecommended: true });

      expect(findActionsDropdown().props('disabled')).toBe(true);
      expect(findActionsWrapper().attributes('title')).toBe(
        "GitLab-managed profiles can't be edited or deleted. Duplicate this profile to make a customized version.",
      );
    });

    it('enables a custom profile without a tooltip', () => {
      createComponent({ gitlabRecommended: false }, {}, { canUpdate: true, canDelete: true });

      expect(findActionsDropdown().props('disabled')).toBe(false);
      expect(findActionsWrapper().attributes('title')).toBe('');
    });

    it('emits edit when the Edit item is activated', () => {
      createComponent({ gitlabRecommended: false }, {}, { canUpdate: true, canDelete: true });

      findActionByText('Edit').action();

      expect(wrapper.emitted('edit')).toHaveLength(1);
    });

    it('emits delete when the Delete item is activated, styled as danger', () => {
      createComponent({ gitlabRecommended: false }, {}, { canUpdate: true, canDelete: true });

      const deleteItem = findActionByText('Delete');
      deleteItem.action();

      expect(wrapper.emitted('delete')).toHaveLength(1);
      expect(deleteItem.variant).toBe('danger');
    });
  });

  describe('duplicate button', () => {
    it('sits outside the dropdown so it reads as the primary way to copy a profile', () => {
      createComponent();

      expect(findDuplicateButton().text()).toBe('Duplicate');
    });

    it.each([true, false])(
      'emits duplicate when clicked, gitlabRecommended %s',
      (gitlabRecommended) => {
        createComponent({ gitlabRecommended });

        findDuplicateButton().vm.$emit('click');

        expect(wrapper.emitted('duplicate')).toHaveLength(1);
      },
    );
  });

  describe('permissions', () => {
    const findPermissionsPopovers = () => wrapper.findAllComponents(InsufficientPermissionsPopover);
    const findPopoverTarget = () => findPermissionsPopovers().at(0).props('target')();
    const isActionDisabled = (text) => findActionByText(text).disabled;

    it('enables every action with all permissions', () => {
      createComponent(
        { gitlabRecommended: false },
        {},
        { canCreate: true, canUpdate: true, canDelete: true },
      );

      expect(findDuplicateButton().props('disabled')).toBe(false);
      expect(findActionsDropdown().props('disabled')).toBe(false);
      expect(isActionDisabled('Edit')).toBe(false);
      expect(isActionDisabled('Delete')).toBe(false);
      expect(findPermissionsPopovers()).toHaveLength(0);
    });

    it('disables Duplicate without create permission', () => {
      createComponent(
        { gitlabRecommended: false },
        {},
        { canCreate: false, canUpdate: true, canDelete: true },
      );

      expect(findDuplicateButton().props('disabled')).toBe(true);
      expect(findPopoverTarget()).toBe(
        wrapper.findByTestId('scan-profile-duplicate-wrapper').element,
      );
      expect(findPermissionsPopovers().at(0).props('description')).toBe(
        'To create scan profiles, you need the Security Manager, Maintainer, or Owner role in the top-level group.',
      );
    });

    it.each([
      {
        denied: 'Edit',
        allowed: 'Delete',
        event: 'edit',
        testId: 'scan-profile-edit-action',
        permissions: { canUpdate: false, canDelete: true },
        itemClass: 'js-scan-profile-edit-item',
        description:
          'To edit scan profiles, you need the Security Manager, Maintainer, or Owner role in the top-level group.',
      },
      {
        denied: 'Delete',
        allowed: 'Edit',
        event: 'delete',
        testId: 'scan-profile-delete-action',
        permissions: { canUpdate: true, canDelete: false },
        itemClass: 'js-scan-profile-delete-item',
        description:
          'To delete scan profiles, you need the Security Manager, Maintainer, or Owner role in the top-level group.',
      },
    ])(
      'disables only $denied and explains it',
      async ({ denied, allowed, event, testId, permissions, itemClass, description }) => {
        wrapper = mountExtended(ScanProfileDetail, {
          propsData: {
            profile: { ...profile, gitlabRecommended: false },
            canCreate: true,
            ...permissions,
          },
          provide: { rootGroupName: 'Acme Corp' },
          stubs: { InsufficientPermissionsPopover: true },
        });

        const popovers = findPermissionsPopovers();
        const target = popovers.at(0).props('target')();

        expect(findActionsDropdown().props('disabled')).toBe(false);
        expect(isActionDisabled(denied)).toBe(true);
        expect(isActionDisabled(allowed)).toBe(false);
        expect(popovers).toHaveLength(1);
        expect(target.tagName).toBe('LI');
        expect(target.classList.contains(itemClass)).toBe(true);
        expect(target.getAttribute('aria-disabled')).toBe('true');
        expect(popovers.at(0).props('description')).toBe(description);

        await wrapper.findByTestId(testId).trigger('click');

        expect(wrapper.emitted(event)).toBeUndefined();
      },
    );

    it('disables the dropdown without edit or delete', () => {
      createComponent(
        { gitlabRecommended: false },
        {},
        { canCreate: true, canUpdate: false, canDelete: false },
      );

      expect(findActionsDropdown().props('disabled')).toBe(true);
      expect(findPopoverTarget()).toBe(findActionsWrapper().element);
      expect(findPermissionsPopovers().at(0).props('description')).toBe(
        'To edit or delete scan profiles, you need the Security Manager, Maintainer, or Owner role in the top-level group.',
      );
      expect(findActionsWrapper().attributes('title')).toBe('');
    });

    it('explains a managed profile with the tooltip', () => {
      createComponent(
        { gitlabRecommended: true },
        {},
        { canCreate: true, canUpdate: false, canDelete: false },
      );

      expect(findActionsDropdown().props('disabled')).toBe(true);
      expect(findActionsWrapper().attributes('title')).toContain("GitLab-managed profiles can't");
      expect(findPermissionsPopovers()).toHaveLength(0);
    });
  });
});
