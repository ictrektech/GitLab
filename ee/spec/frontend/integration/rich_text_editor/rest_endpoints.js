import { join } from 'node:path';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/rich_text_editor/integration/');

const { autocompleteMembers, autocompleteLabels, uploadSamplePdf } = loadFixturesMap(FIXTURES_PATH);

export const richTextEditorRestEndpoints = [
  {
    name: 'autocompleteMembers',
    method: 'get',
    path: /\/-\/autocomplete_sources\/members/,
    response: autocompleteMembers,
  },
  {
    name: 'autocompleteLabels',
    method: 'get',
    path: /\/-\/autocomplete_sources\/labels/,
    response: autocompleteLabels,
  },
  // Typing a `%{placeholder}` triggers milestone autocomplete; no spec asserts on it.
  {
    name: 'autocompleteMilestones',
    method: 'get',
    path: /\/-\/autocomplete_sources\/milestones/,
    response: [],
  },
  {
    name: 'uploadFile',
    method: 'post',
    path: /\/uploads$/,
    response: uploadSamplePdf,
  },
];
