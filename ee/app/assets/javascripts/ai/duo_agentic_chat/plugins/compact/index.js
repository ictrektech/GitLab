import { s__ } from '~/locale';
import { COMPACT_COMMAND, PROMPT_COMPOSER_ACTIONS } from '../../constants';
import { isCompactionMessage } from '../../utils/messages_utils';
import MessageCompaction from './components/message_compaction.vue';
import { dropCompactPrompt } from './transformers/drop_compact_prompt';
import { dropNoopCompaction } from './transformers/drop_noop_compaction';

/**
 * Summarising a conversation so it fits back into the context window.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const compactPlugin = {
  name: 'compact',
  messageWidgets: [
    {
      matchMessage: isCompactionMessage,
      component: MessageCompaction,
      // A compaction marks a boundary between two stretches of conversation, so folding
      // it into an adjacent tool-group would hide the very thing it announces.
      groupable: false,
      defaultProps: {},
    },
  ],
  messageTransformers: [
    { transformMessages: dropCompactPrompt },
    { transformMessages: dropNoopCompaction },
  ],
  slashCommands: [
    {
      getCommands: () => [
        {
          value: COMPACT_COMMAND,
          description: s__('DuoAgenticChat|Summarize and compact this conversation'),
          startOnly: true,
          action: PROMPT_COMPOSER_ACTIONS.INSERT,
        },
      ],
    },
  ],
};
