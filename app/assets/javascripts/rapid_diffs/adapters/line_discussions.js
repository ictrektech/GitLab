import { nextTick, watch } from 'vue';
import { MOUNTED, HIGHLIGHT_LINES, CLEAR_HIGHLIGHT } from '~/rapid_diffs/adapter_events';
import DiffDiscussionRow from '~/rapid_diffs/app/discussions/diff_discussion_row.vue';
import {
  getLineNumbers,
  getLineChange,
  getLineCode,
  findLineRow,
} from '~/rapid_diffs/utils/line_utils';
import { getCodeSuggestionsConfig } from '~/rapid_diffs/utils/code_suggestions';
import { createAlert } from '~/alert';
import { pinia } from '~/pinia/instance';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { initVueApp, unmountVueApp } from '~/lib/utils/vue3compat/init_vue_app';

function mountDiscussionRow({
  lineRow,
  diffElement,
  parallel,
  appData,
  store,
  trigger,
  id,
  showWhitespace,
  diffRefs,
}) {
  if (lineRow.nextElementSibling?.dataset.discussionRow === 'true') return;
  const [rowOldLine, rowNewLine] = getLineNumbers(lineRow);
  const changed = lineRow.querySelector('[data-change]') !== null;
  const placeholder = lineRow.closest('tbody').insertRow(lineRow.sectionRowIndex + 1);
  const instance = initVueApp({
    el: placeholder,
    component: DiffDiscussionRow,
    pinia,
    apolloProvider,
    name: 'DiffDiscussionRowRoot',
    provide() {
      return {
        store,
        userPermissions: appData.userPermissions,
        sourceBranch: appData.sourceBranch,
        iid: appData.iid,
        endpoints: {
          discussions: appData.discussionsEndpoint,
          previewMarkdown: appData.previewMarkdownEndpoint,
          markdownDocs: appData.markdownDocsEndpoint,
          register: appData.registerPath,
          signIn: appData.signInPath,
          reportAbuse: appData.reportAbusePath,
        },
        noteableType: appData.noteableType,
        filePaths: { oldPath: appData.oldPath, newPath: appData.newPath },
        diffRefs,
        blobRawPath: appData.blobRawPath,
        suggestionsHelpPath: appData.suggestionsHelpPath,
        defaultSuggestionCommitMessage: appData.defaultSuggestionCommitMessage,
        linkedFileData: appData.linkedFileData,
        newCommentTemplatePaths: appData.newCommentTemplatePaths || [],
        showWhitespace,
        resolveCodeSuggestions: (discussion) =>
          getCodeSuggestionsConfig({
            discussion,
            diffElement,
            diffRefs,
            canReceiveSuggestion: store.canReceiveSuggestion,
            blobRawPath: appData.blobRawPath,
          }),
      };
    },
    props: {
      oldLine: rowOldLine,
      newLine: rowNewLine,
      parallel,
      changed,
    },
    events: {
      'start-thread': ({ oldPath, newPath, oldLine, newLine }) => {
        const side = newLine && !oldLine ? 'new' : 'old';
        const lineChange = getLineChange(lineRow.querySelector(`[data-position="${side}"]`));
        const lineCode = getLineCode({ id, row: lineRow, oldLine, newLine });
        const linePos = { old_line: oldLine, new_line: newLine };
        const lineRange = { start: linePos, end: linePos };
        store.addNewLineDiscussionForm({
          oldPath,
          newPath,
          lineChange,
          lineCode,
          lineRange,
          diffRefs,
        });
      },
      empty() {
        trigger(CLEAR_HIGHLIGHT);
        const row = instance.$el;
        unmountVueApp(instance);
        row.remove();
      },
      // Hiding threads removes the focused element, so keep focus on the toggle that shows them again
      hide() {
        const cell = [...instance.$el.cells].find((td) => td.contains(document.activeElement));
        if (!cell) return;
        nextTick(() => {
          cell.querySelector('[data-gutter-toggle] button')?.focus();
          trigger(CLEAR_HIGHLIGHT);
        });
      },
      highlight(lineRange) {
        if (store.lineRangeEditing) return;
        trigger(HIGHLIGHT_LINES, lineRange);
      },
      'clear-highlight': () => {
        if (store.lineRangeEditing) return;
        trigger(CLEAR_HIGHLIGHT);
      },
    },
  });
  instance.$el.destroy = () => unmountVueApp(instance);
}

export const createLineDiscussionsAdapter = ({ store, parallel, errorMessage }) => ({
  [MOUNTED](addCleanup) {
    const { diffElement, appData, trigger, id } = this;
    const { oldPath, newPath, blobRawPath, showWhitespace, diffRefs } = this.data;
    const stopWatcher = watch(
      () => store.findLinePositionsForFile({ oldPath, newPath, diffRefs }),
      (matchedPositions) => {
        matchedPositions.forEach((position) => {
          try {
            const lineRow = findLineRow(diffElement, position.old_line, position.new_line);
            if (!lineRow) return;
            mountDiscussionRow({
              lineRow,
              diffElement,
              parallel,
              appData: { ...appData, oldPath, newPath, blobRawPath },
              store,
              trigger,
              id,
              showWhitespace,
              diffRefs,
            });
          } catch (error) {
            createAlert({
              message: errorMessage,
              parent: diffElement,
              error,
              captureError: true,
            });
          }
        });
      },
      { immediate: true },
    );
    addCleanup(() => {
      stopWatcher();
      diffElement.querySelectorAll('[data-discussion-row]').forEach((row) => {
        row.destroy?.();
      });
    });
  },
  clicks: {
    newDiscussion(event, button) {
      const lineChange = getLineChange(button.closest('[data-position]'));
      const row = button.closest('tr');
      const [oldLine, newLine] = getLineNumbers(row);
      const { oldPath, newPath, diffRefs } = this.data;
      const lineCode = getLineCode({ id: this.id, row, oldLine, newLine });
      const existingDiscussionId = store.addNewLineDiscussionForm({
        oldPath,
        newPath,
        lineChange,
        lineCode,
        lineRange: button.lineRange,
        diffRefs,
      });
      if (existingDiscussionId) {
        document
          .querySelector(`[data-discussion-id="${existingDiscussionId}"] textarea:not(.hidden)`)
          ?.focus();
      }
    },
  },
});
