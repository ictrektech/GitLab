import createRouter from '~/explore/analytics_dashboards/router';
import DashboardEdit from 'ee/explore/analytics_dashboards/pages/edit.vue';

// Vue Router 3 returns { route } from resolve(), Vue Router 4 returns the route directly.
const resolveRoute = (router, path) => {
  const resolved = router.resolve(path);
  return resolved.route ?? resolved;
};

describe('EE analytics dashboards router', () => {
  const basePath = '/explore/analytics_dashboards';
  const breadcrumbState = { name: 'Some dashboard', slug: '3' };

  let router;

  const getRouteNames = () => router.options.routes.map(({ name }) => name);

  describe('dashboard-edit route', () => {
    describe('when the customDashboardStorage feature flag is enabled', () => {
      beforeEach(() => {
        gon.features = { customDashboardStorage: true };
        router = createRouter(basePath, breadcrumbState);
      });

      it('is registered when the router is constructed', () => {
        expect(getRouteNames()).toContain('dashboard-edit');
      });

      it('matches a custom dashboard ID', () => {
        const route = resolveRoute(router, '/3/edit');

        expect(route.name).toBe('dashboard-edit');
        expect(route.params.slug).toBe('3');
        expect(route.matched[0].components.default).toBe(DashboardEdit);
      });

      it('returns the breadcrumb name from breadcrumbState', () => {
        const route = resolveRoute(router, '/3/edit');

        expect(route.meta.getName()).toBe('Edit');
      });

      it('returns the parent breadcrumbs from breadcrumbState', () => {
        const route = resolveRoute(router, '/3/edit');

        expect(route.meta.getParents()).toEqual([{ text: 'Some dashboard', to: '/3' }]);
      });
    });

    describe('when the customDashboardStorage feature flag is disabled', () => {
      beforeEach(() => {
        gon.features = { customDashboardStorage: false };
        router = createRouter(basePath, breadcrumbState);
      });

      it('is not registered when the router is constructed', () => {
        expect(getRouteNames()).not.toContain('dashboard-edit');
      });

      it('redirects the edit path to the root list route', async () => {
        await router.push('/3/edit');

        // Vue Router 4 exposes currentRoute as a ref
        const currentRoute = router.currentRoute.value ?? router.currentRoute;
        expect(currentRoute.name).toBe('root');
      });
    });
  });
});
