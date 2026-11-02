export const DASHBOARD_CACHE_CONFIG = {
  typePolicies: {
    // Orbit has no ID, and every dashboard tab selects its own groups field of it.
    Orbit: { merge: true },
    // OrbitAccess and OrbitTrial have no ID, and the Off page and the owned-trials query select
    // different fields.
    OrbitAccess: { merge: true },
    OrbitTrial: { merge: true },
    OrbitNamespace: {
      merge: true,
      fields: {
        // Orbit returns a null status when it throttles or fails. Keeping the last one keeps the poll on.
        // A first write must store null, or Apollo treats the field as missing and refetches.
        indexing: { merge: (existing, incoming) => incoming ?? existing ?? null },
      },
    },
  },
};
