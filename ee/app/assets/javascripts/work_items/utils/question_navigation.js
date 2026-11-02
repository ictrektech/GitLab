/**
 * Jumps between the open questions a workplan flow asked in a work item's discussion.
 *
 * Mirrors how the merge request page moves between unresolved threads
 * (`~/notes/mixins/discussion_navigation.js`): the next question is picked relative to
 * where the reader is scrolled, rather than from a remembered position, so the Workplan
 * widget and the sticky header can share it without sharing state.
 */

import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { contentTop } from '~/lib/utils/common_utils';
import { getScrollingElement } from '~/lib/utils/panels';
import { scrollPastCoveringElements } from '~/lib/utils/sticky';
import { withHiddenTooltips } from '~/lib/utils/viewport';
import { QUESTION_NAVIGATION_PREVIOUS } from '../constants';

// A question resting within this many pixels of the reading line counts as the current one.
const ACTIVE_TOLERANCE = 4;

// Notes hidden by the discussion filter aren't rendered, so they drop out here. Matches come
// back in page order, which keeps Up and Down right when the discussion is sorted newest first.
const findQuestionElements = (noteIds) => {
  if (!noteIds.length) return [];

  const selector = noteIds.map((noteId) => `#note_${getIdFromGraphQLId(noteId)}`).join(',');
  return [...document.querySelectorAll(selector)];
};

const isStickyOrFixed = (el) => ['sticky', 'fixed'].includes(getComputedStyle(el).position);

const findStickyAncestor = (el) => {
  let current = el;
  while (current && current !== document.body) {
    if (isStickyOrFixed(current)) return current;
    current = current.offsetParent;
  }
  return null;
};

// The reading line is the bottom of whatever sticky header covers the top of the panel,
// which is also where `scrollPastCoveringElements` leaves a question once it has scrolled.
const getReadingLine = (panel) =>
  withHiddenTooltips(() => {
    const { left, top } = panel.getBoundingClientRect();
    const hit = document.elementFromPoint(left + 1, top + 1);
    const sticky = hit ? findStickyAncestor(hit) : null;

    return sticky ? sticky.getBoundingClientRect().bottom : contentTop();
  });

const hasReachedPanelEnd = (panel) =>
  panel.scrollHeight <= Math.ceil(panel.scrollTop + panel.clientHeight);

const findClosest = (elements, panel) => {
  const readingLine = getReadingLine(panel);
  let isActive = false;
  const index = elements.findIndex((element) => {
    const offset = Math.ceil(element.getBoundingClientRect().top) - readingLine;
    isActive = offset < ACTIVE_TOLERANCE;
    return offset >= -ACTIVE_TOLERANCE;
  });

  return { index, isActive };
};

const getNext = (elements, panel) => {
  const [first] = elements;
  if (hasReachedPanelEnd(panel)) return first;

  const { index, isActive } = findClosest(elements, panel);
  if (index === -1) return first;
  if (!isActive) return elements[index];
  return elements[index + 1] || first;
};

const getPrevious = (elements, panel) => {
  const { index } = findClosest(elements, panel);
  const previous = index === -1 ? elements.length - 1 : index - 1;
  return elements[previous] || elements[elements.length - 1];
};

const nextFrame = () =>
  new Promise((resolve) => {
    requestAnimationFrame(resolve);
  });

// The work item sticky header slides in once its IntersectionObserver sees the scroll,
// which only reports after the next frame renders, so wait for that and the slide itself.
const waitForStickyHeader = async () => {
  await nextFrame();
  await nextFrame();
  const transitions = document
    .getAnimations()
    .filter((animation) => animation instanceof CSSTransition);
  await Promise.allSettled(transitions.map((transition) => transition.finished));
};

/**
 * Scrolls to the open question after or before the reader's position, wrapping at
 * either end. Does nothing when none of the questions is rendered, for example
 * while the discussion is filtered to history only.
 *
 * @param {Object} options
 * @param {Array<string>} options.noteIds Global IDs of the notes that asked an open question.
 * @param {string} options.direction `QUESTION_NAVIGATION_NEXT` or `QUESTION_NAVIGATION_PREVIOUS`.
 */
export const jumpToQuestion = async ({ noteIds, direction }) => {
  const elements = findQuestionElements(noteIds);
  if (!elements.length) return;

  const panel = getScrollingElement(elements[0]);
  const target =
    direction === QUESTION_NAVIGATION_PREVIOUS
      ? getPrevious(elements, panel)
      : getNext(elements, panel);

  target.scrollIntoView(true);
  scrollPastCoveringElements(target);
  await waitForStickyHeader();
  scrollPastCoveringElements(target);
};
