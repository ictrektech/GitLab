import { BV_HIDE_TOOLTIP, BV_SHOW_TOOLTIP } from '~/lib/utils/constants';

// Keeps components independent of how @gitlab/ui shows tooltips, which changes with
// https://gitlab.com/gitlab-org/gitlab-services/design.gitlab.com/-/merge_requests/6294
const emitOnRoot = (vm, eventName, id) =>
  id === undefined ? vm.$root.$emit(eventName) : vm.$root.$emit(eventName, id);

/**
 * Shows the tooltip whose target element or tooltip has the given `id`,
 * or all tooltips when `id` is omitted.
 *
 * @param {Object} vm The calling component (`this`)
 * @param {string} [id] Id of the tooltip's target element, or of the tooltip itself
 */
export const showGlTooltip = (vm, id) => emitOnRoot(vm, BV_SHOW_TOOLTIP, id);

/**
 * Hides the tooltip whose target element or tooltip has the given `id`,
 * or all tooltips when `id` is omitted.
 *
 * @param {Object} vm The calling component (`this`)
 * @param {string} [id] Id of the tooltip's target element, or of the tooltip itself
 */
export const hideGlTooltip = (vm, id) => emitOnRoot(vm, BV_HIDE_TOOLTIP, id);
