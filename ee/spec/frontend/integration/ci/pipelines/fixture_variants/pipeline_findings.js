import base from 'test_fixtures/graphql/ci/pipelines/integration/pipeline_findings.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export const FINDINGS_PAGE_SIZE = 20;
export const MANY_PAGES_FINDINGS_COUNT = FINDINGS_PAGE_SIZE + 1;

export default defineFixtureVariants({
  query: 'pipelineFindings',
  variants: {
    BASE: base,
    MANY_PAGES: setFixtureItemsCount({
      fixture: base,
      lookupKey: 'securityReportFindings',
      itemCount: MANY_PAGES_FINDINGS_COUNT,
    }),
  },
});
