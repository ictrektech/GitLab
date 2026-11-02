import { join } from 'node:path';
import { http, HttpResponse } from 'msw';
import { isEqual } from 'lodash-es';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import {
  captureMissingOperation,
  captureRequest,
} from 'ee_jest/integration/core/operation_helpers';
import { server } from '../server';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/rich_text_editor/integration/');

const { previewMarkdown } = loadFixturesMap(FIXTURES_PATH);

export const installRichTextEditorHandlers = () => {
  server.use(
    http.post(/\/-\/preview_markdown(\?|$)/, async ({ request }) => {
      const { text } = await request.json();
      const params = Object.fromEntries(new URL(request.url).searchParams);

      if (
        !isEqual(params, previewMarkdown.params) ||
        !Object.hasOwn(previewMarkdown.previews, text)
      ) {
        captureMissingOperation(`previewMarkdown ${JSON.stringify({ params, text })}`);
        return new HttpResponse(null, { status: 400 });
      }

      captureRequest('previewMarkdown', request, { text });
      return HttpResponse.json(previewMarkdown.previews[text]);
    }),
  );
};
