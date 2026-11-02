import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlModal, GlButton, GlSkeletonLoader, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';

import ScanProfileDetailsModal from 'ee/security_configuration/components/scan_profiles/scan_profile_details_modal.vue';
import ScanTriggersDetail from 'ee/security_configuration/components/scan_profiles/scan_triggers_detail.vue';
import InsufficientPermissionsPopover from 'ee/security_configuration/components/scan_profiles/insufficient_permissions_popover.vue';
import AdvancedConfigurationTable from 'ee/security_configuration/components/scan_profiles/advanced_configuration_table.vue';
import queryProfile from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile.query.graphql';

Vue.use(VueApollo);

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

const buildSastConfiguration = (values) => ({
  __typename: 'SastConfiguration',
  secureAnalyzersPrefix: null,
  imageSuffix: null,
  analyzerImageTag: null,
  excludedAnalyzers: null,
  excludedPaths: null,
  advancedSastPartialScan: null,
  gitlabAdvSastIncrScan: null,
  ...values,
});

const buildDependencyScanningConfiguration = (values) => ({
  __typename: 'DependencyScanningConfiguration',
  secureAnalyzersPrefix: null,
  additionalCaCertBundle: null,
  secureLogLevel: null,
  excludedPaths: null,
  includeDevDependencies: null,
  maxDepth: null,
  pipDependencyPath: null,
  staticReachabilityEnabled: null,
  enableManifestFallback: null,
  pipcompileLockfileFileNamePattern: null,
  pipManifestFileNamePattern: null,
  enableVulnerabilityScan: null,
  apiTimeout: null,
  apiScanDownloadDelay: null,
  mavenDependencyPluginVersion: null,
  mavenArgs: null,
  gradleCliOpts: null,
  disabledResolutionJobs: null,
  mavenResolutionImage: null,
  gradleResolutionImage: null,
  pythonResolutionImage: null,
  pipIndexUrl: null,
  pipExtraIndexUrl: null,
  searchIgnoreHiddenDirs: null,
  ...values,
});

describe('ScanProfileDetailsModal', () => {
  let wrapper;

  const mockProfile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection Profile',
    description: 'Default profile for secret detection',
    scanType: 'SECRET_DETECTION',
    gitlabRecommended: false,
    triggers: ['GIT_PUSH_EVENT', 'MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
    projectCount: 0,
    triggerSettings: [
      { triggerType: 'GIT_PUSH_EVENT', configuration: null },
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: buildConfiguration({ historicScan: true, excludedPaths: ['spec/'] }),
      },
      {
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        configuration: buildConfiguration({ historicScan: true }),
      },
    ],
    __typename: 'ScanProfileType',
  };

  const createSuccessResolver = (profile = mockProfile) =>
    jest.fn().mockResolvedValue({
      data: {
        securityScanProfile: {
          ...profile,
          __typename: 'ScanProfileType',
        },
      },
    });

  const createErrorResolver = () => jest.fn().mockRejectedValue(new Error('Query failed'));
  const createLoadingResolver = () => jest.fn(() => new Promise(() => {}));

  const createComponent = ({
    props = {},
    resolver = createSuccessResolver(),
    canApplyProfiles = true,
    rootGroupName = 'Acme',
  } = {}) => {
    const apolloProvider = createMockApollo([[queryProfile, resolver]]);

    wrapper = shallowMountExtended(ScanProfileDetailsModal, {
      apolloProvider,
      propsData: {
        visible: true,
        profileId: mockProfile.id,
        ...props,
      },
      provide: {
        canApplyProfiles,
        rootGroupName,
      },
      stubs: { GlModal },
    });

    return wrapper;
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findApplyButton = () => wrapper.findComponent(GlButton);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findInfoPopover = () => wrapper.findComponent(GlPopover);
  const findInsufficientPermissionsPopover = () =>
    wrapper.findComponent(InsufficientPermissionsPopover);
  const findScanTriggersDetail = () => wrapper.findComponent(ScanTriggersDetail);
  const findAdvancedConfiguration = () => wrapper.findComponent(AdvancedConfigurationTable);
  const findProfileName = () => wrapper.find('h3');

  describe('modal rendering', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders modal with correct props', () => {
      expect(findModal().props()).toMatchObject({
        modalId: 'scan-profile-details-modal',
        size: 'lg',
        visible: true,
        modalClass: 'scanner-profile-modal',
        ariaLabel: 'Secret detection profile',
      });
    });

    it('renders modal title', () => {
      expect(wrapper.text()).toContain('Secret detection profile');
    });

    it('renders info popover with correct props', () => {
      const popover = findInfoPopover();
      expect(popover.props('target')).toBe('header-info');
      expect(popover.props('title')).toBe('What are configuration profiles?');
      expect(popover.text()).toContain(
        'Configuration profiles are reusable settings templates for security tools',
      );
    });
  });

  describe('loading state', () => {
    beforeEach(() => {
      createComponent({ resolver: createLoadingResolver() });
    });

    it('shows skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
      expect(findSkeletonLoader().attributes('lines')).toBe('3');
    });

    it('does not render profile content', () => {
      expect(findProfileName().exists()).toBe(false);
      expect(findApplyButton().exists()).toBe(false);
    });

    it('falls back to the generic aria-label until the title resolves', () => {
      expect(findModal().props('ariaLabel')).toBe('Scan profile details');
    });
  });

  describe('loaded state', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('hides skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(false);
    });

    it('renders profile name', () => {
      expect(findProfileName().text()).toBe(mockProfile.name);
    });

    it('renders apply button with correct props', () => {
      const button = findApplyButton();

      expect(button.exists()).toBe(true);
      expect(button.text()).toBe('Apply profile');
      expect(button.props('variant')).toBe('confirm');
    });

    it('renders general details', () => {
      expect(wrapper.text()).toContain('General Details');
      expect(wrapper.text()).toContain('Information about this configuration profile.');
    });

    it('renders scan triggers', () => {
      expect(wrapper.text()).toContain('Scan triggers');
      expect(wrapper.text()).toContain('When and how scans are run.');
    });

    it('renders scan triggers detail component', () => {
      expect(findScanTriggersDetail().exists()).toBe(true);
    });

    it('passes the scan type variable definitions down, so the triggers table can show display labels instead of raw values', () => {
      expect(findScanTriggersDetail().props('variableDefinitions')).toMatchObject({
        historicScan: { valueType: 'boolean' },
        imageSuffix: { valueType: 'enum' },
      });
    });

    it('passes each trigger its own variable rows', () => {
      const rowsPerTrigger = findScanTriggersDetail()
        .props('triggers')
        .map(({ title, variableRows }) => [title, variableRows]);

      expect(rowsPerTrigger).toEqual([
        [
          'Merge Request Pipelines',
          [
            { setting: 'historicScan', value: true },
            { setting: 'excludedPaths', value: ['spec/'] },
          ],
        ],
        ['Branch pipelines (default only)', [{ setting: 'historicScan', value: true }]],
        ['Secret push protection', []],
      ]);
    });

    it('keeps the same trigger order after a trigger is disabled and re-enabled', async () => {
      createComponent({
        resolver: createSuccessResolver({
          ...mockProfile,
          triggers: ['DEFAULT_BRANCH_PIPELINE', 'GIT_PUSH_EVENT', 'MERGE_REQUEST_PIPELINE'],
        }),
      });
      await waitForPromises();

      const titles = findScanTriggersDetail()
        .props('triggers')
        .map(({ title }) => title);

      expect(titles).toEqual([
        'Merge Request Pipelines',
        'Branch pipelines (default only)',
        'Secret push protection',
      ]);
    });

    it('renders profile description', () => {
      expect(wrapper.text()).toContain('Description');
      expect(wrapper.text()).toContain(mockProfile.description);
    });

    it('renders analyzer type', () => {
      expect(wrapper.text()).toContain('Analyzer type');
      expect(wrapper.text()).toContain('Secret Detection');
    });
  });

  describe('business logic profile', () => {
    it('shows the business logic trigger text', async () => {
      const profile = {
        ...mockProfile,
        scanType: 'BUSINESS_LOGIC',
        triggers: ['MERGE_REQUEST_PIPELINE'],
        triggerSettings: [{ triggerType: 'MERGE_REQUEST_PIPELINE', configuration: null }],
      };
      createComponent({ resolver: createSuccessResolver(profile) });
      await waitForPromises();

      expect(findScanTriggersDetail().props('triggers')[0]).toMatchObject({
        infoDescription:
          "GitLab scans the files a merge request changes after the merge request's head pipeline succeeds.",
      });
    });
  });

  describe('advanced configuration', () => {
    it('shows a shared value as the profile value and a divergent one as varying', async () => {
      createComponent();
      await waitForPromises();

      expect(findAdvancedConfiguration().props('rows')).toEqual([
        expect.objectContaining({ setting: 'historicScan', value: true }),
        expect.objectContaining({ setting: 'excludedPaths', varies: true }),
      ]);
    });

    it('translates a GraphQL enum value (e.g. imageSuffix DEFAULT) to the backend value its variable definition maps to a display label', async () => {
      const profile = {
        ...mockProfile,
        triggers: ['MERGE_REQUEST_PIPELINE'],
        triggerSettings: [
          {
            triggerType: 'MERGE_REQUEST_PIPELINE',
            configuration: buildConfiguration({ imageSuffix: 'DEFAULT' }),
          },
        ],
      };
      createComponent({ resolver: createSuccessResolver(profile) });
      await waitForPromises();

      expect(findAdvancedConfiguration().props('rows')).toEqual([
        expect.objectContaining({ setting: 'imageSuffix', value: '' }),
      ]);
    });

    it('passes the scan type variable definitions, so raw values render with their display label', async () => {
      createComponent();
      await waitForPromises();

      expect(findAdvancedConfiguration().props('variableDefinitions')).toMatchObject({
        historicScan: { valueType: 'boolean' },
        imageSuffix: { valueType: 'enum' },
      });
    });

    it('shows advanced configuration rows for a SAST profile', async () => {
      const sastProfile = {
        ...mockProfile,
        name: 'SAST Profile',
        description: 'Default profile for SAST',
        scanType: 'SAST',
        triggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
        triggerSettings: [
          {
            triggerType: 'MERGE_REQUEST_PIPELINE',
            configuration: buildSastConfiguration({
              excludedAnalyzers: ['semgrep'],
              excludedPaths: ['spec/'],
            }),
          },
          {
            triggerType: 'DEFAULT_BRANCH_PIPELINE',
            configuration: buildSastConfiguration({
              excludedAnalyzers: ['semgrep'],
            }),
          },
        ],
      };
      createComponent({ resolver: createSuccessResolver(sastProfile) });
      await waitForPromises();

      expect(findAdvancedConfiguration().props('rows')).toEqual([
        expect.objectContaining({ setting: 'excludedAnalyzers', value: ['semgrep'] }),
        expect.objectContaining({ setting: 'excludedPaths', varies: true }),
      ]);
    });

    it('shows rows for a dependency scanning profile', async () => {
      const configuration = buildDependencyScanningConfiguration({ secureLogLevel: 'DEBUG' });
      const dependencyScanningProfile = {
        ...mockProfile,
        name: 'Dependency Scanning Profile',
        description: 'Default profile for dependency scanning',
        scanType: 'DEPENDENCY_SCANNING',
        triggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
        triggerSettings: [
          { triggerType: 'MERGE_REQUEST_PIPELINE', configuration },
          { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration },
        ],
      };
      createComponent({ resolver: createSuccessResolver(dependencyScanningProfile) });
      await waitForPromises();

      expect(findAdvancedConfiguration().props('rows')).toEqual([
        expect.objectContaining({ setting: 'secureLogLevel', value: 'debug' }),
      ]);
    });

    it.each([
      [
        'a profile whose enabled triggers accept no settings',
        {
          triggers: ['GIT_PUSH_EVENT'],
          triggerSettings: [{ triggerType: 'GIT_PUSH_EVENT', configuration: null }],
        },
      ],
      [
        'a GitLab-managed profile',
        { gitlabRecommended: true, triggers: ['GIT_PUSH_EVENT'], triggerSettings: [] },
      ],
      ['a profile with no triggers', { triggers: [], triggerSettings: [] }],
      [
        'triggers that set nothing',
        {
          triggerSettings: [
            { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: buildConfiguration({}) },
            { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: buildConfiguration({}) },
          ],
        },
      ],
    ])('renders no advanced configuration for %s', async (name, overrides) => {
      createComponent({ resolver: createSuccessResolver({ ...mockProfile, ...overrides }) });
      await waitForPromises();

      expect(findAdvancedConfiguration().exists()).toBe(false);
      expect(wrapper.text()).not.toContain('Advanced configuration');
    });
  });

  describe('managed by', () => {
    it.each`
      description           | overrides                       | label
      ${'a GitLab-managed'} | ${{ gitlabRecommended: true }}  | ${'GitLab'}
      ${'a custom'}         | ${{ gitlabRecommended: false }} | ${'Acme'}
    `('shows $label for $description profile', async ({ overrides, label }) => {
      createComponent({ resolver: createSuccessResolver({ ...mockProfile, ...overrides }) });
      await waitForPromises();

      expect(wrapper.findByTestId('managed-by').text()).toBe(label);
    });
  });

  describe('event handling', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('emits close event when modal is closed', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('emits apply event with profile id when button is clicked', () => {
      findApplyButton().vm.$emit('click');

      expect(wrapper.emitted('apply')).toHaveLength(1);
      expect(wrapper.emitted('apply')[0]).toEqual([mockProfile.id]);
    });
  });

  describe('apollo query', () => {
    it('calls resolver with correct variables', async () => {
      const resolver = createSuccessResolver();
      createComponent({
        resolver,
        props: { profileId: 'gid://gitlab/Security::ScanProfile/secret_detection' },
      });
      await waitForPromises();

      expect(resolver).toHaveBeenCalledWith({
        id: 'gid://gitlab/Security::ScanProfile/secret_detection',
      });
    });

    it('handles query errors gracefully', async () => {
      createComponent({ resolver: createErrorResolver() });
      await waitForPromises();

      expect(findSkeletonLoader().exists()).toBe(false);
    });
  });

  describe('visibility prop', () => {
    it('passes visible true to modal by default', () => {
      createComponent();

      expect(findModal().props('visible')).toBe(true);
    });

    it('passes visible false to modal when prop is false', () => {
      createComponent({ props: { visible: false } });

      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('permissions', () => {
    it('shows lock icon and popover when user cannot apply profiles', async () => {
      createComponent({ canApplyProfiles: false });
      await waitForPromises();

      const button = findApplyButton();
      expect(button.props('disabled')).toBe(true);
      expect(button.html()).toContain('lock');
      expect(findInsufficientPermissionsPopover().exists()).toBe(true);
      expect(findInsufficientPermissionsPopover().props('target')).toBe('modal-apply-button');
    });

    it('does not show lock icon or popover when user can apply profiles', async () => {
      createComponent({ canApplyProfiles: true });
      await waitForPromises();

      const button = findApplyButton();
      expect(button.props('disabled')).toBe(false);
      expect(button.html()).not.toContain('lock');
    });

    it('hides apply button when profile is already attached', async () => {
      createComponent({ props: { isAttached: true } });
      await waitForPromises();

      expect(findApplyButton().exists()).toBe(false);
      expect(wrapper.text()).toContain('Currently active');
    });
  });

  describe.each([true, false])('when withApplyAction is %s', (withApplyAction) => {
    beforeEach(async () => {
      createComponent({ props: { withApplyAction } });
      await waitForPromises();
    });

    it(`${withApplyAction ? 'shows' : 'hides'} the apply button`, () => {
      expect(findApplyButton().exists()).toBe(withApplyAction);
    });
  });
});
