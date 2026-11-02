import { watch } from 'vue';
import { pinia } from '~/pinia/instance';
import { createAlert } from '~/alert';
import { __ } from '~/locale';
import { RapidDiffsFacade } from '~/rapid_diffs/app';
import { adapters } from '~/rapid_diffs/app/adapter_configs/merge_request';
import { useCodeReview } from '~/diffs/stores/code_review';
import { useMergeRequestDiscussions } from '~/merge_request/stores/merge_request_discussions';
import { useMergeRequestVersions } from '~/merge_request/stores/merge_request_versions';
import { useTestCoverage } from '~/rapid_diffs/stores/test_coverage';
import { useDiffsList } from '~/rapid_diffs/stores/diffs_list';
import { useDiffsView } from '~/rapid_diffs/stores/diffs_view';
import { DiffFile } from '~/rapid_diffs/web_components/diff_file';
import { setLocationHash } from '~/lib/utils/url_utility';
import { scrollPastCoveringElements } from '~/lib/utils/sticky';
import { settledScroll } from '~/rapid_diffs/utils/settled_scroll_into_view';
import { initCommitWidget } from '~/rapid_diffs/app/init_commit_widget';
import { initCompareVersions } from '~/rapid_diffs/app/init_compare_versions';
import { initNewDiscussionToggle } from '~/rapid_diffs/app/init_new_discussions_toggle';
import { initLineRangeSelection } from '~/rapid_diffs/app/init_line_range_selection';
import { initLineRangeEditing } from '~/rapid_diffs/app/init_line_range_editing';
import { initHotkeys } from '~/rapid_diffs/app/init_hotkeys';
import { initFileFinder } from '~/rapid_diffs/app/init_file_finder';

const scrollToThread = (diffFile, thread) =>
  settledScroll(diffFile.closest('[data-rapid-diffs]'), () => {
    thread.scrollIntoView({ block: 'start' });
    scrollPastCoveringElements(thread);
  });

const topOffset = (discussion) => {
  const position = discussion.position || discussion.original_position;
  if (position.position_type === 'image') return position.y;
  return Math.max(position.new_line, position.old_line);
};

const findDiffFile = (oldPath, newPath) =>
  DiffFile.getAll().find((file) => file.data.oldPath === oldPath && file.data.newPath === newPath);

export class MergeRequestRapidDiffsApp extends RapidDiffsFacade {
  adapterConfig = adapters;

  #unresolvedThreads = {
    count: (file) => this.#findUnresolvedDiscussions(file).length,
    goToFirst: (file) => this.#goToFirstUnresolvedThread(file),
  };

  initSidebar() {
    return super.initSidebar({ provide: { unresolvedThreads: this.#unresolvedThreads } });
  }

  async init() {
    this.#initCodeReview();
    super.init();
    this.#initCompareVersions();
    this.#initCommitWidget();
    this.#initCoverage();
    this.#initChangesTabCount();
    await this.#initDiscussions();
    initNewDiscussionToggle(this.root, { allowExpandedLines: true });
    initLineRangeSelection(this.root);
    initLineRangeEditing(this.root);
    initHotkeys();
    initFileFinder();
  }

  // eslint-disable-next-line class-methods-use-this
  async scrollToDiffNote(discussion) {
    const store = useDiffsList(pinia);
    const view = useDiffsView(pinia);
    const position = discussion.position || discussion.original_position;
    const endLine = position.line_range?.end || position;

    if (view.singleFileMode && !findDiffFile(position.old_path, position.new_path)) {
      view.resolveInitialFileIndex({
        file: { old_path: position.old_path, new_path: position.new_path },
      });
      await view.loadCurrentFile();
    }

    let stop;

    const handler = () => {
      const diffFile = findDiffFile(position.old_path, position.new_path);
      if (diffFile) {
        const thread = diffFile.querySelector(`[data-discussion-id="${discussion.id}"]`);
        if (thread) {
          setLocationHash(`note_${discussion.notes[0].id}`);
          scrollToThread(diffFile, thread);
        } else {
          diffFile.selectLine(endLine.old_line, endLine.new_line);
        }
        useMergeRequestDiscussions(pinia).expandDiscussion(discussion);
        stop?.();
      } else if (store.status === 'idle' || store.status === 'error') {
        stop?.();
      }
    };

    stop = watch(() => store.loadedFiles, handler, { immediate: true });
  }

  // eslint-disable-next-line class-methods-use-this
  setLinkedFile(position) {
    useDiffsList(pinia).setLinkedFileData({
      old_path: position.old_path,
      new_path: position.new_path,
    });
  }

  #goToFirstUnresolvedThread(file) {
    const [first] = this.#findUnresolvedDiscussions(file).sort(
      (a, b) => topOffset(a) - topOffset(b),
    );
    if (first) this.scrollToDiffNote(first);
  }

  // eslint-disable-next-line class-methods-use-this
  #findUnresolvedDiscussions({ filePaths }) {
    const { diffRefs } = useMergeRequestVersions(pinia);
    if (!diffRefs) return [];
    return useMergeRequestDiscussions(pinia)
      .findDiscussionsForFile({ oldPath: filePaths.old, newPath: filePaths.new, diffRefs })
      .filter((discussion) => discussion.resolvable && !discussion.resolved);
  }

  // eslint-disable-next-line class-methods-use-this
  #initDiscussions() {
    return useMergeRequestDiscussions(pinia)
      .fetchNotesAndDrafts()
      .catch((error) => {
        createAlert({
          message: __('An error occurred while loading comments'),
          captureError: true,
          error,
        });
      });
  }

  #initCodeReview() {
    if (!gon.current_user_id) return;
    const { mr_path: mrPath } = JSON.parse(this.root.dataset.appData);
    if (!mrPath) return;

    const store = useCodeReview(pinia);

    store.setMrPath(mrPath);
    store.restoreFromAutosave();
    store.restoreFromLegacyMrReviews();
  }

  #initCompareVersions() {
    if (!this.appData.versions) return;
    initCompareVersions(this.root.querySelector('[data-after-browser-toggle]'), this.appData);
  }

  #initCommitWidget() {
    initCommitWidget(this.root.querySelector('[data-commit-widget]'));
  }

  #initCoverage() {
    const { coverageEndpoint } = this.appData;
    if (!coverageEndpoint) return;
    const store = useTestCoverage(pinia);
    store.endpoint = coverageEndpoint;
    store.fetchCoverage();
  }

  // eslint-disable-next-line class-methods-use-this
  #initChangesTabCount() {
    const tabCount = document.querySelector('.js-changes-tab-count');
    if (!tabCount) return;
    const store = useDiffsView(pinia);
    watch(
      () => store.totalFilesCount,
      (count) => {
        if (count == null) return;
        tabCount.textContent = count;
      },
      { immediate: true },
    );
  }
}

export const createMergeRequestRapidDiffsApp = (options) => {
  return new MergeRequestRapidDiffsApp(options);
};
