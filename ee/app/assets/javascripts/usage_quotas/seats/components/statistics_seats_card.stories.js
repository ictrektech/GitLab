import { GlCard } from '@gitlab/ui';
import VueApollo from 'vue-apollo';
import StatisticsSeatsCard from 'ee/usage_quotas/seats/components/statistics_seats_card.vue';
import { getSubscriptionPermissionsData } from 'ee/fulfillment/shared_queries/subscription_actions_reason.customer.query.graphql';
import { createMockClient } from 'helpers/mock_apollo_helper';
import { createMockSubscriptionPermissionsResponse } from 'ee_jest/usage_quotas/seats/mock_data';

export default {
  component: StatisticsSeatsCard,
  title: 'ee/usage_quotas/seats/components/statistics_seats_card',
};

const createApolloProvider = () => {
  const defaultClient = createMockClient();
  const customersDotClient = createMockClient([
    [
      getSubscriptionPermissionsData,
      () => Promise.resolve(createMockSubscriptionPermissionsResponse({ canAddSeats: true })),
    ],
  ]);
  return new VueApollo({ defaultClient, clients: { customersDotClient } });
};

const Template = (_, { argTypes }) => ({
  components: { StatisticsSeatsCard, GlCard },
  props: Object.keys(argTypes),
  apolloProvider: createApolloProvider(),
  provide: {
    explorePlansPath: 'example.com',
    namespaceId: '42',
  },
  template: `<gl-card class="gl-w-1/2">
      <statistics-seats-card v-bind="$props">
      </statistics-seats-card>
     </gl-card>`,
});
export const Default = Template.bind({});

Default.args = {
  seatsUsed: 160,
  seatsOwed: 10,
  purchaseButtonLink: 'purchase.com/test',
};
