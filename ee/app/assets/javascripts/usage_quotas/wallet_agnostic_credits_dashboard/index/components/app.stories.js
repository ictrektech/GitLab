import VueApollo from 'vue-apollo';
import {
  mockSubscriptionCreditsUsageData,
  mockSubscriptionNonBillableUsageData,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/mock_data';
import { createMockClient } from 'helpers/mock_apollo_helper';
import subscriptionCreditsUsageQuery from '../graphql/get_subscription_credits_usage_overview.query.graphql';
import subscriptionNonBillableUsageQuery from '../graphql/get_subscription_non_billable_usage.query.graphql';
import WalletAgnosticCreditsDashboard from './app.vue';

const mockData = mockSubscriptionCreditsUsageData.data.subscriptionUsage;

const mockResponse = (overrides = {}) => ({
  data: { subscriptionUsage: { ...mockData, ...overrides } },
});

const meta = {
  title: 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index/components/app',
  component: WalletAgnosticCreditsDashboard,
};

export default meta;

const createTemplate = (config = {}) => {
  const {
    queryHandler = () => Promise.resolve(mockResponse()),
    nonBillableUsageHandler = () => Promise.resolve(mockSubscriptionNonBillableUsageData),
  } = config;

  const resolvers = {};

  const defaultClient = createMockClient(
    [
      [subscriptionCreditsUsageQuery, queryHandler],
      [subscriptionNonBillableUsageQuery, nonBillableUsageHandler],
    ],
    resolvers,
  );

  const apolloProvider = new VueApollo({ defaultClient });

  window.gon.display_gitlab_credits_user_data = config.display_gitlab_credits_user_data ?? true;
  window.gon.features = config.features ?? { creditCapsUi: true };

  return (args, { argTypes }) => ({
    apolloProvider,
    components: {
      WalletAgnosticCreditsDashboard,
    },
    provide: {
      namespacePath: 'gitlab-org',
      userUsagePath: '/gitlab-org/-/usage_quotas/usage_billing/users/__USERNAME__',
      ...config.provide,
    },
    props: Object.keys(argTypes),
    template: `<wallet-agnostic-credits-dashboard />`,
  });
};

export const Default = {
  render: createTemplate(),
};

export const WithoutNonBillableUsage = {
  render: (...args) =>
    createTemplate({
      nonBillableUsageHandler: () =>
        Promise.resolve({
          data: {
            subscriptionUsage: { __typename: 'GitlabSubscriptionUsage', nonBillableUsage: [] },
          },
        }),
    })(...args),
};

export const EmptyDailyUsage = {
  render: (...args) =>
    createTemplate({
      queryHandler: () => Promise.resolve(mockResponse({ dailyUsage: [], creditsUsed: null })),
    })(...args),
};

export const LoadingState = {
  render: (...args) => {
    const queryHandler = () => new Promise(() => {});

    return createTemplate({ queryHandler })(...args);
  },
};

export const ErrorState = {
  render: (...args) => {
    const queryHandler = () => Promise.reject(new Error('Failed to fetch credit usage data'));

    return createTemplate({ queryHandler })(...args);
  },
};

export const UsageBillingDisabled = {
  render: (...args) =>
    createTemplate({
      queryHandler: () => Promise.resolve(mockResponse({ enabled: false })),
    })(...args),
};

export const OutdatedClient = {
  render: (...args) => {
    const originalGon = window.gon;
    window.gon = { ...window.gon, subscriptions_url: 'https://customers.gitlab.com' };

    return {
      ...createTemplate({
        queryHandler: () => Promise.resolve(mockResponse({ isOutdatedClient: true })),
      })(...args),
      beforeDestroy() {
        window.gon = originalGon;
      },
    };
  },
};
