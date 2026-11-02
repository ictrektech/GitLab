// The dashboard reads aiGovernanceMetrics from three separate queries and
// aiGovernanceToolCalls from two, each pair agreeing on `timeframe` and
// `agentClass`, so Apollo keys them to one cache entry per field. Each query
// selects a disjoint set of fields, and the default behaviour replaces the
// whole object, dropping whichever fields arrived first.
export const cacheConfig = {
  typePolicies: {
    Group: {
      fields: {
        aiGovernanceMetrics: { merge: true },
        aiGovernanceToolCalls: { merge: true },
      },
    },
    Project: {
      fields: {
        aiGovernanceMetrics: { merge: true },
        aiGovernanceToolCalls: { merge: true },
      },
    },
  },
};
