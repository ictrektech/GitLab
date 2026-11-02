import { isNoopCompaction } from '../../../utils/messages_utils';

/**
 * Drops compactions that summarized nothing.
 *
 * Dropped rather than hidden at render time: duo-ui wraps every message in its own flex
 * item, so a widget that renders nothing still leaves that wrapper behind and doubles the
 * gap between the messages either side of it.
 *
 * @param {Object[]} messages
 * @returns {Object[]}
 */
export const dropNoopCompaction = (messages) => messages.filter((m) => !isNoopCompaction(m));
