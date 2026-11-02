export const GROUP_SETTINGS_CACHE_CONFIG = {
  typePolicies: {
    // OrbitNamespace has no ID, and the orbitUpdate payload selects only `enabled` of it.
    OrbitNamespace: { merge: true },
  },
};
