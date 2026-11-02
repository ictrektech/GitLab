<script>
import { defineComponent } from 'vue';
import { editor as monacoEditor, KeyCode, KeyMod, Range } from 'monaco-editor';
import { EDITOR_READY_EVENT } from '~/editor/constants';
import dark from '~/ide/lib/themes/dark';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { s__ } from '~/locale';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { EDITOR_OPTIONS, ORBIT_GQL_LANGUAGE } from './constants';
import { registerOrbitGqlCompletions, registerOrbitGqlLanguage } from './gql_language';

const GHOST_CONTEXT_KEY = 'orbitQueryShowsGhost';

export default defineComponent({
  name: 'QuerySourceEditor',
  components: { SourceEditor },
  props: {
    value: {
      type: String,
      required: true,
    },
    schema: {
      type: Object,
      required: true,
    },
    ghostQuery: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input', 'run', 'ready'],
  expose: ['insertText', 'replaceText'],
  computed: {
    editorOptions() {
      return { ...EDITOR_OPTIONS, language: ORBIT_GQL_LANGUAGE };
    },
  },
  watch: {
    ghostQuery: 'renderGhostQuery',
  },
  created() {
    registerOrbitGqlLanguage();
  },
  beforeDestroy() {
    this.completions?.dispose();
    this.actions?.forEach((action) => action.dispose());
  },
  methods: {
    onEditorReady({ detail: { instance } }) {
      if (darkModeEnabled()) {
        monacoEditor.defineTheme('gl-dark', dark);
        monacoEditor.setTheme('gl-dark');
      }

      this.editorInstance = instance;
      this.ghostContextKey = instance.createContextKey(GHOST_CONTEXT_KEY, false);
      this.actions = [
        instance.addAction({
          id: 'orbit-query-run',
          label: s__('Orbit|Run query'),
          // eslint-disable-next-line no-bitwise -- Monaco combines key codes as bit flags
          keybindings: [KeyMod.CtrlCmd | KeyCode.Enter],
          run: () => this.$emit('run'),
        }),
        instance.addAction({
          id: 'orbit-query-use-ghost',
          label: s__('Orbit|Use the default query'),
          keybindings: [KeyCode.Tab],
          precondition: `${GHOST_CONTEXT_KEY} && !editorTabMovesFocus`,
          run: () => this.replaceText(this.ghostQuery),
        }),
      ];
      this.renderGhostQuery();

      this.completions = registerOrbitGqlCompletions(() => this.schema);
      // SourceEditor starts to report edits only after its ready event returns.
      this.$nextTick(() => this.$emit('ready'));
    },
    renderGhostQuery() {
      if (!this.editorInstance) return;

      this.ghostContextKey.set(Boolean(this.ghostQuery));
      const decorations = this.ghostQuery
        ? [
            {
              range: new Range(1, 1, 1, 1),
              options: {
                showIfCollapsed: true,
                after: { content: this.ghostQuery, inlineClassName: '!gl-text-disabled' },
              },
            },
          ]
        : [];
      this.ghostDecorations = this.editorInstance.deltaDecorations(
        this.ghostDecorations ?? [],
        decorations,
      );
    },
    insertText(text) {
      const position = this.editorInstance.getPosition();
      const lineBeforeCursor = this.editorInstance
        .getModel()
        .getValueInRange(new Range(position.lineNumber, 1, position.lineNumber, position.column));
      const insertion = lineBeforeCursor.endsWith('.') ? text.replace(/^\w+\./, '') : text;
      const separator = /\w$/.test(lineBeforeCursor) ? ' ' : '';

      this.editorInstance.trigger('orbit-query-reference', 'type', {
        text: `${separator}${insertion}`,
      });
      this.editorInstance.focus();
    },
    replaceText(text) {
      const model = this.editorInstance.getModel();

      this.editorInstance.pushUndoStop();
      this.editorInstance.executeEdits('orbit-query-editor', [
        { range: model.getFullModelRange(), text },
      ]);
      this.editorInstance.pushUndoStop();
      this.editorInstance.setPosition(model.getPositionAt(text.length));
      this.editorInstance.focus();
    },
  },
  readyEvent: EDITOR_READY_EVENT,
});
</script>

<template>
  <div class="orbit-editor-wrapper gl-h-28">
    <source-editor
      :value="value"
      :editor-options="editorOptions"
      :use-dynamic-height="false"
      :debounce-value="0"
      file-name="query.gql"
      file-global-id="orbit-query-editor"
      @input="$emit('input', $event)"
      @[$options.readyEvent]="onEditorReady"
    />
  </div>
</template>
