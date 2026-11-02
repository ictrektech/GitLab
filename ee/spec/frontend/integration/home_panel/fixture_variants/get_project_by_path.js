import base from 'test_fixtures/graphql/home_panel/integration/get_project_by_path.query.graphql.json';
import developer from 'test_fixtures/graphql/home_panel/integration/get_project_by_path_developer.query.graphql.json';
import nonMember from 'test_fixtures/graphql/home_panel/integration/get_project_by_path_non_member.query.graphql.json';
import groupDeveloper from 'test_fixtures/graphql/home_panel/integration/get_project_by_path_group_developer.query.graphql.json';
import groupMaintainer from 'test_fixtures/graphql/home_panel/integration/get_project_by_path_group_maintainer.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// Recorded per membership level because the actions dropdown derives its items
// from the server-side userPermissions; BASE is a direct maintainer.
export default defineFixtureVariants({
  query: 'getProjectByPath',
  variants: {
    BASE: base,
    DEVELOPER: developer,
    NON_MEMBER: nonMember,
    GROUP_DEVELOPER: groupDeveloper,
    GROUP_MAINTAINER: groupMaintainer,
  },
});
