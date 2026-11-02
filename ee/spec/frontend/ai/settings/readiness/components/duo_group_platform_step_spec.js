import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupPlatformStep from 'ee/ai/settings/readiness/components/duo_group_platform_step.vue';
import { AVAILABILITY_OPTIONS } from 'ee/ai/settings/constants';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';

const ROOT_GROUP = {
  isSaaS: true,
  onGeneralSettingsPage: false,
  showDuoAgentPlatformEnablementSetting: true,
  duoAgentPlatformOwnerEnabled: true,
  rootAncestorName: 'my-group',
};

const SUBGROUP = {
  isSaaS: true,
  onGeneralSettingsPage: true,
  duoAgentPlatformOwnerEnabled: true,
  duoAgentPlatformOwnerSettingsPath: '/groups/my-group/-/settings/gitlab_duo/configuration',
  rootAncestorName: 'my-group',
};

const SELF_MANAGED = {
  ...SUBGROUP,
  isSaaS: false,
  duoAgentPlatformOwnerSettingsPath: '/admin/gitlab_duo/configuration',
};

const ALL_ON = {
  duoAvailability: AVAILABILITY_OPTIONS.DEFAULT_ON,
  duoAgentPlatformEnabled: true,
  duoCoreFeaturesEnabled: true,
  toolApprovalForSessionAvailability: AVAILABILITY_OPTIONS.DEFAULT_ON,
};

const LOCKED_BY_GROUP = {
  lockedByAncestor: true,
  lockedByApplicationSetting: false,
  ancestorNamespace: { fullName: 'my-group', path: '/my-group' },
};

const LOCKED_BY_INSTANCE = {
  lockedByAncestor: false,
  lockedByApplicationSetting: true,
};

const UNLOCKED = {
  lockedByAncestor: false,
  lockedByApplicationSetting: false,
};

describe('DuoGroupPlatformStep', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = ROOT_GROUP } = {}) => {
    wrapper = shallowMountExtended(DuoGroupPlatformStep, {
      propsData: { ...ALL_ON, ...props },
      provide,
      stubs: { DuoReadinessRow },
    });
  };

  const findRow = (testId) =>
    wrapper
      .findAllComponents(DuoReadinessRow)
      .wrappers.find((row) => row.attributes('data-testid') === testId);
  const findSeatlessAccessToggle = () => wrapper.findComponentByTestId('seatless-access-toggle');
  const findToggleDescription = (toggle) => wrapper.find(`#${toggle.props('ariaDescribedby')}`);

  describe('GitLab Duo row', () => {
    it('shows the selected option and its help text', () => {
      createComponent({ props: { duoAvailability: AVAILABILITY_OPTIONS.DEFAULT_OFF } });

      expect(findRow('duo-row').props('status')).toBe('done');
      expect(wrapper.findComponentByTestId('duo-availability-listbox').props()).toMatchObject({
        selected: AVAILABILITY_OPTIONS.DEFAULT_OFF,
        toggleText: 'Off by default',
        disabled: false,
      });
      expect(findRow('duo-row').props('description')).toBe(
        'AI-native features are off for every project in this group. Subgroups and projects can opt in individually.',
      );
      expect(findRow('duo-row').find('[data-testid="readiness-row-note"]').exists()).toBe(false);
    });

    it('is todo while GitLab Duo is always off', () => {
      createComponent({ props: { duoAvailability: AVAILABILITY_OPTIONS.NEVER_ON } });

      expect(findRow('duo-row').props('status')).toBe('todo');
    });

    it('emits the new availability', () => {
      createComponent();

      wrapper
        .findComponentByTestId('duo-availability-listbox')
        .vm.$emit('select', AVAILABILITY_OPTIONS.NEVER_ON);

      expect(wrapper.emitted('change-duo-availability')).toEqual([[AVAILABILITY_OPTIONS.NEVER_ON]]);
    });

    it.each`
      provide         | lock                  | adminLocked | note
      ${SUBGROUP}     | ${LOCKED_BY_GROUP}    | ${false}    | ${'Inherited: On by default, set by an Owner of my-group.'}
      ${SELF_MANAGED} | ${LOCKED_BY_INSTANCE} | ${false}    | ${'Inherited: On by default, set by an instance administrator.'}
      ${ROOT_GROUP}   | ${UNLOCKED}           | ${true}     | ${'Inherited: On by default, set by an instance administrator.'}
    `('shows "$note" while the setting is locked', ({ provide, lock, adminLocked, note }) => {
      createComponent({
        provide: {
          ...provide,
          duoAvailabilityCascadingSettings: lock,
          duoAvailabilityAdminLocked: adminLocked,
        },
      });

      expect(findRow('duo-row').findComponent(CascadingLockIcon).exists()).toBe(true);
      expect(findRow('duo-row').find('[data-testid="readiness-row-note"]').text()).toBe(note);
      expect(wrapper.findComponentByTestId('duo-availability-listbox').props('disabled')).toBe(
        true,
      );
    });
  });

  describe('Agent Platform row', () => {
    it('renders a toggle for the owning root group', () => {
      createComponent();

      expect(wrapper.findComponentByTestId('platform-toggle').props('value')).toBe(true);
      expect(wrapper.findByTestId('platform-owner-link').exists()).toBe(false);
      expect(findRow('platform-row').props('description')).toBe(
        'Projects in this group can run agents and flows.',
      );
      expect(findRow('platform-row').find('[data-testid="readiness-row-note"]').exists()).toBe(
        false,
      );

      wrapper.findComponentByTestId('platform-toggle').vm.$emit('change', false);

      expect(wrapper.emitted('change-duo-agent-platform-enabled')).toEqual([[false]]);
    });

    it('asks the owning group to turn the platform on while it is off', () => {
      createComponent({ props: { duoAgentPlatformEnabled: false } });

      expect(findRow('platform-row').props('status')).toBe('todo');
      expect(findRow('platform-row').find('[data-testid="readiness-row-note"]').text()).toBe(
        'Turn on Agent Platform to change the settings below.',
      );
    });

    it.each`
      namespace         | provide         | linkText
      ${'subgroup'}     | ${SUBGROUP}     | ${'Group settings'}
      ${'self-managed'} | ${SELF_MANAGED} | ${'Admin settings'}
    `('links a $namespace to the owner settings', ({ provide, linkText }) => {
      createComponent({ provide });

      expect(wrapper.findByTestId('platform-toggle').exists()).toBe(false);
      expect(wrapper.findComponentByTestId('platform-owner-link').props('href')).toBe(
        provide.duoAgentPlatformOwnerSettingsPath,
      );
      expect(wrapper.findByTestId('platform-owner-link').text()).toBe(linkText);
      expect(wrapper.findComponentByTestId('platform-owner-link').props('icon')).toBe(
        'external-link',
      );
      expect(findRow('platform-row').props('description')).toBe(
        'Projects in this group can run agents and flows.',
      );
    });

    it('reads the owner value without a note when the owner has it off', () => {
      createComponent({ provide: { ...SUBGROUP, duoAgentPlatformOwnerEnabled: false } });

      expect(findRow('platform-row').props('status')).toBe('todo');
      expect(findRow('platform-row').props('description')).toBe(
        'Projects in this group can run agents and flows.',
      );
      expect(findRow('platform-row').find('[data-testid="readiness-row-note"]').exists()).toBe(
        false,
      );
    });

    it('renders no control when the user cannot reach the owner settings', () => {
      createComponent({ provide: { ...SUBGROUP, duoAgentPlatformOwnerSettingsPath: null } });

      expect(wrapper.findByTestId('platform-toggle').exists()).toBe(false);
      expect(wrapper.findByTestId('platform-owner-link').exists()).toBe(false);
    });
  });

  describe('settings nested under the Agent Platform', () => {
    it('shows Seatless access only on the configuration page', () => {
      createComponent();
      expect(findRow('seatless-access-row').exists()).toBe(true);

      createComponent({ provide: SUBGROUP });
      expect(findRow('seatless-access-row')).toBeUndefined();
    });

    it('keeps the values but disables the controls while the platform is off', () => {
      createComponent({ props: { duoAgentPlatformEnabled: false } });

      expect(findRow('seatless-access-row').props('disabled')).toBe(true);
      expect(findSeatlessAccessToggle().props()).toMatchObject({
        value: true,
        disabled: true,
        accessibleDisabled: true,
      });
      expect(findToggleDescription(findSeatlessAccessToggle()).text()).toBe(
        'Turn on Agent Platform to change the settings below.',
      );
      expect(findRow('tool-approval-row').props('disabled')).toBe(true);
      expect(wrapper.findComponentByTestId('tool-approval-listbox').props()).toMatchObject({
        selected: AVAILABILITY_OPTIONS.DEFAULT_ON,
        toggleText: 'On by default',
        disabled: true,
      });
    });

    it.each`
      state                               | provide
      ${'the platform is on'}             | ${ROOT_GROUP}
      ${'the owner has the platform off'} | ${{ ...SUBGROUP, onGeneralSettingsPage: false, duoAgentPlatformOwnerEnabled: false }}
    `('leaves Seatless access without a description when $state', ({ provide }) => {
      createComponent({ provide });

      expect(findSeatlessAccessToggle().props('ariaDescribedby')).toBeUndefined();
    });

    it('keeps the step and its nested rows enabled while GitLab Duo is always off', () => {
      createComponent({ props: { duoAvailability: AVAILABILITY_OPTIONS.NEVER_ON } });

      expect(findRow('platform-row').props('disabled')).toBe(false);
      expect(wrapper.findComponentByTestId('platform-toggle').props('disabled')).toBe(false);
      expect(findRow('seatless-access-row').props('disabled')).toBe(false);
      expect(wrapper.findComponentByTestId('tool-approval-listbox').props('disabled')).toBe(false);
    });

    it('emits the seatless access change', () => {
      createComponent();

      wrapper.findComponentByTestId('seatless-access-toggle').vm.$emit('change', false);

      expect(wrapper.emitted('change-duo-core-features-enabled')).toEqual([[false]]);
    });

    it('emits tool approval changes and shows no status', () => {
      createComponent();

      expect(findRow('tool-approval-row').props('status')).toBeNull();
      wrapper
        .findComponentByTestId('tool-approval-listbox')
        .vm.$emit('select', AVAILABILITY_OPTIONS.NEVER_ON);

      expect(wrapper.emitted('change-tool-approval-for-session')).toEqual([
        [AVAILABILITY_OPTIONS.NEVER_ON],
      ]);
    });

    it('locks tool approval when an ancestor locked the setting', () => {
      createComponent({
        provide: { ...SUBGROUP, toolApprovalForSessionCascadingSettings: LOCKED_BY_GROUP },
      });

      expect(findRow('tool-approval-row').findComponent(CascadingLockIcon).props()).toMatchObject({
        isLockedByGroupAncestor: true,
        ancestorNamespace: LOCKED_BY_GROUP.ancestorNamespace,
      });
      expect(wrapper.findComponentByTestId('tool-approval-listbox').props('disabled')).toBe(true);
    });
  });
});
