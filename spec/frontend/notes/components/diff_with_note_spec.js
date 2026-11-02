import { cloneDeep } from 'lodash-es';
import Vue from 'vue';
import { shallowMount } from '@vue/test-utils';
import { PiniaVuePlugin } from 'pinia';
import { createTestingPinia } from '@pinia/testing';
import discussionFixture from 'test_fixtures/merge_requests/diff_discussion.json';
import imageDiscussionFixture from 'test_fixtures/merge_requests/image_diff_discussion.json';
import DiffWithNote from '~/notes/components/diff_with_note.vue';
import DiffViewer from '~/vue_shared/components/diff_viewer/diff_viewer.vue';
import DiffFileHeader from '~/diffs/components/diff_file_header.vue';
import { globalAccessorPlugin } from '~/pinia/plugins';
import { useLegacyDiffs } from '~/diffs/stores/legacy_diffs';
import { useNotes } from '~/notes/store/legacy_notes';

Vue.use(PiniaVuePlugin);

describe('diff_with_note', () => {
  let pinia;
  let wrapper;

  const selectors = {
    get diffTable() {
      return wrapper.find('.diff-content table');
    },
    get diffRows() {
      return wrapper.findAll('.diff-content .line_holder');
    },
    get noteRow() {
      return wrapper.find('.diff-content .notes_holder');
    },
  };

  const findDiffViewer = () => wrapper.findComponent(DiffViewer);
  const findDiffFileHeader = () => wrapper.findComponent(DiffFileHeader);

  const createComponent = (propsData) => {
    wrapper = shallowMount(DiffWithNote, {
      propsData,
      pinia,
    });
  };

  beforeEach(() => {
    pinia = createTestingPinia({ plugins: [globalAccessorPlugin] });
    useLegacyDiffs();
    useNotes().noteableData = { current_user: {} };
  });

  describe('text diff', () => {
    beforeEach(() => {
      createComponent({ discussion: discussionFixture[0] });
    });

    it('removes trailing "+" char', () => {
      const richText = wrapper.element
        .querySelectorAll('.line_holder')[4]
        .querySelector('.line_content').textContent[0];

      expect(richText).not.toEqual('+');
    });

    it('removes trailing "-" char', () => {
      const richText = wrapper.element.querySelector('.line .deletion').closest('.line').parentNode
        .textContent[0];

      expect(richText).not.toEqual('-');
    });

    it('shows text diff', () => {
      expect(wrapper.classes('text-file')).toBe(true);
      expect(selectors.diffTable.exists()).toBe(true);
    });

    it('shows diff lines', () => {
      expect(selectors.diffRows).toHaveLength(12);
    });

    it('shows notes row', () => {
      expect(selectors.noteRow.exists()).toBe(true);
    });
  });

  describe('highlighted lines', () => {
    const lastLineIndex = discussionFixture[0].truncated_diff_lines.length - 1;

    const highlightedRowIndexes = () => {
      const indexes = selectors.diffRows.wrappers
        .map((row, index) => (row.findAll('td.hll').length === 3 ? index : null))
        .filter((index) => index !== null);

      expect(wrapper.findAll('td.hll')).toHaveLength(indexes.length * 3);
      return indexes;
    };

    const createWithLineRange = (lineRange) => {
      const discussion = cloneDeep(discussionFixture[0]);
      discussion.original_position.line_range = lineRange;
      createComponent({ discussion });
    };

    it('highlights only the commented line for a single-line comment', () => {
      createComponent({ discussion: discussionFixture[0] });

      expect(highlightedRowIndexes()).toEqual([lastLineIndex]);
    });

    it('highlights only the commented line when there is no original position', () => {
      const discussion = cloneDeep(discussionFixture[0]);
      delete discussion.original_position;
      createComponent({ discussion });

      expect(highlightedRowIndexes()).toEqual([lastLineIndex]);
    });

    it('highlights every line in a multi-line comment range', () => {
      const lines = discussionFixture[0].truncated_diff_lines;
      createWithLineRange({
        start: { line_code: lines[8].line_code },
        end: { line_code: lines[11].line_code },
      });

      expect(highlightedRowIndexes()).toEqual([8, 9, 10, 11]);
    });

    it('marks the edges of the highlighted range like Rapid Diffs', () => {
      const lines = discussionFixture[0].truncated_diff_lines;
      createWithLineRange({
        start: { line_code: lines[8].line_code },
        end: { line_code: lines[11].line_code },
      });

      expect(selectors.diffRows.wrappers.map((row) => row.attributes('data-highlight'))).toEqual([
        ...Array(8).fill(undefined),
        'start',
        '',
        '',
        'end',
      ]);
    });

    it('marks a single highlighted line as both edges', () => {
      createComponent({ discussion: discussionFixture[0] });

      expect(selectors.diffRows.at(lastLineIndex).attributes('data-highlight')).toBe('start end');
    });

    it('highlights all lines when the range starts before the truncated lines', () => {
      createWithLineRange({
        start: { line_code: 'line_outside_of_truncated_lines' },
        end: { line_code: discussionFixture[0].truncated_diff_lines[11].line_code },
      });

      expect(highlightedRowIndexes()).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });
  });

  describe('image diff', () => {
    describe('when discussion has a diff_file', () => {
      beforeEach(() => {
        const imageDiscussion = imageDiscussionFixture[0];
        createComponent({ discussion: imageDiscussion, diffFile: {} });
      });

      it('shows image diff', () => {
        expect(selectors.diffTable.exists()).toBe(false);
        expect(findDiffViewer().exists()).toBe(true);
        expect(findDiffFileHeader().exists()).toBe(true);
      });
    });

    describe('when discussion does not have a diff_file', () => {
      beforeEach(() => {
        const imageDiscussion = cloneDeep(imageDiscussionFixture[0]);
        delete imageDiscussion.diff_file;

        createComponent({ discussion: imageDiscussion, diffFile: {} });
      });

      it('does not show image diff', () => {
        expect(findDiffViewer().exists()).toBe(false);
        expect(selectors.diffTable.exists()).toBe(false);
        expect(findDiffFileHeader().exists()).toBe(true);
      });
    });
  });

  describe('file diff', () => {
    describe('when discussion has a diff_file', () => {
      beforeEach(() => {
        const fileDiscussion = JSON.parse(JSON.stringify(discussionFixture[0]));
        fileDiscussion.position.position_type = 'file';
        fileDiscussion.original_position.position_type = 'file';

        createComponent({ discussion: fileDiscussion, diffFile: {} });
      });

      it('shows file header', () => {
        expect(findDiffFileHeader().exists()).toBe(true);
      });
    });

    describe('when discussion does not have a diff_file', () => {
      beforeEach(() => {
        const fileDiscussion = JSON.parse(JSON.stringify(discussionFixture[0]));
        delete fileDiscussion.diff_file;

        fileDiscussion.position.position_type = 'file';
        fileDiscussion.original_position.position_type = 'file';

        createComponent({ discussion: fileDiscussion, diffFile: {} });
      });

      it('shows file header', () => {
        expect(findDiffFileHeader().exists()).toBe(true);
      });
    });
  });

  describe('legacy diff note', () => {
    const mockCommitId = 'abc123';

    beforeEach(() => {
      const diffDiscussion = {
        ...discussionFixture[0],
        commit_id: mockCommitId,
        diff_file: {
          ...discussionFixture[0].diff_file,
          diff_refs: null,
          viewer: {
            ...discussionFixture[0].diff_file.viewer,
            name: 'no_preview',
          },
        },
      };

      createComponent({ discussion: diffDiscussion });
    });

    it('shows file diff', () => {
      expect(selectors.diffTable.exists()).toBe(false);
    });

    it('uses "no_preview" diff mode', () => {
      expect(findDiffViewer().props('diffMode')).toBe('no_preview');
    });

    it('falls back to discussion.commit_id for baseSha and headSha', () => {
      expect(findDiffViewer().props('oldSha')).toBe(mockCommitId);
      expect(findDiffViewer().props('newSha')).toBe(mockCommitId);
    });
  });

  describe('diff header', () => {
    let fileDiscussion;

    beforeEach(() => {
      fileDiscussion = JSON.parse(JSON.stringify(discussionFixture[0]));
      fileDiscussion.position.position_type = 'file';
      fileDiscussion.original_position.position_type = 'file';
    });

    describe('when the discussion has a diff_file', () => {
      beforeEach(() => {
        wrapper = shallowMount(DiffWithNote, {
          propsData: { discussion: fileDiscussion, diffFile: {} },
          pinia,
        });
      });

      it('links directly to the file to take advantage of the prioritized Linked File feature', () => {
        const header = findDiffFileHeader();

        expect(header.attributes('discussionpath')).toContain(
          `file=${fileDiscussion.diff_file.file_hash}`,
        );
      });
    });

    describe('when the discussion does not have a diff_file', () => {
      beforeEach(() => {
        delete fileDiscussion.diff_file;

        wrapper = shallowMount(DiffWithNote, {
          propsData: { discussion: fileDiscussion, diffFile: {} },
          pinia,
        });
      });

      it('does not include the `file` search parameter in the file link', () => {
        const header = findDiffFileHeader();

        expect(header.attributes('discussionpath')).not.toContain('file=');
      });
    });
  });
});
