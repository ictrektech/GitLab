import { attachmentsPlugin } from 'ee/ai/duo_agentic_chat/plugins/attachments';
import MessageAttachmentsPrompt from 'ee/ai/duo_agentic_chat/plugins/attachments/components/message_attachments_prompt.vue';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';

describe('attachmentsPlugin', () => {
  const reference = {
    category: 'attachments',
    id: 'attachment-1',
    content: '',
    metadata: {
      title: 'diagram.png',
      enabled: true,
      icon: 'paperclip',
      secondaryText: 'image/png',
    },
  };

  it('is filed under a name that identifies it in plugin reports', () => {
    expect(attachmentsPlugin.name).toBe('attachments');
  });

  // Guards the shipped plugin against its own contract: the registry drops anything
  // malformed, so a broken descriptor would otherwise only show up as a missing widget.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(attachmentsPlugin);

    expect(registry.plugins).toEqual([attachmentsPlugin]);
  });

  describe('a turn with files in the transcript', () => {
    const [widget] = attachmentsPlugin.messageWidgets;

    it('renders it with MessageAttachmentsPrompt', () => {
      expect(attachmentsPlugin.messageWidgets).toEqual([
        { matchMessage: expect.any(Function), component: MessageAttachmentsPrompt },
      ]);
    });

    it('claims a user prompt that sent files', () => {
      expect(
        widget.matchMessage({
          role: 'user',
          content: 'what is this?',
          additional_context: [reference],
        }),
      ).toBe(true);
    });

    it('leaves a prompt without files to duo-ui', () => {
      expect(widget.matchMessage({ role: 'user', content: 'what is this?' })).toBe(false);
    });
  });
});
