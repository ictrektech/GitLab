import { s__ } from '~/locale';
import { GOAL_COMMAND, PROMPT_COMPOSER_ACTIONS } from '../../constants';
import { isGoalPromptMessage } from '../../utils/messages_utils';
import { getGoalFlow } from '../../services/goal_flow';
import MessageGoalPrompt from './components/message_goal_prompt.vue';

/**
 * Labelled with the token rather than prose, so the suggestion menu lists it the way it
 * lists `/compact` and `/new`. The toolbar row spells it out for itself.
 */
const goalSlashCommand = {
  label: s__('DuoAgenticChat|/goal'),
  value: GOAL_COMMAND,
  description: s__('DuoAgenticChat|Work until a goal is met'),
  startOnly: true,
  action: PROMPT_COMPOSER_ACTIONS.START_GOAL,
};

/**
 * `/goal` puts the composer in goal mode, where the prompt is a condition to work
 * towards rather than a question to answer.
 *
 * Hardcoded rather than read off the AI Catalog like `flow_commands` does, since goal is
 * one flow in one configuration. It is still only offered where that flow can run.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const goalPlugin = {
  name: 'goal',
  messageWidgets: [
    {
      matchMessage: isGoalPromptMessage,
      component: MessageGoalPrompt,
    },
  ],
  slashCommands: [
    {
      async getCommands({ apollo, duoChatContext } = {}) {
        const goalFlow = await getGoalFlow({ apollo, projectId: duoChatContext?.projectId });

        return goalFlow ? [goalSlashCommand] : [];
      },
    },
  ],
};
