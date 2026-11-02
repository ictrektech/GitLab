const SETTLE_TIMEOUT = 150;
let activeController;

/**
 * Runs a scroll that is repeated on contentvisibilityautostatechange until layout settles.
 * Aborts if the user scrolls manually or another call is made.
 * @param {HTMLElement|Document} root - ancestor where contentvisibilityautostatechange bubbles
 * @param {Function} scroll
 */
export function settledScroll(root, scroll) {
  activeController?.abort();
  const controller = new AbortController();
  const { signal } = controller;
  activeController = controller;
  let programmaticScroll = false;
  const scrollTo = () => {
    programmaticScroll = true;
    scroll();
  };
  root.addEventListener('contentvisibilityautostatechange', scrollTo, { capture: true, signal });
  window.addEventListener(
    'scroll',
    () => {
      if (programmaticScroll) {
        programmaticScroll = false;
        return;
      }
      controller.abort();
    },
    { capture: true, signal },
  );
  scrollTo();
  return new Promise((resolve) => {
    setTimeout(() => {
      controller.abort();
      activeController = undefined;
      scrollTo();
      resolve();
    }, SETTLE_TIMEOUT);
  });
}

/**
 * scrollIntoView that re-scrolls on contentvisibilityautostatechange until layout settles.
 * @param {HTMLElement} element
 * @param {HTMLElement|Document} root - ancestor where contentvisibilityautostatechange bubbles
 * @param {ScrollIntoViewOptions} options
 */
export function settledScrollIntoView(element, root, options = { block: 'start' }) {
  return settledScroll(root, () => element.scrollIntoView(options));
}
