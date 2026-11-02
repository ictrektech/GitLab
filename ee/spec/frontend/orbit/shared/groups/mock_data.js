import { ALL_GROUP_ACTIONS } from 'ee/orbit/shared/groups/constants';

export const ENABLED_AT = '2026-10-01T10:00:00Z';

export const buildRow = ({ name = 'acme', ...overrides } = {}) => ({
  id: `gid://gitlab/Group/${name}`,
  name,
  fullPath: name,
  webPath: `/${name}`,
  avatarUrl: null,
  allowedActions: ALL_GROUP_ACTIONS,
  isOn: false,
  isExcluded: false,
  indexingState: null,
  indexingAreas: [],
  enabledAt: null,
  failure: null,
  note: null,
  ...overrides,
});
