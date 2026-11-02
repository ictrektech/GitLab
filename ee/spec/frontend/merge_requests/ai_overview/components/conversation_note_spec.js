import { GlAvatar } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ConversationNote from 'ee/merge_requests/ai_overview/components/conversation_note.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { author, makeNote } from '../mock_data';

describe('AI Overview conversation note', () => {
  let wrapper;

  const createComponent = ({ props = {}, slots = {} } = {}) => {
    wrapper = mountExtended(ConversationNote, {
      propsData: { note: makeNote(), ...props },
      slots,
    });
  };

  const findAuthor = () => wrapper.findByTestId('conversation-author');

  describe('by default', () => {
    beforeEach(() => {
      createComponent({
        slots: { badges: '<span>Unresolved</span>', default: '<span>app/models/user.rb</span>' },
      });
    });

    it('links the author with a full-size avatar', () => {
      expect(findAuthor().text()).toBe('Priya Nair');
      expect(findAuthor().attributes('href')).toBe('/priya');
      expect(wrapper.findComponent(GlAvatar).props('size')).toBe(24);
    });

    it('shows the extra badges, the time and the first line of the note', () => {
      expect(wrapper.text()).toContain('Unresolved');
      expect(wrapper.text()).toContain('app/models/user.rb');
      expect(wrapper.findComponent(TimeAgoTooltip).props('time')).toBe('2026-09-20T10:00:00Z');
      expect(wrapper.findByTestId('conversation-body').html()).toContain('<code>method</code>');
    });

    it('keeps the first line inline', () => {
      expect(wrapper.findByTestId('conversation-body').find('p p').exists()).toBe(false);
    });
  });

  it('uses a smaller avatar when compact', () => {
    createComponent({ props: { compact: true } });

    expect(wrapper.findComponent(GlAvatar).props('size')).toBe(16);
  });

  it('shows an agent with its own avatar, like anyone else', () => {
    createComponent({ props: { note: makeNote({ author: { ...author, bot: true } }) } });

    expect(wrapper.findComponent(GlAvatar).props('src')).toBe(author.avatarUrl);
  });
});
