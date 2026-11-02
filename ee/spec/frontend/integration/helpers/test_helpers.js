import { appendFileSync } from 'node:fs';
import { getConfig, waitFor, screen, within } from '@testing-library/vue';
import { mount } from '@vue/test-utils';
import setWindowLocation from 'helpers/set_window_location_helper';
import { unmountVueApp } from '~/lib/utils/vue3compat/init_vue_app';

export { screen, within };

export const assignRouter = (routerFn, args) => {
  const { routerLocation, ...routerArgs } = args ?? {};

  setWindowLocation(routerLocation || routerArgs.routerPath || '/');

  const router = routerFn(routerArgs);

  // We inject the router metadata globally so that our test setup can
  // pick it up and do the router setup and cleanup
  global.metadata = { ...global.metadata, router };
  return router;
};

// MSW 2 streams response bodies, so a test can end before Apollo has consumed its last
// responses. `test_setup.js` cancels those in-flight operations before the next test;
// `cache.reset()` alone leaves them pending and query deduplication reuses their result.
const mountedApolloClients = new Set();

export const fullMount = (component, params) => {
  const { apolloProvider } = params ?? {};
  [apolloProvider?.defaultClient, ...Object.values(apolloProvider?.clients ?? {})]
    .filter(Boolean)
    .forEach((client) => mountedApolloClients.add(client));

  return mount(component, { attachTo: document.body, ...params });
};

// Apps booted by their production init function are not VTU wrappers, so
// `enableAutoDestroy` never reaches them; the harness unmounts them instead.
let bootstrappedApps = [];

/**
 * Hands an app created by its real page bootstrap (for example `initCdRoot`) to the
 * harness, which unmounts it, removes its root element and clears its Apollo cache
 * between tests.
 *
 * Throws when the bootstrap returned no app, and when the app exposes no Apollo client.
 * The second one is worth a guard because, unlike the harness's other failure modes, it
 * does not surface on its own: the cache outlives the test and the next mount reads it,
 * so the symptom is an order-dependent failure elsewhere. Add an opt-out here if a page
 * that genuinely does not use Apollo ever needs to register.
 *
 * @param {Object} app - The root instance the bootstrap returned.
 * @returns {Object} The app, so callers can return it directly.
 */
export const registerBootstrappedApp = (app) => {
  if (!app) {
    throw new Error('registerBootstrappedApp: the bootstrap returned no app, so it never mounted');
  }

  // Registered before the Apollo check, so the harness still tears down an app that check
  // rejects instead of leaving it in the document for every later test.
  bootstrappedApps.push(app);

  const { defaultClient, clients } = app.$apolloProvider ?? {};
  // The same set `fullMount` collects: a named client's cache needs clearing too.
  const appClients = [defaultClient, ...Object.values(clients ?? {})].filter(Boolean);
  if (!appClients.length) {
    throw new Error(
      'registerBootstrappedApp: the app exposes no Apollo client, so its cache cannot be cleared',
    );
  }

  appClients.forEach((client) => mountedApolloClients.add(client));

  return app;
};

/**
 * The harness's own teardown hook, called by the global `afterEach`. Specs must not call
 * it: it empties the registry, so an app mounted afterwards is never torn down.
 */
export const unmountBootstrappedApps = () => {
  const apps = bootstrappedApps;
  bootstrappedApps = [];
  const errors = [];

  // Contained per app, and rethrown once the loop is done. The ConsoleWatcher turns a
  // warning raised during one app's teardown into a throw, which would otherwise abandon
  // every app after it with no registry entry left to clean them up.
  apps.forEach((app) => {
    try {
      // `unmountVueApp` resolves the app through `$root`, so read the element from there
      // too: a bootstrap may hand out an inner instance as its public API, and on the
      // Vue 2 lane this removal is the only thing that takes the DOM with it.
      const root = app.$root ?? app;
      const el = root.$el;

      unmountVueApp(app);
      // `unmountVueApp` only tears down `initVueApp` roots, so on the Vue 3 lane a
      // `new Vue` root (for example `initSinglePageApplication`) still needs `$destroy`.
      // The gap belongs in `unmountVueApp` itself rather than in a spec helper.
      root.$destroy?.();
      el?.remove();
    } catch (error) {
      errors.push(error);
    }
  });

  if (errors.length) {
    throw errors[0];
  }
};

export const clearMountedApolloStores = async () => {
  await Promise.all([...mountedApolloClients].map((client) => client.clearStore()));
  mountedApolloClients.clear();
  // Apollo cancels the pending fetches in a `setTimeout(0)`; let it run before the next mount.
  await new Promise((resolve) => {
    setTimeout(resolve);
  });
};

export const waitForElement = (finder) =>
  waitFor(() => {
    const element = finder();
    expect(element).not.toBe(null);
    return element;
  });

/**
 * Returns the text content of a DOM element with normalized whitespace.
 * Equivalent to VTU's `.text()` method — collapses all whitespace runs
 * into a single space and trims leading/trailing whitespace.
 * @param {HTMLElement} el
 * @returns {string}
 */
export function getText(el) {
  return el.textContent.replace(/\s+/g, ' ').trim();
}

// GlToast portals into #gl-toaster on document.body, outside the mounted app
// root. No testid or usable role exists: GlLoadingIcon shares role="status".
export const findToastMessages = () =>
  Array.from(document.querySelectorAll('#gl-toaster .toast-body'), (el) => getText(el));

/**
 * Finds a button element by its text content or aria-label.
 * Uses @testing-library/vue's queryAllByRole under the hood,
 * returning the first match or null.
 * @param {string} text - The text content or aria-label to search for
 * @param {HTMLElement} [container=document.body] - The container to search within
 * @returns {HTMLElement|null}
 */
export function findButtonByText(text, container = document.body) {
  const matches = within(container).queryAllByRole('button', { name: text });
  return matches[0] || null;
}

/**
 * Sets the value of an input element and dispatches the appropriate event.
 * @param {HTMLElement} input - The input element
 * @param {string} value - The value to set
 * @param {string} [eventType='input'] - The event type to dispatch ('input', 'change', etc.)
 */
export function setInputValue(input, value, eventType = 'input') {
  // eslint-disable-next-line no-param-reassign
  input.value = value;
  input.dispatchEvent(new Event(eventType, { bubbles: true }));
}

/**
 * Waits for an element to appear, then clicks it.
 * @param {Function} finder - A function that returns the element to click
 * @returns {Promise<HTMLElement>}
 */
export async function waitAndClick(finder) {
  const element = await waitForElement(finder);
  element.click();
  return element;
}

/**
 * Waits for a GlModal's primary (confirm) button to become clickable, then clicks it.
 *
 * BModal renders its content a tick before `isVisible` is set and swallows any
 * hide trigger until then, so a click on a just-found button can be lost.
 * The `show` class lands strictly after that, making it the clickable signal.
 * @returns {Promise<HTMLElement>}
 */
export function waitForModalConfirm() {
  return waitAndClick(() => {
    const button = screen.queryByTestId('confirm-ok-button');
    const modal = button?.closest('.modal');
    return modal?.classList.contains('show') ? button : null;
  });
}

/**
 * Waits for an element to appear, then sets its value.
 * @param {Function} finder - A function that returns the input element
 * @param {string} value - The value to set
 * @param {string} [eventType='input'] - The event type to dispatch
 * @returns {Promise<HTMLElement>}
 */
export async function waitAndSetValue(finder, value, eventType = 'input') {
  const element = await waitForElement(finder);
  setInputValue(element, value, eventType);
  return element;
}

/**
 * Waits for an element to disappear (become null).
 * @param {Function} finder - A function that returns the element
 * @returns {Promise<void>}
 */
export function waitForElementToBeNull(finder) {
  return waitFor(() => {
    expect(finder()).toBe(null);
  });
}

/**
 * Finds an element by its GraphQL ID.
 * Converts GraphQL ID to numeric ID and finds the corresponding issuable element.
 * @param {string} graphqlId - The GraphQL ID (e.g., 'gid://gitlab/WorkItem/123')
 * @param {Function} getIdFromGraphQLId - Function to extract numeric ID from GraphQL ID
 * @returns {HTMLElement|null}
 */
export function findByGraphQLId(graphqlId, getIdFromGraphQLId, elementPrefix = 'issuable_') {
  const numericId = getIdFromGraphQLId(graphqlId);
  return document.querySelector(`#${elementPrefix}${numericId}`);
}

/**
 * Waits for a condition to be true with a custom assertion.
 * @param {Function} assertion - A function that performs the assertion
 * @returns {Promise<void>}
 */
export function waitForAssertion(assertion) {
  return waitFor(() => {
    assertion();
  });
}

// Booting the app is setup, not the behaviour under test, so it gets its own budget. Stays
// under the hook timeout `createFrontendIntegrationConfig` sets (20s in CI, 7s locally).
const SETUP_WAIT_TIMEOUT = process.env.CI ? 15000 : 6000;
const SLOW_WAIT_MS = 2000;

let settingUp = false;

/**
 * Waits for the app to finish booting, from `beforeEach` or a mount helper, with a longer
 * budget than test bodies get. Assertions stay in the test with the regular waits.
 * @param {Function} callback - Same contract as `waitFor`: throws until the app is ready.
 * @returns {Promise<*>} Whatever `callback` returns once it stops throwing.
 */
export async function waitForSetup(callback) {
  settingUp = true;
  try {
    return await waitFor(callback, { timeout: SETUP_WAIT_TIMEOUT });
  } finally {
    settingUp = false;
  }
}

// Installed as @testing-library's `asyncWrapper`, so every `waitFor` runs through it. A wait
// that nears the ceiling passes locally and flakes on a starved CI runner, so it is logged.
// `console.log`, not `warn`: the console watcher turns `warn` into a failure.
export async function timedAsyncWrapper(callback) {
  const start = performance.now();
  try {
    return await callback();
  } finally {
    const elapsed = Math.round(performance.now() - start);
    if (!settingUp && elapsed > SLOW_WAIT_MS) {
      const { testPath, currentTestName } = expect.getState();
      const ceilingMs = getConfig().asyncUtilTimeout;
      // eslint-disable-next-line no-console
      console.log(
        `[integration] slow wait: ${elapsed}ms in "${currentTestName}" (ceiling ${ceilingMs}ms). Boot the app in beforeEach with waitForSetup, or split the wait.`,
      );
      // CI sets the path and uploads the file, so scripts/frontend/post_integration_test_summary.mjs
      // can list the slow waits in the MR comment. One line per wait; appends stay atomic across workers.
      if (process.env.JEST_INTEGRATION_SLOW_WAITS_FILE) {
        appendFileSync(
          process.env.JEST_INTEGRATION_SLOW_WAITS_FILE,
          `${JSON.stringify({ file: testPath, test: currentTestName, elapsedMs: elapsed, ceilingMs })}\n`,
        );
      }
    }
  }
}
