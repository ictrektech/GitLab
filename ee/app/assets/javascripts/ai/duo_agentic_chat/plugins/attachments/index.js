import { hasAttachments } from '../../utils/messages_utils';
import MessageAttachmentsPrompt from './components/message_attachments_prompt.vue';

/**
 * Shows the files a user sent as chips on their turn, where duo-ui would only list them
 * among the generic references. Gated on the same flag as the composer's upload.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const attachmentsPlugin = {
  name: 'attachments',
  messageWidgets: [
    {
      matchMessage: hasAttachments,
      component: MessageAttachmentsPrompt,
    },
  ],
};
