import { UserMessage } from '@gitlab/duo-ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import MessageGoalPrompt from 'ee/ai/duo_agentic_chat/plugins/goal/components/message_goal_prompt.vue';
import GoalToken from 'ee/ai/duo_agentic_chat/components/prompt_composer/goal_token.vue';

describe('MessageGoalPrompt', () => {
  let wrapper;

  const MESSAGE = {
    id: 'msg-1',
    role: 'user',
    message_type: 'user',
    content: '/goal keep the pipeline green',
  };

  const createComponent = ({ mountFn = shallowMountExtended, propsData = {} } = {}) => {
    wrapper = mountFn(MessageGoalPrompt, { propsData: { message: MESSAGE, ...propsData } });
  };

  const findUserMessage = () => wrapper.findComponent(UserMessage);

  it('shows the goal without the token that marked it', () => {
    createComponent();

    expect(findUserMessage().props('message').content).toBe('keep the pipeline green');
  });

  it('leaves the rest of the message as it arrived', () => {
    createComponent();

    expect(findUserMessage().props('message')).toEqual({
      ...MESSAGE,
      content: 'keep the pipeline green',
    });
  });

  // The same token the composer shows, as a label rather than something to take off.
  it('badges the bubble as a goal', () => {
    createComponent({ mountFn: mountExtended });

    expect(wrapper.find('.duo-chat-message').text()).toBe('Goal');
    expect(wrapper.findComponent(GoalToken).props('viewOnly')).toBe(true);
    expect(wrapper.findByRole('button', { name: 'Remove goal' }).exists()).toBe(false);
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
