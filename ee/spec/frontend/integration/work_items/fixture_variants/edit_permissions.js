import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

// A guest keeps `adminWorkItemLink`, so the Parent widget stays editable for them while every
// `setWorkItemMetadata` widget does not. An anonymous visitor loses that too, which the drawer
// harness cannot model because it provides `isSignedIn: true`.
export const withoutEditPermissions = (fixture) =>
  setFixtureData(setFixtureData(fixture, 'setWorkItemMetadata', false), 'updateWorkItem', false);

// Queries that hang off the same work item select a narrower permission set, but Apollo
// normalises them onto the same entity, so they have to agree or the last response wins.
export const withoutMetadataPermission = (fixture) =>
  setFixtureData(fixture, 'setWorkItemMetadata', false);
