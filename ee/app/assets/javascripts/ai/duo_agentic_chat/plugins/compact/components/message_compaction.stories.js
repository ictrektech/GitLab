import MessageCompaction from './message_compaction.vue';

export default {
  component: MessageCompaction,
  title: 'ee/ai/duo_agentic_chat/plugins/compact/components/message_compaction',
};

export const Default = () => ({
  components: { MessageCompaction },
  template: '<message-compaction />',
});
