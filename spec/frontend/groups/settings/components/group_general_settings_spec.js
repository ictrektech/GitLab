import { GlFormInput, GlFormTextarea, GlButton } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import GroupGeneralSettings from '~/groups/settings/components/group_general_settings.vue';
import GroupSettingsReadme from '~/groups/settings/components/group_settings_readme.vue';
import AvatarUploadDropzone from '~/vue_shared/components/avatar_upload_dropzone.vue';
import RepositorySizeLimitRegistrationCta from '~/groups_projects/components/repository_size_limit_registration_cta.vue';
import VisibilityLevelRadioButtons from '~/visibility_level/components/visibility_level_radio_buttons.vue';
import {
  GROUP_VISIBILITY_LEVEL_DESCRIPTIONS,
  VISIBILITY_LEVEL_INTERNAL_INTEGER,
  VISIBILITY_LEVEL_PRIVATE_INTEGER,
  VISIBILITY_LEVEL_PUBLIC_INTEGER,
} from '~/visibility_level/constants';

jest.mock('~/lib/utils/csrf', () => ({
  token: 'mock-csrf-token',
}));

// Explicit stub so the async `ee_component` import behaves the same in EE and
// FOSS test runs.
const RepositorySizeLimitFieldStub = {
  name: 'RepositorySizeLimitField',
  props: ['value', 'helpText', 'fieldNamePrefix'],
  template: '<div data-testid="repository-size-limit-field"></div>',
};

describe('GroupGeneralSettings', () => {
  let wrapper;

  const defaultProps = {
    groupId: 22,
    groupName: 'Test Group',
    groupDescription: 'Test description',
    groupAvatarUrl: 'https://example.com/avatar.png',
    groupAvatarRemovable: true,
    maxDescriptionLength: 500,
    formAction: '/groups/test-group',
    groupPath: 'test-group',
    groupReadmePath: '',
    readmeProjectPath: '',
    visibilityLevel: VISIBILITY_LEVEL_PRIVATE_INTEGER,
    visibilityLevels: [
      VISIBILITY_LEVEL_PRIVATE_INTEGER,
      VISIBILITY_LEVEL_INTERNAL_INTEGER,
      VISIBILITY_LEVEL_PUBLIC_INTEGER,
    ],
    visibilityLevelDescriptions: GROUP_VISIBILITY_LEVEL_DESCRIPTIONS,
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GroupGeneralSettings, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      stubs: {
        RepositorySizeLimitField: RepositorySizeLimitFieldStub,
      },
    });
  };

  const createFullComponent = (props = {}) => {
    wrapper = mountExtended(GroupGeneralSettings, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      stubs: {
        AvatarUploadDropzone: true,
        GroupSettingsReadme: true,
        RepositorySizeLimitField: RepositorySizeLimitFieldStub,
      },
    });
  };

  const findForm = () => wrapper.find('form');
  const findNameInput = () => wrapper.findComponent(GlFormInput);
  const findIdInput = () => wrapper.findAllComponents(GlFormInput).at(1);
  const findDescriptionTextarea = () => wrapper.findComponent(GlFormTextarea);
  const findAvatarUploadDropzone = () => wrapper.findComponent(AvatarUploadDropzone);
  const findReadme = () => wrapper.findComponent(GroupSettingsReadme);
  const findSaveButton = () => wrapper.findComponent(GlButton);
  const findSizeLimitField = () => wrapper.findComponent(RepositorySizeLimitFieldStub);
  const findCta = () => wrapper.findComponent(RepositorySizeLimitRegistrationCta);
  const findAvatarRemovalInput = () => wrapper.find('input[name="group[avatar]"][type="hidden"]');
  const findVisibilityRadios = () => wrapper.findComponent(VisibilityLevelRadioButtons);
  const findVisibilityReadonly = () => wrapper.findByTestId('group-visibility-level-readonly');

  const submitForm = async () => {
    const submitEvent = new Event('submit', { cancelable: true, bubbles: true });
    const preventDefaultSpy = jest.spyOn(submitEvent, 'preventDefault');

    findForm().element.dispatchEvent(submitEvent);
    await nextTick();

    return preventDefaultSpy;
  };

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the form with the correct attributes', () => {
      expect(findForm().attributes()).toMatchObject({
        action: '/groups/test-group',
        method: 'post',
        enctype: 'multipart/form-data',
      });
    });

    it('renders hidden form fields for Rails', () => {
      const hiddenInputsData = wrapper
        .findAll('input[type="hidden"]')
        .wrappers.map((w) => ({ name: w.attributes('name'), value: w.attributes('value') }));

      expect(hiddenInputsData).toEqual(
        expect.arrayContaining([
          { name: 'authenticity_token', value: 'mock-csrf-token' },
          { name: '_method', value: 'put' },
          { name: 'update_section', value: 'js-general-settings' },
        ]),
      );
    });

    it('renders the group name input', () => {
      expect(findNameInput().attributes()).toMatchObject({
        name: 'group[name]',
        value: 'Test Group',
        maxlength: '255',
      });
    });

    it('renders the group ID field as readonly so it stays copyable', () => {
      expect(findIdInput().attributes('value')).toBe('22');
      expect(findIdInput().attributes('readonly')).toBeDefined();
      expect(findIdInput().attributes('disabled')).toBeUndefined();
    });

    it('renders the description textarea', () => {
      expect(findDescriptionTextarea().attributes('name')).toBe('group[description]');
      expect(findDescriptionTextarea().attributes('value')).toBe('Test description');
      expect(findDescriptionTextarea().props('characterCountLimit')).toBe(500);
    });

    it('renders the avatar upload dropzone with the correct props', () => {
      expect(findAvatarUploadDropzone().props()).toMatchObject({
        value: 'https://example.com/avatar.png',
        label: 'Group avatar',
        inputFieldName: 'group[avatar]',
        canRemove: true,
      });
    });

    it('renders the group README component with the correct props', () => {
      expect(findReadme().props()).toEqual({
        groupReadmePath: '',
        readmeProjectPath: '',
        groupPath: 'test-group',
        groupId: '22',
      });
    });

    it('renders the save button disabled while the form is clean', () => {
      expect(findSaveButton().text()).toBe('Save changes');
      expect(findSaveButton().props('disabled')).toBe(true);
    });
  });

  describe('name validation', () => {
    it('shows the rule error and disables saving for an invalid name', async () => {
      createComponent();

      findNameInput().vm.$emit('input', '-starts-with-dash');
      await nextTick();

      expect(findNameInput().props('state')).toBe(false);
      expect(findSaveButton().props('disabled')).toBe(true);
    });

    it('shows the required error for an empty name', async () => {
      createFullComponent();

      findNameInput().vm.$emit('input', '');
      await nextTick();

      expect(wrapper.text()).toContain('Group name is required.');
    });

    it('prevents submission when the name is invalid', async () => {
      createComponent();

      findNameInput().vm.$emit('input', '-invalid');
      await nextTick();

      expect(await submitForm()).toHaveBeenCalled();
    });
  });

  describe('character counter', () => {
    it('renders the remaining character count', () => {
      // 'Test description' is 16 characters, so 500 - 16 = 484 remain.
      createFullComponent();

      expect(wrapper.text()).toContain('484 characters remaining');
    });

    it('disables saving when the description is over the limit', async () => {
      createComponent({ groupDescription: 'a'.repeat(600) });

      findNameInput().vm.$emit('input', 'Changed Name');
      await nextTick();

      expect(findSaveButton().props('disabled')).toBe(true);
      expect(await submitForm()).toHaveBeenCalled();
    });
  });

  describe('avatar', () => {
    it('adds a hidden removal field and unnames the file input when removed', async () => {
      createComponent();

      findAvatarUploadDropzone().vm.$emit('input', null);
      await nextTick();

      expect(findAvatarRemovalInput().attributes('value')).toBe('');
      expect(findAvatarUploadDropzone().props('inputFieldName')).toBe('');
      expect(findSaveButton().props('disabled')).toBe(false);
    });

    it('restores the persisted avatar when a staged file is discarded', async () => {
      createComponent();
      const file = new File(['avatar'], 'avatar.png', { type: 'image/png' });

      findAvatarUploadDropzone().vm.$emit('input', file);
      await nextTick();
      expect(findSaveButton().props('disabled')).toBe(false);

      findAvatarUploadDropzone().vm.$emit('input', null);
      await nextTick();

      expect(findAvatarUploadDropzone().props('value')).toBe(defaultProps.groupAvatarUrl);
      expect(findAvatarRemovalInput().exists()).toBe(false);
      expect(findSaveButton().props('disabled')).toBe(true);
    });
  });

  describe('repository size limit', () => {
    it('renders neither field nor CTA by default', () => {
      createComponent();

      expect(findSizeLimitField().exists()).toBe(false);
      expect(findCta().exists()).toBe(false);
    });

    it('renders the EE field with the group prefix when editable', () => {
      createComponent({
        canEditRepositorySizeLimit: true,
        repositorySizeLimitValue: 100,
        repositorySizeLimitHelpText: 'Help',
      });

      expect(findSizeLimitField().props()).toMatchObject({
        value: 100,
        helpText: 'Help',
        fieldNamePrefix: 'group',
      });
      expect(findCta().exists()).toBe(false);
    });

    it('marks the form dirty when the size limit changes', async () => {
      createComponent({ canEditRepositorySizeLimit: true, repositorySizeLimitValue: 100 });

      findSizeLimitField().vm.$emit('input', 200);
      await nextTick();

      expect(findSaveButton().props('disabled')).toBe(false);
    });

    it.each`
      initialValue | value
      ${null}      | ${''}
      ${100}       | ${'100'}
    `(
      'does not mark the form dirty when $initialValue is edited back to $value',
      async ({ initialValue, value }) => {
        createComponent({
          canEditRepositorySizeLimit: true,
          repositorySizeLimitValue: initialValue,
        });

        findSizeLimitField().vm.$emit('input', 5);
        await nextTick();
        findSizeLimitField().vm.$emit('input', value);
        await nextTick();

        expect(findSaveButton().props('disabled')).toBe(true);
      },
    );

    it('renders the registration features CTA with the group prefix', () => {
      createComponent({
        showRepositorySizeLimitCta: true,
        servicePingSettingsPath: '/admin/settings',
      });

      expect(findCta().props()).toEqual({
        fieldNamePrefix: 'group',
        servicePingSettingsPath: '/admin/settings',
      });
    });
  });

  describe('visibility level', () => {
    const disabledVisibilityLevels = {
      [VISIBILITY_LEVEL_PUBLIC_INTEGER]:
        'Not allowed because a child of Test Group is public. %{linkStart}Learn more%{linkEnd}.',
    };

    describe('when the user can change the visibility level', () => {
      beforeEach(() => {
        createComponent({ canChangeVisibilityLevel: true, disabledVisibilityLevels });
      });

      it('renders the shared radio buttons bound to the group field', () => {
        expect(findVisibilityRadios().props()).toMatchObject({
          checked: VISIBILITY_LEVEL_PRIVATE_INTEGER,
          name: 'group[visibility_level]',
          visibilityLevels: defaultProps.visibilityLevels,
          visibilityLevelDescriptions: GROUP_VISIBILITY_LEVEL_DESCRIPTIONS,
          disabledVisibilityLevels,
        });
        expect(findVisibilityReadonly().exists()).toBe(false);
      });

      it('marks the form dirty when the visibility level changes', async () => {
        findVisibilityRadios().vm.$emit('input', VISIBILITY_LEVEL_INTERNAL_INTEGER);
        await nextTick();

        expect(findVisibilityRadios().props('checked')).toBe(VISIBILITY_LEVEL_INTERNAL_INTEGER);
        expect(findSaveButton().props('disabled')).toBe(false);
      });
    });

    it('renders the disabled reason with a documentation link', () => {
      createFullComponent({ canChangeVisibilityLevel: true, disabledVisibilityLevels });

      const reason = wrapper.findByTestId('visibility-level-disabled-reason');

      expect(reason.text()).toMatchInterpolatedText(
        'Not allowed because a child of Test Group is public. Learn more.',
      );
      expect(reason.find('a').attributes('href')).toBe('/help/user/public_access');
    });

    it('renders the documentation link in the label description', () => {
      createFullComponent();

      const field = wrapper.findByTestId('group-visibility-level-field');
      const link = field.find('a[href="/help/user/public_access"]');

      expect(link.text()).toBe('Learn about visibility levels.');
      expect(field.text()).not.toContain('%{');
    });

    it('renders the current level read-only when the user cannot change it', () => {
      createFullComponent();

      expect(findVisibilityRadios().exists()).toBe(false);
      expect(findVisibilityReadonly().text()).toMatchInterpolatedText(
        'Private The group and its projects can only be viewed by members.',
      );
      expect(wrapper.find('input[name="group[visibility_level]"]').exists()).toBe(false);
    });
  });

  describe('form submission', () => {
    it('submits natively and shows the saving state when valid', async () => {
      createComponent();

      findNameInput().vm.$emit('input', 'Changed Name');
      await nextTick();

      expect(await submitForm()).not.toHaveBeenCalled();
      expect(findSaveButton().text()).toBe('Saving changes');
      expect(findSaveButton().props('loading')).toBe(true);
    });

    it('disables saving again when fields are reverted', async () => {
      createComponent();

      findNameInput().vm.$emit('input', 'New Name');
      await nextTick();
      findNameInput().vm.$emit('input', 'Test Group');
      await nextTick();

      expect(findSaveButton().props('disabled')).toBe(true);
    });
  });
});
