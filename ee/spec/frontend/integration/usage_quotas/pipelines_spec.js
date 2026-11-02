import { waitFor } from '@testing-library/vue';
import projectsFixture from 'test_fixtures/graphql/usage_quotas/pipelines/integration/get_projects_ci_minutes_usage.query.graphql.json';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  findNextButton,
  findPrevButton,
  findProjectNames,
  findProjectTable,
  findUsageSummary,
  mountPipelinesTab,
} from './test_setup';

const INSTANCE_RUNNERS_DISABLED_TEXT =
  'No compute usage data because Instance runners are disabled, or there are no projects in this group.';

const projectNames = projectsFixture.data.ciMinutesProjectMonthlyUsage.nodes.map(
  ({ project }) => project.nameWithNamespace,
);

const expectProjectNames = (names) => waitFor(() => expect(findProjectNames()).toEqual(names));

describe('Profile usage quotas pipelines tab', () => {
  describe('when instance runners are enabled', () => {
    describe('when the namespace has a compute minutes limit', () => {
      beforeEach(() => {
        mountPipelinesTab({
          ciMinutesMonthlyMinutesUsed: '1000',
          ciMinutesMonthlyMinutesUsedPercentage: '200',
          ciMinutesMonthlyMinutesLimit: '500',
        });
      });

      it('shows usage against the limit', async () => {
        const summary = await waitForElement(findUsageSummary);

        expect(getText(summary)).toBe('1,000 / 500 compute minutes');
      });

      it('lists the projects using compute minutes', async () => {
        await expectProjectNames(projectNames);

        expect(getText(findProjectTable())).not.toContain(INSTANCE_RUNNERS_DISABLED_TEXT);
      });
    });

    describe('when the namespace has no compute minutes limit', () => {
      beforeEach(() => {
        mountPipelinesTab({
          ciMinutesDisplayMinutesAvailableData: 'false',
          ciMinutesMonthlyMinutesUsedPercentage: '0',
          ciMinutesMonthlyMinutesLimit: 'Unlimited',
        });
      });

      it('shows unlimited usage', async () => {
        const summary = await waitForElement(findUsageSummary);

        expect(getText(summary)).toBe('300 / Unlimited compute minutes');
      });
    });

    describe('when the projects span several pages', () => {
      beforeEach(async () => {
        mountPipelinesTab({ pageSize: '1' });
        await expectProjectNames([projectNames[0]]);
      });

      it('shows the next page when Next is clicked', async () => {
        await waitAndClick(findNextButton);
        await expectProjectNames([projectNames[1]]);

        await waitAndClick(findNextButton);
        await expectProjectNames([projectNames[2]]);

        expect(lastRequestVariables('getProjectsCiMinutesUsage')).toMatchObject({
          first: 1,
          after: expect.any(String),
        });
      });

      it('shows the previous page when Prev is clicked', async () => {
        await waitAndClick(findNextButton);
        await expectProjectNames([projectNames[1]]);
        await waitAndClick(findNextButton);
        await expectProjectNames([projectNames[2]]);

        await waitAndClick(findPrevButton);
        await expectProjectNames([projectNames[1]]);

        await waitAndClick(findPrevButton);
        await expectProjectNames([projectNames[0]]);

        expect(lastRequestVariables('getProjectsCiMinutesUsage')).toMatchObject({
          last: 1,
          before: expect.any(String),
        });
      });
    });
  });

  describe('when instance runners are disabled', () => {
    beforeEach(() => {
      mountPipelinesTab({
        ciMinutesAnyProjectEnabled: 'false',
        ciMinutesDisplayMinutesAvailableData: 'false',
        ciMinutesMonthlyMinutesUsedPercentage: '0',
        ciMinutesMonthlyMinutesLimit: 'Not supported',
      });
    });

    it('shows usage as not supported', async () => {
      const summary = await waitForElement(findUsageSummary);

      expect(getText(summary)).toBe('300 compute minutes / Not supported');
    });

    it('lists the projects with the instance runners disabled message', async () => {
      await expectProjectNames(projectNames);

      expect(getText(findProjectTable())).toContain(INSTANCE_RUNNERS_DISABLED_TEXT);
    });
  });
});
