import { DASHBOARD_CACHE_CONFIG } from 'ee/orbit/dashboard/graphql/cache_config';

describe('DASHBOARD_CACHE_CONFIG OrbitNamespace.indexing', () => {
  const { merge } = DASHBOARD_CACHE_CONFIG.typePolicies.OrbitNamespace.fields.indexing;
  const ready = { state: 'READY', areas: [] };

  describe('when Orbit returns a status', () => {
    it('uses the new status', () => {
      expect(merge({ state: 'INDEXING', areas: [] }, ready)).toBe(ready);
    });
  });

  describe('when Orbit throttles or fails after a status loaded', () => {
    it('keeps the last status', () => {
      expect(merge(ready, null)).toBe(ready);
    });
  });

  describe('when the first load has no status', () => {
    it('stores null', () => {
      expect(merge(undefined, null)).toBeNull();
    });
  });
});
