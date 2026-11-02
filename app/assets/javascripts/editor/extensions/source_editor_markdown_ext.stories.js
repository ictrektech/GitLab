import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { EditorMarkdownExtension } from './source_editor_markdown_ext';
import { ToolbarExtension } from './source_editor_toolbar_ext';

export default {
  component: SourceEditor,
  title: 'editor/extensions/source_editor_markdown_ext',
};

export const MarkdownWithToolbar = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  // The toolbar extension mounts into #editor-toolbar, as on the blob edit page.
  template: `<div class="gl-h-48">
    <div id="editor-toolbar"></div>
    <source-editor v-bind="$props" />
  </div>`,
});
MarkdownWithToolbar.args = {
  fileName: 'README.md',
  value: `# Getting started

Some **bold** text and a [link](https://docs.gitlab.com).
`,
  extensions: [{ definition: ToolbarExtension }, { definition: EditorMarkdownExtension }],
};
MarkdownWithToolbar.parameters = {
  docs: {
    description: {
      story:
        'Loads `ToolbarExtension`, which mounts a toolbar into `#editor-toolbar`, and `EditorMarkdownExtension`, which adds the Markdown formatting buttons to it.',
    },
  },
};
