import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { useFakeRequestAnimationFrame } from 'helpers/fake_request_animation_frame';
import { jumpToQuestion } from 'ee/work_items/utils/question_navigation';
import { contentTop } from '~/lib/utils/common_utils';
import { getScrollingElement } from '~/lib/utils/panels';
import { scrollPastCoveringElements } from '~/lib/utils/sticky';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  contentTop: jest.fn(),
}));
jest.mock('~/lib/utils/sticky');
jest.mock('~/lib/utils/viewport', () => ({
  withHiddenTooltips: jest.fn((fn) => fn()),
}));
jest.mock('~/lib/utils/panels');

const noteGid = (id) => `gid://gitlab/DiscussionNote/${id}`;

describe('jumpToQuestion', () => {
  useFakeRequestAnimationFrame();

  const findNote = (id) => document.getElementById(`note_${id}`);

  // Places each rendered note at a viewport offset from the reading line, which sits at 0.
  const layoutNotes = (tops) => {
    tops.forEach((top, index) => {
      const el = findNote(index + 1);
      el.getBoundingClientRect = () => ({ top });
      el.scrollIntoView = jest.fn();
    });
  };

  const createPanel = (overrides = {}) => ({
    getBoundingClientRect: () => ({ top: 0, left: 0 }),
    scrollHeight: 2000,
    scrollTop: 0,
    clientHeight: 768,
    ...overrides,
  });

  const findScrolledNoteId = () =>
    [1, 2, 3].find((id) => findNote(id).scrollIntoView.mock.calls.length > 0);

  beforeEach(() => {
    // jsdom has no layout to hit-test or animate, so nothing ever covers the panel top.
    document.elementFromPoint = () => null;
    document.getAnimations = () => [];
    contentTop.mockReturnValue(0);
    getScrollingElement.mockReturnValue(createPanel());
    setHTMLFixture(`
      <ul>
        <li id="note_1"></li>
        <li id="note_2"></li>
        <li id="note_3"></li>
      </ul>
    `);
  });

  afterEach(() => {
    delete document.elementFromPoint;
    delete document.getAnimations;
    resetHTMLFixture();
  });

  describe('when going to the next question', () => {
    it.each`
      scenario                                 | tops                  | expectedId
      ${'the reader is above every question'}  | ${[100, 300, 500]}    | ${1}
      ${'the reader is on the first question'} | ${[0, 200, 400]}      | ${2}
      ${'the reader is between two questions'} | ${[-100, 100, 300]}   | ${2}
      ${'the reader is on the last question'}  | ${[-400, -200, 0]}    | ${1}
      ${'the reader is below every question'}  | ${[-500, -300, -100]} | ${1}
    `('scrolls to question $expectedId when $scenario', async ({ tops, expectedId }) => {
      layoutNotes(tops);

      await jumpToQuestion({ noteIds: [1, 2, 3].map(noteGid), direction: 'next' });

      expect(findScrolledNoteId()).toBe(expectedId);
    });

    describe('when the panel is scrolled to the end', () => {
      beforeEach(() => {
        getScrollingElement.mockReturnValue(createPanel({ scrollTop: 1232 }));
        layoutNotes([-300, -100, 100]);
      });

      it('wraps around to the first question', async () => {
        await jumpToQuestion({ noteIds: [1, 2, 3].map(noteGid), direction: 'next' });

        expect(findScrolledNoteId()).toBe(1);
      });
    });
  });

  describe('when going to the previous question', () => {
    it.each`
      scenario                                  | tops                  | expectedId
      ${'the reader is on the second question'} | ${[-200, 0, 200]}     | ${1}
      ${'the reader is between two questions'}  | ${[-100, 100, 300]}   | ${1}
      ${'the reader is above every question'}   | ${[100, 300, 500]}    | ${3}
      ${'the reader is below every question'}   | ${[-500, -300, -100]} | ${3}
    `('scrolls to question $expectedId when $scenario', async ({ tops, expectedId }) => {
      layoutNotes(tops);

      await jumpToQuestion({ noteIds: [1, 2, 3].map(noteGid), direction: 'previous' });

      expect(findScrolledNoteId()).toBe(expectedId);
    });
  });

  describe('when the questions are listed in a different order than the page', () => {
    beforeEach(() => {
      layoutNotes([100, 300, 500]);
    });

    it('follows page order', async () => {
      await jumpToQuestion({ noteIds: [3, 2, 1].map(noteGid), direction: 'next' });

      expect(findScrolledNoteId()).toBe(1);
    });
  });

  describe('when some questions are not rendered', () => {
    beforeEach(() => {
      layoutNotes([-100, 100, 300]);
    });

    it('skips them', async () => {
      await jumpToQuestion({ noteIds: [4, 3].map(noteGid), direction: 'next' });

      expect(findScrolledNoteId()).toBe(3);
    });
  });

  describe('when there is no question to jump to', () => {
    beforeEach(() => {
      layoutNotes([100, 300, 500]);
    });

    it.each`
      scenario                           | noteIds
      ${'none of the questions renders'} | ${[4, 5].map(noteGid)}
      ${'no question is open'}           | ${[]}
    `('does not scroll when $scenario', async ({ noteIds }) => {
      await jumpToQuestion({ noteIds, direction: 'next' });

      expect(findScrolledNoteId()).toBeUndefined();
      expect(scrollPastCoveringElements).not.toHaveBeenCalled();
    });
  });

  describe('when a question is scrolled to', () => {
    beforeEach(() => {
      layoutNotes([100, 300, 500]);
    });

    it('clears the sticky header before and after it settles', async () => {
      await jumpToQuestion({ noteIds: [1, 2, 3].map(noteGid), direction: 'next' });

      expect(findNote(1).scrollIntoView).toHaveBeenCalledWith(true);
      expect(scrollPastCoveringElements).toHaveBeenCalledTimes(2);
      expect(scrollPastCoveringElements).toHaveBeenCalledWith(findNote(1));
    });
  });
});
