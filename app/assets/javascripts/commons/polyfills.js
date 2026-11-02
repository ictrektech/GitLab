/**
 * Polyfill
 * @what Element.prototype.ariaNotify and Document.prototype.ariaNotify
 * @why To announce messages to screen readers without managing live regions
 * @browsers Chrome < 141, Edge < 141, Firefox < 150, Safari < 27
 * @see https://caniuse.com/mdn-api_element_arianotify
 */
import '@github/arianotify-polyfill';

/**
 * Polyfill
 * @what requestIdleCallback
 * @why To align browser features
 * @browsers Safari (all versions)
 * @see https://caniuse.com/#feat=requestidlecallback
 */
window.requestIdleCallback =
  window.requestIdleCallback ||
  function requestShim(cb) {
    const start = Date.now();
    return setTimeout(() => {
      cb({
        didTimeout: false,
        timeRemaining: () => Math.max(0, 50 - (Date.now() - start)),
      });
    }, 1);
  };

window.cancelIdleCallback =
  window.cancelIdleCallback ||
  function cancelShim(id) {
    clearTimeout(id);
  };
