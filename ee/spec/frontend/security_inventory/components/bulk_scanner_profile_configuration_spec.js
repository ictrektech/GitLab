import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import {
  SCAN_PROFILE_STATUS_APPLIED,
  SCAN_PROFILE_STATUS_DISABLED,
  SCAN_PROFILE_STATUS_MIXED,
} from '~/security_configuration/constants';
import BulkScannerProfileConfiguration from 'ee/security_inventory/components/bulk_scanner_profile_configuration.vue';
import AvailableSecurityScanProfiles from 'ee/security_inventory/graphql/available_security_scan_profiles.query.graphql';

Vue.use(VueApollo);

describe('BulkScannerProfileConfiguration', () => {
  let wrapper;
  let mockApollo;

  const mockQueryResponse = () => {
    return {
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          availableSecurityScanProfiles: [
            {
              id: 'gid://gitlab/Security::ScanProfile/1',
              name: 'Secret Detection (default)',
              description: 'Default Secret Detection configuration',
              scanType: 'SECRET_DETECTION',
              gitlabRecommended: true,
            },
          ],
        },
      },
    };
  };

  const handler = jest.fn().mockResolvedValue(mockQueryResponse());

  const createComponent = ({
    availableSecurityScanProfilesHandler = handler,
    statusPatches = {},
  } = {}) => {
    mockApollo = createMockApollo([
      [AvailableSecurityScanProfiles, availableSecurityScanProfilesHandler],
    ]);

    wrapper = mountExtended(BulkScannerProfileConfiguration, {
      apolloProvider: mockApollo,
      propsData: {
        statusPatches,
      },
      provide: {
        groupFullPath: 'test-group',
        rootGroupName: 'Acme Corp',
      },
    });
  };

  const findScanTypeCell = () => wrapper.findByTestId('scan-type-cell');
  const findScanTypeCells = () => wrapper.findAllByTestId('scan-type-cell');
  const findProfileNameCell = () => wrapper.findByTestId('profile-name-cell');
  const findManagedByBadge = () => wrapper.findByTestId('managed-by-badge');
  const findApplyDefaultProfileButton = () => wrapper.findByTestId('apply-default-profile-button');
  const findPreviewDefaultProfileButton = () =>
    wrapper.findByTestId('preview-default-profile-button');
  const findDisableForAllButton = () => wrapper.findByTestId('disable-for-all-button');

  beforeEach(async () => {
    createComponent();
    await waitForPromises();
  });

  it('queries available security scan profiles', () => {
    expect(handler).toHaveBeenCalledWith({
      fullPath: 'test-group',
    });
  });

  it('excludes scanners with an unsupported scan type', async () => {
    createComponent({
      availableSecurityScanProfilesHandler: jest.fn().mockResolvedValue({
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            availableSecurityScanProfiles: [
              {
                id: 'gid://gitlab/Security::ScanProfile/1',
                name: 'Secret Detection (default)',
                description: 'Default Secret Detection configuration',
                scanType: 'SECRET_DETECTION',
                gitlabRecommended: true,
              },
              {
                id: 'gid://gitlab/Security::ScanProfile/2',
                name: 'Unsupported profile',
                description: 'Unsupported configuration',
                scanType: 'UNSUPPORTED_SCAN_TYPE',
                gitlabRecommended: true,
              },
            ],
          },
        },
      }),
    });
    await waitForPromises();

    expect(findScanTypeCells()).toHaveLength(1);
  });

  it('renders the label and name for a business logic scanner', async () => {
    createComponent({
      availableSecurityScanProfilesHandler: jest.fn().mockResolvedValue({
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            availableSecurityScanProfiles: [
              {
                id: 'gid://gitlab/Security::ScanProfile/3',
                name: 'Business Logic (default)',
                description: 'Default Business Logic configuration',
                scanType: 'BUSINESS_LOGIC',
                gitlabRecommended: true,
              },
            ],
          },
        },
      }),
    });
    await waitForPromises();

    expect(findScanTypeCell().text()).toContain('BL');
    expect(findScanTypeCell().text()).toContain('Business logic scanning');
    expect(findScanTypeCell().text()).not.toContain('Unknown');
  });

  describe('with a triage and remediation profile', () => {
    const createComponentWithTriage = () =>
      createComponent({
        availableSecurityScanProfilesHandler: jest.fn().mockResolvedValue({
          data: {
            group: {
              id: 'gid://gitlab/Group/1',
              availableSecurityScanProfiles: [
                {
                  id: 'gid://gitlab/Security::ScanProfile/1',
                  name: 'Secret Detection (default)',
                  description: 'Default Secret Detection configuration',
                  scanType: 'SECRET_DETECTION',
                  gitlabRecommended: true,
                },
                {
                  id: 'gid://gitlab/Security::ScanProfile/triage_and_remediation',
                  name: 'Triage and remediation (standard)',
                  description: 'Standard triage and remediation configuration',
                  scanType: 'TRIAGE_AND_REMEDIATION',
                  gitlabRecommended: true,
                },
              ],
            },
          },
        }),
      });

    it('shows it with the feature flag enabled', async () => {
      window.gon.features = { triageAndRemediationProfilesUi: true };
      createComponentWithTriage();
      await waitForPromises();

      expect(findScanTypeCells()).toHaveLength(2);
      expect(findScanTypeCells().at(1).text()).toContain('Automated Triage and Remediation');
      expect(findScanTypeCells().at(1).text()).toContain('ATR');
    });

    it('hides it with the feature flag disabled', async () => {
      window.gon.features = { triageAndRemediationProfilesUi: false };
      createComponentWithTriage();
      await waitForPromises();

      expect(findScanTypeCells()).toHaveLength(1);
    });

    it('sets the standard preset as selected', async () => {
      window.gon.features = { triageAndRemediationProfilesUi: true };
      createComponent({
        availableSecurityScanProfilesHandler: jest.fn().mockResolvedValue({
          data: {
            group: {
              id: 'gid://gitlab/Group/1',
              availableSecurityScanProfiles: [
                {
                  id: 'gid://gitlab/Security::ScanProfile/triage_and_remediation_conservative',
                  name: 'Triage and Remediation (Conservative)',
                  description: 'Conservative triage and remediation configuration',
                  scanType: 'TRIAGE_AND_REMEDIATION',
                  gitlabRecommended: true,
                },
                {
                  id: 'gid://gitlab/Security::ScanProfile/triage_and_remediation_standard',
                  name: 'Triage and Remediation (Standard)',
                  description: 'Standard triage and remediation configuration',
                  scanType: 'TRIAGE_AND_REMEDIATION',
                  gitlabRecommended: true,
                },
              ],
            },
          },
        }),
      });
      await waitForPromises();

      expect(wrapper.findComponent(GlCollapsibleListbox).props('selected')).toBe(
        'gid://gitlab/Security::ScanProfile/triage_and_remediation_standard',
      );
    });
  });

  describe('default state', () => {
    it('renders scanner type label and name', () => {
      expect(findScanTypeCell().text()).toContain('SD');
      expect(findScanTypeCell().text()).toContain('Secret detection');
    });

    it('applies status classes to icon', () => {
      const classes = wrapper.findByTestId('scan-type-icon').classes();

      expect(classes).toContain('gl-bg-feedback-neutral');
      expect(classes).toContain('gl-border-feedback-neutral');
    });

    it('renders relevant buttons', () => {
      expect(findApplyDefaultProfileButton().exists()).toBe(true);
      expect(findPreviewDefaultProfileButton().exists()).toBe(true);
      expect(findDisableForAllButton().exists()).toBe(true);
    });
  });

  describe('with applied status patch', () => {
    beforeEach(async () => {
      createComponent({
        statusPatches: {
          'gid://gitlab/Security::ScanProfile/1': {
            status: SCAN_PROFILE_STATUS_APPLIED,
          },
        },
      });
      await waitForPromises();
    });

    it('applies status classes to icon', () => {
      const classes = wrapper.findByTestId('scan-type-icon').classes();

      expect(classes).toContain('gl-bg-green-100');
      expect(classes).toContain('gl-border-green-500');
    });

    it('renders profile name as link', () => {
      expect(findProfileNameCell().text()).toContain('Secret Detection (default)');
    });

    it('renders "Disable for all" button', () => {
      expect(findDisableForAllButton().exists()).toBe(true);
    });

    it('shows the badge on its own line below the name', () => {
      expect(findManagedByBadge().text()).toBe('GitLab');
      expect(findProfileNameCell().classes()).toContain('gl-flex-col');
      expect(findProfileNameCell().element.lastElementChild).toBe(findManagedByBadge().element);
    });
  });

  describe('with multiple profiles for one scan type', () => {
    const defaultProfile = {
      id: 'gid://gitlab/Security::ScanProfile/1',
      name: 'Secret Detection (default)',
      description: 'Default Secret Detection configuration',
      scanType: 'SECRET_DETECTION',
      gitlabRecommended: true,
    };
    const customProfile = {
      id: 'gid://gitlab/Security::ScanProfile/2',
      name: 'Secret Detection Custom',
      description: 'Custom Secret Detection configuration',
      scanType: 'SECRET_DETECTION',
      gitlabRecommended: false,
    };

    const multiProfileHandler = () =>
      jest.fn().mockResolvedValue({
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            availableSecurityScanProfiles: [defaultProfile, customProfile],
          },
        },
      });

    const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);

    beforeEach(async () => {
      createComponent({ availableSecurityScanProfilesHandler: multiProfileHandler() });
      await waitForPromises();
    });

    it('renders one row per scan type', () => {
      expect(findScanTypeCells()).toHaveLength(1);
    });

    it('renders a profile picker listbox pre-selected to the recommended profile', () => {
      expect(findListbox().exists()).toBe(true);
      expect(findListbox().props('selected')).toBe(defaultProfile.id);
      expect(findListbox().props('items')).toEqual([
        { value: defaultProfile.id, text: defaultProfile.name, profile: defaultProfile },
        { value: customProfile.id, text: customProfile.name, profile: customProfile },
      ]);
    });

    it('shows no badge beside the picker', () => {
      expect(findManagedByBadge().exists()).toBe(false);
    });

    it('shows a badge on each option in the picker', async () => {
      await findListbox().find('button').trigger('click');

      expect(
        findListbox()
          .findAllComponents(GlBadge)
          .wrappers.map((badge) => badge.text()),
      ).toEqual(['GitLab', 'Acme Corp']);
    });

    it('changes the row identity to the picked profile when a listbox item is selected', async () => {
      findListbox().vm.$emit('select', customProfile.id);
      await waitForPromises();

      wrapper.findComponentByTestId('apply-default-profile-button').vm.$emit('click');

      expect(wrapper.emitted('attach-profile')[0][0]).toMatchObject({
        id: customProfile.id,
        name: customProfile.name,
      });
    });

    it('keeps default-profile labels while the recommended profile is selected', () => {
      expect(findApplyDefaultProfileButton().text()).toBe('Apply default profile to all');
      expect(findPreviewDefaultProfileButton().attributes('aria-label')).toBe(
        'Preview default profile',
      );
    });

    it('switches to non-default labels when a non-recommended profile is picked', async () => {
      findListbox().vm.$emit('select', customProfile.id);
      await nextTick();

      expect(findApplyDefaultProfileButton().text()).toBe('Apply profile to all');
      expect(findPreviewDefaultProfileButton().attributes('aria-label')).toBe('Preview profile');
    });

    it('wires the listbox to the scanner name via toggle-aria-labelled-by', () => {
      expect(findListbox().attributes('id')).toBeUndefined();
      expect(findListbox().props('toggleAriaLabelledBy')).toBe('SECRET_DETECTION-scanner-name');
    });

    it('replaces the picker with the applied-profile link once the recommended profile is applied', async () => {
      createComponent({
        availableSecurityScanProfilesHandler: multiProfileHandler(),
        statusPatches: {
          [defaultProfile.id]: { status: SCAN_PROFILE_STATUS_APPLIED },
        },
      });
      await waitForPromises();

      expect(findListbox().exists()).toBe(false);
      expect(findProfileNameCell().text()).toContain(defaultProfile.name);
      expect(findApplyDefaultProfileButton().exists()).toBe(false);
    });

    it('replaces the picker with the applied-profile link once a custom-selected profile is applied', async () => {
      findListbox().vm.$emit('select', customProfile.id);
      await nextTick();

      await wrapper.setProps({
        statusPatches: {
          [customProfile.id]: { status: SCAN_PROFILE_STATUS_APPLIED },
        },
        lastStatusPatch: customProfile.id,
      });

      expect(findListbox().exists()).toBe(false);
      expect(findProfileNameCell().text()).toContain(customProfile.name);
      expect(findApplyDefaultProfileButton().exists()).toBe(false);
    });
  });

  describe('with disabled status patch', () => {
    beforeEach(async () => {
      createComponent({
        statusPatches: {
          'gid://gitlab/Security::ScanProfile/1': {
            status: SCAN_PROFILE_STATUS_DISABLED,
          },
        },
      });
      await waitForPromises();
    });

    it('applies status classes to icon', () => {
      const classes = wrapper.findByTestId('scan-type-icon').classes();

      expect(classes).toContain('gl-bg-feedback-danger');
      expect(classes).toContain('gl-border-feedback-danger');
    });

    it('renders the profile name so the user can see what will be enabled', () => {
      expect(findProfileNameCell().text()).toContain('Secret Detection (default)');
      expect(findProfileNameCell().text()).not.toContain('No profile applied');
    });

    it('renders an sr-only "Disabled" label so the state is announced without a visual change', () => {
      expect(wrapper.findByTestId('disabled-status-sr-label').text()).toBe('Disabled');
    });

    it('renders relevant buttons', () => {
      expect(findApplyDefaultProfileButton().exists()).toBe(true);
      expect(findPreviewDefaultProfileButton().exists()).toBe(true);
    });

    it('shows the badge below the name', () => {
      expect(findManagedByBadge().text()).toBe('GitLab');
      expect(findProfileNameCell().element.lastElementChild).toBe(findManagedByBadge().element);
    });
  });

  describe('with mixed status patch', () => {
    beforeEach(async () => {
      createComponent({
        statusPatches: {
          'gid://gitlab/Security::ScanProfile/1': {
            status: SCAN_PROFILE_STATUS_MIXED,
          },
        },
      });
      await waitForPromises();
    });

    it('hides the badge on a mixed profile', () => {
      expect(findManagedByBadge().exists()).toBe(false);
    });
  });

  describe('without a disabled status patch', () => {
    it('does not render the sr-only "Disabled" label', () => {
      expect(wrapper.findByTestId('disabled-status-sr-label').exists()).toBe(false);
    });
  });
});
