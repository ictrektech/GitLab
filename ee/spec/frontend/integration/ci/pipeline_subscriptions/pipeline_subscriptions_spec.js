import downstreamFixture from 'test_fixtures/graphql/ci/pipeline_subscriptions/integration/get_downstream_subscriptions.query.graphql.json';
import subscribedFixture from 'test_fixtures/graphql/ci/pipeline_subscriptions/integration/get_upstream_subscriptions_subscribed.query.graphql.json';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import { resetPipelineSubscriptionsCache } from './handlers';
import addPipelineSubscriptionVariants from './fixture_variants/add_pipeline_subscription';
import {
  PROJECT_PATH,
  deleteSubscription,
  expectAlert,
  expectSectionCount,
  findAlerts,
  findDeleteButton,
  findDownstreamSection,
  findSubscriptionRows,
  findUpstreamSection,
  mountPipelineSubscriptionsApp,
  subscribeTo,
} from './test_setup';

const { downstreamProject } = downstreamFixture.data.project.ciSubscribedProjects.nodes[0];
const { upstreamProject } = subscribedFixture.data.project.ciSubscriptionsProjects.nodes[0];
const upstreamProjectPath = new URL(upstreamProject.webUrl).pathname.slice(1);

const NOT_FOUND_MESSAGE = addPipelineSubscriptionVariants.NOT_FOUND.errors[0].message;
const CREATED_MESSAGE = 'Subscription successfully created.';
const DELETED_MESSAGE = 'Subscription successfully deleted.';
const UPSTREAM_EMPTY_TEXT = 'This project is not subscribed to any project pipelines.';

const expectUpstreamToBeEmpty = async () => {
  await expectSectionCount(findUpstreamSection, 0);

  expect(getText(findUpstreamSection())).toContain(UPSTREAM_EMPTY_TEXT);
  expect(findSubscriptionRows(findUpstreamSection())).toHaveLength(0);
};

describe('Pipeline subscriptions settings', () => {
  beforeEach(() => {
    resetPipelineSubscriptionsCache();
    mountPipelineSubscriptionsApp();
  });

  describe('projects subscribed to this project', () => {
    beforeEach(async () => {
      await expectSectionCount(findDownstreamSection, 1);
    });

    it('lists the downstream project with its namespace', () => {
      const text = getText(findDownstreamSection());

      expect(text).toContain(downstreamProject.name);
      expect(text).toContain(downstreamProject.namespace.name);
    });

    it('does not offer to delete the subscription', () => {
      expect(findSubscriptionRows(findDownstreamSection())).toHaveLength(1);
      expect(findDeleteButton()).toBe(null);
    });
  });

  describe('upstream subscriptions', () => {
    it('shows the empty state', async () => {
      await expectUpstreamToBeEmpty();
    });

    describe('when subscribing to an upstream project', () => {
      // Wait for the refetch the mutation triggers, so a test cannot end with it in flight
      // and have its response land in the next test's fresh Apollo cache.
      beforeEach(async () => {
        await expectUpstreamToBeEmpty();
        await subscribeTo(upstreamProjectPath);
        await expectSectionCount(findUpstreamSection, 1);
      });

      it('sends the typed path for this project', () => {
        expect(lastRequestVariables('addPipelineSubscription').input).toEqual({
          projectPath: PROJECT_PATH,
          upstreamPath: upstreamProjectPath,
        });
      });

      it('shows the success alert', () => {
        expect(findAlerts()).toEqual([CREATED_MESSAGE]);
      });

      it('lists the new subscription with its namespace', () => {
        const text = getText(findUpstreamSection());

        expect(text).toContain(upstreamProject.name);
        expect(text).toContain(upstreamProject.namespace.name);
      });

      describe('when the subscription is deleted', () => {
        beforeEach(async () => {
          await deleteSubscription();
          await expectSectionCount(findUpstreamSection, 0);
        });

        it('shows the deleted alert', () => {
          expect(findAlerts()).toContain(DELETED_MESSAGE);
        });

        it('returns to the empty state', () => {
          expect(getText(findUpstreamSection())).toContain(UPSTREAM_EMPTY_TEXT);
          expect(findSubscriptionRows(findUpstreamSection())).toHaveLength(0);
        });
      });
    });

    describe('when the upstream project path cannot be found', () => {
      beforeEach(async () => {
        setQueryVariant(addPipelineSubscriptionVariants).notFound();

        await expectUpstreamToBeEmpty();
        await subscribeTo('wrong/path');
        await expectAlert(NOT_FOUND_MESSAGE);
      });

      it('shows only the server error', () => {
        expect(findAlerts()).toEqual([NOT_FOUND_MESSAGE]);
      });

      it('keeps the list empty', async () => {
        await expectUpstreamToBeEmpty();
      });
    });
  });
});
