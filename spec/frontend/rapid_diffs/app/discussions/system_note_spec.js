import { shallowMount } from '@vue/test-utils';
import { GlIcon } from '@gitlab/ui';
import SystemNote from '~/rapid_diffs/app/discussions/system_note.vue';
import NoteAuthor from '~/rapid_diffs/app/discussions/note_author.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import TimelineEntryItem from '~/rapid_diffs/app/discussions/timeline_entry_item.vue';

describe('SystemNote', () => {
  let wrapper;

  const createComponent = (props = {}, { stubs } = {}) => {
    wrapper = shallowMount(SystemNote, {
      propsData: {
        ...props,
        note: { created_at: '2024-01-01T00:00:00Z', ...props.note },
      },
      stubs,
    });
  };

  const findTimelineEntryItem = () => wrapper.findComponent(TimelineEntryItem);
  const findIcon = () => wrapper.findComponent(GlIcon);
  const findDot = () => wrapper.find('[data-testid="system-note-dot"]');

  it('shows system message', () => {
    const note = { note_html: '<p id="test">test</p>' };
    createComponent({ note });
    expect(wrapper.find('p#test').text()).toBe('test');
  });

  it('shows message author', () => {
    const note = { note_html: 'test', author: { username: 'user' } };
    createComponent({ note });
    const author = wrapper.findComponent(NoteAuthor);
    expect(author.props('author')).toStrictEqual(note.author);
    expect(author.props('showUsername')).toBe(false);
  });

  it('shows deleted author', () => {
    const note = { note_html: 'test' };
    createComponent({ note });
    expect(wrapper.text()).toContain('A deleted user');
  });

  it('shows timestamp', () => {
    const note = { note_html: 'test', created_at: Date.now().toString() };
    createComponent({ note });
    expect(wrapper.findComponent(TimeAgoTooltip).props('time')).toBe(note.created_at);
  });

  it('renders icon in timeline layout', () => {
    const note = { note_html: 'test' };
    createComponent({ note }, { stubs: { TimelineEntryItem } });
    expect(findIcon().props('name')).toBe('comment-dots');
    expect(findDot().exists()).toBe(false);
  });

  it('renders dot instead of icon when not in timeline layout', () => {
    const note = { note_html: 'test' };
    createComponent({ note, timelineLayout: false }, { stubs: { TimelineEntryItem } });
    expect(findDot().exists()).toBe(true);
    expect(findIcon().exists()).toBe(false);
  });

  describe('TimelineEntryItem', () => {
    it('defaults timelineLayout to true', () => {
      const note = { note_html: 'test' };
      createComponent({ note });
      expect(findTimelineEntryItem().props('timelineLayout')).toBe(true);
    });

    it('passes timelineLayout prop', () => {
      const note = { note_html: 'test' };
      createComponent({ note, timelineLayout: false });
      expect(findTimelineEntryItem().props('timelineLayout')).toBe(false);
    });

    it('passes isLastDiscussion prop', () => {
      const note = { note_html: 'test' };
      createComponent({ note, isLastDiscussion: true });
      expect(findTimelineEntryItem().props('isLastDiscussion')).toBe(true);
    });

    it('defaults isLastDiscussion to false', () => {
      const note = { note_html: 'test' };
      createComponent({ note });
      expect(findTimelineEntryItem().props('isLastDiscussion')).toBe(false);
    });
  });
});
