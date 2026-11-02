import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import { isSameOriginUrl } from '~/lib/utils/url_utility';
import { extractGroupOrProject } from '~/glql/utils/common';

const REFERENCE_TYPES = {
  issues: 'issue',
  work_items: 'work_item',
  merge_requests: 'merge_request',
  epics: 'epic',
};

const HOVER_AND_FOCUS_EVENTS = ['mouseenter', 'mouseleave', 'focusin', 'focusout'];
const ISSUABLE_PATH_REGEX = /\/-\/(issues|work_items|merge_requests|epics)\/(\d+)$/;
const COMMIT_PATH_REGEX = /\/-\/commit\/([0-9a-f]{7,64})$/i;

/**
 * Derives reference popover data from a same-instance URL. Chat anchors come from
 * sanitized model output, so nothing but the href is trusted.
 */
export function parseReferenceUrl(href) {
  if (!isSameOriginUrl(href)) return null;

  const { pathname } = new URL(href, window.location.origin);
  const { group, project } = extractGroupOrProject(href);

  const [, sha] = pathname.match(COMMIT_PATH_REGEX) ?? [];
  if (sha) {
    return project ? { referenceType: 'commit', projectPath: project, commitSha: sha } : null;
  }

  const [, segment, iid] = pathname.match(ISSUABLE_PATH_REGEX) ?? [];
  // Groups have no merge requests and projects have no epics.
  if ((group && segment === 'merge_requests') || (project && segment === 'epics')) return null;

  const namespacePath = group || project;
  return segment && namespacePath
    ? { referenceType: REFERENCE_TYPES[segment], namespacePath, iid }
    : null;
}

// Chat markdown is re-morphed on every streamed frame, so the per-element listeners and
// data-attribute markers of `initIssuablePopovers` do not survive. Resolve on hover instead,
// as `~/work_item_attribute_popovers` does for async content.
// Returns a function that removes the listeners.
export function initChatReferencePopovers(root) {
  let apolloProvider;
  const getApolloProvider = () => {
    if (!apolloProvider) {
      Vue.use(VueApollo);
      apolloProvider = new VueApollo({ defaultClient: createDefaultClient() });
    }
    return apolloProvider;
  };
  // Keyed by element so morphdom's attribute churn cannot reset them.
  const pending = new WeakSet();
  const mounted = new WeakMap();
  // Iterable, so dispose can reach anchors the view has already removed.
  const teardowns = new Set();
  const popovers = new Set();

  const arm = ({ target, type }) => {
    const anchor = target.closest('a[href]');
    if (!anchor) return;

    const { href } = anchor;
    const previous = mounted.get(anchor);
    if (pending.has(anchor) || previous?.href === href) return;

    const reference = parseReferenceUrl(href);
    if (!reference) return;

    pending.add(anchor);
    let cancel = () => {};
    let released = false;
    let hovered = type === 'mouseover';
    let focused = type === 'focusin';
    let update;
    const teardown = () => {
      released = true;
      pending.delete(anchor);
      cancel();
      HOVER_AND_FOCUS_EVENTS.forEach((name) => anchor.removeEventListener(name, update));
      teardowns.delete(teardown);
    };
    // The mount waits 200 ms. Losing both hover and focus before then cancels it, so
    // the link stays eligible for the next hover or focus; only a mounted popover blocks it.
    update = (event) => {
      if (event.type === 'mouseenter' || event.type === 'mouseleave') {
        hovered = event.type === 'mouseenter';
      } else {
        focused = event.type === 'focusin';
      }
      if (!hovered && !focused) teardown();
    };
    HOVER_AND_FOCUS_EVENTS.forEach((name) => anchor.addEventListener(name, update));
    teardowns.add(teardown);

    import(/* webpackChunkName: 'IssuablePopoverBundle' */ '~/issuable/popover')
      .then(({ handleIssuablePopoverMount }) => {
        if (released) return;
        cancel = handleIssuablePopoverMount({
          target: anchor,
          apolloProvider: getApolloProvider(),
          // Link text is model-written; never show it as a verified title.
          innerText: '',
          cancelOnMouseLeave: false,
          onMount: (popover) => {
            // A streamed href can change under a mounted popover; drop the stale one.
            previous?.popover?.$destroy();
            popovers.delete(previous?.popover);
            mounted.set(anchor, { href, popover });
            popovers.add(popover);
          },
          ...reference,
        });
      })
      .catch(() => {});
  };

  root.addEventListener('mouseover', arm);
  root.addEventListener('focusin', arm);

  // The view is going away: nothing may mount later and nothing stays mounted.
  return () => {
    root.removeEventListener('mouseover', arm);
    root.removeEventListener('focusin', arm);
    teardowns.forEach((teardown) => teardown());
    popovers.forEach((popover) => popover.$destroy());
    popovers.clear();
  };
}
