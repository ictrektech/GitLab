import { FLOW_COMMAND_PREFIX, GOAL_COMMAND } from '../../constants';

/**
 * @typedef {import('../plugin_capabilities/slash_commands').SlashCommand} SlashCommand
 */

/**
 * @typedef {Object} PromptAttachment
 * @property {string} id
 * @property {string} filename
 * @property {string} mimeType
 * @property {number} byteSize
 * @property {string} data - base64 payload, without the data URL prefix
 * @property {string} previewUrl - data URL, for the composer's thumbnail only
 */

/**
 * A plain, JSON-serializable object rather than a class instance: prompt_queue.vue
 * persists queued prompts to sessionStorage, and a class instance would not survive
 * that round trip.
 *
 * @typedef {Object} UserPrompt
 * @property {string} text
 * @property {SlashCommand[]} slashCommands
 * @property {{ consumerId: number, goal: string }|null} goalFlow - Set once `START_GOAL`
 *   has run, naming the flow to run and the goal to work towards. `text` carries the
 *   same goal behind a `/goal` token, which is presentation: it is what the transcript
 *   recognises the turn by. Composer state rather than a command, since the menu and the
 *   toolbar both run that action.
 * @property {PromptAttachment[]} attachments - Mapped to `additional_context` items by
 *   the state manager. A queued prompt never carries any: sessionStorage cannot hold
 *   the payloads, so the composer refuses to queue a draft that has them.
 */

/**
 * @param {Partial<UserPrompt>} [parts]
 * @returns {UserPrompt}
 */
export function createUserPrompt({
  text = '',
  slashCommands = [],
  goalFlow = null,
  attachments = [],
} = {}) {
  return Object.freeze({
    text,
    // Copied, so a caller mutating its own array afterwards cannot reach into this prompt.
    slashCommands: Object.freeze([...slashCommands]),
    goalFlow,
    attachments: Object.freeze([...attachments]),
  });
}

export const EMPTY_USER_PROMPT = createUserPrompt();

const withoutCustomerData = (commandName) =>
  commandName?.startsWith(FLOW_COMMAND_PREFIX) ? FLOW_COMMAND_PREFIX : commandName;

/**
 * The slash commands a prompt invoked, by token.
 *
 * `slashCommands` is derived from the draft text, which goal mode strips the `/goal`
 * token from, so `goalFlow` is the only record that the command ran.
 *
 * @param {UserPrompt} [userPrompt]
 * @returns {string[]}
 */
export function invokedSlashCommands({ slashCommands = [], goalFlow = null } = {}) {
  const invoked = new Set(slashCommands.map(({ value }) => withoutCustomerData(value)));
  if (goalFlow) invoked.add(GOAL_COMMAND);

  return [...invoked];
}
