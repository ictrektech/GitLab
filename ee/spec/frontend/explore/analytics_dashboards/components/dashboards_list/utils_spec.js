import { getDashboardsListFields } from 'ee/explore/analytics_dashboards/components/dashboards_list/utils';

describe('dashboards list utils', () => {
  describe('getDashboardsListFields', () => {
    const keys = () => getDashboardsListFields().map(({ key }) => key);

    it('includes the last edited column when customDashboardStorage is enabled', () => {
      gon.features = { customDashboardStorage: true };

      expect(keys()).toEqual(['name', 'author', 'updatedAt', 'actions']);
    });

    it.each([{ customDashboardStorage: false }, {}, undefined])(
      'omits the last edited column when gon.features is %o',
      (features) => {
        gon.features = features;

        expect(keys()).toEqual(['name', 'author', 'actions']);
      },
    );
  });
});
