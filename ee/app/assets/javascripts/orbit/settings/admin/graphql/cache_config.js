export const ADMIN_CACHE_CONFIG = {
  typePolicies: {
    // OrbitNamespace has no ID, and the orbitUpdate payload selects only `enabled` of it.
    OrbitNamespace: { merge: true },
    // Orbit has no ID, and the group and exclusion queries both select fields of it.
    Orbit: {
      merge: true,
      fields: {
        excludedGroups: {
          keyArgs: false,
          merge(existing, incoming, { args }) {
            if (!existing || !args?.after) return incoming;
            if (!incoming) return existing;

            return { ...incoming, nodes: [...existing.nodes, ...incoming.nodes] };
          },
        },
      },
    },
  },
};
