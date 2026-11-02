import createRouter from 'ee/insights/insights_router';
import { useInsightsStore } from 'ee/insights/stores';
import { pinia } from '~/pinia/instance';

describe('insights router', () => {
  let router;
  let store;

  beforeEach(async () => {
    store = useInsightsStore(pinia);
    jest.spyOn(store, 'setActiveTab').mockImplementation(() => {});

    router = createRouter('base');
    await router.push('/initial');
  });

  it(`sets the activeTab when route changed`, async () => {
    const route = 'route';

    await router.push(`/${route}`);

    expect(store.setActiveTab).toHaveBeenCalledWith(route);
  });
});
