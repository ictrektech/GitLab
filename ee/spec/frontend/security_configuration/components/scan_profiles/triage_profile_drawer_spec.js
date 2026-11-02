import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlDrawer, GlTab } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import ProfileListDrawer from 'ee/security_configuration/components/scan_profiles/profile_list_drawer.vue';
import TriagePresetCapabilities from 'ee/security_configuration/components/scan_profiles/triage_preset_capabilities.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import {
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
} from '~/security_configuration/constants';

Vue.use(VueApollo);

jest.mock('~/alert');

const GROUP_FULL_PATH = 'my-group';

describe('TriageProfileDrawer', () => {
  let wrapper;
  let resolver;

  const buildPreset = (preset, name, overrides = {}) => ({
    id: `gid://gitlab/Security::ScanProfile/triage_and_remediation_${preset}`,
    name,
    description: `The ${preset} preset`,
    scanType: SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
    gitlabRecommended: true,
    triggers: [],
    triggerSettings: [],
    projectCount: 0,
    __typename: 'ScanProfileType',
    ...overrides,
  });

  const conservative = buildPreset('conservative', 'Triage and Remediation (Conservative)');
  const standard = buildPreset('standard', 'Triage and Remediation (Standard)', {
    triggers: ['SAST_FALSE_POSITIVE', 'SAST_VULNERABILITY_RESOLUTION'],
  });
  const proactive = buildPreset('proactive', 'Triage and Remediation (Proactive)', {
    triggers: ['SBOM_INGESTED'],
  });
  const secretDetection = buildPreset('secret', 'Secret Detection (default)', {
    id: 'gid://gitlab/Security::ScanProfile/secret_detection',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
  });

  const createResolver = (profiles = [conservative, secretDetection, standard, proactive]) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          name: GROUP_FULL_PATH,
          userPermissions: {
            createSecurityScanProfiles: false,
            updateSecurityScanProfiles: false,
            deleteSecurityScanProfiles: false,
            __typename: 'GroupPermissions',
          },
          availableSecurityScanProfiles: profiles,
          __typename: 'Group',
        },
      },
    });

  const createComponent = ({ props = {}, queryResolver = createResolver() } = {}) => {
    resolver = queryResolver;

    wrapper = shallowMountExtended(TriageProfileDrawer, {
      apolloProvider: createMockApollo([[groupAvailableSecurityScanProfilesQuery, resolver]]),
      propsData: {
        open: true,
        ...props,
      },
      provide: {
        groupFullPath: GROUP_FULL_PATH,
      },
      stubs: {
        CrudComponent,
        ProfileListDrawer,
        GlDrawer: stubComponent(GlDrawer, {
          template: '<div><slot name="title" /><slot /></div>',
        }),
      },
    });
  };

  const findListItems = () => wrapper.findAllByTestId('triage-profile-list-item');
  const findSelectedItem = () => wrapper.find('[aria-current="true"]');
  const findDetail = () => wrapper.findByTestId('triage-profile-detail');
  const findItemByName = (name) =>
    findListItems().wrappers.find((item) => item.text().includes(name));

  const findBadge = (name, testId) => findItemByName(name).find(`[data-testid="${testId}"]`);
  const findAppliedBadges = () => wrapper.findAllByTestId('applied-badge');
  const findDetailValues = () =>
    findDetail()
      .findAll('dd')
      .wrappers.map((cell) => cell.text());
  const project = { id: 'gid://gitlab/Project/1' };

  it('fetches the recommended profiles of the group', async () => {
    createComponent();
    await waitForPromises();

    expect(resolver).toHaveBeenCalledWith({ fullPath: GROUP_FULL_PATH, gitlabRecommended: true });
  });

  it('renders the triage and remediation presets', async () => {
    createComponent();
    await waitForPromises();

    expect(findListItems()).toHaveLength(3);
    expect(wrapper.text()).not.toContain(secretDetection.name);
  });

  describe('with no preset passed', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders Standard as current', () => {
      expect(findSelectedItem().text()).toContain(standard.name);
    });

    it('shows the details of Standard', () => {
      expect(findDetail().text()).toContain(standard.description);
    });

    it('renders the general details of Standard', () => {
      expect(findDetailValues()).toEqual([
        'The standard preset',
        'Automated Triage and Remediation',
        'GitLab',
      ]);
    });

    it('shows the Recommended badge beside the heading', () => {
      expect(wrapper.findByTestId('detail-recommended-badge').text()).toBe('Recommended');
      expect(wrapper.findByTestId('detail-applied-badge').exists()).toBe(false);
    });

    it('passes the triggers of Standard', () => {
      expect(wrapper.findComponent(TriagePresetCapabilities).props('triggers')).toEqual(
        standard.triggers,
      );
    });

    it('renders the tab titled Configuration', () => {
      expect(wrapper.findComponent(GlTab).attributes('title')).toBe('Configuration');
    });

    it('shows the Recommended badge on Standard', () => {
      expect(wrapper.findAllByTestId('recommended-badge')).toHaveLength(1);
      expect(findBadge(standard.name, 'recommended-badge').exists()).toBe(true);
    });

    it('hides the Applied badge', () => {
      expect(findAppliedBadges()).toHaveLength(0);
    });

    describe('and a preset clicked', () => {
      beforeEach(async () => {
        await findItemByName(conservative.name).trigger('click');
      });

      it('renders the clicked preset as current', () => {
        expect(findSelectedItem().text()).toContain(conservative.name);
      });

      it('shows the details of the clicked preset', () => {
        expect(findDetail().text()).toContain(conservative.description);
      });

      it('passes the triggers of the clicked preset', () => {
        expect(wrapper.findComponent(TriagePresetCapabilities).props('triggers')).toEqual(
          conservative.triggers,
        );
      });

      it('hides the badge beside the heading', () => {
        expect(wrapper.findByTestId('detail-recommended-badge').exists()).toBe(false);
        expect(wrapper.findByTestId('detail-applied-badge').exists()).toBe(false);
      });

      it('resets to Standard on reopen', async () => {
        await wrapper.setProps({ open: false });
        await wrapper.setProps({ open: true });
        await waitForPromises();

        expect(findSelectedItem().text()).toContain(standard.name);
      });
    });
  });

  describe('with a preset passed', () => {
    beforeEach(async () => {
      createComponent({ props: { presetId: proactive.id } });
      await waitForPromises();
    });

    it('renders the passed preset as current', () => {
      expect(findSelectedItem().text()).toContain(proactive.name);
      expect(findDetail().text()).toContain(proactive.description);
    });

    it('hides the Applied badge', () => {
      expect(findAppliedBadges()).toHaveLength(0);
    });

    it('resets to the passed preset on reopen', async () => {
      await findItemByName(conservative.name).trigger('click');
      await wrapper.setProps({ open: false });
      await wrapper.setProps({ open: true });
      await waitForPromises();

      expect(findSelectedItem().text()).toContain(proactive.name);
    });
  });

  describe('with a project passed', () => {
    it('shows the Applied badge on its preset', async () => {
      createComponent({ props: { project, presetId: proactive.id } });
      await waitForPromises();

      expect(findAppliedBadges()).toHaveLength(1);
      expect(findBadge(proactive.name, 'applied-badge').exists()).toBe(true);
    });

    it('shows Applied in place of Recommended', async () => {
      createComponent({ props: { project, presetId: standard.id } });
      await waitForPromises();

      expect(findBadge(standard.name, 'applied-badge').exists()).toBe(true);
      expect(findBadge(standard.name, 'recommended-badge').exists()).toBe(false);
    });

    it('shows Applied beside the heading', async () => {
      createComponent({ props: { project, presetId: standard.id } });
      await waitForPromises();

      expect(wrapper.findByTestId('detail-applied-badge').text()).toBe('Applied');
      expect(wrapper.findByTestId('detail-recommended-badge').exists()).toBe(false);
    });

    it('hides the Applied badge with no preset', async () => {
      createComponent({ props: { project } });
      await waitForPromises();

      expect(findAppliedBadges()).toHaveLength(0);
    });
  });

  it('fetches nothing while closed', async () => {
    createComponent({ props: { open: false } });
    await waitForPromises();

    expect(resolver).not.toHaveBeenCalled();
  });

  describe('with no Standard in the data', () => {
    it('renders the first preset as current', async () => {
      createComponent({ queryResolver: createResolver([conservative, proactive]) });
      await waitForPromises();

      expect(findSelectedItem().text()).toContain(conservative.name);
    });
  });

  describe('with a failed query', () => {
    const error = new Error('Network error');

    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException');
      createComponent({ queryResolver: jest.fn().mockRejectedValue(error) });
      await waitForPromises();
    });

    it('shows an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to load triage and remediation profiles.',
        containerSelector: '.js-triage-profile-drawer-flash-container',
      });
    });

    it('passes the error to Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalled();
    });

    it('hides the list', () => {
      expect(wrapper.findByTestId('triage-profile-list').exists()).toBe(false);
    });
  });

  it('emits close on dismiss', () => {
    createComponent();

    wrapper.findComponent(GlDrawer).vm.$emit('close');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
