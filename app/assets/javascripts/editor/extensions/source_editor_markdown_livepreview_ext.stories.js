import MockAdapter from 'axios-mock-adapter';
import { marked } from 'marked';
import { EDITOR_READY_EVENT } from '~/editor/constants';
import { sanitize } from '~/lib/dompurify';
import axios from '~/lib/utils/axios_utils';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { EditorMarkdownPreviewExtension } from './source_editor_markdown_livepreview_ext';

const PREVIEW_MARKDOWN_PATH = '/preview_markdown';

export default {
  component: SourceEditor,
  title: 'editor/extensions/source_editor_markdown_livepreview_ext',
};

export const MarkdownLivePreview = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  // Storybook has no backend, so the preview request renders the editor's Markdown in the browser.
  created() {
    this.mock = new MockAdapter(axios, { onNoMatch: 'passthrough' });
    this.mock
      .onPost(PREVIEW_MARKDOWN_PATH)
      .reply(({ data }) => [200, { body: sanitize(marked.parse(JSON.parse(data).text)) }]);
  },
  beforeDestroy() {
    this.mock.restore();
  },
  methods: {
    // Opens the preview on load. Cmd/Ctrl+Shift+P toggles it.
    showPreview({ detail: { instance } }) {
      instance.use({
        definition: EditorMarkdownPreviewExtension,
        setupOptions: { previewMarkdownPath: PREVIEW_MARKDOWN_PATH },
      });
      instance.togglePreview();
    },
  },
  readyEvent: EDITOR_READY_EVENT,
  template: `<div class="gl-h-48">
    <source-editor v-bind="$props" @[$options.readyEvent]="showPreview" />
  </div>`,
});
MarkdownLivePreview.args = {
  fileName: 'README.md',
  value: `# Getting started

Some **bold** text.
`,
};
