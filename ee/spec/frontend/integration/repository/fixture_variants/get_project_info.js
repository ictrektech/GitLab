import base from 'test_fixtures/graphql/repository/integration/get_project_info.query.graphql.json';
import locked from 'test_fixtures/graphql/repository/integration/get_project_info_locked.query.graphql.json';
import fileLockedByOther from 'test_fixtures/graphql/repository/integration/get_project_info_file_locked_by_other.query.graphql.json';
import directoryLocked from 'test_fixtures/graphql/repository/integration/get_project_info_directory_locked.query.graphql.json';
import directoryLockedAsReporter from 'test_fixtures/graphql/repository/integration/get_project_info_directory_locked_as_reporter.query.graphql.json';
import filesDirectoryLocked from 'test_fixtures/graphql/repository/integration/get_project_info_files_directory_locked.query.graphql.json';
import nestedDirectoryLocked from 'test_fixtures/graphql/repository/integration/get_project_info_nested_directory_locked.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getProjectInfoEE',
  variants: {
    BASE: base,
    LOCKED: locked,
    FILE_LOCKED_BY_OTHER: fileLockedByOther,
    DIRECTORY_LOCKED: directoryLocked,
    DIRECTORY_LOCKED_AS_REPORTER: directoryLockedAsReporter,
    FILES_DIRECTORY_LOCKED: filesDirectoryLocked,
    NESTED_DIRECTORY_LOCKED: nestedDirectoryLocked,
    CANNOT_CREATE_LOCK: setFixtureData(base, 'createPathLock', false),
  },
});
