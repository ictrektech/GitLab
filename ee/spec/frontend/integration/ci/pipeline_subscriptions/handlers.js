import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import addPipelineSubscriptionVariants from './fixture_variants/add_pipeline_subscription';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/ci/pipeline_subscriptions/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

let upstreamCache = fixtures.getUpstreamSubscriptions;

export function resetPipelineSubscriptionsCache() {
  upstreamCache = fixtures.getUpstreamSubscriptions;
}

const OPERATION_HANDLERS = {
  getUpstreamSubscriptions: () => upstreamCache,
  getDownstreamSubscriptions: () => fixtures.getDownstreamSubscriptions,
  addPipelineSubscription: () => {
    const variant = getActiveVariant('addPipelineSubscription');
    if (variant) return variant;

    upstreamCache = fixtures.getUpstreamSubscriptionsSubscribed;
    return addPipelineSubscriptionVariants.BASE;
  },
  deletePipelineSubscription: () => {
    upstreamCache = fixtures.getUpstreamSubscriptions;
    return fixtures.deletePipelineSubscription;
  },
};

export function handlePipelineSubscriptionsOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const pipelineSubscriptionsRestEndpoints = [];
