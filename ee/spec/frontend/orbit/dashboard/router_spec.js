import Vue from 'vue';
import VueRouter from 'vue-router';
import createDashboardRouter from 'ee/orbit/dashboard/router';

Vue.use(VueRouter);

describe('Orbit dashboard router', () => {
  let router;

  // A redirect rejects the push promise and, without a handler, vue-router logs a warning.
  const push = (location) => router.push(location).catch(() => {});

  beforeEach(() => {
    router = createDashboardRouter('/dashboard/orbit');
    router.onError(() => {});
  });

  it.each(['/', '/explore', '/configuration', '/nope'])(
    'redirects %s to Overview',
    async (path) => {
      await push(path);

      expect(router.currentRoute.name).toBe('overview');
    },
  );

  describe('when an old Explore link names an entity', () => {
    beforeEach(() => push('/explore?panel=map&entity=Project'));

    it('opens Overview with the entity in the query', () => {
      expect(router.currentRoute.name).toBe('overview');
      expect(router.currentRoute.query).toEqual({ panel: 'map', entity: 'Project' });
    });
  });

  describe('when the user opens /query', () => {
    beforeEach(() => push('/query'));

    it('opens the Query editor', () => {
      expect(router.currentRoute.name).toBe('query');
    });
  });

  describe('when the user opens /schema', () => {
    beforeEach(() => push('/schema'));

    it('opens Schema', () => {
      expect(router.currentRoute.name).toBe('schema');
    });
  });

  describe('when the user opens /group-status', () => {
    beforeEach(() => push('/group-status'));

    it('opens Status', () => {
      expect(router.currentRoute.name).toBe('group_status');
    });
  });
});
