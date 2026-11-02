import { GlFormGroup, GlIcon, GlLink, GlModal, GlSprintf } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import InviteMembersModal from 'ee/organizations/access/components/invite_members_modal.vue';
import { RESOURCES } from 'ee/organizations/access/constants';
import MembersTokenSelect from '~/invite_members/components/members_token_select.vue';
import RoleSelector from '~/members/components/role_selector.vue';

const USER = { id: 7, name: 'Casey Wu', username: 'cwu', avatar_url: '/avatar.png' };

describe('OrganizationAccessInviteMembersModal', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(InviteMembersModal, {
      propsData: { resource: RESOURCES['artifact-registry'] },
      stubs: { GlFormGroup, GlSprintf },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findTokenSelect = () => wrapper.findComponent(MembersTokenSelect);
  const findRoleSelector = () => wrapper.findComponent(RoleSelector);
  const findUsersFormGroup = () => wrapper.findAllComponents(GlFormGroup).at(0);
  const findAccessSummary = () =>
    wrapper
      .findByTestId('access-summary')
      .findAll('li')
      .wrappers.map((item) => [item.findComponent(GlIcon).props('name'), item.text()]);
  const isInviteDisabled = () => findModal().props('actionPrimary').attributes.disabled;

  const selectUsers = async (users) => {
    findTokenSelect().vm.$emit('input', users);
    await nextTick();
  };
  const selectRole = async (value) => {
    findRoleSelector().vm.$emit('input', { value });
    await nextTick();
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the modal with its title and actions', () => {
    expect(findModal().props()).toMatchObject({
      modalId: 'organization-access-invite-members-modal',
      title: 'Invite members',
      actionPrimary: { text: 'Invite', attributes: { variant: 'confirm', disabled: true } },
      actionCancel: { text: 'Cancel' },
    });
  });

  it('names the resource in the intro', () => {
    expect(findModal().find('p').text()).toBe("You're inviting members to Artifact Registry.");
    expect(findModal().find('p strong').text()).toBe('Artifact Registry');
  });

  it('labels the user picker and turns off email invites', () => {
    expect(findUsersFormGroup().attributes('label')).toBe('GitLab usernames');
    expect(findTokenSelect().props()).toMatchObject({
      inputId: 'organization-access-invite-members-input',
      invalidMembers: {},
      allowEmails: false,
      noMatchesText: 'No matching organization members.',
    });
  });

  it('opens the user picker with no validation state', () => {
    expect(findTokenSelect().props('exceptionState')).toBeNull();
  });

  it('labels the role selector', () => {
    expect(wrapper.findAllComponents(GlFormGroup).at(1).attributes('labelfor')).toBe(
      'organization-access-invite-members-role',
    );
    expect(findRoleSelector().props('toggleId')).toBe('organization-access-invite-members-role');
  });

  it('links to the roles help page', () => {
    const link = wrapper.findComponent(GlLink);

    expect(link.text()).toBe('What are roles?');
    expect(link.attributes('href')).toBe('/help/user/permissions');
  });

  it('lists the resource roles with their descriptions', () => {
    const items = [
      {
        value: 'ARTIFACT_ADMIN',
        text: 'Artifact Admin',
        description: 'Manage repository configuration and access.',
      },
      {
        value: 'ARTIFACT_MANAGER',
        text: 'Artifact Manager',
        description: 'Manage artifacts and repository configuration.',
      },
      {
        value: 'ARTIFACT_CONTRIBUTOR',
        text: 'Artifact Contributor',
        description: 'Publish artifacts (for example, CI jobs).',
      },
      {
        value: 'ARTIFACT_VIEWER',
        text: 'Artifact Viewer',
        description: 'Pull and browse artifacts.',
      },
    ];

    expect(findRoleSelector().props('roles')).toEqual({ formatted: items, flatten: items });
    expect(findRoleSelector().props('headerText')).toBe('Select a role');
  });

  it('selects Artifact Viewer and shows its access summary by default', () => {
    expect(findRoleSelector().props('value').value).toBe('ARTIFACT_VIEWER');
    expect(findAccessSummary()).toEqual([
      ['check', 'View the list of artifacts and repositories in Artifact Registry'],
      ['check', 'View artifact metadata (tags, versions, size, upload date)'],
      ['check', 'Download or pull artifacts (for example, Docker pulls or package installs)'],
      ['close', 'Push, upload, or delete artifacts'],
      ['close', 'Manage roles and settings'],
    ]);
  });

  it('labels the access summary icons for screen readers', async () => {
    await selectRole('ARTIFACT_MANAGER');
    const icons = wrapper.findByTestId('access-summary').findAllComponents(GlIcon);

    expect(icons.wrappers.map((icon) => icon.props('ariaLabel'))).toEqual([
      'Allowed',
      'Allowed',
      'Allowed',
      'Not allowed',
    ]);
  });

  it('says Artifact Manager configures repositories but cannot manage roles', async () => {
    await selectRole('ARTIFACT_MANAGER');

    expect(findAccessSummary()).toEqual([
      ['check', 'Everything an Artifact Contributor can do'],
      ['check', 'Delete artifacts'],
      ['check', 'Configure repositories'],
      ['close', 'Manage roles'],
    ]);
  });

  describe('when a different role is selected', () => {
    beforeEach(async () => {
      await selectRole('ARTIFACT_ADMIN');
    });

    it('updates the role and access summary', () => {
      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_ADMIN');
      expect(findAccessSummary()).toEqual([
        ['check', 'Create and configure repositories'],
        ['check', 'Invite members and change their roles'],
        ['check', 'Remove members from Artifact Registry'],
      ]);
    });
  });

  describe('when a user is picked', () => {
    beforeEach(async () => {
      await selectUsers([USER]);
    });

    it('enables Invite', () => {
      expect(isInviteDisabled()).toBe(false);
    });

    it('disables Invite again when the picker is cleared', async () => {
      findTokenSelect().vm.$emit('clear');
      await nextTick();

      expect(isInviteDisabled()).toBe(true);
    });

    it('emits invite with the users and role on submit', async () => {
      await selectRole('ARTIFACT_CONTRIBUTOR');
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('invite')).toEqual([
        [{ users: [USER], role: 'ARTIFACT_CONTRIBUTOR' }],
      ]);
    });

    describe('when the modal is hidden', () => {
      beforeEach(async () => {
        await selectRole('ARTIFACT_ADMIN');
        findModal().vm.$emit('hidden');
        await nextTick();
      });

      it('resets the users and role', () => {
        expect(isInviteDisabled()).toBe(true);
        expect(findRoleSelector().props('value').value).toBe('ARTIFACT_VIEWER');
      });
    });
  });

  describe('when the picker holds text that is not picked yet', () => {
    beforeEach(async () => {
      await selectUsers([USER]);
      findTokenSelect().vm.$emit('tokenization-state-change', true);
      await nextTick();
    });

    it('disables Invite', () => {
      expect(isInviteDisabled()).toBe(true);
    });

    it('enables Invite once the text is picked or cleared', async () => {
      findTokenSelect().vm.$emit('tokenization-state-change', false);
      await nextTick();

      expect(isInviteDisabled()).toBe(false);
    });

    it('clears the pending state when the modal is hidden', async () => {
      findModal().vm.$emit('hidden');
      await selectUsers([USER]);

      expect(isInviteDisabled()).toBe(false);
    });
  });
});
