import { UserMessage } from '@gitlab/duo-ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import MessageAttachmentsPrompt from 'ee/ai/duo_agentic_chat/plugins/attachments/components/message_attachments_prompt.vue';
import AttachmentChip from 'ee/ai/duo_agentic_chat/components/prompt_composer/attachment_chip.vue';
import GoalToken from 'ee/ai/duo_agentic_chat/components/prompt_composer/goal_token.vue';
import { mockAttachmentsMessage, mockIssueContextItem } from 'ee_jest/ai/mocks';

describe('MessageAttachmentsPrompt', () => {
  let wrapper;

  const createComponent = ({ mountFn = shallowMountExtended, propsData = {} } = {}) => {
    wrapper = mountFn(MessageAttachmentsPrompt, {
      propsData: { message: mockAttachmentsMessage, ...propsData },
    });
  };

  const findUserMessage = () => wrapper.findComponent(UserMessage);
  const findChips = () => wrapper.findAllComponents(AttachmentChip);

  it('shows one view-only chip per file sent', () => {
    createComponent({ mountFn: mountExtended });

    expect(findChips()).toHaveLength(2);
    expect(findChips().at(0).props()).toEqual({
      attachment: { id: 'attachment-1', filename: 'diagram.png', mimeType: 'image/png' },
      disabled: false,
      viewOnly: true,
    });
    expect(findChips().at(1).props('attachment').filename).toBe('photo.jpeg');
    expect(wrapper.findAllByRole('button', { name: /^Remove/ })).toHaveLength(0);
  });

  it('draws the thumbnails the turn still holds from when it was sent', () => {
    createComponent({
      propsData: {
        message: {
          ...mockAttachmentsMessage,
          attachments: [
            { id: 'l-1', filename: 'diagram.png', byteSize: 1, previewUrl: 'data:1' },
            { id: 'l-2', filename: 'photo.jpeg', byteSize: 2, previewUrl: 'data:2' },
          ],
        },
      },
    });

    expect(findChips().wrappers.map((chip) => chip.props('attachment').previewUrl)).toEqual([
      'data:1',
      'data:2',
    ]);
  });

  // duo-ui lists every context item under "Included references"; the files are already
  // on screen as chips, so only the other references are left for it to list.
  it('takes the files off the references duo-ui lists, keeping the rest', () => {
    createComponent();

    expect(findUserMessage().props('message').extras.contextItems).toEqual([mockIssueContextItem]);
  });

  it('takes the files off the list whichever way the category is spelled', () => {
    const upper = (item) => ({ ...item, category: item.category.toUpperCase() });
    createComponent({
      propsData: {
        message: {
          ...mockAttachmentsMessage,
          additional_context: mockAttachmentsMessage.additional_context.map(upper),
          extras: { contextItems: mockAttachmentsMessage.extras.contextItems.map(upper) },
        },
      },
    });

    expect(findUserMessage().props('message').extras.contextItems).toEqual([
      upper(mockIssueContextItem),
    ]);
    expect(wrapper.findAllComponents(AttachmentChip)).toHaveLength(2);
  });

  it('leaves the rest of the message as it arrived', () => {
    createComponent();

    const { extras, ...rest } = findUserMessage().props('message');

    expect(rest).toEqual({
      id: 'msg-1',
      role: 'user',
      message_type: 'user',
      content: 'what is in these?',
      additional_context: mockAttachmentsMessage.additional_context,
    });
  });

  it('copes with a message that has no extras yet', () => {
    createComponent({ propsData: { message: { ...mockAttachmentsMessage, extras: undefined } } });

    expect(findUserMessage().props('message').extras).toEqual({ contextItems: [] });
  });

  // The composer lets a goal be sent with files, and this widget claims that turn
  // first, so it has to keep what the goal widget would have drawn.
  describe('for a goal turn with files', () => {
    beforeEach(() => {
      createComponent({
        mountFn: mountExtended,
        propsData: { message: { ...mockAttachmentsMessage, content: '/goal describe these' } },
      });
    });

    it('keeps the goal badge and shows the goal without its token', () => {
      expect(wrapper.findComponent(GoalToken).props('viewOnly')).toBe(true);
      expect(findUserMessage().props('message').content).toBe('describe these');
    });

    it('draws the tiles under the badge', () => {
      expect(findChips()).toHaveLength(2);
    });
  });

  // Dropping these would render the same message with fewer links than duo-ui does.
  it('passes on the hosts whose links may be rendered', () => {
    createComponent({ propsData: { trustedUrls: ['gitlab.com'] } });

    expect(findUserMessage().props('trustedUrls')).toEqual(['gitlab.com']);
  });

  it('reports a request for a context item to whoever can fetch it', () => {
    createComponent();

    findUserMessage().vm.$emit('get-context-item-content', { messageId: 'msg-1' });

    expect(wrapper.emitted('get-context-item-content')).toEqual([[{ messageId: 'msg-1' }]]);
  });
});
