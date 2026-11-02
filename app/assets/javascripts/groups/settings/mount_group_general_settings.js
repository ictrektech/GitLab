import Vue from 'vue';
import { parseBoolean } from '@gitlab/frontend-utils';
import GroupGeneralSettings from './components/group_general_settings.vue';

export default () => {
  const el = document.getElementById('js-group-general-settings');

  if (!el) {
    return null;
  }

  const {
    groupId,
    groupName,
    groupDescription,
    groupAvatarUrl,
    groupAvatarRemovable,
    maxDescriptionLength,
    formAction,
    groupPath,
    groupReadmePath,
    readmeProjectPath,
    canEditRepositorySizeLimit,
    repositorySizeLimitValue,
    repositorySizeLimitHelpText,
    showRepositorySizeLimitCta,
    servicePingSettingsPath,
    visibilityLevel,
    canChangeVisibilityLevel,
    visibilityLevels,
    visibilityLevelDescriptions,
    disabledVisibilityLevels,
  } = el.dataset;

  const parseJson = (value, fallback) => (value ? JSON.parse(value) : fallback);

  return new Vue({
    el,
    name: 'GroupGeneralSettingsRoot',
    render(createElement) {
      return createElement(GroupGeneralSettings, {
        props: {
          groupId: parseInt(groupId, 10),
          groupName,
          groupDescription: groupDescription || '',
          groupAvatarUrl: groupAvatarUrl || '',
          groupAvatarRemovable: parseBoolean(groupAvatarRemovable),
          maxDescriptionLength: parseInt(maxDescriptionLength, 10),
          formAction,
          groupPath,
          groupReadmePath: groupReadmePath || '',
          readmeProjectPath: readmeProjectPath || '',
          canEditRepositorySizeLimit: parseBoolean(canEditRepositorySizeLimit),
          repositorySizeLimitValue: repositorySizeLimitValue
            ? parseInt(repositorySizeLimitValue, 10)
            : null,
          repositorySizeLimitHelpText: repositorySizeLimitHelpText || '',
          showRepositorySizeLimitCta: parseBoolean(showRepositorySizeLimitCta),
          servicePingSettingsPath: servicePingSettingsPath || '',
          visibilityLevel: parseInt(visibilityLevel, 10),
          canChangeVisibilityLevel: parseBoolean(canChangeVisibilityLevel),
          visibilityLevels: parseJson(visibilityLevels, []),
          visibilityLevelDescriptions: parseJson(visibilityLevelDescriptions, {}),
          disabledVisibilityLevels: parseJson(disabledVisibilityLevels, {}),
        },
      });
    },
  });
};
