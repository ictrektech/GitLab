import { parseBoolean } from '@gitlab/frontend-utils';
import { initMarkdownEditor as initMarkdownEditorFOSS } from '~/pages/projects/merge_requests/init_markdown_editor';

export function initMarkdownEditor() {
  const { projectId, targetBranch, sourceBranch, canSummarize, summarizeDisabledReason } =
    document.querySelector('.js-markdown-editor').dataset;

  return initMarkdownEditorFOSS({
    projectId,
    targetBranch,
    sourceBranch,
    canSummarizeChanges: parseBoolean(canSummarize),
    summarizeDisabledReason,
  });
}
